import Foundation

/// A single user profile discovered from an installed browser.
struct BrowserProfile: Identifiable, Equatable {
    var id: String { profileKey }

    /// The stable key used to launch with this profile.
    /// For Chromium-based browsers: the profile directory name (e.g. "Default", "Profile 1"),
    /// passed as --profile-directory=<profileKey> when launching.
    /// For Firefox-based browsers: the relative profile path from profiles.ini
    /// (e.g. "Profiles/abc123.default-release").
    let profileKey: String

    /// Human-readable display name shown in the browser's profile switcher.
    let displayName: String
}

protocol BrowserProfileDiscovering {
    func discoverProfiles() throws -> [BrowserProfile]
}
