import AppKit
import Foundation

protocol WorkspaceLaunching {
    func openURLs(_ urls: [URL], withApplicationAt applicationURL: URL) async throws
    func launchApplicationExecutable(at applicationURL: URL, arguments: [String]) async throws
}

enum NSWorkspaceLauncherError: Error, Equatable {
    case applicationExecutableNotFound(applicationURL: URL)
    case applicationBundleIdentifierNotFound(applicationURL: URL)
}

enum RunningApplicationActivatorError: Error, Equatable {
    case runningApplicationNotFound(bundleIdentifier: String)
    case activateFailed(bundleIdentifier: String)
}

protocol ProcessRunning {
    func run(executableURL: URL, arguments: [String]) throws -> pid_t
}

protocol RunningApplicationActivating {
    func activate(bundleIdentifier: String) async throws
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
            try await workspaceLauncher.launchApplicationExecutable(at: applicationURL, arguments: arguments)
        }
    }
}

struct NSWorkspaceLauncher: WorkspaceLaunching {
    private let workspace: NSWorkspace
    private let processRunner: any ProcessRunning
    private let runningApplicationActivator: any RunningApplicationActivating

    init(
        workspace: NSWorkspace = .shared,
        processRunner: any ProcessRunning = ProcessRunner(),
        runningApplicationActivator: any RunningApplicationActivating = RunningApplicationActivator()
    ) {
        self.workspace = workspace
        self.processRunner = processRunner
        self.runningApplicationActivator = runningApplicationActivator
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

        guard let bundleIdentifier = Bundle(url: applicationURL)?.bundleIdentifier else {
            AppLogger.error("Could not resolve bundle identifier for application \(applicationURL.path())", category: .launch)
            throw NSWorkspaceLauncherError.applicationBundleIdentifierNotFound(applicationURL: applicationURL)
        }

        do {
            let processIdentifier = try processRunner.run(executableURL: executableURL, arguments: arguments)
            AppLogger.info(
                "Launched executable \(executableURL.path()) with arguments \(arguments) as pid \(processIdentifier)",
                category: .launch
            )
            try await runningApplicationActivator.activate(bundleIdentifier: bundleIdentifier)
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

struct RunningApplicationActivator: RunningApplicationActivating {
    private let activationOptions: NSApplication.ActivationOptions = [.activateAllWindows]

    func activate(bundleIdentifier: String) async throws {
        for attempt in 1...20 {
            let runningApplications = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            if let runningApplication = runningApplications.max(by: { lhs, rhs in
                (lhs.launchDate ?? .distantPast) < (rhs.launchDate ?? .distantPast)
            }) {
                AppLogger.info(
                    "Resolved running application \(runningApplication.processIdentifier) for bundle ID \(bundleIdentifier) on activation attempt \(attempt)",
                    category: .launch
                )

                if runningApplication.activate(options: activationOptions) {
                    AppLogger.info(
                        "Activated running application \(runningApplication.processIdentifier) for bundle ID \(bundleIdentifier)",
                        category: .launch
                    )
                    return
                }

                AppLogger.error(
                    "NSRunningApplication.activate returned false for bundle ID \(bundleIdentifier)",
                    category: .launch
                )
                throw RunningApplicationActivatorError.activateFailed(bundleIdentifier: bundleIdentifier)
            }

            AppLogger.debug(
                "Running application for bundle ID \(bundleIdentifier) was not available on activation attempt \(attempt)",
                category: .launch
            )
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        AppLogger.error("Could not resolve running application for bundle ID \(bundleIdentifier) after activation retries", category: .launch)
        throw RunningApplicationActivatorError.runningApplicationNotFound(bundleIdentifier: bundleIdentifier)
    }
}
