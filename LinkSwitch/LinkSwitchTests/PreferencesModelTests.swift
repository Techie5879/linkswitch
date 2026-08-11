import XCTest
@testable import LinkSwitch

final class PreferencesModelTests: XCTestCase {
    @MainActor
    func testLoadPopulatesDraftFromStoredConfig() async throws {
        let config = RouterConfig(
            defaultBrowserBundleID: FirefoxBrowserAppSupportPath.zenBrowserBundleID,
            defaultBrowserAppURL: URL(fileURLWithPath: "/Applications/Zen.app"),
            defaultBrowserRoute: .zenContainer(containerName: "Work"),
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
            configFileURLDescription: "/tmp/router-config.json",
            browserDiscovery: StubBrowserDiscovering(browsers: [
                DiscoveredBrowser(
                    bundleID: BrowserLauncher.heliumBundleID,
                    name: "Helium",
                    appURL: URL(fileURLWithPath: "/Applications/Helium.app")
                ),
            ]),
            installedApplicationDiscovery: StubInstalledApplicationDiscovering(applications: [])
        )

        try model.load()

        XCTAssertEqual(model.defaultBrowserBundleID, FirefoxBrowserAppSupportPath.zenBrowserBundleID)
        XCTAssertEqual(model.defaultBrowserAppURL, URL(fileURLWithPath: "/Applications/Zen.app"))
        XCTAssertEqual(model.defaultBrowserRoute, .zenContainer(containerName: "Work"))
        XCTAssertEqual(
            model.ruleDrafts,
            [
                PreferencesRuleDraft(
                    id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
                    sourceBundleID: "com.tinyspeck.slackmacgap",
                    targetSelection: .browser(
                        bundleID: BrowserLauncher.heliumBundleID,
                        applicationURL: URL(fileURLWithPath: "/Applications/Helium.app")
                    ),
                    browserRoute: .chromiumProfile(profileDirectory: "Profile 1")
                ),
            ]
        )
    }

    @MainActor
    func testLoadPopulatesDomainRuleDraftFromStoredConfig() throws {
        let ruleID = UUID(uuidString: "99999999-AAAA-BBBB-CCCC-DDDDDDDDDDDD")!
        let config = RouterConfig(
            defaultBrowserBundleID: "com.apple.Safari",
            defaultBrowserAppURL: URL(fileURLWithPath: "/Applications/Safari.app"),
            defaultBrowserRoute: .plain,
            domainRules: [
                DomainRule(
                    id: ruleID,
                    domain: "example.com",
                    target: .defaultBrowser
                ),
            ],
            rules: []
        )
        let model = PreferencesModel(
            configStore: PreferencesConfigStoreStub(loadResult: config),
            browserLauncher: PreferencesBrowserLauncherSpy(),
            configFileURLDescription: "/tmp/router-config.json",
            browserDiscovery: StubBrowserDiscovering(browsers: []),
            installedApplicationDiscovery: StubInstalledApplicationDiscovering(applications: [])
        )

        try model.load()

        XCTAssertEqual(
            model.domainRuleDrafts,
            [
                PreferencesDomainRuleDraft(
                    id: ruleID,
                    domain: "example.com",
                    targetSelection: .defaultBrowser,
                    browserRoute: .plain
                ),
            ]
        )
    }

    @MainActor
    func testLoadPopulatesDefaultBrowserFirefoxProfileRuleFromStoredConfig() throws {
        let config = RouterConfig(
            defaultBrowserBundleID: "org.mozilla.firefox",
            defaultBrowserAppURL: URL(fileURLWithPath: "/Applications/Firefox.app"),
            defaultBrowserRoute: .plain,
            rules: [
                SourceAppRule(
                    id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
                    sourceBundleID: "com.apple.mail",
                    target: .defaultBrowserFirefoxProfile(profileKey: "Profiles/work.default")
                ),
            ]
        )
        let model = PreferencesModel(
            configStore: PreferencesConfigStoreStub(loadResult: config),
            browserLauncher: PreferencesBrowserLauncherSpy(),
            configFileURLDescription: "/tmp/router-config.json",
            browserDiscovery: StubBrowserDiscovering(browsers: []),
            installedApplicationDiscovery: StubInstalledApplicationDiscovering(applications: [])
        )

        try model.load()

        XCTAssertEqual(
            model.ruleDrafts,
            [
                PreferencesRuleDraft(
                    id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
                    sourceBundleID: "com.apple.mail",
                    targetSelection: .defaultBrowser,
                    browserRoute: .firefoxProfile(profileKey: "Profiles/work.default")
                ),
            ]
        )
    }

