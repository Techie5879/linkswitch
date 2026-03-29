import Foundation

/// Creates the appropriate BrowserProfileDiscovering instance for a given browser bundle ID.
/// Returns nil when the bundle ID is not a known profile-capable browser.
struct BrowserProfileDiscoveryFactory {
    private let appSupportURL: URL

    init() {
        appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    init(appSupportURL: URL) {
        self.appSupportURL = appSupportURL
    }

    func makeDiscoverer(forBundleID bundleID: String) -> (any BrowserProfileDiscovering)? {
        if let relativePath = ChromiumBrowserAppSupportPath.relativePath(forBundleID: bundleID) {
            let localStateURL = appSupportURL
                .appendingPathComponent(relativePath)
                .appendingPathComponent("Local State")
            AppLogger.info(
                "BrowserProfileDiscoveryFactory: Chromium discoverer for \(bundleID) at \(localStateURL.path(percentEncoded: false))",
                category: .app
            )
            return ChromiumProfileDiscovery(localStateURL: localStateURL)
        }

        if let relativePath = FirefoxBrowserAppSupportPath.relativePath(forBundleID: bundleID) {
            let profilesIniURL: URL
            if relativePath.hasPrefix("~/") {
                // e.g. LibreWolf: ~/.librewolf/profiles.ini
                let home = FileManager.default.homeDirectoryForCurrentUser
                profilesIniURL = home
                    .appendingPathComponent(String(relativePath.dropFirst(2)))
                    .appendingPathComponent("profiles.ini")
            } else {
                profilesIniURL = appSupportURL
                    .appendingPathComponent(relativePath)
                    .appendingPathComponent("profiles.ini")
            }
            AppLogger.info(
                "BrowserProfileDiscoveryFactory: Firefox discoverer for \(bundleID) at \(profilesIniURL.path(percentEncoded: false))",
                category: .app
            )
            return FirefoxProfileDiscovery(profilesIniURL: profilesIniURL)
        }

        AppLogger.info(
            "BrowserProfileDiscoveryFactory: no discoverer registered for bundle ID \(bundleID)",
            category: .app
        )
        return nil
    }
}
