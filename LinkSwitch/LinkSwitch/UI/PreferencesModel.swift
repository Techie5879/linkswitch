import Foundation

protocol RouterConfigSaving {
    func save(_ config: RouterConfig) throws
}

enum PreferencesRuleTargetKind: String, CaseIterable, Equatable {
    case fallbackBrowser
    case helium
}

struct PreferencesRuleDraft: Equatable {
    let id: UUID
    var sourceBundleID: String
    var targetKind: PreferencesRuleTargetKind
    var fallbackBrowserRoute: FallbackBrowserRoute
    var heliumProfileDirectory: String
}

enum PreferencesModelError: Error, Equatable {
    case missingFallbackBrowserSelection
    case fallbackBrowserBundleIdentifierNotFound(applicationURL: URL)
    case linkSwitchBundleIdentifierNotFound(applicationURL: URL)
    case invalidSampleURL(String)
    case ruleNotFound(UUID)
    case emptySourceBundleID(UUID)
    case emptyFallbackBrowserFirefoxProfile(UUID)
    case emptyFallbackBrowserZenContainer(UUID)
    case emptyFallbackBrowserDefaultFirefoxProfile
    case emptyFallbackBrowserDefaultZenContainer
    case emptyHeliumProfileDirectory(UUID)
}

@MainActor
final class PreferencesModel {
    private let configStore: any RouterConfigLoading & RouterConfigSaving
    private let browserLauncher: any BrowserLaunching
    private let launchServicesBridge: LaunchServicesBridge
    private let browserDiscovery: any BrowserDiscovering
    private let installedApplicationDiscovery: any InstalledApplicationDiscovering

    let configFileURLDescription: String
    var fallbackBrowserBundleID = ""
    var fallbackBrowserAppURL: URL?
    var fallbackBrowserRoute: FallbackBrowserRoute = .plain
    var sampleURLString = "https://example.com"
    private(set) var ruleDrafts: [PreferencesRuleDraft] = []
    private(set) var discoveredBrowsers: [DiscoveredBrowser] = []
    private(set) var discoveredApplications: [DiscoveredApplication] = []

    init(
        configStore: any RouterConfigLoading & RouterConfigSaving,
        browserLauncher: any BrowserLaunching,
        configFileURLDescription: String,
        launchServicesBridge: LaunchServicesBridge = LaunchServicesBridge(),
        browserDiscovery: any BrowserDiscovering = BrowserDiscovery(),
        installedApplicationDiscovery: any InstalledApplicationDiscovering = InstalledApplicationDiscovery()
    ) {
        self.configStore = configStore
        self.browserLauncher = browserLauncher
        self.configFileURLDescription = configFileURLDescription
        self.launchServicesBridge = launchServicesBridge
        self.browserDiscovery = browserDiscovery
        self.installedApplicationDiscovery = installedApplicationDiscovery
    }

    static func live() throws -> PreferencesModel {
        let store = RouterConfigStore(configFileURL: try RouterConfigStore.defaultConfigFileURL())
        return PreferencesModel(
            configStore: store,
            browserLauncher: BrowserLauncher(),
            configFileURLDescription: store.configFileURL.path(percentEncoded: false),
            launchServicesBridge: LaunchServicesBridge()
        )
    }

    func load() throws {
        AppLogger.info("Loading preferences model from \(configFileURLDescription)", category: .config)
        refreshDiscoveredBrowsers()
        refreshInstalledApplications()
        guard let config = try configStore.load() else {
            AppLogger.info("No router config exists yet; preferences model will start empty", category: .config)
            fallbackBrowserBundleID = ""
            fallbackBrowserAppURL = nil
            fallbackBrowserRoute = .plain
            ruleDrafts = []
            return
        }

        fallbackBrowserBundleID = config.fallbackBrowserBundleID
        fallbackBrowserAppURL = config.fallbackBrowserAppURL
        fallbackBrowserRoute = config.fallbackBrowserRoute
        ruleDrafts = config.rules.map { rule in
            switch rule.target {
            case .fallbackBrowser:
                return PreferencesRuleDraft(
                    id: rule.id,
                    sourceBundleID: rule.sourceBundleID,
                    targetKind: .fallbackBrowser,
                    fallbackBrowserRoute: .plain,
                    heliumProfileDirectory: ""
                )
            case let .fallbackBrowserFirefoxProfile(profileKey):
                return PreferencesRuleDraft(
                    id: rule.id,
                    sourceBundleID: rule.sourceBundleID,
                    targetKind: .fallbackBrowser,
                    fallbackBrowserRoute: .firefoxProfile(profileKey: profileKey),
                    heliumProfileDirectory: ""
                )
            case let .fallbackBrowserZenContainer(containerName):
                return PreferencesRuleDraft(
                    id: rule.id,
                    sourceBundleID: rule.sourceBundleID,
                    targetKind: .fallbackBrowser,
                    fallbackBrowserRoute: .zenContainer(containerName: containerName),
                    heliumProfileDirectory: ""
                )
            case let .helium(profileDirectory):
                return PreferencesRuleDraft(
                    id: rule.id,
                    sourceBundleID: rule.sourceBundleID,
                    targetKind: .helium,
                    fallbackBrowserRoute: .plain,
                    heliumProfileDirectory: profileDirectory
                )
            }
        }
        normalizeFallbackRuleTargetsForCurrentBrowser()
    }

