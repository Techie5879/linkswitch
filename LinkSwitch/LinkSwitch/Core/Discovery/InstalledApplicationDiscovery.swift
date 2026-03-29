import AppKit
import Foundation

struct DiscoveredApplication: Identifiable, Equatable {
    var id: String { bundleID }
    let bundleID: String
    let name: String
    let appURL: URL
}

protocol InstalledApplicationDiscovering {
    func discoverInstalledApplications(excludingBundleID: String?) -> [DiscoveredApplication]
}

struct InstalledApplicationDiscovery: InstalledApplicationDiscovering {
    func discoverInstalledApplications(excludingBundleID: String?) -> [DiscoveredApplication] {
        var roots: [URL] = []
        if let urls = try? FileManager.default.urls(for: .applicationDirectory, in: .allDomainsMask) {
            roots.append(contentsOf: urls)
        }
        let systemApplications = URL(fileURLWithPath: "/System/Applications", isDirectory: true)
        if FileManager.default.fileExists(atPath: systemApplications.path(percentEncoded: false)) {
            roots.append(systemApplications)
        }

        AppLogger.info("Installed application discovery scanning \(roots.count) root directory(ies)", category: .app)

        var bestByBundleID: [String: (url: URL, priority: Int, name: String)] = [:]

        let resourceKeys: [URLResourceKey] = [.isDirectoryKey]
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]

        for root in roots {
            guard FileManager.default.fileExists(atPath: root.path(percentEncoded: false)) else { continue }

            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: resourceKeys,
                options: options
            ) else {
                AppLogger.debug("Could not create enumerator for \(root.path(percentEncoded: false))", category: .app)
                continue
            }

            while let item = enumerator.nextObject() {
                guard let itemURL = item as? URL else { continue }
                guard itemURL.pathExtension == "app" else { continue }
                guard let bundle = Bundle(url: itemURL), let bundleID = bundle.bundleIdentifier, !bundleID.isEmpty else { continue }

                if let excluded = excludingBundleID, bundleID == excluded {
                    continue
                }

                let name =
                    bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? itemURL.deletingPathExtension().lastPathComponent

                let priority = priorityScore(applicationURL: itemURL)
                if let existing = bestByBundleID[bundleID] {
                    if priority < existing.priority {
                        bestByBundleID[bundleID] = (itemURL, priority, name)
                    }
                } else {
                    bestByBundleID[bundleID] = (itemURL, priority, name)
                }
            }
        }

        let apps = bestByBundleID.map { key, value in
            DiscoveredApplication(bundleID: key, name: value.name, appURL: value.url)
        }
        let sorted = apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        AppLogger.info(
            "Installed application discovery completed: \(sorted.count) application(s)",
            category: .app
        )
        return sorted
    }

    /// Lower is better: prefer /Applications over /System/Applications over other locations.
    private func priorityScore(applicationURL: URL) -> Int {
        let p = applicationURL.path(percentEncoded: false)
        if p.hasPrefix("/Applications/"), !p.hasPrefix("/System/Applications/") {
            return 0
        }
        if p.hasPrefix("/System/Applications/") {
            return 1
        }
        if p.contains("/Applications/") {
            return 2
        }
        return 3
    }
}
