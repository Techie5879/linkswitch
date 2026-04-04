import XCTest
@testable import LinkSwitch

final class BrowserProfileRoutePickerTests: XCTestCase {
    func testDefaultBrowserModeUsesDefaultHeliumProfileForHeliumBundleID() {
        XCTAssertEqual(
            BrowserProfileRouteSelectionMode.mode(forDefaultBrowserBundleID: BrowserLauncher.heliumBundleID),
            .defaultHeliumProfile
        )
    }

    func testDefaultBrowserRuleModeUsesDefaultHeliumProfileWhenDefaultBrowserIsHelium() {
        XCTAssertEqual(
            BrowserProfileRouteSelectionMode.mode(
                targetKind: .defaultBrowser,
                defaultBrowserBundleID: BrowserLauncher.heliumBundleID
            ),
            .defaultHeliumProfile
        )
    }

    func testDefaultHeliumProfileModeIncludesBrowserDefaultCard() {
        XCTAssertTrue(BrowserProfileRouteSelectionMode.defaultHeliumProfile.includesBrowserDefaultCard)
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
