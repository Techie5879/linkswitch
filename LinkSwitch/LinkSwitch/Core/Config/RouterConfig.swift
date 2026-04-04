import Foundation

enum DefaultBrowserRoute: Codable, Equatable, CustomStringConvertible {
    case plain
    case chromiumProfile(profileDirectory: String)
    case firefoxProfile(profileKey: String)
    case zenContainer(containerName: String)

    var description: String {
        switch self {
        case .plain:
            return "plain"
        case let .chromiumProfile(profileDirectory):
            return "chromiumProfile(profileDirectory: \(profileDirectory))"
        case let .firefoxProfile(profileKey):
            return "firefoxProfile(profileKey: \(profileKey))"
        case let .zenContainer(containerName):
            return "zenContainer(containerName: \(containerName))"
        }
    }

    /// Maps a persisted default-browser route to the `BrowserTarget` used for unmatched links.
    var browserTarget: BrowserTarget {
        switch self {
        case .plain:
            return .defaultBrowser
        case let .chromiumProfile(profileDirectory):
            return .defaultBrowserChromiumProfile(profileDirectory: profileDirectory)
        case let .firefoxProfile(profileKey):
            return .defaultBrowserFirefoxProfile(profileKey: profileKey)
        case let .zenContainer(containerName):
            return .defaultBrowserZenContainer(containerName: containerName)
        }
    }
}

enum BrowserTarget: Codable, Equatable, CustomStringConvertible {
    case defaultBrowser
    case defaultBrowserChromiumProfile(profileDirectory: String)
    case defaultBrowserFirefoxProfile(profileKey: String)
    case defaultBrowserZenContainer(containerName: String)
    case application(bundleID: String, applicationURL: URL)
    case applicationChromiumProfile(bundleID: String, applicationURL: URL, profileDirectory: String)
    case applicationFirefoxProfile(bundleID: String, applicationURL: URL, profileKey: String)
    case applicationZenContainer(bundleID: String, applicationURL: URL, containerName: String)
    case helium(profileDirectory: String)

