import XCTest
@testable import LinkSwitch

final class RuleEngineTests: XCTestCase {
    private let ruleEngine = RuleEngine()

    func testMatchingSourceBundleIDReturnsRuleTarget() {
        let context = IncomingOpenContext(
            url: URL(string: "https://example.com")!,
            sourceBundleID: "com.tinyspeck.slackmacgap"
        )
        let config = RouterConfig(
            fallbackBrowserBundleID: "com.apple.Safari",
            fallbackBrowserAppURL: URL(fileURLWithPath: "/Applications/Safari.app"),
            rules: [
                SourceAppRule(
                    id: UUID(),
                    sourceBundleID: "com.tinyspeck.slackmacgap",
                    target: .helium(profileDirectory: "Profile 1")
                ),
            ]
        )

        XCTAssertEqual(ruleEngine.target(for: context, config: config), .helium(profileDirectory: "Profile 1"))
    }

    func testFirstMatchingRuleWins() {
        let context = IncomingOpenContext(
            url: URL(string: "https://example.com")!,
            sourceBundleID: "com.tinyspeck.slackmacgap"
        )
        let config = RouterConfig(
            fallbackBrowserBundleID: "com.apple.Safari",
            fallbackBrowserAppURL: URL(fileURLWithPath: "/Applications/Safari.app"),
            rules: [
                SourceAppRule(
                    id: UUID(),
                    sourceBundleID: "com.tinyspeck.slackmacgap",
                    target: .helium(profileDirectory: "Profile 1")
                ),
                SourceAppRule(
                    id: UUID(),
                    sourceBundleID: "com.tinyspeck.slackmacgap",
                    target: .fallbackBrowser
                ),
            ]
        )

        XCTAssertEqual(ruleEngine.target(for: context, config: config), .helium(profileDirectory: "Profile 1"))
    }

    func testNilSourceBundleIDReturnsFallbackBrowser() {
        let context = IncomingOpenContext(
            url: URL(string: "https://example.com")!,
            sourceBundleID: nil
        )

        XCTAssertEqual(ruleEngine.target(for: context, config: makeConfig()), .fallbackBrowser)
    }

    func testUnknownSourceBundleIDReturnsFallbackBrowser() {
        let context = IncomingOpenContext(
            url: URL(string: "https://example.com")!,
            sourceBundleID: "com.apple.mail"
        )

        XCTAssertEqual(ruleEngine.target(for: context, config: makeConfig()), .fallbackBrowser)
    }

    private func makeConfig() -> RouterConfig {
        RouterConfig(
            fallbackBrowserBundleID: "com.apple.Safari",
            fallbackBrowserAppURL: URL(fileURLWithPath: "/Applications/Safari.app"),
            rules: [
                SourceAppRule(
                    id: UUID(),
                    sourceBundleID: "com.tinyspeck.slackmacgap",
                    target: .helium(profileDirectory: "Profile 1")
                ),
            ]
        )
    }
}
