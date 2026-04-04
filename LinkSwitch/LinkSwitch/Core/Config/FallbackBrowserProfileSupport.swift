import Foundation

enum FallbackBrowserProfileSupport: Equatable {
    case plainOnly
    case heliumProfile
    case firefoxProfile
    case zenContainer

    static func forBundleID(_ bundleID: String) -> FallbackBrowserProfileSupport {
        if bundleID == FirefoxBrowserAppSupportPath.zenBrowserBundleID {
            return .zenContainer
        }
        if bundleID == BrowserLauncher.heliumBundleID {
            return .heliumProfile
        }
        if FirefoxBrowserAppSupportPath.supportsFallbackProfileRouting(forBundleID: bundleID) {
            return .firefoxProfile
        }
        return .plainOnly
    }
}
