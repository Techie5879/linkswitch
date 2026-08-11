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
            defaultBrowserBundleID: "com.apple.Safari",
            defaultBrowserAppURL: URL(fileURLWithPath: "/Applications/Safari.app"),
            defaultBrowserRoute: .plain,
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
            defaultBrowserBundleID: "com.apple.Safari",
            defaultBrowserAppURL: URL(fileURLWithPath: "/Applications/Safari.app"),
            defaultBrowserRoute: .plain,
            rules: [
                SourceAppRule(
                    id: UUID(),
                    sourceBundleID: "com.tinyspeck.slackmacgap",
                    target: .helium(profileDirectory: "Profile 1")
                ),
                SourceAppRule(
                    id: UUID(),
                    sourceBundleID: "com.tinyspeck.slackmacgap",
                    target: .defaultBrowser
                ),
            ]
        )

        XCTAssertEqual(ruleEngine.target(for: context, config: config), .helium(profileDirectory: "Profile 1"))
    }

    func testDomainRuleMatchesExactHostCaseInsensitively() {
        let context = IncomingOpenContext(
            url: URL(string: "https://Docs.Example.com/path")!,
            sourceBundleID: nil
        )
        let config = makeConfig(
            domainRules: [
                DomainRule(id: UUID(), domain: "docs.example.com", target: .helium(profileDirectory: "Work")),
            ]
        )

        XCTAssertEqual(ruleEngine.target(for: context, config: config), .helium(profileDirectory: "Work"))
    }

    func testDomainRuleMatchesSubdomainsButNotLookalikeHosts() {
        let rule = DomainRule(id: UUID(), domain: "example.com", target: .helium(profileDirectory: "Work"))
        let config = makeConfig(domainRules: [rule])

        XCTAssertEqual(
            ruleEngine.target(
                for: IncomingOpenContext(url: URL(string: "https://deep.team.example.com")!, sourceBundleID: nil),
                config: config
            ),
            .helium(profileDirectory: "Work")
        )
        XCTAssertEqual(
            ruleEngine.target(
                for: IncomingOpenContext(url: URL(string: "https://notexample.com")!, sourceBundleID: nil),
                config: config
            ),
            .defaultBrowser
        )
    }

    func testMostSpecificDomainRuleWinsRegardlessOfConfigurationOrder() {
        let config = makeConfig(
            domainRules: [
                DomainRule(id: UUID(), domain: "example.com", target: .helium(profileDirectory: "General")),
                DomainRule(id: UUID(), domain: "team.example.com", target: .helium(profileDirectory: "Team")),
            ]
        )
        let context = IncomingOpenContext(url: URL(string: "https://docs.team.example.com")!, sourceBundleID: nil)

        XCTAssertEqual(ruleEngine.target(for: context, config: config), .helium(profileDirectory: "Team"))
    }

    func testDomainRuleTakesPrecedenceOverSourceAppRule() {
        let config = makeConfig(
            domainRules: [
                DomainRule(id: UUID(), domain: "example.com", target: .defaultBrowser),
            ]
        )
        let context = IncomingOpenContext(
            url: URL(string: "https://example.com")!,
            sourceBundleID: "com.tinyspeck.slackmacgap"
        )

        XCTAssertEqual(ruleEngine.target(for: context, config: config), .defaultBrowser)
    }

    func testNilSourceBundleIDUsesConfiguredDefaultBrowserRoutePlain() {
        let context = IncomingOpenContext(
            url: URL(string: "https://example.com")!,
            sourceBundleID: nil
        )

        XCTAssertEqual(ruleEngine.target(for: context, config: makeConfig()), .defaultBrowser)
    }

    func testUnknownSourceBundleIDUsesConfiguredDefaultBrowserRoutePlain() {
        let context = IncomingOpenContext(
            url: URL(string: "https://example.com")!,
            sourceBundleID: "com.apple.mail"
        )

        XCTAssertEqual(ruleEngine.target(for: context, config: makeConfig()), .defaultBrowser)
    }

    func testNilSourceBundleIDUsesConfiguredDefaultBrowserFirefoxProfile() {
        let context = IncomingOpenContext(
            url: URL(string: "https://example.com")!,
            sourceBundleID: nil
        )
        let config = RouterConfig(
            defaultBrowserBundleID: "org.mozilla.firefox",
            defaultBrowserAppURL: URL(fileURLWithPath: "/Applications/Firefox.app"),
            defaultBrowserRoute: .firefoxProfile(profileKey: "Profiles/work.default"),
            rules: []
        )

        XCTAssertEqual(
            ruleEngine.target(for: context, config: config),
            .defaultBrowserFirefoxProfile(profileKey: "Profiles/work.default")
        )
    }

    func testUnknownSourceUsesConfiguredDefaultBrowserChromiumProfile() {
        let context = IncomingOpenContext(
            url: URL(string: "https://example.com")!,
            sourceBundleID: "com.apple.mail"
        )
        let config = RouterConfig(
            defaultBrowserBundleID: BrowserLauncher.heliumBundleID,
            defaultBrowserAppURL: URL(fileURLWithPath: "/Applications/Helium.app"),
            defaultBrowserRoute: .chromiumProfile(profileDirectory: "Profile 1"),
            rules: []
        )

        XCTAssertEqual(
            ruleEngine.target(for: context, config: config),
            .defaultBrowserChromiumProfile(profileDirectory: "Profile 1")
        )
    }

    func testUnknownSourceUsesConfiguredDefaultBrowserZenContainer() {
        let context = IncomingOpenContext(
            url: URL(string: "https://example.com")!,
            sourceBundleID: "com.apple.mail"
        )
        let config = RouterConfig(
            defaultBrowserBundleID: FirefoxBrowserAppSupportPath.zenBrowserBundleID,
            defaultBrowserAppURL: URL(fileURLWithPath: "/Applications/Zen.app"),
            defaultBrowserRoute: .zenContainer(containerName: "Work"),
            rules: []
        )

        XCTAssertEqual(
            ruleEngine.target(for: context, config: config),
            .defaultBrowserZenContainer(containerName: "Work")
        )
    }

    private func makeConfig(domainRules: [DomainRule] = []) -> RouterConfig {
        RouterConfig(
            defaultBrowserBundleID: "com.apple.Safari",
            defaultBrowserAppURL: URL(fileURLWithPath: "/Applications/Safari.app"),
            defaultBrowserRoute: .plain,
            domainRules: domainRules,
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
