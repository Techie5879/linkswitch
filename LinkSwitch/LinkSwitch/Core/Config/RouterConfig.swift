import Foundation

enum FallbackBrowserRoute: Codable, Equatable, CustomStringConvertible {
    case plain
    case firefoxProfile(profileKey: String)
    case zenContainer(containerName: String)

    var description: String {
        switch self {
        case .plain:
            return "plain"
        case let .firefoxProfile(profileKey):
            return "firefoxProfile(profileKey: \(profileKey))"
        case let .zenContainer(containerName):
            return "zenContainer(containerName: \(containerName))"
        }
    }

    /// Maps a persisted fallback route to the `BrowserTarget` used for unmatched links.
    var browserTarget: BrowserTarget {
        switch self {
        case .plain:
            return .fallbackBrowser
        case let .firefoxProfile(profileKey):
            return .fallbackBrowserFirefoxProfile(profileKey: profileKey)
        case let .zenContainer(containerName):
            return .fallbackBrowserZenContainer(containerName: containerName)
        }
    }
}

enum BrowserTarget: Codable, Equatable, CustomStringConvertible {
    case fallbackBrowser
    case fallbackBrowserFirefoxProfile(profileKey: String)
    case fallbackBrowserZenContainer(containerName: String)
    case helium(profileDirectory: String)

    var description: String {
        switch self {
        case .fallbackBrowser:
            return "fallbackBrowser"
        case let .fallbackBrowserFirefoxProfile(profileKey):
            return "fallbackBrowserFirefoxProfile(profileKey: \(profileKey))"
        case let .fallbackBrowserZenContainer(containerName):
            return "fallbackBrowserZenContainer(containerName: \(containerName))"
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
    var fallbackBrowserBundleID: String
    var fallbackBrowserAppURL: URL
    var fallbackBrowserRoute: FallbackBrowserRoute
    var rules: [SourceAppRule]
}
