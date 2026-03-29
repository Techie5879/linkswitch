import AppKit

protocol ApplicationIconResolving {
    func applicationURL(forBundleIdentifier bundleID: String) -> URL?
    func icon(forFilePath path: String) -> NSImage
}

struct WorkspaceApplicationIconResolver: ApplicationIconResolving {
    func applicationURL(forBundleIdentifier bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    func icon(forFilePath path: String) -> NSImage {
        NSWorkspace.shared.icon(forFile: path)
    }
}

/// Resolves and caches NSImage icons for applications by bundle ID or app URL.
/// All access must happen on the main actor; icons are AppKit objects.
@MainActor
final class AppIconProvider {
    private let resolver: any ApplicationIconResolving
    private var cache: [String: NSImage] = [:]

    init(resolver: any ApplicationIconResolving = WorkspaceApplicationIconResolver()) {
        self.resolver = resolver
    }

    /// Returns the icon for an application identified by its bundle ID.
    /// Falls back to a generic application icon placeholder when the app cannot be located.
    func icon(forBundleID bundleID: String) -> NSImage {
        if let cached = cache[bundleID] {
            return cached
        }

        guard let appURL = resolver.applicationURL(forBundleIdentifier: bundleID) else {
            AppLogger.debug(
                "AppIconProvider could not locate app URL for bundle ID \(bundleID); using placeholder",
                category: .app
            )
            let placeholder = genericAppIcon()
            cache[bundleID] = placeholder
            return placeholder
        }

        let icon = resolver.icon(forFilePath: appURL.path(percentEncoded: false))
        cache[bundleID] = icon
        AppLogger.debug("AppIconProvider cached icon for bundle ID \(bundleID)", category: .app)
        return icon
    }

    /// Returns the icon for an application at the given file URL.
    func icon(forAppURL appURL: URL) -> NSImage {
        let cacheKey = appURL.path(percentEncoded: false)
        if let cached = cache[cacheKey] {
            return cached
        }

        if let bundleID = Bundle(url: appURL)?.bundleIdentifier {
            if let cached = cache[bundleID] {
                cache[cacheKey] = cached
                AppLogger.debug(
                    "AppIconProvider reused cached icon for app URL \(cacheKey) via bundle ID \(bundleID)",
                    category: .app
                )
                return cached
            }

            if let canonicalAppURL = resolver.applicationURL(forBundleIdentifier: bundleID) {
                let icon = resolver.icon(forFilePath: canonicalAppURL.path(percentEncoded: false))
                cache[bundleID] = icon
                cache[cacheKey] = icon
                AppLogger.debug(
                    "AppIconProvider resolved app URL \(cacheKey) to canonical app URL \(canonicalAppURL.path(percentEncoded: false)) for bundle ID \(bundleID)",
                    category: .app
                )
                return icon
            }

            AppLogger.debug(
                "AppIconProvider could not resolve canonical app URL for bundle ID \(bundleID); using provided app URL \(cacheKey)",
                category: .app
            )
        }

        let icon = resolver.icon(forFilePath: cacheKey)
        cache[cacheKey] = icon
        AppLogger.debug("AppIconProvider cached icon for app URL \(cacheKey)", category: .app)
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
