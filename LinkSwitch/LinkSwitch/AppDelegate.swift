//
//  AppDelegate.swift
//  LinkSwitch
//
//  Created by Aritra Bandyopadhyay on 27/03/26.
//

import Cocoa

private enum LaunchArgument {
    static let showMainWindowForUITests = "--ui-test-show-main-window"
}

private enum StatusItemIcon {
    static func makeTemplateImage() -> NSImage {
        let imageSize = NSSize(width: 18, height: 18)
        let image = NSImage(size: imageSize, flipped: false) { _ in
            NSColor.black.setFill()
            NSColor.black.setStroke()

            NSBezierPath(
                roundedRect: NSRect(x: 2.0, y: 6.0, width: 4.5, height: 6.0),
                xRadius: 1.2,
                yRadius: 1.2
            ).fill()

            NSBezierPath(
                roundedRect: NSRect(x: 11.0, y: 11.5, width: 5.0, height: 3.0),
                xRadius: 1.0,
                yRadius: 1.0
            ).fill()

            NSBezierPath(
                roundedRect: NSRect(x: 11.0, y: 3.5, width: 5.0, height: 3.0),
                xRadius: 1.0,
                yRadius: 1.0
            ).fill()

            let routePath = NSBezierPath()
            routePath.lineWidth = 2.0
            routePath.lineCapStyle = .round
            routePath.lineJoinStyle = .round
            routePath.move(to: NSPoint(x: 1.0, y: 9.0))
            routePath.line(to: NSPoint(x: 2.0, y: 9.0))
            routePath.move(to: NSPoint(x: 6.5, y: 9.0))
            routePath.line(to: NSPoint(x: 9.0, y: 9.0))
            routePath.line(to: NSPoint(x: 9.0, y: 13.0))
            routePath.line(to: NSPoint(x: 11.0, y: 13.0))
            routePath.move(to: NSPoint(x: 9.0, y: 9.0))
            routePath.line(to: NSPoint(x: 9.0, y: 5.0))
            routePath.line(to: NSPoint(x: 11.0, y: 5.0))
            routePath.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    @IBOutlet var window: NSWindow!
    var sourceBundleIDResolver: any SourceBundleIDResolving = SourceAppResolver()
    var urlIntakeHandler: (any URLIntakeHandling)?
    private var preferencesViewController: PreferencesViewController?
    private var mainWindowConfigurationError: (any Error)?
    private var statusItem: NSStatusItem?


    func applicationDidFinishLaunching(_ aNotification: Notification) {
        AppLogger.info("Application finished launching", category: .app)
        wirePreferencesMenuItem()
        configureMainWindowContent()
        installStatusItem()
        registerMainWindowLifecycleObserver()
        configureInitialPresentation()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        AppLogger.info("Application will terminate", category: .app)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        AppLogger.info("Application received \(urls.count) URL(s) from AppKit open handler", category: .app)
        let sourceBundleID = sourceBundleIDResolver.resolveSourceBundleID()
        AppLogger.info("AppDelegate resolved source bundle ID \(sourceBundleID ?? "nil") before async intake", category: .app)

        Task { @MainActor in
            do {
                let intakeHandler = try makeURLIntakeHandler()
                try await intakeHandler.handle(urls: urls, sourceBundleID: sourceBundleID)
            } catch {
                AppLogger.error("Failed handling incoming URLs \(urls): \(error)", category: .app)
            }
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        AppLogger.debug("Secure restorable state requested", category: .app)
        return true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppLogger.info("Application reopen requested. hasVisibleWindows=\(flag)", category: .app)
        guard !flag else {
            return true
        }

        showMainWindow(nil)
        return false
    }

    @objc func showMainWindow(_ sender: Any?) {
        guard let window else {
            AppLogger.error("Main window was unavailable when presentation was requested", category: .app)
            return
        }

        if let mainWindowConfigurationError {
            AppLogger.error(
                "Refusing to present main window because the embedded preferences UI failed to load: \(mainWindowConfigurationError)",
                category: .app
            )
            presentMainWindowConfigurationError(mainWindowConfigurationError)
            return
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        AppLogger.info("Presented main window", category: .app)
    }

    @objc func showPreferencesWindow(_ sender: Any?) {
        AppLogger.info("Preferences presentation requested; using the single main window", category: .app)
        showMainWindow(sender)
    }

    private func makeURLIntakeHandler() throws -> any URLIntakeHandling {
        if let urlIntakeHandler {
            return urlIntakeHandler
        }

        return try URLIntakeController.live()
    }

    private func wirePreferencesMenuItem() {
        guard
            let mainMenu = NSApp.mainMenu,
            let preferencesMenuItem = findPreferencesMenuItem(in: mainMenu)
        else {
            AppLogger.info("Preferences menu item was not present in the loaded main menu", category: .app)
            return
        }

        preferencesMenuItem.target = self
        preferencesMenuItem.action = #selector(showPreferencesWindow(_:))
        AppLogger.info("Wired Preferences menu item to AppDelegate", category: .app)
    }

    private func findPreferencesMenuItem(in menu: NSMenu) -> NSMenuItem? {
        for item in menu.items {
            if item.title == "Preferences…" {
                return item
            }

            if
                item.keyEquivalent == ",",
                item.keyEquivalentModifierMask.contains(.command)
            {
                return item
            }

            if let submenu = item.submenu, let nestedItem = findPreferencesMenuItem(in: submenu) {
                return nestedItem
            }
        }

        return nil
    }

    private func configureMainWindowContent() {
        guard let window else {
            AppLogger.error("Main window was unavailable for configuration", category: .app)
            return
        }

        do {
            let preferencesViewController = try makePreferencesViewController()
            preferencesViewController.configureWindow(window)
            window.contentViewController = preferencesViewController
            mainWindowConfigurationError = nil
            AppLogger.info("Configured main window with embedded preferences UI", category: .app)
        } catch {
            mainWindowConfigurationError = error
            AppLogger.error("Failed to configure main window with embedded preferences UI: \(error)", category: .app)
        }
    }

    private func installStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.statusItem = statusItem

        guard let button = statusItem.button else {
            AppLogger.error("Status item button was unavailable after installation", category: .app)
            return
        }

        button.title = ""
        button.image = StatusItemIcon.makeTemplateImage()
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = "LinkSwitch"
        button.setAccessibilityLabel("LinkSwitch status item")

        let menu = NSMenu()

        let preferencesItem = NSMenuItem(title: "Preferences…", action: #selector(showPreferencesWindow(_:)), keyEquivalent: ",")
        preferencesItem.keyEquivalentModifierMask = [.command]
        preferencesItem.target = self
        menu.addItem(preferencesItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit LinkSwitch", action: #selector(terminateApp(_:)), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        AppLogger.info("Installed icon-based status item menu with preferences and quit actions", category: .app)
    }

    private func registerMainWindowLifecycleObserver() {
        guard let window else {
            AppLogger.error("Main window was unavailable when registering lifecycle observer", category: .app)
            return
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: window
        )
        AppLogger.info("Registered main window lifecycle observer", category: .app)
    }

    private func configureInitialPresentation() {
        if ProcessInfo.processInfo.arguments.contains(LaunchArgument.showMainWindowForUITests) {
            let activationPolicyChanged = NSApp.setActivationPolicy(.regular)
            AppLogger.info(
                "Enabled UI-test launch mode with visible main window. activationPolicyChanged=\(activationPolicyChanged)",
                category: .app
            )
            showMainWindow(nil)
            return
        }

        guard let window else {
            AppLogger.error("Main window was unavailable when configuring initial presentation", category: .app)
            return
        }

        window.orderOut(nil)
        AppLogger.info("Configured status-item-first launch by hiding the main window", category: .app)
    }

    @objc private func handleWindowWillClose(_ notification: Notification) {
        guard let closedWindow = notification.object as? NSWindow else {
            AppLogger.error("Received window close notification without an NSWindow instance", category: .app)
            return
        }

        let windowRole: String
        if let window, closedWindow == window {
            windowRole = "main"
        } else {
            windowRole = "unknown"
        }

        AppLogger.info("Window will close. role=\(windowRole)", category: .app)
    }

    @objc private func terminateApp(_ sender: Any?) {
        AppLogger.info("Application termination requested from status item", category: .app)
        NSApp.terminate(sender)
    }

    private func presentMainWindowConfigurationError(_ error: any Error) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Could not load the LinkSwitch window."
        alert.informativeText = String(describing: error)
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func makePreferencesViewController() throws -> PreferencesViewController {
        if let preferencesViewController {
            return preferencesViewController
        }

        let viewController = try PreferencesViewController(model: PreferencesModel.live())
        preferencesViewController = viewController
        AppLogger.info("Created preferences view controller for the main window", category: .app)
        return viewController
    }
}

