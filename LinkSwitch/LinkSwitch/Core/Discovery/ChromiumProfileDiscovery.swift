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

// MARK: - Known Chromium browser capabilities

/// Chromium browser registry keyed by bundle ID.
/// Keeps discovery location and launch support together so callers can ask
/// explicit questions without duplicating browser lists in multiple files.
enum ChromiumBrowserAppSupportPath {
    private struct Capabilities {
        let discoveryRelativePath: String
        let supportsProfileLaunch: Bool
    }

    private static func capabilities(forBundleID bundleID: String) -> Capabilities? {
        switch bundleID {
        case "net.imput.helium":
            return Capabilities(discoveryRelativePath: "net.imput.helium", supportsProfileLaunch: true)
        case "com.google.Chrome":
            return Capabilities(discoveryRelativePath: "Google/Chrome", supportsProfileLaunch: true)
        case "com.google.Chrome.canary":
            return Capabilities(discoveryRelativePath: "Google/Chrome Canary", supportsProfileLaunch: true)
        case "com.google.Chrome.beta":
            return Capabilities(discoveryRelativePath: "Google/Chrome Beta", supportsProfileLaunch: true)
        case "com.google.Chrome.dev":
            return Capabilities(discoveryRelativePath: "Google/Chrome Dev", supportsProfileLaunch: true)
        case "com.brave.Browser":
            return Capabilities(discoveryRelativePath: "BraveSoftware/Brave-Browser", supportsProfileLaunch: true)
        case "com.microsoft.edgemac":
            return Capabilities(discoveryRelativePath: "Microsoft Edge", supportsProfileLaunch: true)
        case "com.microsoft.edgemac.Beta":
            return Capabilities(discoveryRelativePath: "Microsoft Edge Beta", supportsProfileLaunch: true)
        case "com.microsoft.edgemac.Dev":
            return Capabilities(discoveryRelativePath: "Microsoft Edge Dev", supportsProfileLaunch: true)
        case "com.microsoft.edgemac.Canary":
            return Capabilities(discoveryRelativePath: "Microsoft Edge Canary", supportsProfileLaunch: true)
        case "com.vivaldi.Vivaldi":
            return Capabilities(discoveryRelativePath: "Vivaldi", supportsProfileLaunch: true)
        case "company.thebrowser.Browser":
            // Arc inserts an extra "User Data" level like Windows Chrome layout.
            return Capabilities(discoveryRelativePath: "Arc/User Data", supportsProfileLaunch: true)
        case "com.operasoftware.Opera":
            return Capabilities(discoveryRelativePath: "com.operasoftware.Opera", supportsProfileLaunch: true)
        case "org.chromium.Chromium":
            return Capabilities(discoveryRelativePath: "Chromium", supportsProfileLaunch: true)
        default:
            return nil
        }
    }

    /// Returns the Application Support relative path for Chromium profile discovery.
    static func discoveryRelativePath(forBundleID bundleID: String) -> String? {
        capabilities(forBundleID: bundleID)?.discoveryRelativePath
    }

    static func supportsProfileDiscovery(forBundleID bundleID: String) -> Bool {
        discoveryRelativePath(forBundleID: bundleID) != nil
    }

    static func supportsProfileLaunch(forBundleID bundleID: String) -> Bool {
        capabilities(forBundleID: bundleID)?.supportsProfileLaunch ?? false
    }
}
