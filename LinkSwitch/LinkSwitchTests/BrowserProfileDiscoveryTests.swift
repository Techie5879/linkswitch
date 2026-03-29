import XCTest
@testable import LinkSwitch

final class ChromiumProfileDiscoveryTests: XCTestCase {
    func testDiscoverProfilesReturnsSortedByProfilesOrder() throws {
        let (dir, url) = try makeLocalState(json: """
        {
          "profile": {
            "info_cache": {
              "Default": { "name": "Alice" },
              "Profile 1": { "name": "Work" }
            },
            "profiles_order": ["Profile 1", "Default"]
          }
        }
        """)
        defer { try? FileManager.default.removeItem(at: dir) }

        let profiles = try ChromiumProfileDiscovery(localStateURL: url).discoverProfiles()

        XCTAssertEqual(profiles, [
            BrowserProfile(profileKey: "Profile 1", displayName: "Work"),
            BrowserProfile(profileKey: "Default", displayName: "Alice"),
        ])
    }

    func testDiscoverProfilesFallsBackToAlphabeticWhenNoProfilesOrder() throws {
        let (dir, url) = try makeLocalState(json: """
        {
          "profile": {
            "info_cache": {
              "Profile 1": { "name": "Work" },
              "Default": { "name": "Alice" }
            }
          }
        }
        """)
        defer { try? FileManager.default.removeItem(at: dir) }

        let profiles = try ChromiumProfileDiscovery(localStateURL: url).discoverProfiles()

        // alphabetical: Default < Profile 1
        XCTAssertEqual(profiles.map(\.profileKey), ["Default", "Profile 1"])
    }

    func testDiscoverProfilesSkipsEphemeralProfiles() throws {
        let (dir, url) = try makeLocalState(json: """
        {
          "profile": {
            "info_cache": {
              "Default": { "name": "Alice" },
              "Guest Profile": { "name": "Guest", "is_ephemeral": true }
            }
          }
        }
        """)
        defer { try? FileManager.default.removeItem(at: dir) }

        let profiles = try ChromiumProfileDiscovery(localStateURL: url).discoverProfiles()

        XCTAssertEqual(profiles.map(\.profileKey), ["Default"])
    }

    func testDiscoverProfilesThrowsWhenLocalStateNotFound() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("Local State")

        XCTAssertThrowsError(
            try ChromiumProfileDiscovery(localStateURL: url).discoverProfiles()
        ) { error in
            XCTAssertEqual(
                error as? ChromiumProfileDiscoveryError,
                .localStateNotFound(url)
            )
        }
    }

    func testDiscoverProfilesThrowsWhenLocalStateContainsMalformedJSON() throws {
        let (dir, url) = try makeLocalState(json: "{ not json }")
        defer { try? FileManager.default.removeItem(at: dir) }

        XCTAssertThrowsError(
            try ChromiumProfileDiscovery(localStateURL: url).discoverProfiles()
        ) { error in
            if case .localStateDecodingFailed = error as? ChromiumProfileDiscoveryError {
                // expected
            } else {
                XCTFail("Expected localStateDecodingFailed, got \(error)")
            }
        }
    }

    // MARK: Helpers

    private func makeLocalState(json: String) throws -> (URL, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("Local State")
        try json.data(using: .utf8)!.write(to: url)
        return (dir, url)
    }
}

final class FirefoxProfileDiscoveryTests: XCTestCase {
    func testDiscoverProfilesReturnsAllProfileSections() throws {
        let (dir, url) = try makeProfilesIni(content: """
        [General]
        StartWithLastProfile=1
        Version=2

        [Profile0]
        Name=Default Profile
        IsRelative=1
        Path=Profiles/abc123.default

        [Profile1]
        Name=Work
        IsRelative=1
        Path=Profiles/xyz789.work
        """)
        defer { try? FileManager.default.removeItem(at: dir) }

        let profiles = try FirefoxProfileDiscovery(profilesIniURL: url).discoverProfiles()

        XCTAssertEqual(profiles.map(\.displayName), ["Default Profile", "Work"])
        XCTAssertEqual(profiles.map(\.profileKey), ["Profiles/abc123.default", "Profiles/xyz789.work"])
    }

    func testDiscoverProfilesIgnoresInstallAndGeneralSections() throws {
        let (dir, url) = try makeProfilesIni(content: """
        [Install6ED35B3CA1B5D3AF]
        Default=Profiles/abc123.default
        Locked=1

        [Profile0]
        Name=Default Profile
        IsRelative=1
        Path=Profiles/abc123.default

        [General]
        StartWithLastProfile=1
        """)
        defer { try? FileManager.default.removeItem(at: dir) }

        let profiles = try FirefoxProfileDiscovery(profilesIniURL: url).discoverProfiles()

        XCTAssertEqual(profiles.map(\.displayName), ["Default Profile"])
    }

    func testDiscoverProfilesThrowsWhenProfilesIniNotFound() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("profiles.ini")

        XCTAssertThrowsError(
            try FirefoxProfileDiscovery(profilesIniURL: url).discoverProfiles()
        ) { error in
            XCTAssertEqual(
                error as? FirefoxProfileDiscoveryError,
                .profilesIniNotFound(url)
            )
        }
    }

    func testDiscoverProfilesHandlesProfileNamesWithSpacesAndParentheses() throws {
        let (dir, url) = try makeProfilesIni(content: """
        [Profile0]
        Name=Default (release)
        IsRelative=1
        Path=Profiles/5wng7prr.Default (release)
        """)
        defer { try? FileManager.default.removeItem(at: dir) }

        let profiles = try FirefoxProfileDiscovery(profilesIniURL: url).discoverProfiles()

        XCTAssertEqual(profiles.first?.displayName, "Default (release)")
        XCTAssertEqual(profiles.first?.profileKey, "Profiles/5wng7prr.Default (release)")
    }

    // MARK: Helpers

    private func makeProfilesIni(content: String) throws -> (URL, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("profiles.ini")
        try content.data(using: .utf8)!.write(to: url)
        return (dir, url)
    }
}
