import XCTest
@testable import LinkSwitch

final class BrowserLauncherTests: XCTestCase {
    func testOpenFallbackBrowserUsesConfiguredBrowserAppURL() async throws {
        let workspaceLauncher = WorkspaceLaunchSpy()
        let launcher = BrowserLauncher(
            launchServicesBridge: makeBridge(),
            workspaceLauncher: workspaceLauncher
        )
        let url = URL(string: "https://example.com/fallback")!
        let config = makeConfig()

        try await launcher.open(url, target: .fallbackBrowser, config: config)

        XCTAssertEqual(
            workspaceLauncher.openURLCalls,
            [
                WorkspaceLaunchSpy.OpenURLCall(
                    urls: [url],
                    applicationURL: config.fallbackBrowserAppURL
                ),
            ]
        )
        XCTAssertTrue(workspaceLauncher.launchApplicationExecutableCalls.isEmpty)
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

    func testOpenFallbackFirefoxProfileLaunchesExecutableWithAbsoluteProfilePath() async throws {
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
            fallbackBrowserBundleID: "org.mozilla.firefox",
            fallbackBrowserAppURL: URL(fileURLWithPath: "/Applications/Firefox.app"),
            fallbackBrowserRoute: .plain,
            rules: []
        )

        try await launcher.open(url, target: .fallbackBrowserFirefoxProfile(profileKey: "Profiles/work.default"), config: config)

        XCTAssertEqual(
            workspaceLauncher.launchApplicationExecutableCalls,
            [
                WorkspaceLaunchSpy.LaunchApplicationExecutableCall(
                    applicationURL: config.fallbackBrowserAppURL,
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

    func testOpenFallbackZenContainerUsesExtContainerURL() async throws {
        let workspaceLauncher = WorkspaceLaunchSpy()
        let launcher = BrowserLauncher(
            launchServicesBridge: makeBridge(),
            workspaceLauncher: workspaceLauncher
        )
        let url = URL(string: "https://example.com/zen?tab=1")!
        let config = RouterConfig(
            fallbackBrowserBundleID: FirefoxBrowserAppSupportPath.zenBrowserBundleID,
            fallbackBrowserAppURL: URL(fileURLWithPath: "/Applications/Zen.app"),
            fallbackBrowserRoute: .plain,
            rules: []
        )

        try await launcher.open(url, target: .fallbackBrowserZenContainer(containerName: "Work"), config: config)

        XCTAssertEqual(
            workspaceLauncher.openURLCalls,
            [
                WorkspaceLaunchSpy.OpenURLCall(
                    urls: [try XCTUnwrap(URL(string: "ext+container:name=Work&url=https%3A%2F%2Fexample.com%2Fzen%3Ftab%3D1"))],
                    applicationURL: config.fallbackBrowserAppURL
                ),
            ]
        )
        XCTAssertTrue(workspaceLauncher.launchApplicationExecutableCalls.isEmpty)
    }

    func testOpenFallbackFirefoxProfileThrowsForUnsupportedFallbackBrowserBundleID() async {
        let launcher = BrowserLauncher(
            launchServicesBridge: makeBridge(),
            workspaceLauncher: WorkspaceLaunchSpy()
        )
        let config = RouterConfig(
            fallbackBrowserBundleID: "com.apple.Safari",
            fallbackBrowserAppURL: URL(fileURLWithPath: "/Applications/Safari.app"),
            fallbackBrowserRoute: .plain,
            rules: []
        )

        do {
            try await launcher.open(
                URL(string: "https://example.com/firefox")!,
                target: .fallbackBrowserFirefoxProfile(profileKey: "Profiles/work.default"),
                config: config
            )
            XCTFail("Expected open to throw")
        } catch {
            XCTAssertEqual(
                error as? BrowserLauncherError,
                .unsupportedFallbackBrowserProfile(bundleID: "com.apple.Safari")
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
            fallbackBrowserBundleID: "com.apple.Safari",
            fallbackBrowserAppURL: URL(fileURLWithPath: "/Applications/Safari.app"),
            fallbackBrowserRoute: .plain,
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
