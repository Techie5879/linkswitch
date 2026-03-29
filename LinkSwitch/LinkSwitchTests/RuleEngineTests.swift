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
            fallbackBrowserRoute: .plain,
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
            fallbackBrowserRoute: .plain,
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

    func testNilSourceBundleIDUsesConfiguredFallbackRoutePlain() {
        let context = IncomingOpenContext(
            url: URL(string: "https://example.com")!,
            sourceBundleID: nil
        )

        XCTAssertEqual(ruleEngine.target(for: context, config: makeConfig()), .fallbackBrowser)
    }

    func testUnknownSourceBundleIDUsesConfiguredFallbackRoutePlain() {
        let context = IncomingOpenContext(
            url: URL(string: "https://example.com")!,
            sourceBundleID: "com.apple.mail"
        )

        XCTAssertEqual(ruleEngine.target(for: context, config: makeConfig()), .fallbackBrowser)
    }

    func testNilSourceBundleIDUsesConfiguredFallbackFirefoxProfile() {
        let context = IncomingOpenContext(
            url: URL(string: "https://example.com")!,
            sourceBundleID: nil
        )
        let config = RouterConfig(
            fallbackBrowserBundleID: "org.mozilla.firefox",
            fallbackBrowserAppURL: URL(fileURLWithPath: "/Applications/Firefox.app"),
            fallbackBrowserRoute: .firefoxProfile(profileKey: "Profiles/work.default"),
            rules: []
        )

        XCTAssertEqual(
            ruleEngine.target(for: context, config: config),
            .fallbackBrowserFirefoxProfile(profileKey: "Profiles/work.default")
        )
    }

    func testUnknownSourceUsesConfiguredFallbackZenContainer() {
        let context = IncomingOpenContext(
            url: URL(string: "https://example.com")!,
            sourceBundleID: "com.apple.mail"
        )
        let config = RouterConfig(
            fallbackBrowserBundleID: FirefoxBrowserAppSupportPath.zenBrowserBundleID,
            fallbackBrowserAppURL: URL(fileURLWithPath: "/Applications/Zen.app"),
            fallbackBrowserRoute: .zenContainer(containerName: "Work"),
            rules: []
        )

        XCTAssertEqual(
            ruleEngine.target(for: context, config: config),
            .fallbackBrowserZenContainer(containerName: "Work")
        )
    }

    private func makeConfig() -> RouterConfig {
        RouterConfig(
            fallbackBrowserBundleID: "com.apple.Safari",
            fallbackBrowserAppURL: URL(fileURLWithPath: "/Applications/Safari.app"),
            fallbackBrowserRoute: .plain,
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
