import Foundation

struct RouterConfigStore {
    let configFileURL: URL

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        configFileURL: URL,
        fileManager: FileManager = .default,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.configFileURL = configFileURL
        self.fileManager = fileManager
        self.encoder = encoder
        self.decoder = decoder
    }

    static func defaultConfigFileURL(fileManager: FileManager = .default) throws -> URL {
        let applicationSupportDirectory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let configDirectory = applicationSupportDirectory.appendingPathComponent("LinkSwitch", isDirectory: true)
        let configFileURL = configDirectory.appendingPathComponent("router-config.json", isDirectory: false)
        AppLogger.debug("Resolved default config path: \(configFileURL.path())", category: .config)
        return configFileURL
    }

    func load() throws -> RouterConfig? {
        AppLogger.info("Loading router config from \(configFileURL.path())", category: .config)
        guard fileManager.fileExists(atPath: configFileURL.path()) else {
            AppLogger.info("Router config file does not exist yet", category: .config)
            return nil
        }

        let data = try Data(contentsOf: configFileURL)
        let config = try decoder.decode(RouterConfig.self, from: data)
        AppLogger.info(
            "Loaded router config with fallback browser \(config.fallbackBrowserBundleID) and \(config.rules.count) rule(s)",
            category: .config
        )
        return config
    }

    func save(_ config: RouterConfig) throws {
        let directoryURL = configFileURL.deletingLastPathComponent()
        AppLogger.info("Saving router config to \(configFileURL.path())", category: .config)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let data = try encoder.encode(config)
        try data.write(to: configFileURL, options: .atomic)
        AppLogger.info(
            "Saved router config with fallback browser \(config.fallbackBrowserBundleID) and \(config.rules.count) rule(s)",
            category: .config
        )
    }
}