    func refreshDiscoveredBrowsers() {
        let selfBundleID = Bundle.main.bundleIdentifier
        discoveredBrowsers = browserDiscovery.discoverBrowsers(excludingBundleID: selfBundleID)
        AppLogger.info(
            "Refreshed discovered browsers: \(discoveredBrowsers.count) found",
            category: .config
        )
    }

    func refreshInstalledApplications() {
        let selfBundleID = Bundle.main.bundleIdentifier
        discoveredApplications = installedApplicationDiscovery.discoverInstalledApplications(excludingBundleID: selfBundleID)
        AppLogger.info(
            "Refreshed installed applications: \(discoveredApplications.count) found",
            category: .config
        )
    }

    func setFallbackBrowser(discoveredBrowser: DiscoveredBrowser) {
        AppLogger.info(
            "Setting fallback browser from discovered browser \(discoveredBrowser.bundleID) at \(discoveredBrowser.appURL.path())",
            category: .config
        )
        fallbackBrowserBundleID = discoveredBrowser.bundleID
        fallbackBrowserAppURL = discoveredBrowser.appURL
        normalizeFallbackRuleTargetsForCurrentBrowser()
    }

    func setFallbackBrowser(applicationURL: URL) throws {
        AppLogger.info("Setting fallback browser from selected app \(applicationURL.path())", category: .config)
        guard let bundleID = Bundle(url: applicationURL)?.bundleIdentifier else {
            AppLogger.error("Selected fallback browser app did not expose a bundle ID: \(applicationURL.path())", category: .config)
            throw PreferencesModelError.fallbackBrowserBundleIdentifierNotFound(applicationURL: applicationURL)
        }

        fallbackBrowserBundleID = bundleID
        fallbackBrowserAppURL = applicationURL
        normalizeFallbackRuleTargetsForCurrentBrowser()
    }

    @discardableResult
    func addRule() -> UUID {
        let ruleID = UUID()
        ruleDrafts.append(
            PreferencesRuleDraft(
                id: ruleID,
                sourceBundleID: "",
                targetKind: .fallbackBrowser,
                fallbackBrowserRoute: .plain,
                heliumProfileDirectory: ""
            )
        )
        AppLogger.info("Added preferences rule draft \(ruleID)", category: .config)
        return ruleID
    }

    func removeRule(id: UUID) {
        ruleDrafts.removeAll { $0.id == id }
        AppLogger.info("Removed preferences rule draft \(id)", category: .config)
    }

    func updateRuleSourceBundleID(id: UUID, value: String) {
        updateRule(id: id) { $0.sourceBundleID = value }
    }

    func updateRuleTargetKind(id: UUID, targetKind: PreferencesRuleTargetKind) {
        updateRule(id: id) { draft in
            draft.targetKind = targetKind
            if targetKind == .fallbackBrowser {
                draft.heliumProfileDirectory = ""
            } else {
                draft.fallbackBrowserRoute = .plain
            }
        }
    }

    func updateRuleFallbackBrowserRoute(id: UUID, route: FallbackBrowserRoute) {
        updateRule(id: id) { $0.fallbackBrowserRoute = route }
    }

    func updateFallbackBrowserRoute(_ route: FallbackBrowserRoute) {
        fallbackBrowserRoute = route
        AppLogger.info("Updated default fallback browser route to \(route.description)", category: .config)
    }

    func updateRuleHeliumProfileDirectory(id: UUID, value: String) {
        updateRule(id: id) { $0.heliumProfileDirectory = value }
    }

    func save() throws {
        let config = try makeRouterConfig()
        AppLogger.info("Saving preferences model to \(configFileURLDescription)", category: .config)
        try configStore.save(config)
    }

    func testFallbackBrowser() async throws {
        let config = try makeRouterConfig()
        let sampleURL = try makeSampleURL()
        let target = config.fallbackBrowserRoute.browserTarget
        AppLogger.info(
            "Testing fallback browser launch with URL \(sampleURL.absoluteString) and target \(target.description)",
            category: .launch
        )
        try await browserLauncher.open(sampleURL, target: target, config: config)
    }

