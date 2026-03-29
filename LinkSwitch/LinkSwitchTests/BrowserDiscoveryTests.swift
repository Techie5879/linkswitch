import XCTest
@testable import LinkSwitch

final class BrowserDiscoveryTests: XCTestCase {
    func testDiscoverBrowsersExcludesSelfBundleID() {
        let stub = StubBrowserDiscovering(browsers: [
            DiscoveredBrowser(bundleID: "com.example.Zebra", name: "Zebra", appURL: URL(fileURLWithPath: "/Applications/Zebra.app")),
            DiscoveredBrowser(bundleID: "com.example.Alpha", name: "Alpha", appURL: URL(fileURLWithPath: "/Applications/Alpha.app")),
            DiscoveredBrowser(bundleID: "dev.helios.LinkSwitch", name: "LinkSwitch", appURL: URL(fileURLWithPath: "/Applications/LinkSwitch.app")),
        ])

        let results = stub.discoverBrowsers(excludingBundleID: "dev.helios.LinkSwitch")

        let resultBundleIDs = Set(results.map(\.bundleID))
        XCTAssertEqual(resultBundleIDs, ["com.example.Zebra", "com.example.Alpha"])
        XCTAssertFalse(resultBundleIDs.contains("dev.helios.LinkSwitch"))
    }

    func testDiscoverBrowsersReturnsAllWhenNoExclusion() {
        let stub = StubBrowserDiscovering(browsers: [
            DiscoveredBrowser(bundleID: "com.example.Bravo", name: "Bravo", appURL: URL(fileURLWithPath: "/Applications/Bravo.app")),
            DiscoveredBrowser(bundleID: "com.example.Alpha", name: "Alpha", appURL: URL(fileURLWithPath: "/Applications/Alpha.app")),
        ])

        let results = stub.discoverBrowsers(excludingBundleID: nil)

        XCTAssertEqual(results.map(\.bundleID), ["com.example.Bravo", "com.example.Alpha"])
    }

    func testDiscoverBrowsersReturnsEmptyWhenNoBrowsersFound() {
        let stub = StubBrowserDiscovering(browsers: [])

        let results = stub.discoverBrowsers(excludingBundleID: "com.example.Self")

        XCTAssertTrue(results.isEmpty)
    }

    func testDiscoveredBrowserIdIsItsBundleID() {
        let browser = DiscoveredBrowser(bundleID: "com.example.Test", name: "Test", appURL: URL(fileURLWithPath: "/Applications/Test.app"))
        XCTAssertEqual(browser.id, browser.bundleID)
    }

    func testDiscoverInstalledApplicationsExcludesSelfBundleID() {
        let stub = StubInstalledApplicationDiscovering(applications: [
            DiscoveredApplication(bundleID: "com.example.Alpha", name: "Alpha", appURL: URL(fileURLWithPath: "/Applications/Alpha.app")),
            DiscoveredApplication(bundleID: "dev.helios.LinkSwitch", name: "LinkSwitch", appURL: URL(fileURLWithPath: "/Applications/LinkSwitch.app")),
        ])

        let results = stub.discoverInstalledApplications(excludingBundleID: "dev.helios.LinkSwitch")

        XCTAssertEqual(results.map(\.bundleID), ["com.example.Alpha"])
    }

    func testDiscoveredApplicationIdIsItsBundleID() {
        let app = DiscoveredApplication(bundleID: "com.example.Test", name: "Test", appURL: URL(fileURLWithPath: "/Applications/Test.app"))
        XCTAssertEqual(app.id, app.bundleID)
    }
}

// MARK: - Stub

final class StubBrowserDiscovering: BrowserDiscovering {
    private let browsers: [DiscoveredBrowser]

    init(browsers: [DiscoveredBrowser]) {
        self.browsers = browsers
    }

    func discoverBrowsers(excludingBundleID: String?) -> [DiscoveredBrowser] {
        browsers.filter { $0.bundleID != excludingBundleID }
    }
}

// MARK: - Installed applications stub

final class StubInstalledApplicationDiscovering: InstalledApplicationDiscovering {
    private let applications: [DiscoveredApplication]

    init(applications: [DiscoveredApplication]) {
        self.applications = applications
    }

    func discoverInstalledApplications(excludingBundleID: String?) -> [DiscoveredApplication] {
        applications.filter { $0.bundleID != excludingBundleID }
    }
}
