import XCTest
@testable import LinkSwitch

final class BrowserProfileRoutePickerTests: XCTestCase {
    func testDefaultBrowserModeUsesDefaultHeliumProfileForHeliumBundleID() {
        XCTAssertEqual(
            BrowserProfileRouteSelectionMode.mode(forDefaultBrowserBundleID: BrowserLauncher.heliumBundleID),
            .defaultChromiumProfile
        )
    }

    func testDefaultBrowserModeUsesDefaultHeliumProfileForChromeBundleID() {
        XCTAssertEqual(
            BrowserProfileRouteSelectionMode.mode(forDefaultBrowserBundleID: "com.google.Chrome"),
            .defaultChromiumProfile
        )
    }

    func testDefaultBrowserRuleModeUsesDefaultHeliumProfileWhenDefaultBrowserIsHelium() {
        XCTAssertEqual(
            BrowserProfileRouteSelectionMode.mode(
                targetSelection: .defaultBrowser,
                defaultBrowserBundleID: BrowserLauncher.heliumBundleID
            ),
            .defaultChromiumProfile
        )
    }

    func testExplicitBrowserRuleModeUsesBrowserFirefoxProfileForFirefoxBundleID() {
        XCTAssertEqual(
            BrowserProfileRouteSelectionMode.mode(
                targetSelection: .browser(
                    bundleID: "org.mozilla.firefox",
                    applicationURL: URL(fileURLWithPath: "/Applications/Firefox.app")
                ),
                defaultBrowserBundleID: "com.apple.Safari"
            ),
            .browserFirefoxProfile
        )
    }

    func testExplicitBrowserRuleModeUsesBrowserHeliumProfileForChromeBundleID() {
        XCTAssertEqual(
            BrowserProfileRouteSelectionMode.mode(
                targetSelection: .browser(
                    bundleID: "com.google.Chrome",
                    applicationURL: URL(fileURLWithPath: "/Applications/Google Chrome.app")
                ),
                defaultBrowserBundleID: "com.apple.Safari"
            ),
            .browserChromiumProfile
        )
    }

    func testDefaultHeliumProfileModeIncludesBrowserDefaultCard() {
        XCTAssertTrue(BrowserProfileRouteSelectionMode.defaultChromiumProfile.includesBrowserDefaultCard)
    }

    func testDefaultZenContainerModeUsesNoContainerPlainRouteCardLabel() {
        XCTAssertEqual(
            BrowserProfileRouteSelectionMode.browserDefaultCard(for: .defaultZenContainer).displayName,
            "No Container"
        )
    }

    func testDefaultFirefoxProfileModeUsesNoProfilePlainRouteCardLabel() {
        XCTAssertEqual(
            BrowserProfileRouteSelectionMode.browserDefaultCard(for: .defaultFirefoxProfile).displayName,
            "No Profile"
        )
    }
}
