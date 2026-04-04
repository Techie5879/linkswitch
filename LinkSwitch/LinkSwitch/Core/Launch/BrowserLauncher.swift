import AppKit
import Foundation

protocol WorkspaceLaunching {
    func openURLs(_ urls: [URL], withApplicationAt applicationURL: URL) async throws
    func launchApplicationExecutable(at applicationURL: URL, arguments: [String]) async throws
}

enum NSWorkspaceLauncherError: Error, Equatable {
    case applicationExecutableNotFound(applicationURL: URL)
}

protocol ProcessRunning {
    func run(executableURL: URL, arguments: [String]) throws -> pid_t
}

enum BrowserLauncherError: Error, Equatable {
    case unsupportedFallbackBrowserHeliumProfile(bundleID: String)
    case unsupportedFallbackBrowserProfile(bundleID: String)
    case unsupportedFallbackBrowserContainer(bundleID: String)
}

struct BrowserLauncher {
    static let heliumBundleID = "net.imput.helium"

    private let launchServicesBridge: LaunchServicesBridge
    private let workspaceLauncher: any WorkspaceLaunching
    private let appSupportURL: URL
    private let homeDirectoryURL: URL

    init(
        launchServicesBridge: LaunchServicesBridge,
        workspaceLauncher: any WorkspaceLaunching,
        appSupportURL: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0],
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.launchServicesBridge = launchServicesBridge
        self.workspaceLauncher = workspaceLauncher
        self.appSupportURL = appSupportURL
        self.homeDirectoryURL = homeDirectoryURL
    }

    init() {
        self.init(
            launchServicesBridge: LaunchServicesBridge(),
            workspaceLauncher: NSWorkspaceLauncher()
        )
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
        case let .fallbackBrowserHeliumProfile(profileDirectory):
            guard FallbackBrowserProfileSupport.forBundleID(config.fallbackBrowserBundleID) == .heliumProfile else {
                AppLogger.error(
                    "Fallback browser bundle ID \(config.fallbackBrowserBundleID) does not support Helium profile routing",
                    category: .launch
                )
                throw BrowserLauncherError.unsupportedFallbackBrowserHeliumProfile(bundleID: config.fallbackBrowserBundleID)
            }

            let arguments = try HeliumLaunchArguments.make(url: url, profileDirectory: profileDirectory)
            AppLogger.info(
                "Routing URL \(url.absoluteString) to fallback browser \(config.fallbackBrowserBundleID) at \(config.fallbackBrowserAppURL.path()) with Helium profile arguments \(arguments)",
                category: .launch
            )
            try await workspaceLauncher.launchApplicationExecutable(at: config.fallbackBrowserAppURL, arguments: arguments)
        case let .fallbackBrowserFirefoxProfile(profileKey):
            guard FallbackBrowserProfileSupport.forBundleID(config.fallbackBrowserBundleID) == .firefoxProfile else {
                AppLogger.error(
                    "Fallback browser bundle ID \(config.fallbackBrowserBundleID) does not support Firefox-style profile routing",
                    category: .launch
                )
                throw BrowserLauncherError.unsupportedFallbackBrowserProfile(bundleID: config.fallbackBrowserBundleID)
            }

            let arguments = try FirefoxLaunchArguments.make(
                url: url,
                profileKey: profileKey,
                browserBundleID: config.fallbackBrowserBundleID,
                appSupportURL: appSupportURL,
                homeDirectoryURL: homeDirectoryURL
            )
            AppLogger.info(
                "Routing URL \(url.absoluteString) to fallback browser \(config.fallbackBrowserBundleID) at \(config.fallbackBrowserAppURL.path()) with Firefox-style profile arguments \(arguments)",
                category: .launch
            )
            try await workspaceLauncher.launchApplicationExecutable(at: config.fallbackBrowserAppURL, arguments: arguments)
        case let .fallbackBrowserZenContainer(containerName):
            guard FallbackBrowserProfileSupport.forBundleID(config.fallbackBrowserBundleID) == .zenContainer else {
                AppLogger.error(
                    "Fallback browser bundle ID \(config.fallbackBrowserBundleID) does not support Zen container routing",
                    category: .launch
                )
                throw BrowserLauncherError.unsupportedFallbackBrowserContainer(bundleID: config.fallbackBrowserBundleID)
            }

            let containerURL = try ZenContainerOpenURL.make(url: url, containerName: containerName)
            AppLogger.info(
                "Routing URL \(url.absoluteString) to Zen container \(containerName) via \(containerURL.absoluteString)",
                category: .launch
            )
            try await workspaceLauncher.openURLs([containerURL], withApplicationAt: config.fallbackBrowserAppURL)
        case let .helium(profileDirectory):
            let applicationURL = try launchServicesBridge.applicationURL(forBundleIdentifier: Self.heliumBundleID)
            let arguments = try HeliumLaunchArguments.make(url: url, profileDirectory: profileDirectory)
            AppLogger.info(
                "Routing URL \(url.absoluteString) to Helium at \(applicationURL.path()) with arguments \(arguments)",
                category: .launch
            )
            try await workspaceLauncher.launchApplicationExecutable(at: applicationURL, arguments: arguments)
        }
    }
}

struct NSWorkspaceLauncher: WorkspaceLaunching {
    private let workspace: NSWorkspace
    private let processRunner: any ProcessRunning

    init(
        workspace: NSWorkspace = .shared,
        processRunner: any ProcessRunning = ProcessRunner()
    ) {
        self.workspace = workspace
        self.processRunner = processRunner
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

    func launchApplicationExecutable(at applicationURL: URL, arguments: [String]) async throws {
        AppLogger.info(
            "Launching application executable for \(applicationURL.path()) with arguments \(arguments)",
            category: .launch
        )

        guard let executableURL = Bundle(url: applicationURL)?.executableURL else {
            AppLogger.error("Could not resolve executable URL for application \(applicationURL.path())", category: .launch)
            throw NSWorkspaceLauncherError.applicationExecutableNotFound(applicationURL: applicationURL)
        }

        do {
            let processIdentifier = try processRunner.run(executableURL: executableURL, arguments: arguments)
            AppLogger.info(
                "Launched executable \(executableURL.path()) with arguments \(arguments) as pid \(processIdentifier)",
                category: .launch
            )
            AppLogger.info(
                "Skipping manual app activation after launching \(applicationURL.path()) to avoid surfacing the wrong existing window",
                category: .launch
            )
        } catch {
            AppLogger.error(
                "Failed launching executable \(executableURL.path()) with arguments \(arguments): \(error)",
                category: .launch
            )
            throw error
        }
    }
}

struct ProcessRunner: ProcessRunning {
    func run(executableURL: URL, arguments: [String]) throws -> pid_t {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        try process.run()
        return process.processIdentifier
    }
}
