import AppKit
import Foundation

struct DiscoveredBrowser: Identifiable, Equatable {
    var id: String { bundleID }
    let bundleID: String
    let name: String
    let appURL: URL
}

protocol BrowserDiscovering {
    func discoverBrowsers(excludingBundleID: String?) -> [DiscoveredBrowser]
}

struct BrowserDiscovery: BrowserDiscovering {
    func discoverBrowsers(excludingBundleID: String?) -> [DiscoveredBrowser] {
        guard let probeURL = URL(string: "https://example.com") else {
            AppLogger.error("Could not construct probe URL for browser discovery", category: .app)
            return []
        }

        let appURLs = NSWorkspace.shared.urlsForApplications(toOpen: probeURL)
        AppLogger.info("Browser discovery found \(appURLs.count) raw candidate(s) for https URL handler", category: .app)

        var seen = Set<String>()
        var browsers: [DiscoveredBrowser] = []

        for appURL in appURLs {
            guard
                let bundle = Bundle(url: appURL),
                let bundleID = bundle.bundleIdentifier
            else {
                AppLogger.debug(
                    "Skipping browser candidate at \(appURL.path()): missing bundle or bundle ID",
                    category: .app
                )
                continue
            }

            if let excluded = excludingBundleID, bundleID == excluded {
                AppLogger.debug("Excluding \(bundleID) from browser discovery (self-exclusion)", category: .app)
                continue
            }

            guard seen.insert(bundleID).inserted else {
                AppLogger.debug("Skipping duplicate bundle ID \(bundleID) in browser discovery", category: .app)
                continue
            }

            let name =
                bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? appURL.deletingPathExtension().lastPathComponent

            AppLogger.debug("Discovered browser \(bundleID) (\(name)) at \(appURL.path())", category: .app)
            browsers.append(DiscoveredBrowser(bundleID: bundleID, name: name, appURL: appURL))
        }

        browsers.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        AppLogger.info(
            "Browser discovery completed: \(browsers.count) browser(s) — \(browsers.map(\.bundleID).joined(separator: ", "))",
            category: .app
        )
        return browsers
    }
}
