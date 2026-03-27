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
    var heliumProfileDirectory: String
}

enum PreferencesModelError: Error, Equatable {
    case missingFallbackBrowserSelection
    case fallbackBrowserBundleIdentifierNotFound(applicationURL: URL)
    case linkSwitchBundleIdentifierNotFound(applicationURL: URL)
    case invalidSampleURL(String)
    case ruleNotFound(UUID)
    case emptySourceBundleID(UUID)
    case emptyHeliumProfileDirectory(UUID)
}

@MainActor
final class PreferencesModel {
    private let configStore: any RouterConfigLoading & RouterConfigSaving
    private let browserLauncher: any BrowserLaunching
    private let launchServicesBridge: LaunchServicesBridge

    let configFileURLDescription: String
    var fallbackBrowserBundleID = ""
    var fallbackBrowserAppURL: URL?
    var sampleURLString = "https://example.com"
    private(set) var ruleDrafts: [PreferencesRuleDraft] = []

    init(
        configStore: any RouterConfigLoading & RouterConfigSaving,
        browserLauncher: any BrowserLaunching,
        configFileURLDescription: String,
        launchServicesBridge: LaunchServicesBridge = LaunchServicesBridge()
    ) {
        self.configStore = configStore
        self.browserLauncher = browserLauncher
        self.configFileURLDescription = configFileURLDescription
        self.launchServicesBridge = launchServicesBridge
    }

    static func live() throws -> PreferencesModel {
        let store = RouterConfigStore(configFileURL: try RouterConfigStore.defaultConfigFileURL())
        return PreferencesModel(
            configStore: store,
            browserLauncher: BrowserLauncher(),
            configFileURLDescription: store.configFileURL.path(),
            launchServicesBridge: LaunchServicesBridge()
        )
    }

    func load() throws {
        AppLogger.info("Loading preferences model from \(configFileURLDescription)", category: .config)
        guard let config = try configStore.load() else {
            AppLogger.info("No router config exists yet; preferences model will start empty", category: .config)
            fallbackBrowserBundleID = ""
            fallbackBrowserAppURL = nil
            ruleDrafts = []
            return
        }

        fallbackBrowserBundleID = config.fallbackBrowserBundleID
        fallbackBrowserAppURL = config.fallbackBrowserAppURL
        ruleDrafts = config.rules.map { rule in
            switch rule.target {
            case .fallbackBrowser:
                return PreferencesRuleDraft(
                    id: rule.id,
                    sourceBundleID: rule.sourceBundleID,
                    targetKind: .fallbackBrowser,
                    heliumProfileDirectory: ""
                )
            case let .helium(profileDirectory):
                return PreferencesRuleDraft(
                    id: rule.id,
                    sourceBundleID: rule.sourceBundleID,
                    targetKind: .helium,
                    heliumProfileDirectory: profileDirectory
                )
            }
        }
    }

    func setFallbackBrowser(applicationURL: URL) throws {
        AppLogger.info("Setting fallback browser from selected app \(applicationURL.path())", category: .config)
        guard let bundleID = Bundle(url: applicationURL)?.bundleIdentifier else {
            AppLogger.error("Selected fallback browser app did not expose a bundle ID: \(applicationURL.path())", category: .config)
            throw PreferencesModelError.fallbackBrowserBundleIdentifierNotFound(applicationURL: applicationURL)
        }

        fallbackBrowserBundleID = bundleID
        fallbackBrowserAppURL = applicationURL
    }

    @discardableResult
    func addRule() -> UUID {
        let ruleID = UUID()
        ruleDrafts.append(
            PreferencesRuleDraft(
                id: ruleID,
                sourceBundleID: "",
                targetKind: .fallbackBrowser,
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
            }
        }
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
        AppLogger.info("Testing fallback browser launch with URL \(sampleURL.absoluteString)", category: .launch)
        try await browserLauncher.open(sampleURL, target: .fallbackBrowser, config: config)
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
            rules: rules
        )
    }

    private func makeTarget(for draft: PreferencesRuleDraft) throws -> BrowserTarget {
        switch draft.targetKind {
        case .fallbackBrowser:
            return .fallbackBrowser
        case .helium:
            let trimmedProfileDirectory = draft.heliumProfileDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedProfileDirectory.isEmpty else {
                AppLogger.error("Preferences rule \(draft.id) had an empty Helium profile directory", category: .config)
                throw PreferencesModelError.emptyHeliumProfileDirectory(draft.id)
            }
            return .helium(profileDirectory: trimmedProfileDirectory)
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
