import AppKit
import Foundation

protocol WorkspaceLaunching {
    func openURLs(_ urls: [URL], withApplicationAt applicationURL: URL) async throws
    func openApplication(at applicationURL: URL, arguments: [String]) async throws
}

struct BrowserLauncher {
    static let heliumBundleID = "net.imput.helium"

    private let launchServicesBridge: LaunchServicesBridge
    private let workspaceLauncher: any WorkspaceLaunching

    init(launchServicesBridge: LaunchServicesBridge, workspaceLauncher: any WorkspaceLaunching) {
        self.launchServicesBridge = launchServicesBridge
        self.workspaceLauncher = workspaceLauncher
    }

    init() {
        self.launchServicesBridge = LaunchServicesBridge()
        self.workspaceLauncher = NSWorkspaceLauncher()
    }

    func open(_ url: URL, target: BrowserTarget, config: RouterConfig) async throws {
        AppLogger.info(
            "Opening URL \(url.absoluteString) for target \(target.description)",
            category: .launch
        )

        switch target {
        case .fallbackBrowser:
            AppLogger.info(
                "Routing URL \(url.absoluteString) to fallback browser \(config.fallbackBrowserBundleID) at \(config.fallbackBrowserAppURL.path())",
                category: .launch
            )
            try await workspaceLauncher.openURLs([url], withApplicationAt: config.fallbackBrowserAppURL)
        case let .helium(profileDirectory):
            let applicationURL = try launchServicesBridge.applicationURL(forBundleIdentifier: Self.heliumBundleID)
            let arguments = try HeliumLaunchArguments.make(url: url, profileDirectory: profileDirectory)
            AppLogger.info(
                "Routing URL \(url.absoluteString) to Helium at \(applicationURL.path()) with arguments \(arguments)",
                category: .launch
            )
            try await workspaceLauncher.openApplication(at: applicationURL, arguments: arguments)
        }
    }
}

struct NSWorkspaceLauncher: WorkspaceLaunching {
    private let workspace: NSWorkspace

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    func openURLs(_ urls: [URL], withApplicationAt applicationURL: URL) async throws {
        AppLogger.info(
            "NSWorkspace opening URLs \(urls.map(\.absoluteString)) with application \(applicationURL.path())",
            category: .launch
        )

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            workspace.open(urls, withApplicationAt: applicationURL, configuration: configuration) { _, error in
                if let error {
                    AppLogger.error(
                        "NSWorkspace failed opening URLs \(urls.map(\.absoluteString)) with application \(applicationURL.path()): \(error)",
                        category: .launch
                    )
                    continuation.resume(throwing: error)
                    return
                }

                AppLogger.info(
                    "NSWorkspace finished opening URLs \(urls.map(\.absoluteString)) with application \(applicationURL.path())",
                    category: .launch
                )
                continuation.resume(returning: ())
            }
        }
    }

    func openApplication(at applicationURL: URL, arguments: [String]) async throws {
        AppLogger.info(
            "NSWorkspace launching application \(applicationURL.path()) with arguments \(arguments)",
            category: .launch
        )

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.arguments = arguments

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            workspace.openApplication(at: applicationURL, configuration: configuration) { _, error in
                if let error {
                    AppLogger.error(
                        "NSWorkspace failed launching application \(applicationURL.path()) with arguments \(arguments): \(error)",
                        category: .launch
                    )
                    continuation.resume(throwing: error)
                    return
                }

                AppLogger.info(
                    "NSWorkspace finished launching application \(applicationURL.path()) with arguments \(arguments)",
                    category: .launch
                )
                continuation.resume(returning: ())
            }
        }
    }
}
