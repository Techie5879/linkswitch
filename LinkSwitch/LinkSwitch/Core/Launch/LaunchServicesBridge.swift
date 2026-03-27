import AppKit
import Foundation

enum LaunchServicesBridgeError: Error, Equatable {
    case defaultHandlerNotFound(urlScheme: String)
    case applicationNotFound(bundleID: String)
    case setDefaultHandlerFailed(urlScheme: String, message: String)
}

protocol LaunchServicesProviding {
    func defaultHandlerBundleID(forURLScheme urlScheme: String) -> String?
    func applicationURL(forBundleIdentifier bundleID: String) -> URL?
    func setDefaultHandler(applicationURL: URL, urlScheme: String) async throws
}

struct LaunchServicesBridge {
    private let provider: any LaunchServicesProviding

    init(provider: any LaunchServicesProviding) {
        self.provider = provider
    }

    init() {
        self.provider = SystemLaunchServicesProvider()
    }

    func defaultHandlerBundleID(forURLScheme urlScheme: String) throws -> String {
        AppLogger.info("Resolving default handler bundle ID for URL scheme \(urlScheme)", category: .launch)
        guard let bundleID = provider.defaultHandlerBundleID(forURLScheme: urlScheme) else {
            AppLogger.error("No default handler found for URL scheme \(urlScheme)", category: .launch)
            throw LaunchServicesBridgeError.defaultHandlerNotFound(urlScheme: urlScheme)
        }

        AppLogger.info(
            "Resolved default handler bundle ID \(bundleID) for URL scheme \(urlScheme)",
            category: .launch
        )
        return bundleID
    }

    func applicationURL(forBundleIdentifier bundleID: String) throws -> URL {
        AppLogger.info("Resolving application URL for bundle ID \(bundleID)", category: .launch)
        guard let applicationURL = provider.applicationURL(forBundleIdentifier: bundleID) else {
            AppLogger.error("No application URL found for bundle ID \(bundleID)", category: .launch)
            throw LaunchServicesBridgeError.applicationNotFound(bundleID: bundleID)
        }

        AppLogger.info(
            "Resolved application URL \(applicationURL.path()) for bundle ID \(bundleID)",
            category: .launch
        )
        return applicationURL
    }

    func setDefaultHandler(applicationURL: URL, urlSchemes: [String]) async throws {
        AppLogger.info(
            "Setting default handler \(applicationURL.path()) for URL schemes \(urlSchemes)",
            category: .launch
        )

        for urlScheme in urlSchemes {
            do {
                try await provider.setDefaultHandler(applicationURL: applicationURL, urlScheme: urlScheme)
                AppLogger.info(
                    "Set default handler \(applicationURL.path()) for URL scheme \(urlScheme)",
                    category: .launch
                )
            } catch {
                AppLogger.error(
                    "Failed to set default handler \(applicationURL.path()) for URL scheme \(urlScheme): \(error)",
                    category: .launch
                )
                throw LaunchServicesBridgeError.setDefaultHandlerFailed(
                    urlScheme: urlScheme,
                    message: String(describing: error)
                )
            }
        }
    }
}

struct SystemLaunchServicesProvider: LaunchServicesProviding {
    func defaultHandlerBundleID(forURLScheme urlScheme: String) -> String? {
        guard
            let probeURL = URL(string: "\(urlScheme)://example.invalid"),
            let applicationURL = NSWorkspace.shared.urlForApplication(toOpen: probeURL),
            let bundle = Bundle(url: applicationURL),
            let bundleID = bundle.bundleIdentifier
        else {
            return nil
        }

        return bundleID
    }

    func applicationURL(forBundleIdentifier bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    func setDefaultHandler(applicationURL: URL, urlScheme: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.setDefaultApplication(at: applicationURL, toOpenURLsWithScheme: urlScheme) { error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: ())
            }
        }
    }
}
