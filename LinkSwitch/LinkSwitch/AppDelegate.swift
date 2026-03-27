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


    func applicationDidFinishLaunching(_ aNotification: Notification) {
        AppLogger.info("Application finished launching", category: .app)
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        AppLogger.info("Application will terminate", category: .app)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        AppLogger.info("Application received \(urls.count) URL(s) from AppKit open handler", category: .app)

        Task { @MainActor in
            do {
                let intakeController = try URLIntakeController.live()
                try await intakeController.handle(urls: urls, sourceBundleID: nil)
            } catch {
                AppLogger.error("Failed handling incoming URLs \(urls): \(error)", category: .app)
            }
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        AppLogger.debug("Secure restorable state requested", category: .app)
        return true
    }
}

