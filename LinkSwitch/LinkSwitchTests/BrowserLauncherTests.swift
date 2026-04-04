import XCTest
@testable import LinkSwitch

final class BrowserLauncherTests: XCTestCase {
    func testOpenDefaultBrowserUsesConfiguredBrowserAppURL() async throws {
        let workspaceLauncher = WorkspaceLaunchSpy()
        let launcher = BrowserLauncher(
            launchServicesBridge: makeBridge(),
            workspaceLauncher: workspaceLauncher
        )
        let url = URL(string: "https://example.com/default-browser")!
        let config = makeConfig()

        try await launcher.open(url, target: .defaultBrowser, config: config)

        XCTAssertEqual(
            workspaceLauncher.openURLCalls,
            [
                WorkspaceLaunchSpy.OpenURLCall(
                    urls: [url],
                    applicationURL: config.defaultBrowserAppURL
                ),
            ]
        )
        XCTAssertTrue(workspaceLauncher.launchApplicationExecutableCalls.isEmpty)
    }

    func testOpenDefaultBrowserHeliumProfileLaunchesConfiguredDefaultBrowserAppWithProfileArguments() async throws {
        let workspaceLauncher = WorkspaceLaunchSpy()
        let launcher = BrowserLauncher(
            launchServicesBridge: makeBridge(),
            workspaceLauncher: workspaceLauncher
        )
        let url = URL(string: "https://example.com/default-browser-helium")!
        let config = RouterConfig(
            defaultBrowserBundleID: BrowserLauncher.heliumBundleID,
            defaultBrowserAppURL: URL(fileURLWithPath: "/Applications/Helium.app"),
            defaultBrowserRoute: .plain,
            rules: []
        )

        try await launcher.open(
            url,
            target: .defaultBrowserHeliumProfile(profileDirectory: "Profile 1"),
            config: config
        )

        XCTAssertEqual(
            workspaceLauncher.launchApplicationExecutableCalls,
            [
                WorkspaceLaunchSpy.LaunchApplicationExecutableCall(
                    applicationURL: config.defaultBrowserAppURL,
                    arguments: [
                        "--profile-directory=Profile 1",
                        "https://example.com/default-browser-helium",
                    ]
                ),
            ]
        )
        XCTAssertTrue(workspaceLauncher.openURLCalls.isEmpty)
    }

    func testOpenHeliumResolvesAppURLAndLaunchesWithProfileArguments() async throws {
        let heliumApplicationURL = URL(fileURLWithPath: "/Applications/Helium.app")
        let workspaceLauncher = WorkspaceLaunchSpy()
        let provider = LaunchServicesProviderSpy()
        provider.applicationURLResult = heliumApplicationURL
        let bridge = LaunchServicesBridge(provider: provider)
        let launcher = BrowserLauncher(
            launchServicesBridge: bridge,
            workspaceLauncher: workspaceLauncher
        )
        let url = URL(string: "https://example.com/work")!

        try await launcher.open(
            url,
            target: .helium(profileDirectory: "Profile 1"),
            config: makeConfig()
        )

        XCTAssertEqual(provider.applicationURLRequests, [BrowserLauncher.heliumBundleID])
        XCTAssertEqual(
            workspaceLauncher.launchApplicationExecutableCalls,
            [
                WorkspaceLaunchSpy.LaunchApplicationExecutableCall(
                    applicationURL: heliumApplicationURL,
                    arguments: [
                        "--profile-directory=Profile 1",
                        "https://example.com/work",
                    ]
                ),
            ]
        )
        XCTAssertTrue(workspaceLauncher.openURLCalls.isEmpty)
    }

    func testOpenDefaultBrowserFirefoxProfileLaunchesExecutableWithAbsoluteProfilePath() async throws {
        let workspaceLauncher = WorkspaceLaunchSpy()
        let appSupportURL = try makeFirefoxAppSupport(relativePath: "Firefox", profileKey: "Profiles/work.default")
        let launcher = BrowserLauncher(
            launchServicesBridge: makeBridge(),
            workspaceLauncher: workspaceLauncher,
            appSupportURL: appSupportURL,
            homeDirectoryURL: appSupportURL.deletingLastPathComponent()
        )
        let url = URL(string: "https://example.com/firefox")!
        let config = RouterConfig(
            defaultBrowserBundleID: "org.mozilla.firefox",
            defaultBrowserAppURL: URL(fileURLWithPath: "/Applications/Firefox.app"),
            defaultBrowserRoute: .plain,
            rules: []
        )

        try await launcher.open(url, target: .defaultBrowserFirefoxProfile(profileKey: "Profiles/work.default"), config: config)

        XCTAssertEqual(
            workspaceLauncher.launchApplicationExecutableCalls,
            [
                WorkspaceLaunchSpy.LaunchApplicationExecutableCall(
                    applicationURL: config.defaultBrowserAppURL,
                    arguments: [
                        "-new-instance",
                        "-profile",
                        appSupportURL.appendingPathComponent("Firefox/Profiles/work.default").path(percentEncoded: false),
                        "https://example.com/firefox",
                    ]
                ),
            ]
        )
        XCTAssertTrue(workspaceLauncher.openURLCalls.isEmpty)
    }

