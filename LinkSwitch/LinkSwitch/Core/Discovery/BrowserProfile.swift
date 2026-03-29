import Foundation

/// A selectable browser identity used for routing links in preferences (cards UI).
///
/// In LinkSwitch, "profile" means the browser-native target for a link: Chromium profile
/// directories, Firefox `profiles.ini` paths, or Zen container display names (see
/// `ZenContainerDiscovery`), not only literal Gecko/Chromium profile folders.
struct BrowserProfile: Identifiable, Equatable {
    var id: String { profileKey }

    /// The stable key used to launch with this profile.
    /// For Chromium-based browsers: the profile directory name (e.g. "Default", "Profile 1"),
    /// passed as --profile-directory=<profileKey> when launching.
    /// For Firefox-based browsers: the relative profile path from profiles.ini
    /// (e.g. "Profiles/abc123.default-release").
    /// For Zen container discovery: the container display name passed to the
    /// extension-based `ext+container:` URL handoff.
    let profileKey: String

    /// Human-readable display name shown in the browser's profile switcher.
    let displayName: String
}

protocol BrowserProfileDiscovering {
    func discoverProfiles() throws -> [BrowserProfile]
}
