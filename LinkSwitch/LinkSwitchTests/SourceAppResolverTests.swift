import Carbon
import XCTest
@testable import LinkSwitch

final class AppleEventSenderPIDProviderTests: XCTestCase {
    func testSenderPIDReturnsNilWhenCurrentAppleEventIsMissing() {
        let provider = AppleEventSenderPIDProvider(
            currentAppleEventProvider: StubCurrentAppleEventProvider(currentAppleEvent: nil)
        )

        XCTAssertNil(provider.senderPID())
    }

    func testSenderPIDReturnsNilWhenSenderPIDAttributeIsMissing() {
        let provider = AppleEventSenderPIDProvider(
            currentAppleEventProvider: StubCurrentAppleEventProvider(
                currentAppleEvent: StubAppleEventDescriptor(attributes: [:])
            )
        )

        XCTAssertNil(provider.senderPID())
    }

    func testSenderPIDReturnsPIDFromAppleEventAttribute() {
        let provider = AppleEventSenderPIDProvider(
            currentAppleEventProvider: StubCurrentAppleEventProvider(
                currentAppleEvent: StubAppleEventDescriptor(
                    attributes: [AEKeyword(keySenderPIDAttr): NSAppleEventDescriptor(int32: 4242)]
                )
            )
        )

        XCTAssertEqual(provider.senderPID(), 4242)
    }
}

final class SourceAppResolverTests: XCTestCase {
    func testResolveSourceBundleIDReturnsNilWhenSenderPIDIsUnavailable() {
        let bundleIDResolver = BundleIDResolverSpy()
        let resolver = SourceAppResolver(
            senderPIDProvider: StubSenderPIDProvider(resolvedSenderPID: nil),
            bundleIDResolver: bundleIDResolver
        )

        XCTAssertNil(resolver.resolveSourceBundleID())
        XCTAssertTrue(bundleIDResolver.requestedProcessIdentifiers.isEmpty)
    }

    func testResolveSourceBundleIDReturnsResolvedBundleID() {
        let bundleIDResolver = BundleIDResolverSpy()
        bundleIDResolver.bundleIDsByProcessIdentifier[4242] = "com.tinyspeck.slackmacgap"
        let resolver = SourceAppResolver(
            senderPIDProvider: StubSenderPIDProvider(resolvedSenderPID: 4242),
            bundleIDResolver: bundleIDResolver
        )

        XCTAssertEqual(resolver.resolveSourceBundleID(), "com.tinyspeck.slackmacgap")
        XCTAssertEqual(bundleIDResolver.requestedProcessIdentifiers, [4242])
    }

    func testResolveSourceBundleIDReturnsNilWhenBundleIdentifierCannotBeResolved() {
        let bundleIDResolver = BundleIDResolverSpy()
        let resolver = SourceAppResolver(
            senderPIDProvider: StubSenderPIDProvider(resolvedSenderPID: 4242),
            bundleIDResolver: bundleIDResolver
        )

        XCTAssertNil(resolver.resolveSourceBundleID())
        XCTAssertEqual(bundleIDResolver.requestedProcessIdentifiers, [4242])
    }
}

private struct StubCurrentAppleEventProvider: CurrentAppleEventProviding {
    let currentAppleEvent: (any AppleEventDescriptorReading)?
}

private struct StubAppleEventDescriptor: AppleEventDescriptorReading {
    let attributes: [AEKeyword: NSAppleEventDescriptor]

    func attributeDescriptor(forKeyword keyword: AEKeyword) -> NSAppleEventDescriptor? {
        attributes[keyword]
    }
}

private struct StubSenderPIDProvider: SenderPIDProviding {
    let resolvedSenderPID: pid_t?

    func senderPID() -> pid_t? {
        resolvedSenderPID
    }
}

private final class BundleIDResolverSpy: RunningApplicationBundleIDResolving {
    var bundleIDsByProcessIdentifier: [pid_t: String] = [:]
    private(set) var requestedProcessIdentifiers: [pid_t] = []

    func bundleIdentifier(for processIdentifier: pid_t) -> String? {
        requestedProcessIdentifiers.append(processIdentifier)
        return bundleIDsByProcessIdentifier[processIdentifier]
    }
}