    func testOpenDefaultBrowserZenContainerUsesExtContainerURL() async throws {
        let workspaceLauncher = WorkspaceLaunchSpy()
        let launcher = BrowserLauncher(
            launchServicesBridge: makeBridge(),
            workspaceLauncher: workspaceLauncher
        )
        let url = URL(string: "https://example.com/zen?tab=1")!
        let config = RouterConfig(
            defaultBrowserBundleID: FirefoxBrowserAppSupportPath.zenBrowserBundleID,
            defaultBrowserAppURL: URL(fileURLWithPath: "/Applications/Zen.app"),
            defaultBrowserRoute: .plain,
            rules: []
        )

        try await launcher.open(url, target: .defaultBrowserZenContainer(containerName: "Work"), config: config)

        XCTAssertEqual(
            workspaceLauncher.openURLCalls,
            [
                WorkspaceLaunchSpy.OpenURLCall(
                    urls: [try XCTUnwrap(URL(string: "ext+container:name=Work&url=https%3A%2F%2Fexample.com%2Fzen%3Ftab%3D1"))],
                    applicationURL: config.defaultBrowserAppURL
                ),
            ]
        )
        XCTAssertTrue(workspaceLauncher.launchApplicationExecutableCalls.isEmpty)
    }

    func testOpenDefaultBrowserFirefoxProfileThrowsForUnsupportedDefaultBrowserBundleID() async {
        let launcher = BrowserLauncher(
            launchServicesBridge: makeBridge(),
            workspaceLauncher: WorkspaceLaunchSpy()
        )
        let config = RouterConfig(
            defaultBrowserBundleID: "com.apple.Safari",
            defaultBrowserAppURL: URL(fileURLWithPath: "/Applications/Safari.app"),
            defaultBrowserRoute: .plain,
            rules: []
        )

        do {
            try await launcher.open(
                URL(string: "https://example.com/firefox")!,
                target: .defaultBrowserFirefoxProfile(profileKey: "Profiles/work.default"),
                config: config
            )
            XCTFail("Expected open to throw")
        } catch {
            XCTAssertEqual(
                error as? BrowserLauncherError,
                .unsupportedDefaultBrowserProfile(bundleID: "com.apple.Safari")
            )
        }
    }

    func testOpenDefaultBrowserHeliumProfileThrowsForUnsupportedDefaultBrowserBundleID() async {
        let launcher = BrowserLauncher(
            launchServicesBridge: makeBridge(),
            workspaceLauncher: WorkspaceLaunchSpy()
        )
        let config = RouterConfig(
            defaultBrowserBundleID: "com.apple.Safari",
            defaultBrowserAppURL: URL(fileURLWithPath: "/Applications/Safari.app"),
            defaultBrowserRoute: .plain,
            rules: []
        )

        do {
            try await launcher.open(
                URL(string: "https://example.com/helium")!,
                target: .defaultBrowserHeliumProfile(profileDirectory: "Profile 1"),
                config: config
            )
            XCTFail("Expected open to throw")
        } catch {
            XCTAssertEqual(
                error as? BrowserLauncherError,
                .unsupportedDefaultBrowserHeliumProfile(bundleID: "com.apple.Safari")
            )
        }
    }

    func testOpenHeliumPropagatesResolutionErrors() async {
        let launcher = BrowserLauncher(
            launchServicesBridge: makeBridge(applicationURLResult: nil),
            workspaceLauncher: WorkspaceLaunchSpy()
        )

        do {
            try await launcher.open(
                URL(string: "https://example.com/work")!,
                target: .helium(profileDirectory: "Profile 1"),
                config: makeConfig()
            )
            XCTFail("Expected open to throw")
        } catch {
            XCTAssertEqual(
                error as? LaunchServicesBridgeError,
                .applicationNotFound(bundleID: BrowserLauncher.heliumBundleID)
            )
        }
    }

    private func makeBridge(
        applicationURLResult: URL? = URL(fileURLWithPath: "/Applications/Helium.app")
    ) -> LaunchServicesBridge {
        let provider = LaunchServicesProviderSpy()
        provider.applicationURLResult = applicationURLResult
        return LaunchServicesBridge(provider: provider)
    }

    private func makeConfig() -> RouterConfig {
        RouterConfig(
            defaultBrowserBundleID: "com.apple.Safari",
            defaultBrowserAppURL: URL(fileURLWithPath: "/Applications/Safari.app"),
            defaultBrowserRoute: .plain,
            rules: []
        )
    }

    private func makeFirefoxAppSupport(relativePath: String, profileKey: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let appSupportURL = root.appendingPathComponent("Application Support", isDirectory: true)
        let profileURL = appSupportURL
            .appendingPathComponent(relativePath, isDirectory: true)
            .appendingPathComponent(profileKey, isDirectory: true)
        try FileManager.default.createDirectory(at: profileURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return appSupportURL
    }
}

private final class LaunchServicesProviderSpy: LaunchServicesProviding {
    var applicationURLResult: URL?
    private(set) var applicationURLRequests: [String] = []

    func defaultHandlerBundleID(forURLScheme urlScheme: String) -> String? {
        nil
    }

    func applicationURL(forBundleIdentifier bundleID: String) -> URL? {
        applicationURLRequests.append(bundleID)
        return applicationURLResult
    }

    func setDefaultHandler(applicationURL: URL, urlScheme: String) async throws {}
}

private final class WorkspaceLaunchSpy: WorkspaceLaunching {
    struct OpenURLCall: Equatable {
        let urls: [URL]
        let applicationURL: URL
    }

    struct LaunchApplicationExecutableCall: Equatable {
        let applicationURL: URL
        let arguments: [String]
    }

    private(set) var openURLCalls: [OpenURLCall] = []
    private(set) var launchApplicationExecutableCalls: [LaunchApplicationExecutableCall] = []

    func openURLs(_ urls: [URL], withApplicationAt applicationURL: URL) async throws {
        openURLCalls.append(OpenURLCall(urls: urls, applicationURL: applicationURL))
    }

    func launchApplicationExecutable(at applicationURL: URL, arguments: [String]) async throws {
        launchApplicationExecutableCalls.append(
            LaunchApplicationExecutableCall(applicationURL: applicationURL, arguments: arguments)
        )
    }
}
