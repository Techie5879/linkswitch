import XCTest
@testable import LinkSwitch

final class RouterConfigStoreTests: XCTestCase {
    func testLoadReturnsNilWhenConfigFileDoesNotExist() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        let store = RouterConfigStore(configFileURL: temporaryDirectory.appendingPathComponent("router-config.json"))

        XCTAssertNil(try store.load())
    }

    func testSaveCreatesDirectoryAndLoadReturnsSavedConfig() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        let configFileURL = temporaryDirectory
            .appendingPathComponent("nested", isDirectory: true)
            .appendingPathComponent("router-config.json", isDirectory: false)
        let store = RouterConfigStore(configFileURL: configFileURL)
        let config = RouterConfig(
            fallbackBrowserBundleID: "com.apple.Safari",
            fallbackBrowserAppURL: URL(fileURLWithPath: "/Applications/Safari.app"),
            rules: [
                SourceAppRule(
                    id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
                    sourceBundleID: "com.tinyspeck.slackmacgap",
                    target: .helium(profileDirectory: "Profile 1")
                ),
            ]
        )

        try store.save(config)

        XCTAssertTrue(FileManager.default.fileExists(atPath: configFileURL.path()))
        XCTAssertEqual(try store.load(), config)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        return temporaryDirectory
    }
}