    var description: String {
        switch self {
        case .defaultBrowser:
            return "defaultBrowser"
        case let .defaultBrowserChromiumProfile(profileDirectory):
            return "defaultBrowserChromiumProfile(profileDirectory: \(profileDirectory))"
        case let .defaultBrowserFirefoxProfile(profileKey):
            return "defaultBrowserFirefoxProfile(profileKey: \(profileKey))"
        case let .defaultBrowserZenContainer(containerName):
            return "defaultBrowserZenContainer(containerName: \(containerName))"
        case let .application(bundleID, applicationURL):
            return "application(bundleID: \(bundleID), applicationURL: \(applicationURL.path()))"
        case let .applicationChromiumProfile(bundleID, applicationURL, profileDirectory):
            return "applicationChromiumProfile(bundleID: \(bundleID), applicationURL: \(applicationURL.path()), profileDirectory: \(profileDirectory))"
        case let .applicationFirefoxProfile(bundleID, applicationURL, profileKey):
            return "applicationFirefoxProfile(bundleID: \(bundleID), applicationURL: \(applicationURL.path()), profileKey: \(profileKey))"
        case let .applicationZenContainer(bundleID, applicationURL, containerName):
            return "applicationZenContainer(bundleID: \(bundleID), applicationURL: \(applicationURL.path()), containerName: \(containerName))"
        case let .helium(profileDirectory):
            return "helium(profileDirectory: \(profileDirectory))"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case plain
        case chromiumProfile
        case legacyHeliumProfile = "heliumProfile"
        case firefoxProfile
        case zenContainer
        case defaultBrowser
        case defaultBrowserChromiumProfile
        case legacyDefaultBrowserHeliumProfile = "defaultBrowserHeliumProfile"
        case defaultBrowserFirefoxProfile
        case defaultBrowserZenContainer
        case application
        case applicationChromiumProfile
        case legacyApplicationHeliumProfile = "applicationHeliumProfile"
        case applicationFirefoxProfile
        case applicationZenContainer
        case helium
    }

    private struct ChromiumProfilePayload: Codable {
        let profileDirectory: String
    }

    private struct FirefoxProfilePayload: Codable {
        let profileKey: String
    }

    private struct ZenContainerPayload: Codable {
        let containerName: String
    }

    private struct ApplicationPayload: Codable {
        let bundleID: String
        let applicationURL: URL
    }

    private struct ApplicationChromiumProfilePayload: Codable {
        let bundleID: String
        let applicationURL: URL
        let profileDirectory: String
    }

    private struct ApplicationFirefoxProfilePayload: Codable {
        let bundleID: String
        let applicationURL: URL
        let profileKey: String
    }

    private struct ApplicationZenContainerPayload: Codable {
        let bundleID: String
        let applicationURL: URL
        let containerName: String
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if container.contains(.defaultBrowser) {
            self = .defaultBrowser
        } else if let payload = try container.decodeIfPresent(ChromiumProfilePayload.self, forKey: .defaultBrowserChromiumProfile) {
            self = .defaultBrowserChromiumProfile(profileDirectory: payload.profileDirectory)
        } else if let payload = try container.decodeIfPresent(ChromiumProfilePayload.self, forKey: .legacyDefaultBrowserHeliumProfile) {
            self = .defaultBrowserChromiumProfile(profileDirectory: payload.profileDirectory)
        } else if let payload = try container.decodeIfPresent(FirefoxProfilePayload.self, forKey: .defaultBrowserFirefoxProfile) {
            self = .defaultBrowserFirefoxProfile(profileKey: payload.profileKey)
        } else if let payload = try container.decodeIfPresent(ZenContainerPayload.self, forKey: .defaultBrowserZenContainer) {
            self = .defaultBrowserZenContainer(containerName: payload.containerName)
        } else if let payload = try container.decodeIfPresent(ApplicationPayload.self, forKey: .application) {
            self = .application(bundleID: payload.bundleID, applicationURL: payload.applicationURL)
        } else if let payload = try container.decodeIfPresent(ApplicationChromiumProfilePayload.self, forKey: .applicationChromiumProfile) {
            self = .applicationChromiumProfile(
                bundleID: payload.bundleID,
                applicationURL: payload.applicationURL,
                profileDirectory: payload.profileDirectory
            )
        } else if let payload = try container.decodeIfPresent(ApplicationChromiumProfilePayload.self, forKey: .legacyApplicationHeliumProfile) {
            self = .applicationChromiumProfile(
                bundleID: payload.bundleID,
                applicationURL: payload.applicationURL,
                profileDirectory: payload.profileDirectory
            )
        } else if let payload = try container.decodeIfPresent(ApplicationFirefoxProfilePayload.self, forKey: .applicationFirefoxProfile) {
            self = .applicationFirefoxProfile(
                bundleID: payload.bundleID,
                applicationURL: payload.applicationURL,
                profileKey: payload.profileKey
            )
        } else if let payload = try container.decodeIfPresent(ApplicationZenContainerPayload.self, forKey: .applicationZenContainer) {
            self = .applicationZenContainer(
                bundleID: payload.bundleID,
                applicationURL: payload.applicationURL,
                containerName: payload.containerName
            )
        } else if let payload = try container.decodeIfPresent(ChromiumProfilePayload.self, forKey: .helium) {
            self = .helium(profileDirectory: payload.profileDirectory)
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .defaultBrowser,
                in: container,
                debugDescription: "Unsupported BrowserTarget payload"
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .defaultBrowser:
            try container.encode([String: String](), forKey: .defaultBrowser)
        case let .defaultBrowserChromiumProfile(profileDirectory):
            try container.encode(ChromiumProfilePayload(profileDirectory: profileDirectory), forKey: .defaultBrowserChromiumProfile)
        case let .defaultBrowserFirefoxProfile(profileKey):
            try container.encode(FirefoxProfilePayload(profileKey: profileKey), forKey: .defaultBrowserFirefoxProfile)
        case let .defaultBrowserZenContainer(containerName):
            try container.encode(ZenContainerPayload(containerName: containerName), forKey: .defaultBrowserZenContainer)
        case let .application(bundleID, applicationURL):
            try container.encode(ApplicationPayload(bundleID: bundleID, applicationURL: applicationURL), forKey: .application)
        case let .applicationChromiumProfile(bundleID, applicationURL, profileDirectory):
            try container.encode(
                ApplicationChromiumProfilePayload(
                    bundleID: bundleID,
                    applicationURL: applicationURL,
                    profileDirectory: profileDirectory
                ),
                forKey: .applicationChromiumProfile
            )
        case let .applicationFirefoxProfile(bundleID, applicationURL, profileKey):
            try container.encode(
                ApplicationFirefoxProfilePayload(
                    bundleID: bundleID,
                    applicationURL: applicationURL,
                    profileKey: profileKey
                ),
                forKey: .applicationFirefoxProfile
            )
        case let .applicationZenContainer(bundleID, applicationURL, containerName):
            try container.encode(
                ApplicationZenContainerPayload(
                    bundleID: bundleID,
                    applicationURL: applicationURL,
                    containerName: containerName
                ),
                forKey: .applicationZenContainer
            )
        case let .helium(profileDirectory):
            try container.encode(ChromiumProfilePayload(profileDirectory: profileDirectory), forKey: .helium)
        }
    }
}

extension DefaultBrowserRoute {
    private enum CodingKeys: String, CodingKey {
        case plain
        case chromiumProfile
        case legacyHeliumProfile = "heliumProfile"
        case firefoxProfile
        case zenContainer
    }

