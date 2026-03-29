import AppKit

/// Resolves and caches NSImage icons for applications by bundle ID or app URL.
/// All access must happen on the main actor; icons are AppKit objects.
@MainActor
final class AppIconProvider {
    private var cache: [String: NSImage] = [:]

    /// Returns the icon for an application identified by its bundle ID.
    /// Falls back to a generic application icon placeholder when the app cannot be located.
    func icon(forBundleID bundleID: String) -> NSImage {
        if let cached = cache[bundleID] {
            return cached
        }

        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            AppLogger.debug(
                "AppIconProvider could not locate app URL for bundle ID \(bundleID); using placeholder",
                category: .app
            )
            let placeholder = genericAppIcon()
            cache[bundleID] = placeholder
            return placeholder
        }

        let icon = NSWorkspace.shared.icon(forFile: appURL.path())
        cache[bundleID] = icon
        AppLogger.debug("AppIconProvider cached icon for bundle ID \(bundleID)", category: .app)
        return icon
    }

    /// Returns the icon for an application at the given file URL.
    func icon(forAppURL appURL: URL) -> NSImage {
        let cacheKey = appURL.path()
        if let cached = cache[cacheKey] {
            return cached
        }

        let icon = NSWorkspace.shared.icon(forFile: appURL.path())
        cache[cacheKey] = icon
        AppLogger.debug("AppIconProvider cached icon for app URL \(appURL.path())", category: .app)
        return icon
    }

    func clearCache() {
        cache.removeAll()
        AppLogger.debug("AppIconProvider cache cleared", category: .app)
    }

    private func genericAppIcon() -> NSImage {
        NSImage(named: NSImage.applicationIconName) ?? NSImage()
    }
}
