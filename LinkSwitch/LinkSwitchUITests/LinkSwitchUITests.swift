//
//  LinkSwitchUITests.swift
//  LinkSwitchUITests
//
//  Created by Aritra Bandyopadhyay on 27/03/26.
//

import XCTest

final class LinkSwitchUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testMainWindowShowsPreferencesInUITestLaunchMode() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-show-main-window"]
        app.launch()

        XCTAssertTrue(app.windows["LinkSwitch"].waitForExistence(timeout: 2.0))
        XCTAssertTrue(app.popUpButtons["preferences.defaultBrowserPopup"].waitForExistence(timeout: 2.0))
        XCTAssertTrue(app.buttons["preferences.reloadButton"].waitForExistence(timeout: 2.0))
        XCTAssertTrue(app.buttons["preferences.saveButton"].waitForExistence(timeout: 2.0))
        XCTAssertTrue(app.checkBoxes["preferences.openAtLoginCheckbox"].waitForExistence(timeout: 2.0))
        let toggleButton = app.buttons["preferences.toggleRawConfigButton"]
        XCTAssertTrue(toggleButton.waitForExistence(timeout: 2.0))
        XCTAssertFalse(app.textViews["preferences.rawConfigTextView"].exists)

        toggleButton.tap()

        XCTAssertTrue(app.textViews["preferences.rawConfigTextView"].waitForExistence(timeout: 2.0))
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-test-show-main-window"]
            app.launch()
        }
    }
}