    @MainActor
    func testLoadPopulatesDefaultBrowserChromiumProfileSelectionsFromStoredConfig() throws {
        let config = RouterConfig(
            defaultBrowserBundleID: BrowserLauncher.heliumBundleID,
            defaultBrowserAppURL: URL(fileURLWithPath: "/Applications/Helium.app"),
            defaultBrowserRoute: .chromiumProfile(profileDirectory: "Profile 1"),
            rules: [
                SourceAppRule(
                    id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
                    sourceBundleID: "com.apple.mail",
                    target: .defaultBrowserChromiumProfile(profileDirectory: "Profile 2")
                ),
            ]
        )
        let model = PreferencesModel(
            configStore: PreferencesConfigStoreStub(loadResult: config),
            browserLauncher: PreferencesBrowserLauncherSpy(),
            configFileURLDescription: "/tmp/router-config.json",
            browserDiscovery: StubBrowserDiscovering(browsers: []),
            installedApplicationDiscovery: StubInstalledApplicationDiscovering(applications: [])
        )

        try model.load()

        XCTAssertEqual(model.defaultBrowserRoute, .chromiumProfile(profileDirectory: "Profile 1"))
        XCTAssertEqual(
            model.ruleDrafts,
            [
                PreferencesRuleDraft(
                    id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
                    sourceBundleID: "com.apple.mail",
                    targetSelection: .defaultBrowser,
                    browserRoute: .chromiumProfile(profileDirectory: "Profile 2")
                ),
            ]
        )
    }

    @MainActor
    func testLoadReadsDefaultBrowserRouteFromConfigFile() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        let configFileURL = temporaryDirectory.appendingPathComponent("router-config.json", isDirectory: false)
        let expectedConfig = RouterConfig(
            defaultBrowserBundleID: "app.zen-browser.zen",
            defaultBrowserAppURL: URL(fileURLWithPath: "/Applications/Zen.app"),
            defaultBrowserRoute: .zenContainer(containerName: "Work"),
            rules: [
                SourceAppRule(
                    id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
                    sourceBundleID: "com.tinyspeck.slackmacgap",
                    target: .helium(profileDirectory: "Profile 1")
                ),
            ]
        )
        let store = RouterConfigStore(configFileURL: configFileURL)
        try store.save(expectedConfig)

        let model = PreferencesModel(
            configStore: RouterConfigStore(configFileURL: configFileURL),
            browserLauncher: PreferencesBrowserLauncherSpy(),
            configFileURLDescription: configFileURL.path(percentEncoded: false),
            browserDiscovery: StubBrowserDiscovering(browsers: [
                DiscoveredBrowser(
                    bundleID: BrowserLauncher.heliumBundleID,
                    name: "Helium",
                    appURL: URL(fileURLWithPath: "/Applications/Helium.app")
                ),
            ]),
            installedApplicationDiscovery: StubInstalledApplicationDiscovering(applications: [])
        )

        try model.load()

