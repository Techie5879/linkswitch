import XCTest
@testable import LinkSwitch

final class AppBundleConfigurationTests: XCTestCase {
    func testAppBundleDeclaresHTTPAndHTTPSURLSchemes() throws {
        let urlTypes = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
        )
        let urlSchemes = Set(
            urlTypes.flatMap { urlType in
                urlType["CFBundleURLSchemes"] as? [String] ?? []
            }
        )

        XCTAssertTrue(urlSchemes.contains("http"))
        XCTAssertTrue(urlSchemes.contains("https"))
    }
}
