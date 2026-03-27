import XCTest
@testable import LinkSwitch

final class RouterConfigCodingTests: XCTestCase {
    func testRoundTripPreservesFallbackAndRules() throws {
        let config = RouterConfig(
            fallbackBrowserBundleID: "com.apple.Safari",
            fallbackBrowserAppURL: URL(fileURLWithPath: "/Applications/Safari.app"),
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
            rules: []
        )

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(RouterConfig.self, from: data)

        XCTAssertEqual(decoded, config)
    }
}
