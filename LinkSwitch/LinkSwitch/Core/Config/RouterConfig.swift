import Foundation

enum DefaultBrowserRoute: Codable, Equatable, CustomStringConvertible {
    case plain
    case heliumProfile(profileDirectory: String)
    case firefoxProfile(profileKey: String)
    case zenContainer(containerName: String)

    var description: String {
        switch self {
        case .plain:
            return "plain"
        case let .heliumProfile(profileDirectory):
            return "heliumProfile(profileDirectory: \(profileDirectory))"
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
        case let .heliumProfile(profileDirectory):
            return .defaultBrowserHeliumProfile(profileDirectory: profileDirectory)
        case let .firefoxProfile(profileKey):
            return .defaultBrowserFirefoxProfile(profileKey: profileKey)
        case let .zenContainer(containerName):
            return .defaultBrowserZenContainer(containerName: containerName)
        }
    }
}

enum BrowserTarget: Codable, Equatable, CustomStringConvertible {
    case defaultBrowser
    case defaultBrowserHeliumProfile(profileDirectory: String)
    case defaultBrowserFirefoxProfile(profileKey: String)
    case defaultBrowserZenContainer(containerName: String)
    case application(bundleID: String, applicationURL: URL)
    case applicationHeliumProfile(bundleID: String, applicationURL: URL, profileDirectory: String)
    case applicationFirefoxProfile(bundleID: String, applicationURL: URL, profileKey: String)
    case applicationZenContainer(bundleID: String, applicationURL: URL, containerName: String)
    case helium(profileDirectory: String)

    var description: String {
        switch self {
        case .defaultBrowser:
            return "defaultBrowser"
        case let .defaultBrowserHeliumProfile(profileDirectory):
            return "defaultBrowserHeliumProfile(profileDirectory: \(profileDirectory))"
        case let .defaultBrowserFirefoxProfile(profileKey):
            return "defaultBrowserFirefoxProfile(profileKey: \(profileKey))"
        case let .defaultBrowserZenContainer(containerName):
            return "defaultBrowserZenContainer(containerName: \(containerName))"
        case let .application(bundleID, applicationURL):
            return "application(bundleID: \(bundleID), applicationURL: \(applicationURL.path()))"
        case let .applicationHeliumProfile(bundleID, applicationURL, profileDirectory):
            return "applicationHeliumProfile(bundleID: \(bundleID), applicationURL: \(applicationURL.path()), profileDirectory: \(profileDirectory))"
        case let .applicationFirefoxProfile(bundleID, applicationURL, profileKey):
            return "applicationFirefoxProfile(bundleID: \(bundleID), applicationURL: \(applicationURL.path()), profileKey: \(profileKey))"
        case let .applicationZenContainer(bundleID, applicationURL, containerName):
            return "applicationZenContainer(bundleID: \(bundleID), applicationURL: \(applicationURL.path()), containerName: \(containerName))"
        case let .helium(profileDirectory):
            return "helium(profileDirectory: \(profileDirectory))"
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
