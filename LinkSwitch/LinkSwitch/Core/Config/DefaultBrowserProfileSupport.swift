import Foundation

enum DefaultBrowserProfileSupport: Equatable {
    case plainOnly
    case heliumProfile
    case firefoxProfile
    case zenContainer

    static func forBundleID(_ bundleID: String) -> DefaultBrowserProfileSupport {
        if bundleID == FirefoxBrowserAppSupportPath.zenBrowserBundleID {
            return .zenContainer
        }
        if bundleID == BrowserLauncher.heliumBundleID {
            return .heliumProfile
        }
        if FirefoxBrowserAppSupportPath.supportsDefaultProfileRouting(forBundleID: bundleID) {
            return .firefoxProfile
        }
        return .plainOnly
    }
}
