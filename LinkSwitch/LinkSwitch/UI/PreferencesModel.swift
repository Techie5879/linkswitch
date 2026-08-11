import Foundation

protocol RouterConfigSaving {
    func save(_ config: RouterConfig) throws
}

enum PreferencesRuleTargetSelection: Equatable {
    case defaultBrowser
    case browser(bundleID: String, applicationURL: URL?)

    var bundleID: String? {
        switch self {
        case .defaultBrowser:
            return nil
        case let .browser(bundleID, _):
            return bundleID
        }
    }

    var applicationURL: URL? {
        switch self {
        case .defaultBrowser:
            return nil
        case let .browser(_, applicationURL):
            return applicationURL
        }
    }
}

struct PreferencesRuleDraft: Equatable {
    let id: UUID
    var sourceBundleID: String
    var targetSelection: PreferencesRuleTargetSelection
    var browserRoute: DefaultBrowserRoute
}

struct PreferencesDomainRuleDraft: Equatable {
    let id: UUID
    var domain: String
    var targetSelection: PreferencesRuleTargetSelection
    var browserRoute: DefaultBrowserRoute
}

enum PreferencesModelError: Error, Equatable {
    case missingDefaultBrowserSelection
    case defaultBrowserBundleIdentifierNotFound(applicationURL: URL)
    case linkSwitchBundleIdentifierNotFound(applicationURL: URL)
    case invalidSampleURL(String)
    case ruleNotFound(UUID)
    case emptySourceBundleID(UUID)
    case invalidDomain(UUID, String)
    case duplicateDomain(UUID, String)
    case emptyRuleChromiumProfile(UUID)
    case emptyRuleFirefoxProfile(UUID)
    case emptyRuleZenContainer(UUID)
    case emptyDefaultBrowserRouteChromiumProfile
    case emptyDefaultBrowserRouteFirefoxProfile
    case emptyDefaultBrowserRouteZenContainer
    case missingRuleTargetApplication(UUID, bundleID: String)
}

extension PreferencesModelError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingDefaultBrowserSelection:
            return "Select a default browser before saving."
        case let .defaultBrowserBundleIdentifierNotFound(applicationURL):
            return "The selected default browser at \(applicationURL.path()) does not expose a bundle identifier."
        case let .linkSwitchBundleIdentifierNotFound(applicationURL):
            return "The LinkSwitch app at \(applicationURL.path()) does not expose a bundle identifier."
        case let .invalidSampleURL(urlString):
            return "The sample URL '\(urlString)' is not valid."
        case let .ruleNotFound(ruleID):
            return "The selected rule \(ruleID.uuidString) no longer exists."
        case let .emptySourceBundleID(ruleID):
            return "Rule \(ruleID.uuidString) is missing a source app bundle ID."
        case let .invalidDomain(ruleID, domain):
            return "Domain rule \(ruleID.uuidString) has an invalid domain '\(domain)'. Enter a hostname such as example.com."
        case let .duplicateDomain(ruleID, domain):
            return "Domain rule \(ruleID.uuidString) duplicates the domain '\(domain)'."
        case let .emptyRuleChromiumProfile(ruleID):
            return "Rule \(ruleID.uuidString) is missing a Chromium profile."
        case let .emptyRuleFirefoxProfile(ruleID):
            return "Rule \(ruleID.uuidString) is missing a Firefox profile."
        case let .emptyRuleZenContainer(ruleID):
            return "Rule \(ruleID.uuidString) is missing a Zen container."
        case .emptyDefaultBrowserRouteChromiumProfile:
            return "The default browser route is missing a Chromium profile."
        case .emptyDefaultBrowserRouteFirefoxProfile:
            return "The default browser route is missing a Firefox profile."
        case .emptyDefaultBrowserRouteZenContainer:
            return "The default browser route is missing a Zen container."
        case let .missingRuleTargetApplication(ruleID, bundleID):
            return "Rule \(ruleID.uuidString) could not resolve an installed browser app for \(bundleID)."
        }
    }
}

@MainActor
final class PreferencesModel {
    private let configStore: any RouterConfigLoading & RouterConfigSaving
    private let browserLauncher: any BrowserLaunching
    private let launchServicesBridge: LaunchServicesBridge
    private let launchAtLoginBridge: LaunchAtLoginBridge
    private let browserDiscovery: any BrowserDiscovering
    private let installedApplicationDiscovery: any InstalledApplicationDiscovering

