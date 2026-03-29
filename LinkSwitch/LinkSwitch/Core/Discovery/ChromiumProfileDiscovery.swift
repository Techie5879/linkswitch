import Foundation

enum ChromiumProfileDiscoveryError: Error, Equatable {
    case localStateNotFound(URL)
    case localStateDecodingFailed(URL, String)
}

/// Reads Chromium-family browser profiles from the browser's "Local State" JSON file.
///
/// The Local State file lives at <user-data-dir>/Local State and contains
/// a `profile.info_cache` dict keyed by profile directory name (e.g. "Default", "Profile 1"),
/// each with a `name` field. Profiles are returned in the order given by
/// `profile.profiles_order` when available, falling back to alphabetical sort.
struct ChromiumProfileDiscovery: BrowserProfileDiscovering {
    let localStateURL: URL

    func discoverProfiles() throws -> [BrowserProfile] {
        AppLogger.info(
            "ChromiumProfileDiscovery reading Local State from \(localStateURL.path(percentEncoded: false))",
            category: .app
        )

        guard FileManager.default.fileExists(atPath: localStateURL.path(percentEncoded: false)) else {
            AppLogger.error(
                "ChromiumProfileDiscovery Local State not found at \(localStateURL.path(percentEncoded: false))",
                category: .app
            )
            throw ChromiumProfileDiscoveryError.localStateNotFound(localStateURL)
        }

        let data: Data
        do {
            data = try Data(contentsOf: localStateURL)
        } catch {
            AppLogger.error(
                "ChromiumProfileDiscovery failed to read Local State at \(localStateURL.path(percentEncoded: false)): \(error)",
                category: .app
            )
            throw ChromiumProfileDiscoveryError.localStateDecodingFailed(localStateURL, String(describing: error))
        }

        let localState: LocalState
        do {
            localState = try JSONDecoder().decode(LocalState.self, from: data)
        } catch {
            AppLogger.error(
                "ChromiumProfileDiscovery failed to decode Local State at \(localStateURL.path(percentEncoded: false)): \(error)",
                category: .app
            )
            throw ChromiumProfileDiscoveryError.localStateDecodingFailed(localStateURL, String(describing: error))
        }

        let infoCache = localState.profile.infoCache
        let order = localState.profile.profilesOrder ?? infoCache.keys.sorted()

        let profiles: [BrowserProfile] = order.compactMap { key in
            guard let entry = infoCache[key] else { return nil }
            guard entry.isEphemeral != true else { return nil }
            return BrowserProfile(profileKey: key, displayName: entry.name)
        }

        AppLogger.info(
            "ChromiumProfileDiscovery found \(profiles.count) profile(s): \(profiles.map(\.profileKey).joined(separator: ", "))",
            category: .app
        )
        return profiles
    }
}

// MARK: - Codable types for Local State

private struct LocalState: Decodable {
    let profile: ProfileSection

    struct ProfileSection: Decodable {
        let infoCache: [String: ProfileEntry]
        let profilesOrder: [String]?

        enum CodingKeys: String, CodingKey {
            case infoCache = "info_cache"
            case profilesOrder = "profiles_order"
        }
    }

    struct ProfileEntry: Decodable {
        let name: String
        let isEphemeral: Bool?

        enum CodingKeys: String, CodingKey {
            case name
            case isEphemeral = "is_ephemeral"
        }
    }
}

// MARK: - Known Chromium browser Application Support relative paths

/// Maps bundle IDs of Chromium-based browsers to their Application Support subdirectory path
/// (relative to ~/Library/Application Support/). Used by BrowserProfileDiscoveryFactory.
enum ChromiumBrowserAppSupportPath {
    /// Returns the Application Support relative path for the given bundle ID, or nil if unknown.
    static func relativePath(forBundleID bundleID: String) -> String? {
        switch bundleID {
        case "net.imput.helium":
            return "net.imput.helium"
        case "com.google.Chrome":
            return "Google/Chrome"
        case "com.google.Chrome.canary":
            return "Google/Chrome Canary"
        case "com.google.Chrome.beta":
            return "Google/Chrome Beta"
        case "com.google.Chrome.dev":
            return "Google/Chrome Dev"
        case "com.brave.Browser":
            return "BraveSoftware/Brave-Browser"
        case "com.microsoft.edgemac":
            return "Microsoft Edge"
        case "com.microsoft.edgemac.Beta":
            return "Microsoft Edge Beta"
        case "com.microsoft.edgemac.Dev":
            return "Microsoft Edge Dev"
        case "com.microsoft.edgemac.Canary":
            return "Microsoft Edge Canary"
        case "com.vivaldi.Vivaldi":
            return "Vivaldi"
        case "company.thebrowser.Browser":
            // Arc inserts an extra "User Data" level like Windows Chrome layout.
            return "Arc/User Data"
        case "com.operasoftware.Opera":
            return "com.operasoftware.Opera"
        case "org.chromium.Chromium":
            return "Chromium"
        default:
            return nil
        }
    }
}