    func testRule(id: UUID) async throws {
        let config = try makeRouterConfig()
        let sampleURL = try makeSampleURL()
        guard let draft = ruleDrafts.first(where: { $0.id == id }) else {
            AppLogger.error("Attempted to test missing preferences rule \(id)", category: .launch)
            throw PreferencesModelError.ruleNotFound(id)
        }

        let target = try makeTarget(for: draft)
        AppLogger.info("Testing preferences rule \(id) with URL \(sampleURL.absoluteString) and target \(target)", category: .launch)
        try await browserLauncher.open(sampleURL, target: target, config: config)
    }

    func currentHandlerBundleID(forURLScheme urlScheme: String) -> String? {
        do {
            return try launchServicesBridge.defaultHandlerBundleID(forURLScheme: urlScheme)
        } catch {
            AppLogger.info("Current handler lookup for \(urlScheme) did not return a bundle ID: \(error)", category: .launch)
            return nil
        }
    }

    func registerLinkSwitchAsDefaultHandler(applicationURL: URL) async throws -> DefaultHandlerRegistrationResult {
        AppLogger.info("Registering LinkSwitch as the default handler for http/https from preferences", category: .launch)
        guard let bundleIdentifier = Bundle(url: applicationURL)?.bundleIdentifier else {
            AppLogger.error("Could not resolve LinkSwitch bundle identifier from \(applicationURL.path())", category: .launch)
            throw PreferencesModelError.linkSwitchBundleIdentifierNotFound(applicationURL: applicationURL)
        }

        return try await launchServicesBridge.setDefaultHandler(
            applicationURL: applicationURL,
            applicationBundleIdentifier: bundleIdentifier,
            urlSchemes: ["http", "https"]
        )
    }

    /// Sets the configured fallback browser as the system default handler for `http` and `https`.
    func registerFallbackBrowserAsDefaultHandler() async throws -> DefaultHandlerRegistrationResult {
        AppLogger.info("Registering fallback browser as the default handler for http/https from preferences", category: .launch)
        guard let applicationURL = fallbackBrowserAppURL else {
            AppLogger.error("Cannot register fallback browser as default handler without a selected fallback app", category: .launch)
            throw PreferencesModelError.missingFallbackBrowserSelection
        }
        guard !fallbackBrowserBundleID.isEmpty else {
            AppLogger.error("Cannot register fallback browser as default handler without a bundle identifier", category: .launch)
            throw PreferencesModelError.missingFallbackBrowserSelection
        }

        return try await launchServicesBridge.setDefaultHandler(
            applicationURL: applicationURL,
            applicationBundleIdentifier: fallbackBrowserBundleID,
            urlSchemes: ["http", "https"]
        )
    }

    private func updateRule(id: UUID, mutate: (inout PreferencesRuleDraft) -> Void) {
        guard let index = ruleDrafts.firstIndex(where: { $0.id == id }) else {
            AppLogger.error("Attempted to update missing preferences rule \(id)", category: .config)
            return
        }

        mutate(&ruleDrafts[index])
    }

    private func makeRouterConfig() throws -> RouterConfig {
        guard let fallbackBrowserAppURL else {
            AppLogger.error("Preferences model cannot build config without a fallback browser selection", category: .config)
            throw PreferencesModelError.missingFallbackBrowserSelection
        }

        let validatedFallbackRoute = try validatedFallbackBrowserRouteForSave(fallbackBrowserRoute)

        let rules = try ruleDrafts.map { draft in
            let trimmedSourceBundleID = draft.sourceBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedSourceBundleID.isEmpty else {
                AppLogger.error("Preferences rule \(draft.id) had an empty source bundle ID", category: .config)
                throw PreferencesModelError.emptySourceBundleID(draft.id)
            }

            return SourceAppRule(
                id: draft.id,
                sourceBundleID: trimmedSourceBundleID,
                target: try makeTarget(for: draft)
            )
        }

        return RouterConfig(
            fallbackBrowserBundleID: fallbackBrowserBundleID,
            fallbackBrowserAppURL: fallbackBrowserAppURL,
            fallbackBrowserRoute: validatedFallbackRoute,
            rules: rules
        )
    }

    private func validatedFallbackBrowserRouteForSave(_ route: FallbackBrowserRoute) throws -> FallbackBrowserRoute {
        switch route {
        case .plain:
            return .plain
        case let .firefoxProfile(profileKey):
            let trimmedProfileKey = profileKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedProfileKey.isEmpty else {
                AppLogger.error("Default fallback browser route had an empty Firefox profile key", category: .config)
                throw PreferencesModelError.emptyFallbackBrowserDefaultFirefoxProfile
            }
            return .firefoxProfile(profileKey: trimmedProfileKey)
        case let .zenContainer(containerName):
            let trimmedContainerName = containerName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedContainerName.isEmpty else {
                AppLogger.error("Default fallback browser route had an empty Zen container name", category: .config)
                throw PreferencesModelError.emptyFallbackBrowserDefaultZenContainer
            }
            return .zenContainer(containerName: trimmedContainerName)
        }
    }

