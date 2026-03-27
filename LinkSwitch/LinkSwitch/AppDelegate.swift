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

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        AppLogger.debug("Secure restorable state requested", category: .app)
        return true
    }
}

