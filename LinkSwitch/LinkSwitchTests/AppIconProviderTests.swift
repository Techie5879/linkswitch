import AppKit
import XCTest
@testable import LinkSwitch

@MainActor
final class AppIconProviderTests: XCTestCase {
    func testIconForAppURLPrefersCanonicalURLResolvedFromBundleIdentifier() throws {
        let resolver = ApplicationIconResolverSpy()
        let provider = AppIconProvider(resolver: resolver)
        let bundleID = "com.example.Source"
        let discoveredURL = try makeApplicationBundle(
            name: "Discovered",
            bundleIdentifier: bundleID
        )
        let canonicalURL = try makeApplicationBundle(
            name: "Canonical",
            bundleIdentifier: bundleID
        )
        let canonicalImage = NSImage(size: NSSize(width: 32, height: 32))
        let discoveredImage = NSImage(size: NSSize(width: 16, height: 16))

        resolver.applicationURLsByBundleID[bundleID] = canonicalURL
        resolver.imagesByPath[canonicalURL.path(percentEncoded: false)] = canonicalImage
        resolver.imagesByPath[discoveredURL.path(percentEncoded: false)] = discoveredImage

        let icon = provider.icon(forAppURL: discoveredURL)

        XCTAssertTrue(icon === canonicalImage)
        XCTAssertEqual(resolver.applicationURLRequests, [bundleID])
        XCTAssertEqual(
            resolver.iconRequests,
            [canonicalURL.path(percentEncoded: false)]
        )

        let cachedBundleIcon = provider.icon(forBundleID: bundleID)
        XCTAssertTrue(cachedBundleIcon === canonicalImage)
        XCTAssertEqual(resolver.applicationURLRequests, [bundleID])
        XCTAssertEqual(
            resolver.iconRequests,
            [canonicalURL.path(percentEncoded: false)]
        )
    }

    func testIconForAppURLUsesProvidedURLWhenCanonicalBundleLookupFails() throws {
        let resolver = ApplicationIconResolverSpy()
        let provider = AppIconProvider(resolver: resolver)
        let bundleID = "com.example.Source"
        let discoveredURL = try makeApplicationBundle(
            name: "Discovered",
            bundleIdentifier: bundleID
        )
        let discoveredImage = NSImage(size: NSSize(width: 16, height: 16))

        resolver.imagesByPath[discoveredURL.path(percentEncoded: false)] = discoveredImage

        let icon = provider.icon(forAppURL: discoveredURL)

        XCTAssertTrue(icon === discoveredImage)
        XCTAssertEqual(resolver.applicationURLRequests, [bundleID])
        XCTAssertEqual(
            resolver.iconRequests,
            [discoveredURL.path(percentEncoded: false)]
        )
    }

    private func makeApplicationBundle(name: String, bundleIdentifier: String) throws -> URL {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let applicationURL = temporaryDirectory.appendingPathComponent("\(name).app", isDirectory: true)
        let contentsURL = applicationURL.appendingPathComponent("Contents", isDirectory: true)
        let infoPlistURL = contentsURL.appendingPathComponent("Info.plist", isDirectory: false)

        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        let infoPlist: [String: Any] = [
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundlePackageType": "APPL",
            "CFBundleName": name,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: infoPlist, format: .xml, options: 0)
        try data.write(to: infoPlistURL)

        addTeardownBlock {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        return applicationURL
    }
}

private final class ApplicationIconResolverSpy: ApplicationIconResolving {
    var applicationURLsByBundleID: [String: URL] = [:]
    var imagesByPath: [String: NSImage] = [:]

    private(set) var applicationURLRequests: [String] = []
    private(set) var iconRequests: [String] = []

    func applicationURL(forBundleIdentifier bundleID: String) -> URL? {
        applicationURLRequests.append(bundleID)
        return applicationURLsByBundleID[bundleID]
    }

    func icon(forFilePath path: String) -> NSImage {
        iconRequests.append(path)
        return imagesByPath[path] ?? NSImage(size: NSSize(width: 8, height: 8))
    }
}
