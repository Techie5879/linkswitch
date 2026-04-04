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

        preferencesModel.defaultBrowserBundleID = "com.apple.Safari"
        preferencesModel.defaultBrowserAppURL = URL(fileURLWithPath: "/Applications/Safari.app")
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
                        defaultBrowserBundleID: "com.apple.Safari",
                        defaultBrowserAppURL: URL(fileURLWithPath: "/Applications/Safari.app"),
                        defaultBrowserRoute: .plain,
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
    func testSavedPreferencesConfigRoutesMultipleSavedSourceRulesToTheirTargets() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        let configFileURL = temporaryDirectory.appendingPathComponent("router-config.json", isDirectory: false)
        let configStore = RouterConfigStore(configFileURL: configFileURL)
        let preferencesModel = PreferencesModel(
            configStore: configStore,
            browserLauncher: RoutingPipelineBrowserLauncherSpy(),
            configFileURLDescription: configFileURL.path()
        )

        preferencesModel.defaultBrowserBundleID = "com.apple.Safari"
        preferencesModel.defaultBrowserAppURL = URL(fileURLWithPath: "/Applications/Safari.app")

        let slackRuleID = preferencesModel.addRule()
        preferencesModel.updateRuleSourceBundleID(id: slackRuleID, value: "com.tinyspeck.slackmacgap")
        preferencesModel.updateRuleTargetKind(id: slackRuleID, targetKind: .helium)
        preferencesModel.updateRuleHeliumProfileDirectory(id: slackRuleID, value: "Aritra")

        let notionRuleID = preferencesModel.addRule()
        preferencesModel.updateRuleSourceBundleID(id: notionRuleID, value: "notion.id")
        preferencesModel.updateRuleTargetKind(id: notionRuleID, targetKind: .helium)
        preferencesModel.updateRuleHeliumProfileDirectory(id: notionRuleID, value: "Brighterway")

        try preferencesModel.save()

        let browserLauncher = RoutingPipelineBrowserLauncherSpy()
        let intakeController = URLIntakeController(
            configStore: RouterConfigStore(configFileURL: configFileURL),
            ruleEngine: RuleEngine(),
            browserLauncher: browserLauncher
        )

        try await intakeController.handle(
            urls: [URL(string: "https://example.com/from-slack")!],
            sourceBundleID: "com.tinyspeck.slackmacgap"
        )
        try await intakeController.handle(
            urls: [URL(string: "https://example.com/from-notion")!],
            sourceBundleID: "notion.id"
        )

        let savedConfig = RouterConfig(
            defaultBrowserBundleID: "com.apple.Safari",
            defaultBrowserAppURL: URL(fileURLWithPath: "/Applications/Safari.app"),
            defaultBrowserRoute: .plain,
            rules: [
                SourceAppRule(
                    id: slackRuleID,
                    sourceBundleID: "com.tinyspeck.slackmacgap",
                    target: .helium(profileDirectory: "Aritra")
                ),
                SourceAppRule(
                    id: notionRuleID,
                    sourceBundleID: "notion.id",
                    target: .helium(profileDirectory: "Brighterway")
                ),
            ]
        )

        XCTAssertEqual(
            browserLauncher.openCalls,
            [
                RoutingPipelineBrowserLauncherSpy.OpenCall(
                    url: URL(string: "https://example.com/from-slack")!,
                    target: .helium(profileDirectory: "Aritra"),
                    config: savedConfig
                ),
                RoutingPipelineBrowserLauncherSpy.OpenCall(
                    url: URL(string: "https://example.com/from-notion")!,
                    target: .helium(profileDirectory: "Brighterway"),
                    config: savedConfig
                ),
            ]
        )
    }

    @MainActor
    func testSavedPreferencesConfigRoutesUnknownSourceToDefaultBrowser() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        let configFileURL = temporaryDirectory.appendingPathComponent("router-config.json", isDirectory: false)
        let configStore = RouterConfigStore(configFileURL: configFileURL)
        let preferencesModel = PreferencesModel(
            configStore: configStore,
            browserLauncher: RoutingPipelineBrowserLauncherSpy(),
            configFileURLDescription: configFileURL.path()
        )

        preferencesModel.defaultBrowserBundleID = "com.apple.Safari"
        preferencesModel.defaultBrowserAppURL = URL(fileURLWithPath: "/Applications/Safari.app")
        try preferencesModel.save()

        let browserLauncher = RoutingPipelineBrowserLauncherSpy()
        let intakeController = URLIntakeController(
            configStore: RouterConfigStore(configFileURL: configFileURL),
            ruleEngine: RuleEngine(),
            browserLauncher: browserLauncher
        )

        try await intakeController.handle(
            urls: [URL(string: "https://example.com/default-browser")!],
            sourceBundleID: "com.apple.mail"
        )

        XCTAssertEqual(
            browserLauncher.openCalls,
            [
                RoutingPipelineBrowserLauncherSpy.OpenCall(
                    url: URL(string: "https://example.com/default-browser")!,
                    target: .defaultBrowser,
                    config: RouterConfig(
                        defaultBrowserBundleID: "com.apple.Safari",
                        defaultBrowserAppURL: URL(fileURLWithPath: "/Applications/Safari.app"),
                        defaultBrowserRoute: .plain,
                        rules: []
                    )
                ),
            ]
        )
    }

    @MainActor
    func testSavedPreferencesConfigRoutesUnknownSourceToConfiguredDefaultBrowserFirefoxProfile() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        let configFileURL = temporaryDirectory.appendingPathComponent("router-config.json", isDirectory: false)
        let configStore = RouterConfigStore(configFileURL: configFileURL)
        let preferencesModel = PreferencesModel(
            configStore: configStore,
            browserLauncher: RoutingPipelineBrowserLauncherSpy(),
            configFileURLDescription: configFileURL.path()
        )

        preferencesModel.defaultBrowserBundleID = "org.mozilla.firefox"
        preferencesModel.defaultBrowserAppURL = URL(fileURLWithPath: "/Applications/Firefox.app")
        preferencesModel.updateDefaultBrowserRoute(.firefoxProfile(profileKey: "Profiles/work.default"))
        try preferencesModel.save()

        let browserLauncher = RoutingPipelineBrowserLauncherSpy()
        let intakeController = URLIntakeController(
            configStore: RouterConfigStore(configFileURL: configFileURL),
            ruleEngine: RuleEngine(),
            browserLauncher: browserLauncher
        )

        try await intakeController.handle(
            urls: [URL(string: "https://example.com/default-browser")!],
            sourceBundleID: "com.apple.mail"
        )

        XCTAssertEqual(
            browserLauncher.openCalls,
            [
                RoutingPipelineBrowserLauncherSpy.OpenCall(
                    url: URL(string: "https://example.com/default-browser")!,
                    target: .defaultBrowserFirefoxProfile(profileKey: "Profiles/work.default"),
                    config: RouterConfig(
                        defaultBrowserBundleID: "org.mozilla.firefox",
                        defaultBrowserAppURL: URL(fileURLWithPath: "/Applications/Firefox.app"),
                        defaultBrowserRoute: .firefoxProfile(profileKey: "Profiles/work.default"),
                        rules: []
                    )
                ),
            ]
        )
    }

    @MainActor
    func testSavedPreferencesConfigRoutesUnknownSourceToConfiguredDefaultBrowserHeliumProfile() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        let configFileURL = temporaryDirectory.appendingPathComponent("router-config.json", isDirectory: false)
        let configStore = RouterConfigStore(configFileURL: configFileURL)
        let preferencesModel = PreferencesModel(
            configStore: configStore,
            browserLauncher: RoutingPipelineBrowserLauncherSpy(),
            configFileURLDescription: configFileURL.path()
        )

        preferencesModel.defaultBrowserBundleID = BrowserLauncher.heliumBundleID
        preferencesModel.defaultBrowserAppURL = URL(fileURLWithPath: "/Applications/Helium.app")
        preferencesModel.updateDefaultBrowserRoute(.heliumProfile(profileDirectory: "Profile 1"))
        try preferencesModel.save()

        let browserLauncher = RoutingPipelineBrowserLauncherSpy()
        let intakeController = URLIntakeController(
            configStore: RouterConfigStore(configFileURL: configFileURL),
            ruleEngine: RuleEngine(),
            browserLauncher: browserLauncher
        )

        try await intakeController.handle(
            urls: [URL(string: "https://example.com/default-browser-helium")!],
            sourceBundleID: "com.apple.mail"
        )

        XCTAssertEqual(
            browserLauncher.openCalls,
            [
                RoutingPipelineBrowserLauncherSpy.OpenCall(
                    url: URL(string: "https://example.com/default-browser-helium")!,
                    target: .defaultBrowserHeliumProfile(profileDirectory: "Profile 1"),
                    config: RouterConfig(
                        defaultBrowserBundleID: BrowserLauncher.heliumBundleID,
                        defaultBrowserAppURL: URL(fileURLWithPath: "/Applications/Helium.app"),
                        defaultBrowserRoute: .heliumProfile(profileDirectory: "Profile 1"),
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
