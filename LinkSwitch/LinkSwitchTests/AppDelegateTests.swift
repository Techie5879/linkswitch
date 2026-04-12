import AppKit
import XCTest
@testable import LinkSwitch

final class AppDelegateTests: XCTestCase {
    @MainActor
    func testApplicationOpenPassesResolvedSourceBundleIDToIntakeHandler() async {
        let appDelegate = AppDelegate()
        let intakeHandler = URLIntakeHandlerSpy()
        intakeHandler.expectedCallCount = 1
        appDelegate.sourceBundleIDResolver = StubSourceBundleIDResolver(sourceBundleID: "com.tinyspeck.slackmacgap")
        appDelegate.urlIntakeHandler = intakeHandler
        let url = URL(string: "https://example.com/work")!

        appDelegate.application(NSApplication.shared, open: [url])

        await fulfillment(of: [intakeHandler.callsExpectation], timeout: 2.0)
        XCTAssertEqual(
            intakeHandler.calls,
            [
                URLIntakeHandlerSpy.Call(
                    urls: [url],
                    sourceBundleID: "com.tinyspeck.slackmacgap"
                ),
            ]
        )
    }

    @MainActor
    func testApplicationOpenPassesNilWhenSourceBundleIDCannotBeResolved() async {
        let appDelegate = AppDelegate()
        let intakeHandler = URLIntakeHandlerSpy()
        intakeHandler.expectedCallCount = 1
        appDelegate.sourceBundleIDResolver = StubSourceBundleIDResolver(sourceBundleID: nil)
        appDelegate.urlIntakeHandler = intakeHandler
        let url = URL(string: "https://example.com/default-browser")!

        appDelegate.application(NSApplication.shared, open: [url])

        await fulfillment(of: [intakeHandler.callsExpectation], timeout: 2.0)
        XCTAssertEqual(
            intakeHandler.calls,
            [
                URLIntakeHandlerSpy.Call(
                    urls: [url],
                    sourceBundleID: nil
                ),
            ]
        )
    }

    @MainActor
    func testApplicationShouldHandleReopenShowsMainWindowWhenNoVisibleWindows() {
        let appDelegate = AppDelegate()
        let testWindow = makeTestWindow()
        appDelegate.window = testWindow

        let shouldContinueDefaultHandling = appDelegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: false)

        XCTAssertFalse(shouldContinueDefaultHandling)
        XCTAssertTrue(testWindow.isVisible)
    }

    @MainActor
    func testApplicationShouldHandleReopenDefersToSystemWhenVisibleWindowsExist() {
        let appDelegate = AppDelegate()
        appDelegate.window = makeTestWindow()

        let shouldContinueDefaultHandling = appDelegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: true)

        XCTAssertTrue(shouldContinueDefaultHandling)
    }

    @MainActor
    func testShowPreferencesWindowShowsMainWindow() {
        let appDelegate = AppDelegate()
        let testWindow = makeTestWindow()
        appDelegate.window = testWindow

        appDelegate.showPreferencesWindow(nil)

        XCTAssertTrue(testWindow.isVisible)
    }

    @MainActor
    func testAppInstanceCoordinatorPrefersInstalledAppOverBuildArtifacts() {
        let coordinator = AppInstanceCoordinator()

        let resolution = coordinator.resolve(
            currentProcessIdentifier: 200,
            currentBundleURL: URL(fileURLWithPath: "/Applications/LinkSwitch Dev.app"),
            otherInstances: [
                RunningAppInstance(
                    processIdentifier: 100,
                    bundleURL: URL(fileURLWithPath: "/Users/helios/linkswitch/build/DerivedData/Build/Products/Debug/LinkSwitch.app")
                ),
                RunningAppInstance(
                    processIdentifier: 300,
                    bundleURL: URL(fileURLWithPath: "/Users/helios/Library/Developer/Xcode/DerivedData/LinkSwitch/Build/Products/Debug/LinkSwitch.app")
                ),
            ]
        )

        XCTAssertEqual(
            resolution,
            .continueRunning(inferiorProcessIdentifiers: [100, 300])
        )
    }

    @MainActor
    func testAppInstanceCoordinatorTerminatesBuildArtifactWhenInstalledAppExists() {
        let coordinator = AppInstanceCoordinator()

        let resolution = coordinator.resolve(
            currentProcessIdentifier: 300,
            currentBundleURL: URL(fileURLWithPath: "/Users/helios/linkswitch/build/DerivedData/Build/Products/Debug/LinkSwitch.app"),
            otherInstances: [
                RunningAppInstance(
                    processIdentifier: 200,
                    bundleURL: URL(fileURLWithPath: "/Applications/LinkSwitch Dev.app")
                ),
            ]
        )

        XCTAssertEqual(
            resolution,
            .terminateSelf(preferredProcessIdentifier: 200)
        )
    }

    @MainActor
    func testAppInstanceCoordinatorUsesOldestProcessWhenLocationsTie() {
        let coordinator = AppInstanceCoordinator()

        let resolution = coordinator.resolve(
            currentProcessIdentifier: 300,
            currentBundleURL: URL(fileURLWithPath: "/Users/helios/linkswitch/build/DerivedData/Build/Products/Debug/LinkSwitch.app"),
            otherInstances: [
                RunningAppInstance(
                    processIdentifier: 200,
                    bundleURL: URL(fileURLWithPath: "/Users/helios/Library/Developer/Xcode/DerivedData/LinkSwitch/Build/Products/Debug/LinkSwitch.app")
                ),
            ]
        )

        XCTAssertEqual(
            resolution,
            .terminateSelf(preferredProcessIdentifier: 200)
        )
    }
}

private struct StubSourceBundleIDResolver: SourceBundleIDResolving {
    let sourceBundleID: String?

    func resolveSourceBundleID() -> String? {
        sourceBundleID
    }
}

private final class URLIntakeHandlerSpy: URLIntakeHandling {
    struct Call: Equatable {
        let urls: [URL]
        let sourceBundleID: String?
    }

    var expectedCallCount = 1 {
        didSet {
            callsExpectation.expectedFulfillmentCount = expectedCallCount
        }
    }

    let callsExpectation = XCTestExpectation(description: "URL intake handler called")
    private(set) var calls: [Call] = []

    func handle(urls: [URL], sourceBundleID: String?) async throws {
        calls.append(Call(urls: urls, sourceBundleID: sourceBundleID))
        callsExpectation.fulfill()
    }
}

@MainActor
private func makeTestWindow() -> NSWindow {
    NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
    )
}
