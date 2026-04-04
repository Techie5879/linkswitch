import XCTest
@testable import LinkSwitch

final class LaunchAtLoginBridgeTests: XCTestCase {
    func testStatusReturnsProviderStatus() {
        let provider = LaunchAtLoginProviderSpy(status: .enabled)
        let bridge = LaunchAtLoginBridge(provider: provider)

        XCTAssertEqual(bridge.status(), .enabled)
    }

    func testSetEnabledRegistersWhenCurrentlyDisabled() throws {
        let provider = LaunchAtLoginProviderSpy(status: .notRegistered)
        provider.statusAfterRegister = .requiresApproval
        let bridge = LaunchAtLoginBridge(provider: provider)

        let updatedStatus = try bridge.setEnabled(true)

        XCTAssertEqual(provider.registerCallCount, 1)
        XCTAssertEqual(provider.unregisterCallCount, 0)
        XCTAssertEqual(updatedStatus, .requiresApproval)
    }

    func testSetEnabledDoesNotRegisterWhenAlreadyEnabled() throws {
        let provider = LaunchAtLoginProviderSpy(status: .enabled)
        let bridge = LaunchAtLoginBridge(provider: provider)

        let updatedStatus = try bridge.setEnabled(true)

        XCTAssertEqual(provider.registerCallCount, 0)
        XCTAssertEqual(provider.unregisterCallCount, 0)
        XCTAssertEqual(updatedStatus, .enabled)
    }

    func testSetEnabledUnregistersWhenCurrentlyEnabled() throws {
        let provider = LaunchAtLoginProviderSpy(status: .enabled)
        provider.statusAfterUnregister = .notRegistered
        let bridge = LaunchAtLoginBridge(provider: provider)

        let updatedStatus = try bridge.setEnabled(false)

        XCTAssertEqual(provider.registerCallCount, 0)
        XCTAssertEqual(provider.unregisterCallCount, 1)
        XCTAssertEqual(updatedStatus, .notRegistered)
    }

    func testOpenSystemSettingsDelegatesToProvider() {
        let provider = LaunchAtLoginProviderSpy(status: .requiresApproval)
        let bridge = LaunchAtLoginBridge(provider: provider)

        bridge.openSystemSettingsLoginItems()

        XCTAssertEqual(provider.openSystemSettingsCallCount, 1)
    }
}

private final class LaunchAtLoginProviderSpy: LaunchAtLoginProviding {
    var status: LaunchAtLoginStatus
    var statusAfterRegister: LaunchAtLoginStatus
    var statusAfterUnregister: LaunchAtLoginStatus

    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0
    private(set) var openSystemSettingsCallCount = 0

    init(status: LaunchAtLoginStatus) {
        self.status = status
        self.statusAfterRegister = status
        self.statusAfterUnregister = status
    }

    func register() throws {
        registerCallCount += 1
        status = statusAfterRegister
    }

    func unregister() throws {
        unregisterCallCount += 1
        status = statusAfterUnregister
    }

    func openSystemSettingsLoginItems() {
        openSystemSettingsCallCount += 1
    }
}
