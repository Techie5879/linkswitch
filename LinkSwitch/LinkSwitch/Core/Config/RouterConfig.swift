import Foundation

enum BrowserTarget: Codable, Equatable, CustomStringConvertible {
    case fallbackBrowser
    case helium(profileDirectory: String)

    var description: String {
        switch self {
        case .fallbackBrowser:
            return "fallbackBrowser"
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
    var rules: [SourceAppRule]
}