    private struct ChromiumProfilePayload: Codable {
        let profileDirectory: String
    }

    private struct FirefoxProfilePayload: Codable {
        let profileKey: String
    }

    private struct ZenContainerPayload: Codable {
        let containerName: String
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if container.contains(.plain) {
            self = .plain
        } else if let payload = try container.decodeIfPresent(ChromiumProfilePayload.self, forKey: .chromiumProfile) {
            self = .chromiumProfile(profileDirectory: payload.profileDirectory)
        } else if let payload = try container.decodeIfPresent(ChromiumProfilePayload.self, forKey: .legacyHeliumProfile) {
            self = .chromiumProfile(profileDirectory: payload.profileDirectory)
        } else if let payload = try container.decodeIfPresent(FirefoxProfilePayload.self, forKey: .firefoxProfile) {
            self = .firefoxProfile(profileKey: payload.profileKey)
        } else if let payload = try container.decodeIfPresent(ZenContainerPayload.self, forKey: .zenContainer) {
            self = .zenContainer(containerName: payload.containerName)
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .plain,
                in: container,
                debugDescription: "Unsupported DefaultBrowserRoute payload"
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .plain:
            try container.encode([String: String](), forKey: .plain)
        case let .chromiumProfile(profileDirectory):
            try container.encode(ChromiumProfilePayload(profileDirectory: profileDirectory), forKey: .chromiumProfile)
        case let .firefoxProfile(profileKey):
            try container.encode(FirefoxProfilePayload(profileKey: profileKey), forKey: .firefoxProfile)
        case let .zenContainer(containerName):
            try container.encode(ZenContainerPayload(containerName: containerName), forKey: .zenContainer)
        }
    }
}

struct SourceAppRule: Codable, Identifiable, Equatable {
    let id: UUID
    var sourceBundleID: String
    var target: BrowserTarget
}

struct RouterConfig: Codable, Equatable {
    var defaultBrowserBundleID: String
    var defaultBrowserAppURL: URL
    var defaultBrowserRoute: DefaultBrowserRoute
    var rules: [SourceAppRule]
}