    let configFileURLDescription: String
    var defaultBrowserBundleID = ""
    var defaultBrowserAppURL: URL?
    var defaultBrowserRoute: DefaultBrowserRoute = .plain
    var sampleURLString = "https://example.com"
    private(set) var ruleDrafts: [PreferencesRuleDraft] = []
    private(set) var domainRuleDrafts: [PreferencesDomainRuleDraft] = []
    private(set) var discoveredBrowsers: [DiscoveredBrowser] = []
    private(set) var discoveredApplications: [DiscoveredApplication] = []

    init(
        configStore: any RouterConfigLoading & RouterConfigSaving,
        browserLauncher: any BrowserLaunching,
        configFileURLDescription: String,
        launchServicesBridge: LaunchServicesBridge = LaunchServicesBridge(),
        launchAtLoginBridge: LaunchAtLoginBridge = LaunchAtLoginBridge(),
        browserDiscovery: any BrowserDiscovering = BrowserDiscovery(),
        installedApplicationDiscovery: any InstalledApplicationDiscovering = InstalledApplicationDiscovery()
    ) {
        self.configStore = configStore
        self.browserLauncher = browserLauncher
        self.configFileURLDescription = configFileURLDescription
        self.launchServicesBridge = launchServicesBridge
        self.launchAtLoginBridge = launchAtLoginBridge
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
            defaultBrowserBundleID = ""
            defaultBrowserAppURL = nil
            defaultBrowserRoute = .plain
            ruleDrafts = []
            domainRuleDrafts = []
            return
        }

        defaultBrowserBundleID = config.defaultBrowserBundleID
        defaultBrowserAppURL = config.defaultBrowserAppURL
        defaultBrowserRoute = config.defaultBrowserRoute
        ruleDrafts = config.rules.map { rule in
            let targetDraft = preferencesTargetDraft(from: rule.target)
            return PreferencesRuleDraft(
                id: rule.id,
                sourceBundleID: rule.sourceBundleID,
                targetSelection: targetDraft.selection,
                browserRoute: targetDraft.route
            )
        }
        domainRuleDrafts = config.domainRules.map { rule in
            let targetDraft = preferencesTargetDraft(from: rule.target)
            return PreferencesDomainRuleDraft(
                id: rule.id,
                domain: rule.domain,
                targetSelection: targetDraft.selection,
                browserRoute: targetDraft.route
            )
        }
        normalizeDefaultBrowserRuleTargetsForCurrentBrowser()
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

    private func resolvedKnownApplicationURL(forBundleID bundleID: String) -> URL? {
        if let discoveredURL = discoveredBrowsers.first(where: { $0.bundleID == bundleID })?.appURL {
            return discoveredURL
        }
        return try? launchServicesBridge.applicationURL(forBundleIdentifier: bundleID)
    }

    private func preferencesTargetDraft(
        from target: BrowserTarget
    ) -> (selection: PreferencesRuleTargetSelection, route: DefaultBrowserRoute) {
        switch target {
        case .defaultBrowser:
            return (.defaultBrowser, .plain)
        case let .defaultBrowserChromiumProfile(profileDirectory):
            return (.defaultBrowser, .chromiumProfile(profileDirectory: profileDirectory))
        case let .defaultBrowserFirefoxProfile(profileKey):
            return (.defaultBrowser, .firefoxProfile(profileKey: profileKey))
        case let .defaultBrowserZenContainer(containerName):
            return (.defaultBrowser, .zenContainer(containerName: containerName))
        case let .application(bundleID, applicationURL):
            return (.browser(bundleID: bundleID, applicationURL: applicationURL), .plain)
        case let .applicationChromiumProfile(bundleID, applicationURL, profileDirectory):
            return (
                .browser(bundleID: bundleID, applicationURL: applicationURL),
                .chromiumProfile(profileDirectory: profileDirectory)
            )
        case let .applicationFirefoxProfile(bundleID, applicationURL, profileKey):
            return (
                .browser(bundleID: bundleID, applicationURL: applicationURL),
                .firefoxProfile(profileKey: profileKey)
            )
        case let .applicationZenContainer(bundleID, applicationURL, containerName):
            return (
                .browser(bundleID: bundleID, applicationURL: applicationURL),
                .zenContainer(containerName: containerName)
            )
        case let .helium(profileDirectory):
            return (
                .browser(
                    bundleID: BrowserLauncher.heliumBundleID,
                    applicationURL: resolvedKnownApplicationURL(forBundleID: BrowserLauncher.heliumBundleID)
                ),
                .chromiumProfile(profileDirectory: profileDirectory)
            )
        }
    }

