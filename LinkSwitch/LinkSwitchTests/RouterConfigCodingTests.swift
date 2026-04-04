import XCTest
@testable import LinkSwitch

final class RouterConfigCodingTests: XCTestCase {
    func testRoundTripPreservesDefaultBrowserAndRules() throws {
        let config = RouterConfig(
            defaultBrowserBundleID: "com.apple.Safari",
            defaultBrowserAppURL: URL(fileURLWithPath: "/Applications/Safari.app"),
            defaultBrowserRoute: .firefoxProfile(profileKey: "Profiles/personal.default"),
            rules: [
                SourceAppRule(
                    id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
                    sourceBundleID: "com.tinyspeck.slackmacgap",
                    target: .helium(profileDirectory: "Profile 1")
                ),
                SourceAppRule(
                    id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
                    sourceBundleID: "com.apple.mail",
                    target: .defaultBrowser
                ),
                SourceAppRule(
                    id: UUID(uuidString: "22222222-3333-4444-5555-666666666666")!,
                    sourceBundleID: "org.mozilla.firefox",
                    target: .defaultBrowserFirefoxProfile(profileKey: "Profiles/work.default")
                ),
                SourceAppRule(
                    id: UUID(uuidString: "33333333-4444-5555-6666-777777777777")!,
                    sourceBundleID: "app.zen-browser.zen",
                    target: .defaultBrowserZenContainer(containerName: "Work")
                ),
                SourceAppRule(
                    id: UUID(uuidString: "44444444-5555-6666-7777-888888888888")!,
                    sourceBundleID: "com.apple.mail",
                    target: .application(
                        bundleID: "com.google.Chrome",
                        applicationURL: URL(fileURLWithPath: "/Applications/Google Chrome.app")
                    )
                ),
            ]
        )

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(RouterConfig.self, from: data)

        XCTAssertEqual(decoded, config)
    }

    func testRoundTripSupportsEmptyRules() throws {
        let config = RouterConfig(
            defaultBrowserBundleID: "com.google.Chrome",
            defaultBrowserAppURL: URL(fileURLWithPath: "/Applications/Google Chrome.app"),
            defaultBrowserRoute: .plain,
            rules: []
        )

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(RouterConfig.self, from: data)

        XCTAssertEqual(decoded, config)
    }

    func testRoundTripSupportsDefaultHeliumProfileRoute() throws {
        let config = RouterConfig(
            defaultBrowserBundleID: BrowserLauncher.heliumBundleID,
            defaultBrowserAppURL: URL(fileURLWithPath: "/Applications/Helium.app"),
            defaultBrowserRoute: .heliumProfile(profileDirectory: "Profile 1"),
            rules: []
        )

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(RouterConfig.self, from: data)

        XCTAssertEqual(decoded, config)
    }

    func testDecodeThrowsWhenDefaultBrowserRouteKeyMissing() throws {
        let config = RouterConfig(
            defaultBrowserBundleID: "org.mozilla.firefox",
            defaultBrowserAppURL: URL(fileURLWithPath: "/Applications/Firefox.app"),
            defaultBrowserRoute: .plain,
            rules: [
                SourceAppRule(
                    id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
                    sourceBundleID: "com.tinyspeck.slackmacgap",
                    target: .defaultBrowserFirefoxProfile(profileKey: "Profiles/work.default")
                ),
            ]
        )

        let encodedConfig = try JSONEncoder().encode(config)
        var jsonObject = try XCTUnwrap(JSONSerialization.jsonObject(with: encodedConfig) as? [String: Any])
        jsonObject.removeValue(forKey: "defaultBrowserRoute")
        let incompleteData = try JSONSerialization.data(withJSONObject: jsonObject, options: [.sortedKeys])

        XCTAssertThrowsError(try JSONDecoder().decode(RouterConfig.self, from: incompleteData)) { error in
            guard case DecodingError.keyNotFound(let key, _) = error else {
                XCTFail("Expected keyNotFound, got \(error)")
                return
            }
            XCTAssertEqual(key.stringValue, "defaultBrowserRoute")
        }
    }
}
