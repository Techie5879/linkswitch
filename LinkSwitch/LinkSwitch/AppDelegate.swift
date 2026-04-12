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

struct RunningAppInstance: Equatable {
    let processIdentifier: pid_t
    let bundleURL: URL?
}

protocol RunningApplicationMonitoring {
    func runningInstances(bundleIdentifier: String) -> [RunningAppInstance]
    func terminate(processIdentifier: pid_t) -> Bool
}

struct AppInstanceCoordinator {
    func resolve(
        currentProcessIdentifier: pid_t,
        currentBundleURL: URL,
        otherInstances: [RunningAppInstance]
    ) -> SingleInstanceResolution {
        let currentInstance = RunningAppInstance(
            processIdentifier: currentProcessIdentifier,
            bundleURL: currentBundleURL.standardizedFileURL
        )
        let allInstances = [currentInstance] + otherInstances

        guard let preferredInstance = allInstances.min(by: { prefers($0, over: $1) }) else {
            return .continueRunning(inferiorProcessIdentifiers: [])
        }

        guard preferredInstance.processIdentifier == currentProcessIdentifier else {
            return .terminateSelf(preferredProcessIdentifier: preferredInstance.processIdentifier)
        }

        let inferiorProcessIdentifiers = otherInstances
            .filter { prefers(currentInstance, over: $0) }
            .map(\.processIdentifier)

        return .continueRunning(inferiorProcessIdentifiers: inferiorProcessIdentifiers)
    }

    private func prefers(_ lhs: RunningAppInstance, over rhs: RunningAppInstance) -> Bool {
        let lhsRank = installationRank(for: lhs.bundleURL)
        let rhsRank = installationRank(for: rhs.bundleURL)

        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }

        return lhs.processIdentifier < rhs.processIdentifier
    }

    private func installationRank(for bundleURL: URL?) -> Int {
        guard let bundleURL else {
            return 1
        }

        let standardizedPath = bundleURL.standardizedFileURL.path
        let homeApplicationsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
            .path

        if standardizedPath.hasPrefix("/Applications/") || standardizedPath.hasPrefix(homeApplicationsPath + "/") {
            return 0
        }

        return 1
    }
}

enum SingleInstanceResolution: Equatable {
    case continueRunning(inferiorProcessIdentifiers: [pid_t])
    case terminateSelf(preferredProcessIdentifier: pid_t)
}

struct RunningApplicationMonitor: RunningApplicationMonitoring {
    func runningInstances(bundleIdentifier: String) -> [RunningAppInstance] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { !$0.isTerminated }
            .map {
                RunningAppInstance(
                    processIdentifier: $0.processIdentifier,
                    bundleURL: $0.bundleURL?.standardizedFileURL
                )
            }
    }

    func terminate(processIdentifier: pid_t) -> Bool {
        guard let application = NSRunningApplication(processIdentifier: processIdentifier) else {
            return false
        }

        return application.terminate()
    }
}

private enum StatusItemIcon {
    static func makeTemplateImage() -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        guard
            let base = NSImage(systemSymbolName: "shuffle", accessibilityDescription: nil),
            let image = base.withSymbolConfiguration(config)
        else {
            AppLogger.error("Failed to load SF Symbol 'shuffle' for status item", category: .app)
            return NSImage()
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
    var runningApplicationMonitor: any RunningApplicationMonitoring = RunningApplicationMonitor()
    private var preferencesViewController: PreferencesViewController?
    private var mainWindowConfigurationError: (any Error)?
    private var statusItem: NSStatusItem?


    func applicationDidFinishLaunching(_ aNotification: Notification) {
        AppLogger.info("Application finished launching", category: .app)
        guard enforceSingleInstancePolicy() else {
            return
        }

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

    private func enforceSingleInstancePolicy() -> Bool {
        if isRunningForXCTest {
            AppLogger.info("Skipping single-instance enforcement for XCTest-driven launch", category: .app)
            return true
        }

        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            AppLogger.error("Bundle identifier was unavailable during startup single-instance check", category: .app)
            return true
        }

        let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        let currentBundleURL = Bundle.main.bundleURL.standardizedFileURL
        let otherInstances = runningApplicationMonitor.runningInstances(bundleIdentifier: bundleIdentifier)
            .filter { $0.processIdentifier != currentProcessIdentifier }
        let resolution = AppInstanceCoordinator().resolve(
            currentProcessIdentifier: currentProcessIdentifier,
            currentBundleURL: currentBundleURL,
            otherInstances: otherInstances
        )

        switch resolution {
        case let .continueRunning(inferiorProcessIdentifiers):
            for processIdentifier in inferiorProcessIdentifiers {
                let didRequestTermination = runningApplicationMonitor.terminate(processIdentifier: processIdentifier)
                if didRequestTermination {
                    AppLogger.info(
                        "Continuing preferred instance at \(currentBundleURL.path()) and requesting termination of inferior pid \(processIdentifier)",
                        category: .app
                    )
                } else {
                    AppLogger.error(
                        "Preferred instance at \(currentBundleURL.path()) could not request termination of inferior pid \(processIdentifier)",
                        category: .app
                    )
                }
            }
            return true
        case let .terminateSelf(preferredProcessIdentifier):
            AppLogger.info(
                "Detected preferred existing instance pid \(preferredProcessIdentifier); terminating current instance at \(currentBundleURL.path())",
                category: .app
            )
            NSApp.terminate(nil)
            return false
        }
    }

    private var isRunningForXCTest: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCInjectBundleInto"] != nil
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