    func setDefaultBrowser(discoveredBrowser: DiscoveredBrowser) {
        AppLogger.info(
            "Setting default browser from discovered browser \(discoveredBrowser.bundleID) at \(discoveredBrowser.appURL.path())",
            category: .config
        )
        defaultBrowserBundleID = discoveredBrowser.bundleID
        defaultBrowserAppURL = discoveredBrowser.appURL
        normalizeDefaultBrowserRuleTargetsForCurrentBrowser()
    }

    func setDefaultBrowser(applicationURL: URL) throws {
        AppLogger.info("Setting default browser from selected app \(applicationURL.path())", category: .config)
        guard let bundleID = Bundle(url: applicationURL)?.bundleIdentifier else {
            AppLogger.error("Selected default browser app did not expose a bundle ID: \(applicationURL.path())", category: .config)
            throw PreferencesModelError.defaultBrowserBundleIdentifierNotFound(applicationURL: applicationURL)
        }

        defaultBrowserBundleID = bundleID
        defaultBrowserAppURL = applicationURL
        normalizeDefaultBrowserRuleTargetsForCurrentBrowser()
    }

    @discardableResult
    func addRule() -> UUID {
        let ruleID = UUID()
        ruleDrafts.append(
            PreferencesRuleDraft(
                id: ruleID,
                sourceBundleID: "",
                targetSelection: .defaultBrowser,
                browserRoute: .plain
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

    func updateRuleTargetSelection(id: UUID, targetSelection: PreferencesRuleTargetSelection) {
        updateRule(id: id) { draft in
            draft.targetSelection = targetSelection
            let compatibility = switch targetSelection {
            case .defaultBrowser:
                defaultBrowserCompatibility(forBundleID: defaultBrowserBundleID)
            case let .browser(bundleID, _):
                defaultBrowserCompatibility(forBundleID: bundleID)
            }
            draft.browserRoute = normalizedDefaultRoute(draft.browserRoute, compatibility: compatibility)
        }
    }

    func updateRuleBrowserRoute(id: UUID, route: DefaultBrowserRoute) {
        updateRule(id: id) { $0.browserRoute = route }
    }

    @discardableResult
    func addDomainRule() -> UUID {
        let ruleID = UUID()
        domainRuleDrafts.append(
            PreferencesDomainRuleDraft(
                id: ruleID,
                domain: "",
                targetSelection: .defaultBrowser,
                browserRoute: .plain
            )
        )
        AppLogger.info("Added preferences domain-rule draft \(ruleID)", category: .config)
        return ruleID
    }

    func removeDomainRule(id: UUID) {
        domainRuleDrafts.removeAll { $0.id == id }
        AppLogger.info("Removed preferences domain-rule draft \(id)", category: .config)
    }

    func updateDomainRuleDomain(id: UUID, value: String) {
        updateDomainRule(id: id) { $0.domain = value }
    }

    func updateDomainRuleTargetSelection(id: UUID, targetSelection: PreferencesRuleTargetSelection) {
        updateDomainRule(id: id) { draft in
            draft.targetSelection = targetSelection
            let compatibility = switch targetSelection {
            case .defaultBrowser:
                defaultBrowserCompatibility(forBundleID: defaultBrowserBundleID)
            case let .browser(bundleID, _):
                defaultBrowserCompatibility(forBundleID: bundleID)
            }
            draft.browserRoute = normalizedDefaultRoute(draft.browserRoute, compatibility: compatibility)
        }
    }

    func updateDomainRuleBrowserRoute(id: UUID, route: DefaultBrowserRoute) {
        updateDomainRule(id: id) { $0.browserRoute = route }
    }

    func updateDefaultBrowserRoute(_ route: DefaultBrowserRoute) {
        defaultBrowserRoute = route
        AppLogger.info("Updated default browser route to \(route.description)", category: .config)
    }

    func save() throws {
        let config = try makeRouterConfig()
        AppLogger.info("Saving preferences model to \(configFileURLDescription)", category: .config)
        try configStore.save(config)
    }

    func configValidationMessage() -> String? {
        do {
            _ = try makeRouterConfig()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func rawConfigPreview() -> String {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let config = try makeRouterConfig()
            let data = try encoder.encode(config)
            return String(decoding: data, as: UTF8.self)
        } catch {
            return "Config preview unavailable.\n\(error.localizedDescription)"
        }
    }

    func testDefaultBrowser() async throws {
        let config = try makeRouterConfig()
        let sampleURL = try makeSampleURL()
        let target = config.defaultBrowserRoute.browserTarget
        AppLogger.info(
            "Testing default browser launch with URL \(sampleURL.absoluteString) and target \(target.description)",
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

    func testDomainRule(id: UUID) async throws {
        let config = try makeRouterConfig()
        let sampleURL = try makeSampleURL()
        guard let draft = domainRuleDrafts.first(where: { $0.id == id }) else {
            AppLogger.error("Attempted to test missing preferences domain rule \(id)", category: .launch)
            throw PreferencesModelError.ruleNotFound(id)
        }

        let target = try makeTarget(
            id: draft.id,
            targetSelection: draft.targetSelection,
            browserRoute: draft.browserRoute
        )
        AppLogger.info("Testing preferences domain rule \(id) with URL \(sampleURL.absoluteString) and target \(target)", category: .launch)
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

    /// Sets the configured default browser as the system default handler for `http` and `https`.
    func registerDefaultBrowserAsDefaultHandler() async throws -> DefaultHandlerRegistrationResult {
        AppLogger.info("Registering default browser as the default handler for http/https from preferences", category: .launch)
        guard let applicationURL = defaultBrowserAppURL else {
            AppLogger.error("Cannot register default browser as default handler without a selected app", category: .launch)
            throw PreferencesModelError.missingDefaultBrowserSelection
        }
        guard !defaultBrowserBundleID.isEmpty else {
            AppLogger.error("Cannot register default browser as default handler without a bundle identifier", category: .launch)
            throw PreferencesModelError.missingDefaultBrowserSelection
        }

        return try await launchServicesBridge.setDefaultHandler(
            applicationURL: applicationURL,
            applicationBundleIdentifier: defaultBrowserBundleID,
            urlSchemes: ["http", "https"]
        )
    }

    func launchAtLoginStatus() -> LaunchAtLoginStatus {
        launchAtLoginBridge.status()
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) throws -> LaunchAtLoginStatus {
        AppLogger.info("Preferences requested launch-at-login enabled=\(enabled)", category: .launch)
        return try launchAtLoginBridge.setEnabled(enabled)
    }

    func openSystemSettingsLoginItems() {
        AppLogger.info("Preferences requested opening System Settings Login Items", category: .launch)
        launchAtLoginBridge.openSystemSettingsLoginItems()
    }

    private func updateRule(id: UUID, mutate: (inout PreferencesRuleDraft) -> Void) {
        guard let index = ruleDrafts.firstIndex(where: { $0.id == id }) else {
            AppLogger.error("Attempted to update missing preferences rule \(id)", category: .config)
            return
        }

        mutate(&ruleDrafts[index])
    }

    private func updateDomainRule(id: UUID, mutate: (inout PreferencesDomainRuleDraft) -> Void) {
        guard let index = domainRuleDrafts.firstIndex(where: { $0.id == id }) else {
            AppLogger.error("Attempted to update missing preferences domain rule \(id)", category: .config)
            return
        }

        mutate(&domainRuleDrafts[index])
    }

    private func makeRouterConfig() throws -> RouterConfig {
        guard let defaultBrowserAppURL else {
            AppLogger.error("Preferences model cannot build config without a default browser selection", category: .config)
            throw PreferencesModelError.missingDefaultBrowserSelection
        }

        let validatedDefaultRoute = try validatedDefaultBrowserRouteForSave(defaultBrowserRoute)

        var seenDomains = Set<String>()
        let domainRules = try domainRuleDrafts.map { draft in
            let domain = try normalizedDomain(draft.domain, ruleID: draft.id)
            guard seenDomains.insert(domain).inserted else {
                AppLogger.error("Preferences domain rule \(draft.id) duplicated domain \(domain)", category: .config)
                throw PreferencesModelError.duplicateDomain(draft.id, domain)
            }
            return DomainRule(
                id: draft.id,
                domain: domain,
                target: try makeTarget(
                    id: draft.id,
                    targetSelection: draft.targetSelection,
                    browserRoute: draft.browserRoute
                )
            )
        }

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
            defaultBrowserBundleID: defaultBrowserBundleID,
            defaultBrowserAppURL: defaultBrowserAppURL,
            defaultBrowserRoute: validatedDefaultRoute,
            domainRules: domainRules,
            rules: rules
        )
    }

    private func normalizedDomain(_ value: String, ruleID: UUID) throws -> String {
        guard let domain = DomainRulePattern.normalized(value) else {
            AppLogger.error("Preferences domain rule \(ruleID) had invalid domain '\(value)'", category: .config)
            throw PreferencesModelError.invalidDomain(ruleID, value)
        }
        return domain
    }

    private func validatedDefaultBrowserRouteForSave(_ route: DefaultBrowserRoute) throws -> DefaultBrowserRoute {
        switch route {
        case .plain:
            return .plain
        case let .chromiumProfile(profileDirectory):
            let trimmedProfileDirectory = profileDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedProfileDirectory.isEmpty else {
                AppLogger.error("Default browser route had an empty Chromium profile directory", category: .config)
                throw PreferencesModelError.emptyDefaultBrowserRouteChromiumProfile
            }
            return .chromiumProfile(profileDirectory: trimmedProfileDirectory)
        case let .firefoxProfile(profileKey):
            let trimmedProfileKey = profileKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedProfileKey.isEmpty else {
                AppLogger.error("Default browser route had an empty Firefox profile key", category: .config)
                throw PreferencesModelError.emptyDefaultBrowserRouteFirefoxProfile
            }
            return .firefoxProfile(profileKey: trimmedProfileKey)
        case let .zenContainer(containerName):
            let trimmedContainerName = containerName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedContainerName.isEmpty else {
                AppLogger.error("Default browser route had an empty Zen container name", category: .config)
                throw PreferencesModelError.emptyDefaultBrowserRouteZenContainer
            }
            return .zenContainer(containerName: trimmedContainerName)
        }
    }

    private func makeTarget(for draft: PreferencesRuleDraft) throws -> BrowserTarget {
        try makeTarget(id: draft.id, targetSelection: draft.targetSelection, browserRoute: draft.browserRoute)
    }

    private func makeTarget(
        id: UUID,
        targetSelection: PreferencesRuleTargetSelection,
        browserRoute: DefaultBrowserRoute
    ) throws -> BrowserTarget {
        switch targetSelection {
        case .defaultBrowser:
            switch browserRoute {
            case .plain:
                return .defaultBrowser
            case let .chromiumProfile(profileDirectory):
                let trimmedProfileDirectory = profileDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedProfileDirectory.isEmpty else {
                    AppLogger.error("Preferences rule \(id) had an empty default-browser Chromium profile directory", category: .config)
                    throw PreferencesModelError.emptyRuleChromiumProfile(id)
                }
                return .defaultBrowserChromiumProfile(profileDirectory: trimmedProfileDirectory)
            case let .firefoxProfile(profileKey):
                let trimmedProfileKey = profileKey.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedProfileKey.isEmpty else {
                    AppLogger.error("Preferences rule \(id) had an empty default-browser Firefox profile key", category: .config)
                    throw PreferencesModelError.emptyRuleFirefoxProfile(id)
                }
                return .defaultBrowserFirefoxProfile(profileKey: trimmedProfileKey)
            case let .zenContainer(containerName):
                let trimmedContainerName = containerName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedContainerName.isEmpty else {
                    AppLogger.error("Preferences rule \(id) had an empty Zen container name", category: .config)
                    throw PreferencesModelError.emptyRuleZenContainer(id)
                }
                return .defaultBrowserZenContainer(containerName: trimmedContainerName)
            }
        case let .browser(bundleID, applicationURL):
            let resolvedApplicationURL = try resolvedRuleTargetApplicationURL(
                draftID: id,
                bundleID: bundleID,
                applicationURL: applicationURL
            )
            switch browserRoute {
            case .plain:
                return .application(bundleID: bundleID, applicationURL: resolvedApplicationURL)
            case let .chromiumProfile(profileDirectory):
                let trimmedProfileDirectory = profileDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedProfileDirectory.isEmpty else {
                    AppLogger.error("Preferences rule \(id) had an empty Chromium profile directory", category: .config)
                    throw PreferencesModelError.emptyRuleChromiumProfile(id)
                }
                return .applicationChromiumProfile(
                    bundleID: bundleID,
                    applicationURL: resolvedApplicationURL,
                    profileDirectory: trimmedProfileDirectory
                )
            case let .firefoxProfile(profileKey):
                let trimmedProfileKey = profileKey.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedProfileKey.isEmpty else {
                    AppLogger.error("Preferences rule \(id) had an empty Firefox profile key", category: .config)
                    throw PreferencesModelError.emptyRuleFirefoxProfile(id)
                }
                return .applicationFirefoxProfile(
                    bundleID: bundleID,
                    applicationURL: resolvedApplicationURL,
                    profileKey: trimmedProfileKey
                )
            case let .zenContainer(containerName):
                let trimmedContainerName = containerName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedContainerName.isEmpty else {
                    AppLogger.error("Preferences rule \(id) had an empty Zen container name", category: .config)
                    throw PreferencesModelError.emptyRuleZenContainer(id)
                }
                return .applicationZenContainer(
                    bundleID: bundleID,
                    applicationURL: resolvedApplicationURL,
                    containerName: trimmedContainerName
                )
            }
        }
    }

    private func normalizeDefaultBrowserRuleTargetsForCurrentBrowser() {
        let selectedBundleID = defaultBrowserBundleID
        let defaultCompatibility = defaultBrowserCompatibility(forBundleID: selectedBundleID)

        let defaultCurrent = defaultBrowserRoute
        let defaultNormalized = normalizedDefaultRoute(defaultCurrent, compatibility: defaultCompatibility)
        if defaultNormalized != defaultCurrent {
            AppLogger.info(
                "Normalizing default browser route from \(defaultCurrent.description) to \(defaultNormalized.description) for default browser \(selectedBundleID)",
                category: .config
            )
            defaultBrowserRoute = defaultNormalized
        }

        for index in ruleDrafts.indices {
            let compatibility = switch ruleDrafts[index].targetSelection {
            case .defaultBrowser:
                defaultCompatibility
            case let .browser(bundleID, _):
                defaultBrowserCompatibility(forBundleID: bundleID)
            }
            let currentRoute = ruleDrafts[index].browserRoute
            let normalizedRoute = normalizedDefaultRoute(currentRoute, compatibility: compatibility)
            if normalizedRoute != currentRoute {
                AppLogger.info(
                    "Normalizing browser rule \(ruleDrafts[index].id) from \(currentRoute.description) to \(normalizedRoute.description)",
                    category: .config
                )
                ruleDrafts[index].browserRoute = normalizedRoute
            }
        }


        for index in domainRuleDrafts.indices {
            let compatibility = switch domainRuleDrafts[index].targetSelection {
            case .defaultBrowser:
                defaultCompatibility
            case let .browser(bundleID, _):
                defaultBrowserCompatibility(forBundleID: bundleID)
            }
            let currentRoute = domainRuleDrafts[index].browserRoute
            let normalizedRoute = normalizedDefaultRoute(currentRoute, compatibility: compatibility)
            if normalizedRoute != currentRoute {
                AppLogger.info(
                    "Normalizing domain rule \(domainRuleDrafts[index].id) from \(currentRoute.description) to \(normalizedRoute.description)",
                    category: .config
                )
                domainRuleDrafts[index].browserRoute = normalizedRoute
            }
        }
    }

    private func resolvedRuleTargetApplicationURL(
        draftID: UUID,
        bundleID: String,
        applicationURL: URL?
    ) throws -> URL {
        if let applicationURL {
            return applicationURL
        }

        do {
            let resolvedURL = try launchServicesBridge.applicationURL(forBundleIdentifier: bundleID)
            AppLogger.info(
                "Resolved browser rule \(draftID) target \(bundleID) to \(resolvedURL.path()) via Launch Services",
                category: .config
            )
            return resolvedURL
        } catch {
            AppLogger.error(
                "Could not resolve browser rule \(draftID) target app for \(bundleID): \(error)",
                category: .config
            )
            throw PreferencesModelError.missingRuleTargetApplication(draftID, bundleID: bundleID)
        }
    }

    private func defaultBrowserCompatibility(forBundleID bundleID: String) -> DefaultBrowserProfileSupport {
        DefaultBrowserProfileSupport.forBundleID(bundleID)
    }

    private func normalizedDefaultRoute(
        _ route: DefaultBrowserRoute,
        compatibility: DefaultBrowserProfileSupport
    ) -> DefaultBrowserRoute {
        switch compatibility {
        case .plainOnly:
            return .plain
        case .chromiumProfile:
            switch route {
            case .plain, .chromiumProfile:
                return route
            case .firefoxProfile, .zenContainer:
                return .plain
            }
        case .firefoxProfile:
            switch route {
            case .plain, .firefoxProfile:
                return route
            case .chromiumProfile, .zenContainer:
                return .plain
            }
        case .zenContainer:
            switch route {
            case .plain, .zenContainer:
                return route
            case .chromiumProfile, .firefoxProfile:
                return .plain
            }
        }
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
