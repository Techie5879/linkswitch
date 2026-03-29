import XCTest
@testable import LinkSwitch

final class RoutingPipelineIntegrationTests: XCTestCase {
    @MainActor
    func testSavedPreferencesConfigRoutesMatchingSourceToHelium() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        let configFileURL = temporaryDirectory.appendingPathComponent("router-config.json", isDirectory: false)
        let configStore = RouterConfigStore(configFileURL: configFileURL)
        let preferencesModel = PreferencesModel(
            configStore: configStore,
            browserLauncher: RoutingPipelineBrowserLauncherSpy(),
            configFileURLDescription: configFileURL.path()
        )

        preferencesModel.fallbackBrowserBundleID = "com.apple.Safari"
        preferencesModel.fallbackBrowserAppURL = URL(fileURLWithPath: "/Applications/Safari.app")
        let ruleID = preferencesModel.addRule()
        preferencesModel.updateRuleSourceBundleID(id: ruleID, value: "com.tinyspeck.slackmacgap")
        preferencesModel.updateRuleTargetKind(id: ruleID, targetKind: .helium)
        preferencesModel.updateRuleHeliumProfileDirectory(id: ruleID, value: "Profile 1")
        try preferencesModel.save()

        let browserLauncher = RoutingPipelineBrowserLauncherSpy()
        let intakeController = URLIntakeController(
            configStore: RouterConfigStore(configFileURL: configFileURL),
            ruleEngine: RuleEngine(),
            browserLauncher: browserLauncher
        )

        try await intakeController.handle(
            urls: [URL(string: "https://example.com/work")!],
            sourceBundleID: "com.tinyspeck.slackmacgap"
        )

        XCTAssertEqual(
            browserLauncher.openCalls,
            [
                RoutingPipelineBrowserLauncherSpy.OpenCall(
                    url: URL(string: "https://example.com/work")!,
                    target: .helium(profileDirectory: "Profile 1"),
                    config: RouterConfig(
                        fallbackBrowserBundleID: "com.apple.Safari",
                        fallbackBrowserAppURL: URL(fileURLWithPath: "/Applications/Safari.app"),
                        fallbackBrowserRoute: .plain,
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
    func testSavedPreferencesConfigRoutesUnknownSourceToFallbackBrowser() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        let configFileURL = temporaryDirectory.appendingPathComponent("router-config.json", isDirectory: false)
        let configStore = RouterConfigStore(configFileURL: configFileURL)
        let preferencesModel = PreferencesModel(
            configStore: configStore,
            browserLauncher: RoutingPipelineBrowserLauncherSpy(),
            configFileURLDescription: configFileURL.path()
        )

        preferencesModel.fallbackBrowserBundleID = "com.apple.Safari"
        preferencesModel.fallbackBrowserAppURL = URL(fileURLWithPath: "/Applications/Safari.app")
        try preferencesModel.save()

        let browserLauncher = RoutingPipelineBrowserLauncherSpy()
        let intakeController = URLIntakeController(
            configStore: RouterConfigStore(configFileURL: configFileURL),
            ruleEngine: RuleEngine(),
            browserLauncher: browserLauncher
        )

        try await intakeController.handle(
            urls: [URL(string: "https://example.com/fallback")!],
            sourceBundleID: "com.apple.mail"
        )

        XCTAssertEqual(
            browserLauncher.openCalls,
            [
                RoutingPipelineBrowserLauncherSpy.OpenCall(
                    url: URL(string: "https://example.com/fallback")!,
                    target: .fallbackBrowser,
                    config: RouterConfig(
                        fallbackBrowserBundleID: "com.apple.Safari",
                        fallbackBrowserAppURL: URL(fileURLWithPath: "/Applications/Safari.app"),
                        fallbackBrowserRoute: .plain,
                        rules: []
                    )
                ),
            ]
        )
    }

    @MainActor
    func testSavedPreferencesConfigRoutesUnknownSourceToConfiguredFallbackFirefoxProfile() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        let configFileURL = temporaryDirectory.appendingPathComponent("router-config.json", isDirectory: false)
        let configStore = RouterConfigStore(configFileURL: configFileURL)
        let preferencesModel = PreferencesModel(
            configStore: configStore,
            browserLauncher: RoutingPipelineBrowserLauncherSpy(),
            configFileURLDescription: configFileURL.path()
        )

        preferencesModel.fallbackBrowserBundleID = "org.mozilla.firefox"
        preferencesModel.fallbackBrowserAppURL = URL(fileURLWithPath: "/Applications/Firefox.app")
        preferencesModel.updateFallbackBrowserRoute(.firefoxProfile(profileKey: "Profiles/work.default"))
        try preferencesModel.save()

        let browserLauncher = RoutingPipelineBrowserLauncherSpy()
        let intakeController = URLIntakeController(
            configStore: RouterConfigStore(configFileURL: configFileURL),
            ruleEngine: RuleEngine(),
            browserLauncher: browserLauncher
        )

        try await intakeController.handle(
            urls: [URL(string: "https://example.com/fallback")!],
            sourceBundleID: "com.apple.mail"
        )

        XCTAssertEqual(
            browserLauncher.openCalls,
            [
                RoutingPipelineBrowserLauncherSpy.OpenCall(
                    url: URL(string: "https://example.com/fallback")!,
                    target: .fallbackBrowserFirefoxProfile(profileKey: "Profiles/work.default"),
                    config: RouterConfig(
                        fallbackBrowserBundleID: "org.mozilla.firefox",
                        fallbackBrowserAppURL: URL(fileURLWithPath: "/Applications/Firefox.app"),
                        fallbackBrowserRoute: .firefoxProfile(profileKey: "Profiles/work.default"),
                        rules: []
                    )
                ),
            ]
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        return temporaryDirectory
    }
}

private final class RoutingPipelineBrowserLauncherSpy: BrowserLaunching {
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
