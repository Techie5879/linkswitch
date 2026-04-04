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
    case unsupportedDefaultBrowserChromiumProfile(bundleID: String)
    case unsupportedDefaultBrowserProfile(bundleID: String)
    case unsupportedDefaultBrowserContainer(bundleID: String)
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
        case .defaultBrowser:
            try await openDirectApplication(
                url: url,
                bundleID: config.defaultBrowserBundleID,
                applicationURL: config.defaultBrowserAppURL,
                logLabel: "default browser"
            )
        case let .defaultBrowserChromiumProfile(profileDirectory):
            guard DefaultBrowserProfileSupport.forBundleID(config.defaultBrowserBundleID) == .chromiumProfile else {
                AppLogger.error(
                    "Default browser bundle ID \(config.defaultBrowserBundleID) does not support Chromium profile routing",
                    category: .launch
                )
                throw BrowserLauncherError.unsupportedDefaultBrowserChromiumProfile(bundleID: config.defaultBrowserBundleID)
            }

            try await launchChromiumApplication(
                url: url,
                bundleID: config.defaultBrowserBundleID,
                applicationURL: config.defaultBrowserAppURL,
                profileDirectory: profileDirectory,
                logLabel: "default browser"
            )
        case let .defaultBrowserFirefoxProfile(profileKey):
            guard DefaultBrowserProfileSupport.forBundleID(config.defaultBrowserBundleID) == .firefoxProfile else {
                AppLogger.error(
                    "Default browser bundle ID \(config.defaultBrowserBundleID) does not support Firefox-style profile routing",
                    category: .launch
                )
                throw BrowserLauncherError.unsupportedDefaultBrowserProfile(bundleID: config.defaultBrowserBundleID)
            }

            try await launchFirefoxFamilyApplication(
                url: url,
                browserBundleID: config.defaultBrowserBundleID,
                applicationURL: config.defaultBrowserAppURL,
                profileKey: profileKey,
                logLabel: "default browser"
            )
        case let .defaultBrowserZenContainer(containerName):
            guard DefaultBrowserProfileSupport.forBundleID(config.defaultBrowserBundleID) == .zenContainer else {
                AppLogger.error(
                    "Default browser bundle ID \(config.defaultBrowserBundleID) does not support Zen container routing",
                    category: .launch
                )
                throw BrowserLauncherError.unsupportedDefaultBrowserContainer(bundleID: config.defaultBrowserBundleID)
            }

            try await openZenContainer(
                url: url,
                applicationURL: config.defaultBrowserAppURL,
                containerName: containerName,
                logLabel: "default browser"
            )
        case let .application(bundleID, applicationURL):
            try await openDirectApplication(
                url: url,
                bundleID: bundleID,
                applicationURL: applicationURL,
                logLabel: "browser rule"
            )
        case let .applicationChromiumProfile(bundleID, applicationURL, profileDirectory):
            guard DefaultBrowserProfileSupport.forBundleID(bundleID) == .chromiumProfile else {
                AppLogger.error(
                    "Browser rule bundle ID \(bundleID) does not support Chromium profile routing",
                    category: .launch
                )
                throw BrowserLauncherError.unsupportedDefaultBrowserChromiumProfile(bundleID: bundleID)
            }

            try await launchChromiumApplication(
                url: url,
                bundleID: bundleID,
                applicationURL: applicationURL,
                profileDirectory: profileDirectory,
                logLabel: "browser rule"
            )
        case let .applicationFirefoxProfile(bundleID, applicationURL, profileKey):
            guard DefaultBrowserProfileSupport.forBundleID(bundleID) == .firefoxProfile else {
                AppLogger.error(
                    "Browser rule bundle ID \(bundleID) does not support Firefox-style profile routing",
                    category: .launch
                )
                throw BrowserLauncherError.unsupportedDefaultBrowserProfile(bundleID: bundleID)
            }

            try await launchFirefoxFamilyApplication(
                url: url,
                browserBundleID: bundleID,
                applicationURL: applicationURL,
                profileKey: profileKey,
                logLabel: "browser rule"
            )
        case let .applicationZenContainer(bundleID, applicationURL, containerName):
            guard DefaultBrowserProfileSupport.forBundleID(bundleID) == .zenContainer else {
                AppLogger.error(
                    "Browser rule bundle ID \(bundleID) does not support Zen container routing",
                    category: .launch
                )
                throw BrowserLauncherError.unsupportedDefaultBrowserContainer(bundleID: bundleID)
            }

            try await openZenContainer(
                url: url,
                applicationURL: applicationURL,
                containerName: containerName,
                logLabel: "browser rule"
            )
        case let .helium(profileDirectory):
            let applicationURL = try launchServicesBridge.applicationURL(forBundleIdentifier: Self.heliumBundleID)
            try await launchChromiumApplication(
                url: url,
                bundleID: Self.heliumBundleID,
                applicationURL: applicationURL,
                profileDirectory: profileDirectory,
                logLabel: "legacy Helium rule"
            )
        }
    }

    private func openDirectApplication(
        url: URL,
        bundleID: String,
        applicationURL: URL,
        logLabel: String
    ) async throws {
        AppLogger.info(
            "Routing URL \(url.absoluteString) to \(logLabel) \(bundleID) at \(applicationURL.path())",
            category: .launch
        )
        try await workspaceLauncher.openURLs([url], withApplicationAt: applicationURL)
    }

    private func launchChromiumApplication(
        url: URL,
        bundleID: String,
        applicationURL: URL,
        profileDirectory: String,
        logLabel: String
    ) async throws {
        let arguments = try ChromiumLaunchArguments.make(url: url, profileDirectory: profileDirectory)
        AppLogger.info(
            "Routing URL \(url.absoluteString) to \(logLabel) \(bundleID) at \(applicationURL.path()) with Chromium profile arguments \(arguments)",
            category: .launch
        )
        try await workspaceLauncher.launchApplicationExecutable(at: applicationURL, arguments: arguments)
    }

    private func launchFirefoxFamilyApplication(
        url: URL,
        browserBundleID: String,
        applicationURL: URL,
        profileKey: String,
        logLabel: String
    ) async throws {
        let arguments = try FirefoxLaunchArguments.make(
            url: url,
            profileKey: profileKey,
            browserBundleID: browserBundleID,
            appSupportURL: appSupportURL,
            homeDirectoryURL: homeDirectoryURL
        )
        AppLogger.info(
            "Routing URL \(url.absoluteString) to \(logLabel) \(browserBundleID) at \(applicationURL.path()) with Firefox-style profile arguments \(arguments)",
            category: .launch
        )
        try await workspaceLauncher.launchApplicationExecutable(at: applicationURL, arguments: arguments)
    }

    private func openZenContainer(
        url: URL,
        applicationURL: URL,
        containerName: String,
        logLabel: String
    ) async throws {
        let containerURL = try ZenContainerOpenURL.make(url: url, containerName: containerName)
        AppLogger.info(
            "Routing URL \(url.absoluteString) to \(logLabel) Zen container \(containerName) via \(containerURL.absoluteString)",
            category: .launch
        )
        try await workspaceLauncher.openURLs([containerURL], withApplicationAt: applicationURL)
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
