import XCTest
@testable import LinkSwitch

final class URLIntakeControllerTests: XCTestCase {
    func testHandleThrowsWhenRouterConfigIsMissing() async {
        let controller = URLIntakeController(
            configStore: RouterConfigStoreStub(loadResult: nil),
            ruleEngine: RuleEngine(),
            browserLauncher: BrowserLauncherSpy()
        )

        do {
            try await controller.handle(
                urls: [URL(string: "https://example.com")!],
                sourceBundleID: nil
            )
            XCTFail("Expected handle to throw")
        } catch {
            XCTAssertEqual(error as? URLIntakeControllerError, .missingConfig)
        }
    }

    func testHandleRoutesMatchingSourceToHeliumTarget() async throws {
        let browserLauncher = BrowserLauncherSpy()
        let controller = URLIntakeController(
            configStore: RouterConfigStoreStub(loadResult: makeConfig()),
            ruleEngine: RuleEngine(),
            browserLauncher: browserLauncher
        )
        let url = URL(string: "https://example.com/work")!

        try await controller.handle(
            urls: [url],
            sourceBundleID: "com.tinyspeck.slackmacgap"
        )

        XCTAssertEqual(
            browserLauncher.openCalls,
            [
                BrowserLauncherSpy.OpenCall(
                    url: url,
                    target: .helium(profileDirectory: "Profile 1"),
                    config: makeConfig()
                ),
            ]
        )
    }

    func testHandleProcessesEveryIncomingURL() async throws {
        let browserLauncher = BrowserLauncherSpy()
        let controller = URLIntakeController(
            configStore: RouterConfigStoreStub(loadResult: makeConfig()),
            ruleEngine: RuleEngine(),
            browserLauncher: browserLauncher
        )
        let firstURL = URL(string: "https://example.com/one")!
        let secondURL = URL(string: "https://example.com/two")!

        try await controller.handle(
            urls: [firstURL, secondURL],
            sourceBundleID: nil
        )

        XCTAssertEqual(
            browserLauncher.openCalls,
            [
                BrowserLauncherSpy.OpenCall(
                    url: firstURL,
                    target: .fallbackBrowser,
                    config: makeConfig()
                ),
                BrowserLauncherSpy.OpenCall(
                    url: secondURL,
                    target: .fallbackBrowser,
                    config: makeConfig()
                ),
            ]
        )
    }

    private func makeConfig() -> RouterConfig {
        RouterConfig(
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
    }
}

private struct RouterConfigStoreStub: RouterConfigLoading {
    let loadResult: RouterConfig?

    func load() throws -> RouterConfig? {
        loadResult
    }
}

private final class BrowserLauncherSpy: BrowserLaunching {
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
