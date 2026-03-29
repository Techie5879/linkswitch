import XCTest
@testable import LinkSwitch

final class RouterConfigCodingTests: XCTestCase {
    func testRoundTripPreservesFallbackAndRules() throws {
        let config = RouterConfig(
            fallbackBrowserBundleID: "com.apple.Safari",
            fallbackBrowserAppURL: URL(fileURLWithPath: "/Applications/Safari.app"),
            fallbackBrowserRoute: .firefoxProfile(profileKey: "Profiles/personal.default"),
            rules: [
                SourceAppRule(
                    id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
                    sourceBundleID: "com.tinyspeck.slackmacgap",
                    target: .helium(profileDirectory: "Profile 1")
                ),
                SourceAppRule(
                    id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
                    sourceBundleID: "com.apple.mail",
                    target: .fallbackBrowser
                ),
                SourceAppRule(
                    id: UUID(uuidString: "22222222-3333-4444-5555-666666666666")!,
                    sourceBundleID: "org.mozilla.firefox",
                    target: .fallbackBrowserFirefoxProfile(profileKey: "Profiles/work.default")
                ),
                SourceAppRule(
                    id: UUID(uuidString: "33333333-4444-5555-6666-777777777777")!,
                    sourceBundleID: "app.zen-browser.zen",
                    target: .fallbackBrowserZenContainer(containerName: "Work")
                ),
            ]
        )

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(RouterConfig.self, from: data)

        XCTAssertEqual(decoded, config)
    }

    func testRoundTripSupportsEmptyRules() throws {
        let config = RouterConfig(
            fallbackBrowserBundleID: "com.google.Chrome",
            fallbackBrowserAppURL: URL(fileURLWithPath: "/Applications/Google Chrome.app"),
            fallbackBrowserRoute: .plain,
            rules: []
        )

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(RouterConfig.self, from: data)

        XCTAssertEqual(decoded, config)
    }
}
