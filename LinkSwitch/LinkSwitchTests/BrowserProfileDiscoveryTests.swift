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

final class ZenContainerDiscoveryTests: XCTestCase {
    func testDiscoverProfilesReturnsPublicContainersFromInstalledDefaultProfile() throws {
        let appSupportURL = try makeZenAppSupport(
            profilesIni: """
            [Profile0]
            Name=Default (release)
            IsRelative=1
            Path=Profiles/5wng7prr.Default (release)

            [Profile1]
            Name=Other
            IsRelative=1
            Path=Profiles/other.default
            Default=1
            """,
            installsIni: """
            [Install6ED35B3CA1B5D3AF]
            Default=Profiles/5wng7prr.Default (release)
            Locked=1
            """,
            containersByProfilePath: [
                "Profiles/5wng7prr.Default (release)": """
                {
                  "version": 5,
                  "identities": [
                    { "public": true, "l10nId": "user-context-personal", "userContextId": 1 },
                    { "public": true, "name": "Work", "userContextId": 2 },
                    { "public": false, "name": "Internal", "userContextId": 999 }
                  ]
                }
                """,
                "Profiles/other.default": """
                {
                  "version": 5,
                  "identities": [
                    { "public": true, "name": "Shopping", "userContextId": 4 }
                  ]
                }
                """,
            ]
        )
        defer { try? FileManager.default.removeItem(at: appSupportURL.deletingLastPathComponent()) }

        let containers = try ZenContainerDiscovery(appSupportURL: appSupportURL).discoverProfiles()

        XCTAssertEqual(containers, [
            BrowserProfile(profileKey: "Personal", displayName: "Personal"),
            BrowserProfile(profileKey: "Work", displayName: "Work"),
        ])
    }

    func testDiscoverProfilesFallsBackToProfilesIniDefaultWhenInstallsIniMissing() throws {
        let appSupportURL = try makeZenAppSupport(
            profilesIni: """
            [Profile0]
            Name=Default Profile
            IsRelative=1
            Path=Profiles/default.profile
            Default=1
            """,
            installsIni: nil,
            containersByProfilePath: [
                "Profiles/default.profile": """
                {
                  "version": 5,
                  "identities": [
                    { "public": true, "l10nId": "user-context-work", "userContextId": 2 }
                  ]
                }
                """,
            ]
        )
        defer { try? FileManager.default.removeItem(at: appSupportURL.deletingLastPathComponent()) }

        let containers = try ZenContainerDiscovery(appSupportURL: appSupportURL).discoverProfiles()

        XCTAssertEqual(containers, [
            BrowserProfile(profileKey: "Work", displayName: "Work"),
        ])
    }

    func testDiscoverProfilesThrowsWhenProfilesIniIsMissing() throws {
        let appSupportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: appSupportURL) }

        XCTAssertThrowsError(
            try ZenContainerDiscovery(appSupportURL: appSupportURL).discoverProfiles()
        ) { error in
            XCTAssertEqual(
                error as? ZenContainerDiscoveryError,
                .profilesIniNotFound(appSupportURL.appendingPathComponent("zen").appendingPathComponent("profiles.ini"))
            )
        }
    }

    private func makeZenAppSupport(
        profilesIni: String,
        installsIni: String?,
        containersByProfilePath: [String: String]
    ) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let appSupportURL = root.appendingPathComponent("Application Support", isDirectory: true)
        let zenRootURL = appSupportURL.appendingPathComponent("zen", isDirectory: true)
        try FileManager.default.createDirectory(at: zenRootURL, withIntermediateDirectories: true)

        try profilesIni.data(using: .utf8)!.write(to: zenRootURL.appendingPathComponent("profiles.ini"))
        if let installsIni {
            try installsIni.data(using: .utf8)!.write(to: zenRootURL.appendingPathComponent("installs.ini"))
        }

        for (profilePath, containersJSON) in containersByProfilePath {
            let profileURL = zenRootURL.appendingPathComponent(profilePath, isDirectory: true)
            try FileManager.default.createDirectory(at: profileURL, withIntermediateDirectories: true)
            try containersJSON.data(using: .utf8)!.write(to: profileURL.appendingPathComponent("containers.json"))
        }

        return appSupportURL
    }
}
