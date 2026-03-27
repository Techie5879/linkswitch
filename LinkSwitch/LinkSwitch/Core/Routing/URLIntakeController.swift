import AppKit
import Foundation

protocol RouterConfigLoading {
    func load() throws -> RouterConfig?
}

protocol BrowserLaunching {
    func open(_ url: URL, target: BrowserTarget, config: RouterConfig) async throws
}

enum URLIntakeControllerError: Error, Equatable {
    case missingConfig
}

struct URLIntakeController {
    private let configStore: any RouterConfigLoading
    private let ruleEngine: RuleEngine
    private let browserLauncher: any BrowserLaunching

    init(
        configStore: any RouterConfigLoading,
        ruleEngine: RuleEngine,
        browserLauncher: any BrowserLaunching
    ) {
        self.configStore = configStore
        self.ruleEngine = ruleEngine
        self.browserLauncher = browserLauncher
    }

    static func live() throws -> URLIntakeController {
        let configStore = RouterConfigStore(configFileURL: try RouterConfigStore.defaultConfigFileURL())
        return URLIntakeController(
            configStore: configStore,
            ruleEngine: RuleEngine(),
            browserLauncher: BrowserLauncher()
        )
    }

    func handle(urls: [URL], sourceBundleID: String?) async throws {
        AppLogger.info(
            "Handling \(urls.count) incoming URL(s) from source \(sourceBundleID ?? "nil")",
            category: .routing
        )
        guard let config = try configStore.load() else {
            AppLogger.error("No router config is available for incoming URL handling", category: .routing)
            throw URLIntakeControllerError.missingConfig
        }

        for url in urls {
            let context = IncomingOpenContext(url: url, sourceBundleID: sourceBundleID)
            let target = ruleEngine.target(for: context, config: config)
            AppLogger.info(
                "URL intake selected target \(target.description) for \(url.absoluteString)",
                category: .routing
            )
            try await browserLauncher.open(url, target: target, config: config)
        }
    }
}

extension RouterConfigStore: RouterConfigLoading {}
extension BrowserLauncher: BrowserLaunching {}
