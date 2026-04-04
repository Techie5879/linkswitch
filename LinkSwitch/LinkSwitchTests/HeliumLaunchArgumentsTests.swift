import XCTest
@testable import LinkSwitch

final class ChromiumLaunchArgumentsTests: XCTestCase {
    func testMakeProducesProfileFlagAndURL() throws {
        let arguments = try ChromiumLaunchArguments.make(
            url: URL(string: "https://example.com/path?query=1#fragment")!,
            profileDirectory: "Profile 1"
        )

        XCTAssertEqual(
            arguments,
            [
                "--profile-directory=Profile 1",
                "https://example.com/path?query=1#fragment",
            ]
        )
    }

    func testMakeTrimsWhitespaceAroundProfileDirectory() throws {
        let arguments = try ChromiumLaunchArguments.make(
            url: URL(string: "https://example.com")!,
            profileDirectory: "  Profile 1 \n"
        )

        XCTAssertEqual(arguments.first, "--profile-directory=Profile 1")
    }

    func testMakeThrowsForEmptyProfileDirectory() {
        XCTAssertThrowsError(
            try ChromiumLaunchArguments.make(
                url: URL(string: "https://example.com")!,
                profileDirectory: " \n "
            )
        ) { error in
            XCTAssertEqual(error as? ChromiumLaunchArgumentsError, .emptyProfileDirectory)
        }
    }
}
