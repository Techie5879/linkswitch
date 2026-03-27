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

        XCTAssertTrue(FileManager.default.fileExists(atPath: configFileURL.path(percentEncoded: false)))
        XCTAssertEqual(try store.load(), config)
    }

    func testLoadFindsSavedConfigWhenDirectoryContainsSpaces() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        let configDirectoryURL = temporaryDirectory.appendingPathComponent("Application Support", isDirectory: true)
        let configFileURL = configDirectoryURL.appendingPathComponent("router-config.json", isDirectory: false)
        let store = RouterConfigStore(configFileURL: configFileURL)
        let config = RouterConfig(
            fallbackBrowserBundleID: "app.zen-browser.zen",
            fallbackBrowserAppURL: URL(fileURLWithPath: "/Applications/Zen.app"),
            rules: [
                SourceAppRule(
                    id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
                    sourceBundleID: "com.tinyspeck.slackmacgap",
                    target: .helium(profileDirectory: "Profile 1")
                ),
            ]
        )

        try store.save(config)

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