        XCTAssertEqual(model.defaultBrowserBundleID, expectedConfig.defaultBrowserBundleID)
        XCTAssertEqual(model.defaultBrowserAppURL, expectedConfig.defaultBrowserAppURL)
        XCTAssertEqual(model.defaultBrowserRoute, .zenContainer(containerName: "Work"))
        XCTAssertEqual(
            model.ruleDrafts,
            [
                PreferencesRuleDraft(
                    id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
                    sourceBundleID: "com.tinyspeck.slackmacgap",
                    targetSelection: .browser(
                        bundleID: BrowserLauncher.heliumBundleID,
                        applicationURL: URL(fileURLWithPath: "/Applications/Helium.app")
                    ),
                    browserRoute: .chromiumProfile(profileDirectory: "Profile 1")
                ),
            ]
        )
    }

    @MainActor
    func testSetDefaultBrowserReadsBundleIdentifierFromApplicationBundle() async throws {
        let applicationURL = try makeApplicationBundle(
            name: "Test Browser",
            bundleIdentifier: "com.example.TestBrowser"
        )
        let model = PreferencesModel(
            configStore: PreferencesConfigStoreStub(loadResult: nil),
            browserLauncher: PreferencesBrowserLauncherSpy(),
            configFileURLDescription: "/tmp/router-config.json",
            browserDiscovery: StubBrowserDiscovering(browsers: [])
        )

        try model.setDefaultBrowser(applicationURL: applicationURL)

        XCTAssertEqual(model.defaultBrowserBundleID, "com.example.TestBrowser")
        XCTAssertEqual(model.defaultBrowserAppURL, applicationURL)
    }

    @MainActor
    func testSetDefaultBrowserFromDiscoveredBrowserUpdatesBundleIDAndAppURL() {
        let browserURL = URL(fileURLWithPath: "/Applications/TestBrowser.app")
        let discovered = DiscoveredBrowser(bundleID: "com.example.TestBrowser", name: "Test Browser", appURL: browserURL)
        let model = PreferencesModel(
            configStore: PreferencesConfigStoreStub(loadResult: nil),
            browserLauncher: PreferencesBrowserLauncherSpy(),
            configFileURLDescription: "/tmp/router-config.json",
            browserDiscovery: StubBrowserDiscovering(browsers: [discovered])
        )

        model.setDefaultBrowser(discoveredBrowser: discovered)

        XCTAssertEqual(model.defaultBrowserBundleID, "com.example.TestBrowser")
        XCTAssertEqual(model.defaultBrowserAppURL, browserURL)
    }

    @MainActor
    func testLoadPopulatesDiscoveredBrowsersFromDiscovery() throws {
        let browserURL = URL(fileURLWithPath: "/Applications/TestBrowser.app")
        let discovered = DiscoveredBrowser(bundleID: "com.example.TestBrowser", name: "Test Browser", appURL: browserURL)
        let model = PreferencesModel(
            configStore: PreferencesConfigStoreStub(loadResult: nil),
            browserLauncher: PreferencesBrowserLauncherSpy(),
            configFileURLDescription: "/tmp/router-config.json",
            browserDiscovery: StubBrowserDiscovering(browsers: [discovered]),
            installedApplicationDiscovery: StubInstalledApplicationDiscovering(applications: [])
        )

        try model.load()

        XCTAssertEqual(model.discoveredBrowsers, [discovered])
    }

    @MainActor
    func testLoadPopulatesDiscoveredApplicationsFromDiscovery() throws {
        let appURL = URL(fileURLWithPath: "/Applications/Slack.app")
        let slack = DiscoveredApplication(bundleID: "com.tinyspeck.slackmacgap", name: "Slack", appURL: appURL)
        let model = PreferencesModel(
            configStore: PreferencesConfigStoreStub(loadResult: nil),
            browserLauncher: PreferencesBrowserLauncherSpy(),
            configFileURLDescription: "/tmp/router-config.json",
            browserDiscovery: StubBrowserDiscovering(browsers: []),
            installedApplicationDiscovery: StubInstalledApplicationDiscovering(applications: [slack])
        )

        try model.load()

        XCTAssertEqual(model.discoveredApplications, [slack])
    }

    @MainActor
    func testRefreshInstalledApplicationsUpdatesApplicationsList() {
        let appURL = URL(fileURLWithPath: "/Applications/Slack.app")
        let slack = DiscoveredApplication(bundleID: "com.tinyspeck.slackmacgap", name: "Slack", appURL: appURL)
        let stub = StubInstalledApplicationDiscovering(applications: [slack])
        let model = PreferencesModel(
            configStore: PreferencesConfigStoreStub(loadResult: nil),
            browserLauncher: PreferencesBrowserLauncherSpy(),
            configFileURLDescription: "/tmp/router-config.json",
            installedApplicationDiscovery: stub
        )

        XCTAssertTrue(model.discoveredApplications.isEmpty)
        model.refreshInstalledApplications()
        XCTAssertEqual(model.discoveredApplications, [slack])
    }

    @MainActor
    func testRefreshDiscoveredBrowsersUpdatesDiscoveredBrowsersList() {
        let browserURL = URL(fileURLWithPath: "/Applications/TestBrowser.app")
        let discovered = DiscoveredBrowser(bundleID: "com.example.TestBrowser", name: "Test Browser", appURL: browserURL)
        let stub = StubBrowserDiscovering(browsers: [discovered])
        let model = PreferencesModel(
            configStore: PreferencesConfigStoreStub(loadResult: nil),
            browserLauncher: PreferencesBrowserLauncherSpy(),
            configFileURLDescription: "/tmp/router-config.json",
            browserDiscovery: stub
        )

        XCTAssertTrue(model.discoveredBrowsers.isEmpty)
        model.refreshDiscoveredBrowsers()
        XCTAssertEqual(model.discoveredBrowsers, [discovered])
    }

    @MainActor
    func testSavePersistsValidatedRouterConfig() async throws {
        let store = PreferencesConfigStoreStub(loadResult: nil)
        let model = PreferencesModel(
            configStore: store,
            browserLauncher: PreferencesBrowserLauncherSpy(),
            configFileURLDescription: "/tmp/router-config.json"
        )

        model.defaultBrowserBundleID = "com.apple.Safari"
        model.defaultBrowserAppURL = URL(fileURLWithPath: "/Applications/Safari.app")
        let ruleID = model.addRule()
        model.updateRuleSourceBundleID(id: ruleID, value: "com.tinyspeck.slackmacgap")
        model.updateRuleBrowserRoute(id: ruleID, route: .zenContainer(containerName: "Work"))
        let firefoxURL = try makeApplicationBundle(
            name: "Firefox",
            bundleIdentifier: "org.mozilla.firefox"
        )
        try model.setDefaultBrowser(applicationURL: firefoxURL)

        try model.save()

        XCTAssertEqual(
            store.savedConfig,
            RouterConfig(
                defaultBrowserBundleID: "org.mozilla.firefox",
                defaultBrowserAppURL: firefoxURL,
                defaultBrowserRoute: .plain,
                rules: [
                    SourceAppRule(
                        id: ruleID,
                        sourceBundleID: "com.tinyspeck.slackmacgap",
                        target: .defaultBrowser
                    ),
                ]
            )
        )
    }

    @MainActor
    func testSaveNormalizesAndPersistsDomainRule() throws {
        let store = PreferencesConfigStoreStub(loadResult: nil)
        let model = PreferencesModel(
            configStore: store,
            browserLauncher: PreferencesBrowserLauncherSpy(),
            configFileURLDescription: "/tmp/router-config.json"
        )
        let safariURL = try makeApplicationBundle(name: "Safari", bundleIdentifier: "com.apple.Safari")
        try model.setDefaultBrowser(applicationURL: safariURL)
        let ruleID = model.addDomainRule()
        model.updateDomainRuleDomain(id: ruleID, value: "  Docs.Example.COM.  ")

        try model.save()

        XCTAssertEqual(
            store.savedConfig?.domainRules,
            [DomainRule(id: ruleID, domain: "docs.example.com", target: .defaultBrowser)]
        )
    }

    @MainActor
    func testConfigValidationRejectsInvalidAndDuplicateDomains() throws {
        let model = PreferencesModel(
            configStore: PreferencesConfigStoreStub(loadResult: nil),
            browserLauncher: PreferencesBrowserLauncherSpy(),
            configFileURLDescription: "/tmp/router-config.json"
        )
        let safariURL = try makeApplicationBundle(name: "Safari", bundleIdentifier: "com.apple.Safari")
        try model.setDefaultBrowser(applicationURL: safariURL)
        let firstRuleID = model.addDomainRule()
        model.updateDomainRuleDomain(id: firstRuleID, value: "https://example.com/path")

        XCTAssertEqual(
            model.configValidationMessage(),
            "Domain rule \(firstRuleID.uuidString) has an invalid domain 'https://example.com/path'. Enter a hostname such as example.com."
        )

        model.updateDomainRuleDomain(id: firstRuleID, value: "EXAMPLE.com")
        let secondRuleID = model.addDomainRule()
        model.updateDomainRuleDomain(id: secondRuleID, value: "example.com.")

        XCTAssertEqual(
            model.configValidationMessage(),
            "Domain rule \(secondRuleID.uuidString) duplicates the domain 'example.com'."
        )
    }

    @MainActor
    func testSaveThrowsWhenDefaultBrowserIsMissing() async {
        let model = PreferencesModel(
            configStore: PreferencesConfigStoreStub(loadResult: nil),
            browserLauncher: PreferencesBrowserLauncherSpy(),
            configFileURLDescription: "/tmp/router-config.json"
        )

        XCTAssertThrowsError(try model.save()) { error in
            XCTAssertEqual(error as? PreferencesModelError, .missingDefaultBrowserSelection)
        }
    }

    @MainActor
    func testConfigValidationMessageReturnsNilWhenCurrentConfigIsValid() {
        let model = PreferencesModel(
            configStore: PreferencesConfigStoreStub(loadResult: nil),
            browserLauncher: PreferencesBrowserLauncherSpy(),
            configFileURLDescription: "/tmp/router-config.json"
        )
        model.defaultBrowserBundleID = "com.apple.Safari"
        model.defaultBrowserAppURL = URL(fileURLWithPath: "/Applications/Safari.app")

        XCTAssertNil(model.configValidationMessage())
    }

    @MainActor
    func testConfigValidationMessageDescribesEmptySourceBundleID() {
        let model = PreferencesModel(
            configStore: PreferencesConfigStoreStub(loadResult: nil),
            browserLauncher: PreferencesBrowserLauncherSpy(),
            configFileURLDescription: "/tmp/router-config.json"
        )
        model.defaultBrowserBundleID = "com.apple.Safari"
        model.defaultBrowserAppURL = URL(fileURLWithPath: "/Applications/Safari.app")
        _ = model.addRule()

        XCTAssertEqual(
            model.configValidationMessage(),
            "Rule \(model.ruleDrafts[0].id.uuidString) is missing a source app bundle ID."
        )
    }

    @MainActor
    func testRawConfigPreviewReturnsPrettyPrintedCurrentConfig() {
        let model = PreferencesModel(
            configStore: PreferencesConfigStoreStub(loadResult: nil),
            browserLauncher: PreferencesBrowserLauncherSpy(),
            configFileURLDescription: "/tmp/router-config.json"
        )
        model.defaultBrowserBundleID = "com.apple.Safari"
        model.defaultBrowserAppURL = URL(fileURLWithPath: "/Applications/Safari.app")

        let preview = model.rawConfigPreview()

        XCTAssertTrue(preview.contains("\"defaultBrowserBundleID\" : \"com.apple.Safari\""))
        XCTAssertTrue(preview.contains("\"rules\" : ["))
    }

    @MainActor
    func testTestDefaultBrowserUsesCurrentDraftConfig() async throws {
        let launcher = PreferencesBrowserLauncherSpy()
        let model = PreferencesModel(
            configStore: PreferencesConfigStoreStub(loadResult: nil),
            browserLauncher: launcher,
            configFileURLDescription: "/tmp/router-config.json"
        )
        model.defaultBrowserBundleID = "com.apple.Safari"
        model.defaultBrowserAppURL = URL(fileURLWithPath: "/Applications/Safari.app")
        model.sampleURLString = "https://example.com/default-browser"

        try await model.testDefaultBrowser()

        XCTAssertEqual(
            launcher.openCalls,
            [
                PreferencesBrowserLauncherSpy.OpenCall(
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
    func testTestDefaultBrowserUsesConfiguredDefaultBrowserRoute() async throws {
        let launcher = PreferencesBrowserLauncherSpy()
        let model = PreferencesModel(
            configStore: PreferencesConfigStoreStub(loadResult: nil),
            browserLauncher: launcher,
            configFileURLDescription: "/tmp/router-config.json"
        )
        model.defaultBrowserBundleID = "org.mozilla.firefox"
        model.defaultBrowserAppURL = URL(fileURLWithPath: "/Applications/Firefox.app")
        model.defaultBrowserRoute = .firefoxProfile(profileKey: "Profiles/work.default")
        model.sampleURLString = "https://example.com/default-browser"

        try await model.testDefaultBrowser()

        XCTAssertEqual(
            launcher.openCalls,
            [
                PreferencesBrowserLauncherSpy.OpenCall(
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
    func testTestDefaultBrowserUsesConfiguredDefaultChromiumProfileRoute() async throws {
        let launcher = PreferencesBrowserLauncherSpy()
        let model = PreferencesModel(
            configStore: PreferencesConfigStoreStub(loadResult: nil),
            browserLauncher: launcher,
            configFileURLDescription: "/tmp/router-config.json"
        )
        model.defaultBrowserBundleID = BrowserLauncher.heliumBundleID
        model.defaultBrowserAppURL = URL(fileURLWithPath: "/Applications/Helium.app")
        model.defaultBrowserRoute = .chromiumProfile(profileDirectory: "Profile 1")
        model.sampleURLString = "https://example.com/default-browser-helium"

        try await model.testDefaultBrowser()

        XCTAssertEqual(
            launcher.openCalls,
            [
                PreferencesBrowserLauncherSpy.OpenCall(
                    url: URL(string: "https://example.com/default-browser-helium")!,
                    target: .defaultBrowserChromiumProfile(profileDirectory: "Profile 1"),
                    config: RouterConfig(
                        defaultBrowserBundleID: BrowserLauncher.heliumBundleID,
                        defaultBrowserAppURL: URL(fileURLWithPath: "/Applications/Helium.app"),
                        defaultBrowserRoute: .chromiumProfile(profileDirectory: "Profile 1"),
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
        model.defaultBrowserBundleID = "com.apple.Safari"
        model.defaultBrowserAppURL = URL(fileURLWithPath: "/Applications/Safari.app")
        model.sampleURLString = "https://example.com/work"
        let ruleID = model.addRule()
        model.updateRuleSourceBundleID(id: ruleID, value: "com.tinyspeck.slackmacgap")
        model.updateRuleTargetSelection(
            id: ruleID,
            targetSelection: .browser(
                bundleID: BrowserLauncher.heliumBundleID,
                applicationURL: URL(fileURLWithPath: "/Applications/Helium.app")
            )
        )
        model.updateRuleBrowserRoute(id: ruleID, route: .chromiumProfile(profileDirectory: "Profile 1"))

        try await model.testRule(id: ruleID)

        XCTAssertEqual(
            launcher.openCalls,
            [
                PreferencesBrowserLauncherSpy.OpenCall(
                    url: URL(string: "https://example.com/work")!,
                    target: .applicationChromiumProfile(
                        bundleID: BrowserLauncher.heliumBundleID,
                        applicationURL: URL(fileURLWithPath: "/Applications/Helium.app"),
                        profileDirectory: "Profile 1"
                    ),
                    config: RouterConfig(
                        defaultBrowserBundleID: "com.apple.Safari",
                        defaultBrowserAppURL: URL(fileURLWithPath: "/Applications/Safari.app"),
                        defaultBrowserRoute: .plain,
                        rules: [
                            SourceAppRule(
                                id: ruleID,
                                sourceBundleID: "com.tinyspeck.slackmacgap",
                                target: .applicationChromiumProfile(
                                    bundleID: BrowserLauncher.heliumBundleID,
                                    applicationURL: URL(fileURLWithPath: "/Applications/Helium.app"),
                                    profileDirectory: "Profile 1"
                                )
                            ),
                        ]
                    )
                ),
            ]
        )
    }

    @MainActor
    func testTestRuleUsesDirectBrowserTarget() async throws {
        let launcher = PreferencesBrowserLauncherSpy()
        let model = PreferencesModel(
            configStore: PreferencesConfigStoreStub(loadResult: nil),
            browserLauncher: launcher,
            configFileURLDescription: "/tmp/router-config.json"
        )
        model.defaultBrowserBundleID = "com.apple.Safari"
        model.defaultBrowserAppURL = URL(fileURLWithPath: "/Applications/Safari.app")
        model.sampleURLString = "https://example.com/direct"

        let chromeURL = URL(fileURLWithPath: "/Applications/Google Chrome.app")
        let ruleID = model.addRule()
        model.updateRuleSourceBundleID(id: ruleID, value: "com.apple.mail")
        model.updateRuleTargetSelection(
            id: ruleID,
            targetSelection: .browser(bundleID: "com.google.Chrome", applicationURL: chromeURL)
        )

        try await model.testRule(id: ruleID)

        XCTAssertEqual(
            launcher.openCalls,
            [
                PreferencesBrowserLauncherSpy.OpenCall(
                    url: URL(string: "https://example.com/direct")!,
                    target: .application(bundleID: "com.google.Chrome", applicationURL: chromeURL),
                    config: RouterConfig(
                        defaultBrowserBundleID: "com.apple.Safari",
                        defaultBrowserAppURL: URL(fileURLWithPath: "/Applications/Safari.app"),
                        defaultBrowserRoute: .plain,
                        rules: [
                            SourceAppRule(
                                id: ruleID,
                                sourceBundleID: "com.apple.mail",
                                target: .application(bundleID: "com.google.Chrome", applicationURL: chromeURL)
                            ),
                        ]
                    )
                ),
            ]
        )
    }

    @MainActor
    func testTestRuleUsesDraftDefaultBrowserZenContainerTarget() async throws {
        let launcher = PreferencesBrowserLauncherSpy()
        let model = PreferencesModel(
            configStore: PreferencesConfigStoreStub(loadResult: nil),
            browserLauncher: launcher,
            configFileURLDescription: "/tmp/router-config.json"
        )
        let zenURL = try makeApplicationBundle(
            name: "Zen",
            bundleIdentifier: FirefoxBrowserAppSupportPath.zenBrowserBundleID
        )
        try model.setDefaultBrowser(applicationURL: zenURL)
        model.sampleURLString = "https://example.com/work"
        let ruleID = model.addRule()
        model.updateRuleSourceBundleID(id: ruleID, value: "com.tinyspeck.slackmacgap")
        model.updateRuleBrowserRoute(id: ruleID, route: .zenContainer(containerName: "Work"))

        try await model.testRule(id: ruleID)

        XCTAssertEqual(
            launcher.openCalls,
            [
                PreferencesBrowserLauncherSpy.OpenCall(
                    url: URL(string: "https://example.com/work")!,
                    target: .defaultBrowserZenContainer(containerName: "Work"),
                    config: RouterConfig(
                        defaultBrowserBundleID: FirefoxBrowserAppSupportPath.zenBrowserBundleID,
                        defaultBrowserAppURL: zenURL,
                        defaultBrowserRoute: .plain,
                        rules: [
                            SourceAppRule(
                                id: ruleID,
                                sourceBundleID: "com.tinyspeck.slackmacgap",
                                target: .defaultBrowserZenContainer(containerName: "Work")
                            ),
                        ]
                    )
                ),
            ]
        )
    }

    @MainActor
    func testTestRuleUsesDraftDefaultBrowserChromiumProfileTarget() async throws {
        let launcher = PreferencesBrowserLauncherSpy()
        let model = PreferencesModel(
            configStore: PreferencesConfigStoreStub(loadResult: nil),
            browserLauncher: launcher,
            configFileURLDescription: "/tmp/router-config.json"
        )
        let heliumURL = try makeApplicationBundle(
            name: "Helium",
            bundleIdentifier: BrowserLauncher.heliumBundleID
        )
        try model.setDefaultBrowser(applicationURL: heliumURL)
        model.sampleURLString = "https://example.com/work"
        let ruleID = model.addRule()
        model.updateRuleSourceBundleID(id: ruleID, value: "com.tinyspeck.slackmacgap")
        model.updateRuleBrowserRoute(id: ruleID, route: .chromiumProfile(profileDirectory: "Profile 1"))

        try await model.testRule(id: ruleID)

        XCTAssertEqual(
            launcher.openCalls,
            [
                PreferencesBrowserLauncherSpy.OpenCall(
                    url: URL(string: "https://example.com/work")!,
                    target: .defaultBrowserChromiumProfile(profileDirectory: "Profile 1"),
                    config: RouterConfig(
                        defaultBrowserBundleID: BrowserLauncher.heliumBundleID,
                        defaultBrowserAppURL: heliumURL,
                        defaultBrowserRoute: .plain,
                        rules: [
                            SourceAppRule(
                                id: ruleID,
                                sourceBundleID: "com.tinyspeck.slackmacgap",
                                target: .defaultBrowserChromiumProfile(profileDirectory: "Profile 1")
                            ),
                        ]
                    )
                ),
            ]
        )
    }

    @MainActor
    func testSetDefaultBrowserNormalizesDefaultZenContainerRouteWhenSwitchingToNonZenBrowser() async throws {
        let zenURL = try makeApplicationBundle(
            name: "Zen",
            bundleIdentifier: FirefoxBrowserAppSupportPath.zenBrowserBundleID
        )
        let safariURL = try makeApplicationBundle(
            name: "Safari",
            bundleIdentifier: "com.apple.Safari"
        )
        let model = PreferencesModel(
            configStore: PreferencesConfigStoreStub(loadResult: nil),
            browserLauncher: PreferencesBrowserLauncherSpy(),
            configFileURLDescription: "/tmp/router-config.json"
        )
        try model.setDefaultBrowser(applicationURL: zenURL)
        model.updateDefaultBrowserRoute(.zenContainer(containerName: "Work"))
        try model.setDefaultBrowser(applicationURL: safariURL)

        XCTAssertEqual(model.defaultBrowserRoute, .plain)
    }

    @MainActor
    func testSetDefaultBrowserNormalizesDefaultChromiumProfileRouteWhenSwitchingToNonChromiumBrowser() async throws {
        let heliumURL = try makeApplicationBundle(
            name: "Helium",
            bundleIdentifier: BrowserLauncher.heliumBundleID
        )
        let safariURL = try makeApplicationBundle(
            name: "Safari",
            bundleIdentifier: "com.apple.Safari"
        )
        let model = PreferencesModel(
            configStore: PreferencesConfigStoreStub(loadResult: nil),
            browserLauncher: PreferencesBrowserLauncherSpy(),
            configFileURLDescription: "/tmp/router-config.json"
        )
        try model.setDefaultBrowser(applicationURL: heliumURL)
        model.updateDefaultBrowserRoute(.chromiumProfile(profileDirectory: "Profile 1"))
        try model.setDefaultBrowser(applicationURL: safariURL)

        XCTAssertEqual(model.defaultBrowserRoute, .plain)
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
        let applicationURL = try makeApplicationBundle(
            name: "LinkSwitch",
            bundleIdentifier: "dev.helios.LinkSwitch"
        )

        let result = try await model.registerLinkSwitchAsDefaultHandler(applicationURL: applicationURL)

        XCTAssertEqual(result, .registered)
        XCTAssertEqual(
            provider.defaultHandlerSetCalls,
            [
                PreferencesLaunchServicesProviderSpy.SetCall(applicationURL: applicationURL, urlScheme: "http"),
                PreferencesLaunchServicesProviderSpy.SetCall(applicationURL: applicationURL, urlScheme: "https"),
            ]
        )
    }

    @MainActor
    func testRegisterLinkSwitchAsDefaultHandlerReturnsAlreadyRegisteredWhenBothSchemesAlreadyMatch() async throws {
        let provider = PreferencesLaunchServicesProviderSpy()
        provider.defaultHandlerBundleIDsByScheme["http"] = "dev.helios.LinkSwitch"
        provider.defaultHandlerBundleIDsByScheme["https"] = "dev.helios.LinkSwitch"
        let model = PreferencesModel(
            configStore: PreferencesConfigStoreStub(loadResult: nil),
            browserLauncher: PreferencesBrowserLauncherSpy(),
            configFileURLDescription: "/tmp/router-config.json",
            launchServicesBridge: LaunchServicesBridge(provider: provider)
        )
        let applicationURL = try makeApplicationBundle(
            name: "LinkSwitch",
            bundleIdentifier: "dev.helios.LinkSwitch"
        )

        let result = try await model.registerLinkSwitchAsDefaultHandler(applicationURL: applicationURL)

        XCTAssertEqual(result, .alreadyRegistered)
        XCTAssertEqual(provider.defaultHandlerSetCalls, [])
    }

    @MainActor
    func testRegisterDefaultBrowserAsDefaultHandlerRegistersHTTPAndHTTPS() async throws {
        let provider = PreferencesLaunchServicesProviderSpy()
        let model = PreferencesModel(
            configStore: PreferencesConfigStoreStub(loadResult: nil),
            browserLauncher: PreferencesBrowserLauncherSpy(),
            configFileURLDescription: "/tmp/router-config.json",
            launchServicesBridge: LaunchServicesBridge(provider: provider)
        )
        let zenURL = try makeApplicationBundle(
            name: "Zen",
            bundleIdentifier: "app.zen-browser.zen"
        )
        try model.setDefaultBrowser(applicationURL: zenURL)

        let result = try await model.registerDefaultBrowserAsDefaultHandler()

        XCTAssertEqual(result, .registered)
        XCTAssertEqual(
            provider.defaultHandlerSetCalls,
            [
                PreferencesLaunchServicesProviderSpy.SetCall(applicationURL: zenURL, urlScheme: "http"),
                PreferencesLaunchServicesProviderSpy.SetCall(applicationURL: zenURL, urlScheme: "https"),
            ]
        )
    }

    @MainActor
    func testRegisterDefaultBrowserAsDefaultHandlerThrowsWhenNoDefaultBrowserSelected() async throws {
        let provider = PreferencesLaunchServicesProviderSpy()
        let model = PreferencesModel(
            configStore: PreferencesConfigStoreStub(loadResult: nil),
            browserLauncher: PreferencesBrowserLauncherSpy(),
            configFileURLDescription: "/tmp/router-config.json",
            launchServicesBridge: LaunchServicesBridge(provider: provider)
        )

        do {
            _ = try await model.registerDefaultBrowserAsDefaultHandler()
            XCTFail("Expected missingDefaultBrowserSelection error")
        } catch PreferencesModelError.missingDefaultBrowserSelection {
            XCTAssertEqual(provider.defaultHandlerSetCalls, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @MainActor
    func testLaunchAtLoginStatusReturnsBridgeStatus() {
        let provider = PreferencesLaunchAtLoginProviderSpy(status: .requiresApproval)
        let model = PreferencesModel(
            configStore: PreferencesConfigStoreStub(loadResult: nil),
            browserLauncher: PreferencesBrowserLauncherSpy(),
            configFileURLDescription: "/tmp/router-config.json",
            launchAtLoginBridge: LaunchAtLoginBridge(provider: provider)
        )

        XCTAssertEqual(model.launchAtLoginStatus(), .requiresApproval)
    }

    @MainActor
    func testSetLaunchAtLoginEnabledDelegatesToBridge() throws {
        let provider = PreferencesLaunchAtLoginProviderSpy(status: .notRegistered)
        provider.statusAfterRegister = .enabled
        let model = PreferencesModel(
            configStore: PreferencesConfigStoreStub(loadResult: nil),
            browserLauncher: PreferencesBrowserLauncherSpy(),
            configFileURLDescription: "/tmp/router-config.json",
            launchAtLoginBridge: LaunchAtLoginBridge(provider: provider)
        )

        let updatedStatus = try model.setLaunchAtLoginEnabled(true)

        XCTAssertEqual(provider.registerCallCount, 1)
        XCTAssertEqual(provider.unregisterCallCount, 0)
        XCTAssertEqual(updatedStatus, .enabled)
    }

    @MainActor
    func testOpenSystemSettingsLoginItemsDelegatesToBridge() {
        let provider = PreferencesLaunchAtLoginProviderSpy(status: .requiresApproval)
        let model = PreferencesModel(
            configStore: PreferencesConfigStoreStub(loadResult: nil),
            browserLauncher: PreferencesBrowserLauncherSpy(),
            configFileURLDescription: "/tmp/router-config.json",
            launchAtLoginBridge: LaunchAtLoginBridge(provider: provider)
        )

        model.openSystemSettingsLoginItems()

        XCTAssertEqual(provider.openSystemSettingsCallCount, 1)
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

private final class PreferencesLaunchAtLoginProviderSpy: LaunchAtLoginProviding {
    var status: LaunchAtLoginStatus
    var statusAfterRegister: LaunchAtLoginStatus
    var statusAfterUnregister: LaunchAtLoginStatus

    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0
    private(set) var openSystemSettingsCallCount = 0

    init(status: LaunchAtLoginStatus) {
        self.status = status
        self.statusAfterRegister = status
        self.statusAfterUnregister = status
    }

    func register() throws {
        registerCallCount += 1
        status = statusAfterRegister
    }

    func unregister() throws {
        unregisterCallCount += 1
        status = statusAfterUnregister
    }

    func openSystemSettingsLoginItems() {
        openSystemSettingsCallCount += 1
    }
}
