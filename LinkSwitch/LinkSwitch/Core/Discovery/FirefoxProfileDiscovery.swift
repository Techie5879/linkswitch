import Foundation

enum FirefoxProfileDiscoveryError: Error, Equatable {
    case profilesIniNotFound(URL)
    case profilesIniReadFailed(URL, String)
}

/// Reads Firefox-family browser profiles from the browser's profiles.ini file.
///
/// profiles.ini is a plain-text INI file at <app-support-dir>/profiles.ini.
/// [Profile0], [Profile1], … sections each carry Name= and Path= keys.
/// Path= is relative to the profiles.ini directory when IsRelative=1 (the common case).
struct FirefoxProfileDiscovery: BrowserProfileDiscovering {
    let profilesIniURL: URL

    func discoverProfiles() throws -> [BrowserProfile] {
        AppLogger.info(
            "FirefoxProfileDiscovery reading profiles.ini from \(profilesIniURL.path(percentEncoded: false))",
            category: .app
        )

        guard FileManager.default.fileExists(atPath: profilesIniURL.path(percentEncoded: false)) else {
            AppLogger.error(
                "FirefoxProfileDiscovery profiles.ini not found at \(profilesIniURL.path(percentEncoded: false))",
                category: .app
            )
            throw FirefoxProfileDiscoveryError.profilesIniNotFound(profilesIniURL)
        }

        let raw: String
        do {
            raw = try String(contentsOf: profilesIniURL, encoding: .utf8)
        } catch {
            AppLogger.error(
                "FirefoxProfileDiscovery failed to read profiles.ini at \(profilesIniURL.path(percentEncoded: false)): \(error)",
                category: .app
            )
            throw FirefoxProfileDiscoveryError.profilesIniReadFailed(profilesIniURL, String(describing: error))
        }

        let profiles = parseProfilesIni(raw)
        AppLogger.info(
            "FirefoxProfileDiscovery found \(profiles.count) profile(s): \(profiles.map(\.displayName).joined(separator: ", "))",
            category: .app
        )
        return profiles
    }

    private func parseProfilesIni(_ content: String) -> [BrowserProfile] {
        // Section names matching /^Profile\d+$/i contain user profiles.
        // [Install...] and [General] sections are ignored.
        var results: [BrowserProfile] = []
        var currentSection: String? = nil
        var currentKeys: [String: String] = [:]

        func flushSection() {
            guard let section = currentSection,
                  section.lowercased().hasPrefix("profile"),
                  section.dropFirst("profile".count).allSatisfy(\.isNumber),
                  let name = currentKeys["Name"],
                  let path = currentKeys["Path"]
            else { return }

            let isRelative = currentKeys["IsRelative"] == "1"
            let resolvedPath: String
            if isRelative {
                let base = profilesIniURL.deletingLastPathComponent()
                resolvedPath = base.appendingPathComponent(path).path(percentEncoded: false)
            } else {
                resolvedPath = path
            }

            results.append(BrowserProfile(
                profileKey: path,        // stable key: raw path from profiles.ini (relative or absolute)
                displayName: name
            ))
            _ = resolvedPath  // resolved path available if needed for launch
        }

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty || line.hasPrefix(";") || line.hasPrefix("#") {
                continue
            }

            if line.hasPrefix("[") && line.hasSuffix("]") {
                flushSection()
                currentSection = String(line.dropFirst().dropLast())
                currentKeys = [:]
                continue
            }

            if let eqRange = line.range(of: "=") {
                let key = String(line[line.startIndex..<eqRange.lowerBound])
                    .trimmingCharacters(in: .whitespaces)
                let value = String(line[eqRange.upperBound...])
                    .trimmingCharacters(in: .whitespaces)
                currentKeys[key] = value
            }
        }

        flushSection()
        return results
    }
}

// MARK: - Known Firefox browser Application Support relative paths

/// Maps bundle IDs of Firefox/Gecko-based browsers to their Application Support
/// subdirectory path. Returns an absolute path string (starting with "~/") for browsers
/// that use the home directory instead of Application Support (e.g. LibreWolf).
/// Used by BrowserProfileDiscoveryFactory.
enum FirefoxBrowserAppSupportPath {
    /// Returns the Application Support relative path for the given bundle ID, or nil if unknown.
    /// Paths starting with "~/" are relative to the home directory, not Application Support.
    static func relativePath(forBundleID bundleID: String) -> String? {
        switch bundleID {
        case "org.mozilla.firefox":
            return "Firefox"
        case "app.zen-browser.zen":
            return "zen"
        case "net.waterfox.waterfox":
            return "Waterfox"
        case "io.gitlab.librewolf-community.librewolf":
            // LibreWolf uses ~/.librewolf on macOS (same as Linux), not Application Support.
            return "~/.librewolf"
        case "net.sourceforge.Floorp":
            return "Floorp"
        default:
            return nil
        }
    }
}
