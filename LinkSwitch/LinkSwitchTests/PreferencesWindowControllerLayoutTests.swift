import AppKit
import XCTest
@testable import LinkSwitch

@MainActor
final class PreferencesWindowControllerLayoutTests: XCTestCase {
    func testRuleActionButtonsStayWithinVisibleWindowWidth() throws {
        let config = RouterConfig(
            defaultBrowserBundleID: "com.apple.Safari",
            defaultBrowserAppURL: URL(fileURLWithPath: "/Applications/Safari.app"),
            defaultBrowserRoute: .plain,
            rules: [
                SourceAppRule(
                    id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
                    sourceBundleID: "com.tinyspeck.slackmacgap",
                    target: .helium(profileDirectory: "Aritra")
                ),
                SourceAppRule(
                    id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
                    sourceBundleID: "notion.id",
                    target: .helium(profileDirectory: "Brighterway")
                ),
            ]
        )
        let model = PreferencesModel(
            configStore: LayoutPreferencesConfigStoreStub(loadResult: config),
            browserLauncher: LayoutBrowserLauncherSpy(),
            configFileURLDescription: "/tmp/router-config.json",
            browserDiscovery: LayoutBrowserDiscoveryStub(browsers: []),
            installedApplicationDiscovery: LayoutInstalledApplicationDiscoveryStub(
                applications: [
                    DiscoveredApplication(
                        bundleID: "com.tinyspeck.slackmacgap",
                        name: "Slack",
                        appURL: URL(fileURLWithPath: "/Applications/Slack.app")
                    ),
                    DiscoveredApplication(
                        bundleID: "notion.id",
                        name: "Notion",
                        appURL: URL(fileURLWithPath: "/Applications/Notion.app")
                    ),
                ]
            )
        )
        let controller = try PreferencesViewController(model: model)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 680),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        controller.configureWindow(window)
        window.contentViewController = controller
        window.contentView?.layoutSubtreeIfNeeded()
        controller.view.layoutSubtreeIfNeeded()

        let removeButtons = allSubviews(in: controller.view)
            .compactMap { $0 as? NSButton }
            .filter { $0.title == "Remove" }

        XCTAssertEqual(removeButtons.count, 2)

        for button in removeButtons {
            let frameInRootView = button.convert(button.bounds, to: controller.view)
            XCTAssertLessThanOrEqual(
                frameInRootView.maxX,
                controller.view.bounds.maxX,
                "Expected \(button.title) button to stay inside the visible window width"
            )
        }
    }

    func testRuleTargetBrowserPopupListsDiscoveredBrowsersWithoutMenuIcons() throws {
        let config = RouterConfig(
            defaultBrowserBundleID: "com.apple.Safari",
            defaultBrowserAppURL: URL(fileURLWithPath: "/Applications/Safari.app"),
            defaultBrowserRoute: .plain,
            rules: [
                SourceAppRule(
                    id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
                    sourceBundleID: "com.tinyspeck.slackmacgap",
                    target: .defaultBrowser
                ),
            ]
        )
        let controller = try makeController(
            config: config,
            browsers: [
                DiscoveredBrowser(bundleID: "com.google.Chrome", name: "Google Chrome", appURL: URL(fileURLWithPath: "/Applications/Google Chrome.app")),
                DiscoveredBrowser(bundleID: BrowserLauncher.heliumBundleID, name: "Helium", appURL: URL(fileURLWithPath: "/Applications/Helium.app")),
                DiscoveredBrowser(bundleID: "com.apple.Safari", name: "Safari", appURL: URL(fileURLWithPath: "/Applications/Safari.app")),
                DiscoveredBrowser(bundleID: FirefoxBrowserAppSupportPath.zenBrowserBundleID, name: "Zen", appURL: URL(fileURLWithPath: "/Applications/Zen.app")),
            ],
            applications: [
                DiscoveredApplication(
                    bundleID: "com.tinyspeck.slackmacgap",
                    name: "Slack",
                    appURL: URL(fileURLWithPath: "/Applications/Slack.app")
                ),
            ]
        )

        let popup = try XCTUnwrap(
            allSubviews(in: controller.view)
                .compactMap { $0 as? NSPopUpButton }
                .first { $0.accessibilityIdentifier() == "preferences.rule.targetBrowserPopup" }
        )
        let menuItems = try XCTUnwrap(popup.menu?.items)

        XCTAssertEqual(
            menuItems.map(\.title),
            ["Default Browser", "", "Google Chrome", "Helium", "Safari", "Zen"]
        )
        XCTAssertTrue(menuItems.filter { !$0.isSeparatorItem }.allSatisfy { $0.image == nil })
    }

    private func makeController(
        config: RouterConfig,
        browsers: [DiscoveredBrowser],
        applications: [DiscoveredApplication]
    ) throws -> PreferencesViewController {
        let model = PreferencesModel(
            configStore: LayoutPreferencesConfigStoreStub(loadResult: config),
            browserLauncher: LayoutBrowserLauncherSpy(),
            configFileURLDescription: "/tmp/router-config.json",
            browserDiscovery: LayoutBrowserDiscoveryStub(browsers: browsers),
            installedApplicationDiscovery: LayoutInstalledApplicationDiscoveryStub(applications: applications)
        )
        let controller = try PreferencesViewController(model: model)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 680),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        controller.configureWindow(window)
        window.contentViewController = controller
        window.contentView?.layoutSubtreeIfNeeded()
        controller.view.layoutSubtreeIfNeeded()
        return controller
    }

    private func allSubviews(in view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(allSubviews)
    }
}

private struct LayoutPreferencesConfigStoreStub: RouterConfigLoading, RouterConfigSaving {
    let loadResult: RouterConfig?

    func load() throws -> RouterConfig? {
        loadResult
    }

    func save(_ config: RouterConfig) throws {}
}

private final class LayoutBrowserLauncherSpy: BrowserLaunching {
    func open(_ url: URL, target: BrowserTarget, config: RouterConfig) async throws {}
}

private struct LayoutBrowserDiscoveryStub: BrowserDiscovering {
    let browsers: [DiscoveredBrowser]

    func discoverBrowsers(excludingBundleID: String?) -> [DiscoveredBrowser] {
        browsers
    }
}

private struct LayoutInstalledApplicationDiscoveryStub: InstalledApplicationDiscovering {
    let applications: [DiscoveredApplication]

    func discoverInstalledApplications(excludingBundleID: String?) -> [DiscoveredApplication] {
        applications
    }
}
