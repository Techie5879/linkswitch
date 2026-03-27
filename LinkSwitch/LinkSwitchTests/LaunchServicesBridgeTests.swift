import XCTest
@testable import LinkSwitch

final class LaunchServicesBridgeTests: XCTestCase {
    func testDefaultHandlerBundleIDReturnsResolvedBundleID() throws {
        let provider = LaunchServicesProviderSpy()
        provider.defaultHandlerBundleIDResult = "com.apple.Safari"
        let bridge = LaunchServicesBridge(provider: provider)

        XCTAssertEqual(
            try bridge.defaultHandlerBundleID(forURLScheme: "https"),
            "com.apple.Safari"
        )
        XCTAssertEqual(provider.defaultHandlerBundleIDRequests, ["https"])
    }

    func testDefaultHandlerBundleIDThrowsWhenNoHandlerIsAvailable() {
        let bridge = LaunchServicesBridge(provider: LaunchServicesProviderSpy())

        XCTAssertThrowsError(
            try bridge.defaultHandlerBundleID(forURLScheme: "http")
        ) { error in
            XCTAssertEqual(
                error as? LaunchServicesBridgeError,
                .defaultHandlerNotFound(urlScheme: "http")
            )
        }
    }

    func testApplicationURLReturnsResolvedApplicationURL() throws {
        let applicationURL = URL(fileURLWithPath: "/Applications/Safari.app")
        let provider = LaunchServicesProviderSpy()
        provider.applicationURLResult = applicationURL
        let bridge = LaunchServicesBridge(provider: provider)

        XCTAssertEqual(
            try bridge.applicationURL(forBundleIdentifier: "com.apple.Safari"),
            applicationURL
        )
        XCTAssertEqual(provider.applicationURLRequests, ["com.apple.Safari"])
    }

    func testApplicationURLThrowsWhenBundleIDCannotBeResolved() {
        let bridge = LaunchServicesBridge(provider: LaunchServicesProviderSpy())

        XCTAssertThrowsError(
            try bridge.applicationURL(forBundleIdentifier: "net.imput.helium")
        ) { error in
            XCTAssertEqual(
                error as? LaunchServicesBridgeError,
                .applicationNotFound(bundleID: "net.imput.helium")
            )
        }
    }

    func testSetDefaultHandlerRegistersEachScheme() async throws {
        let applicationURL = URL(fileURLWithPath: "/Applications/LinkSwitch.app")
        let provider = LaunchServicesProviderSpy()
        let bridge = LaunchServicesBridge(provider: provider)

        try await bridge.setDefaultHandler(applicationURL: applicationURL, urlSchemes: ["http", "https"])

        XCTAssertEqual(
            provider.defaultHandlerSetCalls,
            [
                LaunchServicesProviderSpy.SetCall(applicationURL: applicationURL, urlScheme: "http"),
                LaunchServicesProviderSpy.SetCall(applicationURL: applicationURL, urlScheme: "https"),
            ]
        )
    }

    func testSetDefaultHandlerThrowsWhenRegistrationFails() async {
        let provider = LaunchServicesProviderSpy()
        provider.setDefaultHandlerErrorByScheme["https"] = RegistrationFailure()
        let bridge = LaunchServicesBridge(provider: provider)

        do {
            try await bridge.setDefaultHandler(
                applicationURL: URL(fileURLWithPath: "/Applications/LinkSwitch.app"),
                urlSchemes: ["http", "https"]
            )
            XCTFail("Expected setDefaultHandler to throw")
        } catch {
            XCTAssertEqual(
                error as? LaunchServicesBridgeError,
                .setDefaultHandlerFailed(urlScheme: "https", message: String(describing: RegistrationFailure()))
            )
        }
    }
}

private struct RegistrationFailure: Error {}

private final class LaunchServicesProviderSpy: LaunchServicesProviding {
    struct SetCall: Equatable {
        let applicationURL: URL
        let urlScheme: String
    }

    var defaultHandlerBundleIDResult: String?
    var applicationURLResult: URL?
    var setDefaultHandlerErrorByScheme: [String: Error] = [:]

    private(set) var defaultHandlerBundleIDRequests: [String] = []
    private(set) var applicationURLRequests: [String] = []
    private(set) var defaultHandlerSetCalls: [SetCall] = []

    func defaultHandlerBundleID(forURLScheme urlScheme: String) -> String? {
        defaultHandlerBundleIDRequests.append(urlScheme)
        return defaultHandlerBundleIDResult
    }

    func applicationURL(forBundleIdentifier bundleID: String) -> URL? {
        applicationURLRequests.append(bundleID)
        return applicationURLResult
    }

    func setDefaultHandler(applicationURL: URL, urlScheme: String) async throws {
        defaultHandlerSetCalls.append(SetCall(applicationURL: applicationURL, urlScheme: urlScheme))
        if let error = setDefaultHandlerErrorByScheme[urlScheme] {
            throw error
        }
    }
}
