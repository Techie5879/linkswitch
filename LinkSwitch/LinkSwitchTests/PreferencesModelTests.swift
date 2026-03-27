import XCTest
@testable import LinkSwitch

final class PreferencesModelTests: XCTestCase {
    @MainActor
    func testLoadPopulatesDraftFromStoredConfig() async throws {
        let config = RouterConfig(
            fallbackBrowserBundleID: "com.apple.Safari",
            fallbackBrowserAppURL: URL(fileURLWithPath: "/Applications/Safari.app"),
            rules: [
                SourceAppRule(
                    id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
                    sourceBundleID: "com.tinyspeck.slackmacgap",
                    target: .helium(profileDirectory: "Profile 1")
                ),
            ]
        )
        let model = PreferencesModel(
            configStore: PreferencesConfigStoreStub(loadResult: config),
            browserLauncher: PreferencesBrowserLauncherSpy(),
            configFileURLDescription: "/tmp/router-config.json"
        )

        try model.load()

        XCTAssertEqual(model.fallbackBrowserBundleID, "com.apple.Safari")
        XCTAssertEqual(model.fallbackBrowserAppURL, URL(fileURLWithPath: "/Applications/Safari.app"))
        XCTAssertEqual(
            model.ruleDrafts,
            [
                PreferencesRuleDraft(
                    id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
                    sourceBundleID: "com.tinyspeck.slackmacgap",
                    targetKind: .helium,
                    heliumProfileDirectory: "Profile 1"
                ),
            ]
        )
    }

    @MainActor
    func testSetFallbackBrowserReadsBundleIdentifierFromApplicationBundle() async throws {
        let applicationURL = try makeApplicationBundle(
            name: "Test Browser",
            bundleIdentifier: "com.example.TestBrowser"
        )
        let model = PreferencesModel(
            configStore: PreferencesConfigStoreStub(loadResult: nil),
            browserLauncher: PreferencesBrowserLauncherSpy(),
            configFileURLDescription: "/tmp/router-config.json"
        )

        try model.setFallbackBrowser(applicationURL: applicationURL)

        XCTAssertEqual(model.fallbackBrowserBundleID, "com.example.TestBrowser")
        XCTAssertEqual(model.fallbackBrowserAppURL, applicationURL)
    }

    @MainActor
    func testSavePersistsValidatedRouterConfig() async throws {
        let store = PreferencesConfigStoreStub(loadResult: nil)
        let model = PreferencesModel(
            configStore: store,
            browserLauncher: PreferencesBrowserLauncherSpy(),
            configFileURLDescription: "/tmp/router-config.json"
        )

        model.fallbackBrowserBundleID = "com.apple.Safari"
        model.fallbackBrowserAppURL = URL(fileURLWithPath: "/Applications/Safari.app")
        let ruleID = model.addRule()
        model.updateRuleSourceBundleID(id: ruleID, value: "com.tinyspeck.slackmacgap")
        model.updateRuleTargetKind(id: ruleID, targetKind: .helium)
        model.updateRuleHeliumProfileDirectory(id: ruleID, value: "Profile 1")

        try model.save()

        XCTAssertEqual(
            store.savedConfig,
            RouterConfig(
                fallbackBrowserBundleID: "com.apple.Safari",
                fallbackBrowserAppURL: URL(fileURLWithPath: "/Applications/Safari.app"),
                rules: [
                    SourceAppRule(
                        id: ruleID,
                        sourceBundleID: "com.tinyspeck.slackmacgap",
                        target: .helium(profileDirectory: "Profile 1")
                    ),
                ]
            )
        )
    }

    @MainActor
    func testSaveThrowsWhenFallbackBrowserIsMissing() async {
        let model = PreferencesModel(
            configStore: PreferencesConfigStoreStub(loadResult: nil),
            browserLauncher: PreferencesBrowserLauncherSpy(),
            configFileURLDescription: "/tmp/router-config.json"
        )

        XCTAssertThrowsError(try model.save()) { error in
            XCTAssertEqual(error as? PreferencesModelError, .missingFallbackBrowserSelection)
        }
    }

    @MainActor
    func testTestFallbackBrowserUsesCurrentDraftConfig() async throws {
        let launcher = PreferencesBrowserLauncherSpy()
        let model = PreferencesModel(
            configStore: PreferencesConfigStoreStub(loadResult: nil),
            browserLauncher: launcher,
            configFileURLDescription: "/tmp/router-config.json"
        )
        model.fallbackBrowserBundleID = "com.apple.Safari"
        model.fallbackBrowserAppURL = URL(fileURLWithPath: "/Applications/Safari.app")
        model.sampleURLString = "https://example.com/fallback"

        try await model.testFallbackBrowser()

        XCTAssertEqual(
            launcher.openCalls,
            [
                PreferencesBrowserLauncherSpy.OpenCall(
                    url: URL(string: "https://example.com/fallback")!,
                    target: .fallbackBrowser,
                    config: RouterConfig(
                        fallbackBrowserBundleID: "com.apple.Safari",
                        fallbackBrowserAppURL: URL(fileURLWithPath: "/Applications/Safari.app"),
                        rules: []
                    )
                ),
            ]
        )
    }

