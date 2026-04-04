import Foundation
import ServiceManagement

enum LaunchAtLoginStatus: Equatable {
    case notRegistered
    case requiresApproval
    case enabled
    case notFound
    case unsupported

    var isToggleOn: Bool {
        switch self {
        case .enabled, .requiresApproval:
            return true
        case .notRegistered, .notFound, .unsupported:
            return false
        }
    }
}

enum LaunchAtLoginBridgeError: Error {
    case registerFailed(String)
    case unregisterFailed(String)
}

extension LaunchAtLoginBridgeError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .registerFailed(message):
            return "Could not register LinkSwitch to open at login. \(message)"
        case let .unregisterFailed(message):
            return "Could not remove LinkSwitch from login items. \(message)"
        }
    }
}

protocol LaunchAtLoginProviding {
    var status: LaunchAtLoginStatus { get }
    func register() throws
    func unregister() throws
    func openSystemSettingsLoginItems()
}

struct LaunchAtLoginBridge {
    private let provider: any LaunchAtLoginProviding

    init(provider: any LaunchAtLoginProviding) {
        self.provider = provider
    }

    init() {
        self.provider = SystemLaunchAtLoginProvider()
    }

    func status() -> LaunchAtLoginStatus {
        let status = provider.status
        AppLogger.info("Resolved launch-at-login status \(status)", category: .launch)
        return status
    }

    @discardableResult
    func setEnabled(_ enabled: Bool) throws -> LaunchAtLoginStatus {
        let currentStatus = provider.status
        AppLogger.info(
            "Setting launch-at-login enabled=\(enabled). currentStatus=\(currentStatus)",
            category: .launch
        )

        if enabled {
            switch currentStatus {
            case .enabled, .requiresApproval:
                AppLogger.info("Launch-at-login is already active or awaiting approval", category: .launch)
                return currentStatus
            case .notRegistered, .notFound, .unsupported:
                do {
                    try provider.register()
                } catch {
                    AppLogger.error("Launch-at-login registration failed: \(error)", category: .launch)
                    throw LaunchAtLoginBridgeError.registerFailed(String(describing: error))
                }
            }
        } else {
            switch currentStatus {
            case .enabled, .requiresApproval:
                do {
                    try provider.unregister()
                } catch {
                    AppLogger.error("Launch-at-login unregistration failed: \(error)", category: .launch)
                    throw LaunchAtLoginBridgeError.unregisterFailed(String(describing: error))
                }
            case .notRegistered, .notFound, .unsupported:
                AppLogger.info("Launch-at-login is already disabled", category: .launch)
                return currentStatus
            }
        }

        let updatedStatus = provider.status
        AppLogger.info(
            "Launch-at-login updated. enabled=\(enabled) updatedStatus=\(updatedStatus)",
            category: .launch
        )
        return updatedStatus
    }

    func openSystemSettingsLoginItems() {
        AppLogger.info("Opening System Settings Login Items pane", category: .launch)
        provider.openSystemSettingsLoginItems()
    }
}

private struct SystemLaunchAtLoginProvider: LaunchAtLoginProviding {
    private let service = SMAppService.mainApp

    var status: LaunchAtLoginStatus {
        switch service.status {
        case .notRegistered:
            return .notRegistered
        case .requiresApproval:
            return .requiresApproval
        case .enabled:
            return .enabled
        case .notFound:
            return .notFound
        @unknown default:
            AppLogger.error("SMAppService reported an unsupported launch-at-login status", category: .launch)
            return .unsupported
        }
    }

    func register() throws {
        try service.register()
    }

    func unregister() throws {
        try service.unregister()
    }

    func openSystemSettingsLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