    private func makeTarget(for draft: PreferencesRuleDraft) throws -> BrowserTarget {
        switch draft.targetKind {
        case .fallbackBrowser:
            switch draft.fallbackBrowserRoute {
            case .plain:
                return .fallbackBrowser
            case let .firefoxProfile(profileKey):
                let trimmedProfileKey = profileKey.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedProfileKey.isEmpty else {
                    AppLogger.error("Preferences rule \(draft.id) had an empty fallback Firefox profile key", category: .config)
                    throw PreferencesModelError.emptyFallbackBrowserFirefoxProfile(draft.id)
                }
                return .fallbackBrowserFirefoxProfile(profileKey: trimmedProfileKey)
            case let .zenContainer(containerName):
                let trimmedContainerName = containerName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedContainerName.isEmpty else {
                    AppLogger.error("Preferences rule \(draft.id) had an empty Zen container name", category: .config)
                    throw PreferencesModelError.emptyFallbackBrowserZenContainer(draft.id)
                }
                return .fallbackBrowserZenContainer(containerName: trimmedContainerName)
            }
        case .helium:
            let trimmedProfileDirectory = draft.heliumProfileDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedProfileDirectory.isEmpty else {
                AppLogger.error("Preferences rule \(draft.id) had an empty Helium profile directory", category: .config)
                throw PreferencesModelError.emptyHeliumProfileDirectory(draft.id)
            }
            return .helium(profileDirectory: trimmedProfileDirectory)
        }
    }

    private func normalizeFallbackRuleTargetsForCurrentBrowser() {
        let selectedBundleID = fallbackBrowserBundleID
        let compatibility = fallbackBrowserCompatibility(forBundleID: selectedBundleID)

        let defaultCurrent = fallbackBrowserRoute
        let defaultNormalized = normalizedFallbackRoute(defaultCurrent, compatibility: compatibility)
        if defaultNormalized != defaultCurrent {
            AppLogger.info(
                "Normalizing default fallback route from \(defaultCurrent.description) to \(defaultNormalized.description) for fallback browser \(selectedBundleID)",
                category: .config
            )
            fallbackBrowserRoute = defaultNormalized
        }

        for index in ruleDrafts.indices where ruleDrafts[index].targetKind == .fallbackBrowser {
            let currentRoute = ruleDrafts[index].fallbackBrowserRoute
            let normalizedRoute = normalizedFallbackRoute(currentRoute, compatibility: compatibility)
            if normalizedRoute != currentRoute {
                AppLogger.info(
                    "Normalizing fallback rule \(ruleDrafts[index].id) from \(currentRoute.description) to \(normalizedRoute.description) for fallback browser \(selectedBundleID)",
                    category: .config
                )
                ruleDrafts[index].fallbackBrowserRoute = normalizedRoute
            }
        }
    }

    private func fallbackBrowserCompatibility(forBundleID bundleID: String) -> FallbackBrowserCompatibility {
        if bundleID == FirefoxBrowserAppSupportPath.zenBrowserBundleID {
            return .zenContainer
        }
        if FirefoxBrowserAppSupportPath.supportsFallbackProfileRouting(forBundleID: bundleID) {
            return .firefoxProfile
        }
        return .plainOnly
    }

    private func normalizedFallbackRoute(
        _ route: FallbackBrowserRoute,
        compatibility: FallbackBrowserCompatibility
    ) -> FallbackBrowserRoute {
        switch (compatibility, route) {
        case (.firefoxProfile, .zenContainer),
             (.zenContainer, .firefoxProfile),
             (.plainOnly, .firefoxProfile),
             (.plainOnly, .zenContainer):
            return .plain
        default:
            return route
        }
    }

    private enum FallbackBrowserCompatibility {
        case plainOnly
        case firefoxProfile
        case zenContainer
    }

    private func makeSampleURL() throws -> URL {
        let trimmedSampleURLString = sampleURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let sampleURL = URL(string: trimmedSampleURLString) else {
            AppLogger.error("Preferences model could not parse sample URL \(trimmedSampleURLString)", category: .launch)
            throw PreferencesModelError.invalidSampleURL(trimmedSampleURLString)
        }
        return sampleURL
    }
}

extension RouterConfigStore: RouterConfigSaving {}
