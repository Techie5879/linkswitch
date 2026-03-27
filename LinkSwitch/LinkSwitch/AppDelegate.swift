//
//  AppDelegate.swift
//  LinkSwitch
//
//  Created by Aritra Bandyopadhyay on 27/03/26.
//

import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    @IBOutlet var window: NSWindow!
    var sourceBundleIDResolver: any SourceBundleIDResolving = SourceAppResolver()
    var urlIntakeHandler: (any URLIntakeHandling)?
    private var preferencesWindowController: PreferencesWindowController?


    func applicationDidFinishLaunching(_ aNotification: Notification) {
        AppLogger.info("Application finished launching", category: .app)
        wirePreferencesMenuItem()
        configureMainWindowContent()
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

    @objc func showPreferencesWindow(_ sender: Any?) {
        do {
            let preferencesWindowController = try makePreferencesWindowController()
            preferencesWindowController.showWindow(nil)
            preferencesWindowController.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            AppLogger.info("Presented preferences window", category: .app)
        } catch {
            AppLogger.error("Failed to present preferences window: \(error)", category: .app)
        }
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
        guard let contentView = window.contentView else {
            AppLogger.error("Main window content view was unavailable for configuration", category: .app)
            return
        }

        contentView.subviews.forEach { $0.removeFromSuperview() }

        let stackView = NSStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 16

        let titleLabel = NSTextField(labelWithString: "LinkSwitch")
        titleLabel.font = .boldSystemFont(ofSize: 24)

        let descriptionLabel = NSTextField(wrappingLabelWithString: "Use Preferences to choose the fallback browser, define source-app rules, and test the routing setup before registering LinkSwitch as the URL handler.")
        descriptionLabel.maximumNumberOfLines = 0
        descriptionLabel.alignment = .center

        let preferencesButton = NSButton(title: "Open Preferences…", target: self, action: #selector(showPreferencesWindow(_:)))
        preferencesButton.bezelStyle = .rounded
        preferencesButton.setAccessibilityIdentifier("mainWindow.openPreferencesButton")

        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(descriptionLabel)
        stackView.addArrangedSubview(preferencesButton)

        contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 24),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -24),
            descriptionLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
        ])

        AppLogger.info("Configured main window content with preferences shortcut UI", category: .app)
    }

    private func makePreferencesWindowController() throws -> PreferencesWindowController {
        if let preferencesWindowController {
            return preferencesWindowController
        }

        let windowController = try PreferencesWindowController(model: PreferencesModel.live())
        preferencesWindowController = windowController
        return windowController
    }
}

