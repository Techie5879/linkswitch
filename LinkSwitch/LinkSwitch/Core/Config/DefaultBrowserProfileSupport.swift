import Foundation

enum DefaultBrowserProfileSupport: Equatable {
    case plainOnly
    /// Chromium-family browsers launched with `--profile-directory=<name>`.
    case chromiumProfile
    case firefoxProfile
    case zenContainer

    static func forBundleID(_ bundleID: String) -> DefaultBrowserProfileSupport {
        if bundleID == FirefoxBrowserAppSupportPath.zenBrowserBundleID {
            return .zenContainer
        }
        if ChromiumBrowserAppSupportPath.relativePath(forBundleID: bundleID) != nil {
            return .chromiumProfile
        }
        if FirefoxBrowserAppSupportPath.supportsDefaultProfileRouting(forBundleID: bundleID) {
            return .firefoxProfile
        }
        return .plainOnly
    }
}
