import XCTest
@testable import LinkSwitch

final class BrowserProfileRoutePickerTests: XCTestCase {
    func testFallbackBrowserModeUsesFallbackHeliumProfileForHeliumBundleID() {
        XCTAssertEqual(
            BrowserProfileRouteSelectionMode.mode(forFallbackBrowserBundleID: BrowserLauncher.heliumBundleID),
            .fallbackHeliumProfile
        )
    }

    func testFallbackBrowserRuleModeUsesFallbackHeliumProfileWhenFallbackBrowserIsHelium() {
        XCTAssertEqual(
            BrowserProfileRouteSelectionMode.mode(
                targetKind: .fallbackBrowser,
                fallbackBrowserBundleID: BrowserLauncher.heliumBundleID
            ),
            .fallbackHeliumProfile
        )
    }

    func testFallbackHeliumProfileModeIncludesBrowserDefaultCard() {
        XCTAssertTrue(BrowserProfileRouteSelectionMode.fallbackHeliumProfile.includesBrowserDefaultCard)
    }

    func testDirectHeliumRuleModeDoesNotIncludeBrowserDefaultCard() {
        XCTAssertFalse(BrowserProfileRouteSelectionMode.heliumProfile.includesBrowserDefaultCard)
    }
}