    @MainActor
    func testTestRuleUsesDraftRuleTarget() async throws {
        let launcher = PreferencesBrowserLauncherSpy()
        let model = PreferencesModel(
            configStore: PreferencesConfigStoreStub(loadResult: nil),
            browserLauncher: launcher,
            configFileURLDescription: "/tmp/router-config.json"
        )
        model.fallbackBrowserBundleID = "com.apple.Safari"
        model.fallbackBrowserAppURL = URL(fileURLWithPath: "/Applications/Safari.app")
        model.sampleURLString = "https://example.com/work"
        let ruleID = model.addRule()
        model.updateRuleSourceBundleID(id: ruleID, value: "com.tinyspeck.slackmacgap")
        model.updateRuleTargetKind(id: ruleID, targetKind: .helium)
        model.updateRuleHeliumProfileDirectory(id: ruleID, value: "Profile 1")

        try await model.testRule(id: ruleID)

        XCTAssertEqual(
            launcher.openCalls,
            [
                PreferencesBrowserLauncherSpy.OpenCall(
                    url: URL(string: "https://example.com/work")!,
                    target: .helium(profileDirectory: "Profile 1"),
                    config: RouterConfig(
                        fallbackBrowserBundleID: "com.apple.Safari",
                        fallbackBrowserAppURL: URL(fileURLWithPath: "/Applications/Safari.app"),
                        rules: [
                            SourceAppRule(
                                id: ruleID,
                                sourceBundleID: "com.tinyspeck.slackmacgap",
                                target: .helium(profileDirectory: "Profile 1")
                            ),
                        ]
                    )
                ),
            ]
        )
    }

    @MainActor
    func testCurrentHandlerBundleIDReturnsResolvedBundleID() async throws {
        let provider = PreferencesLaunchServicesProviderSpy()
        provider.defaultHandlerBundleIDsByScheme["https"] = "com.apple.Safari"
        let model = PreferencesModel(
            configStore: PreferencesConfigStoreStub(loadResult: nil),
            browserLauncher: PreferencesBrowserLauncherSpy(),
            configFileURLDescription: "/tmp/router-config.json",
            launchServicesBridge: LaunchServicesBridge(provider: provider)
        )

        XCTAssertEqual(model.currentHandlerBundleID(forURLScheme: "https"), "com.apple.Safari")
    }

    @MainActor
    func testRegisterLinkSwitchAsDefaultHandlerRegistersHTTPAndHTTPS() async throws {
        let provider = PreferencesLaunchServicesProviderSpy()
        let model = PreferencesModel(
            configStore: PreferencesConfigStoreStub(loadResult: nil),
            browserLauncher: PreferencesBrowserLauncherSpy(),
            configFileURLDescription: "/tmp/router-config.json",
            launchServicesBridge: LaunchServicesBridge(provider: provider)
        )
        let applicationURL = URL(fileURLWithPath: "/Applications/LinkSwitch.app")

        try await model.registerLinkSwitchAsDefaultHandler(applicationURL: applicationURL)

        XCTAssertEqual(
            provider.defaultHandlerSetCalls,
            [
                PreferencesLaunchServicesProviderSpy.SetCall(applicationURL: applicationURL, urlScheme: "http"),
                PreferencesLaunchServicesProviderSpy.SetCall(applicationURL: applicationURL, urlScheme: "https"),
            ]
        )
    }

    private func makeApplicationBundle(name: String, bundleIdentifier: String) throws -> URL {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let applicationURL = temporaryDirectory.appendingPathComponent("\(name).app", isDirectory: true)
        let contentsURL = applicationURL.appendingPathComponent("Contents", isDirectory: true)
        let infoPlistURL = contentsURL.appendingPathComponent("Info.plist", isDirectory: false)

        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        let infoPlist: [String: Any] = [
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundlePackageType": "APPL",
            "CFBundleName": name,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: infoPlist, format: .xml, options: 0)
        try data.write(to: infoPlistURL)

        addTeardownBlock {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        return applicationURL
    }
}

private final class PreferencesConfigStoreStub: RouterConfigLoading, RouterConfigSaving {
    let loadResult: RouterConfig?
    private(set) var savedConfig: RouterConfig?

    init(loadResult: RouterConfig?) {
        self.loadResult = loadResult
    }

    func load() throws -> RouterConfig? {
        loadResult
    }

    func save(_ config: RouterConfig) throws {
        savedConfig = config
    }
}

private final class PreferencesBrowserLauncherSpy: BrowserLaunching {
    struct OpenCall: Equatable {
        let url: URL
        let target: BrowserTarget
        let config: RouterConfig
    }

    private(set) var openCalls: [OpenCall] = []

    func open(_ url: URL, target: BrowserTarget, config: RouterConfig) async throws {
        openCalls.append(OpenCall(url: url, target: target, config: config))
    }
}

private final class PreferencesLaunchServicesProviderSpy: LaunchServicesProviding {
    struct SetCall: Equatable {
        let applicationURL: URL
        let urlScheme: String
    }

    var defaultHandlerBundleIDsByScheme: [String: String] = [:]
    private(set) var defaultHandlerSetCalls: [SetCall] = []

    func defaultHandlerBundleID(forURLScheme urlScheme: String) -> String? {
        defaultHandlerBundleIDsByScheme[urlScheme]
    }

    func applicationURL(forBundleIdentifier bundleID: String) -> URL? {
        nil
    }

    func setDefaultHandler(applicationURL: URL, urlScheme: String) async throws {
        defaultHandlerSetCalls.append(SetCall(applicationURL: applicationURL, urlScheme: urlScheme))
    }
}
