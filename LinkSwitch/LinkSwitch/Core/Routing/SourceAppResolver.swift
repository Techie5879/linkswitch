import AppKit
import Carbon
import Foundation

protocol AppleEventDescriptorReading {
    func attributeDescriptor(forKeyword keyword: AEKeyword) -> NSAppleEventDescriptor?
}

protocol CurrentAppleEventProviding {
    var currentAppleEvent: (any AppleEventDescriptorReading)? { get }
}

protocol SenderPIDProviding {
    func senderPID() -> pid_t?
}

protocol SourceBundleIDResolving {
    func resolveSourceBundleID() -> String?
}

protocol RunningApplicationBundleIDResolving {
    func bundleIdentifier(for processIdentifier: pid_t) -> String?
}

struct SourceAppResolver {
    private let senderPIDProvider: any SenderPIDProviding
    private let bundleIDResolver: any RunningApplicationBundleIDResolving

    init(
        senderPIDProvider: any SenderPIDProviding = AppleEventSenderPIDProvider(),
        bundleIDResolver: any RunningApplicationBundleIDResolving = RunningApplicationBundleIDResolver()
    ) {
        self.senderPIDProvider = senderPIDProvider
        self.bundleIDResolver = bundleIDResolver
    }

    func resolveSourceBundleID() -> String? {
        guard let senderPID = senderPIDProvider.senderPID() else {
            AppLogger.info("No sender PID was available for the current URL open Apple Event", category: .routing)
            return nil
        }

        AppLogger.info("Resolved sender PID \(senderPID) for current URL open Apple Event", category: .routing)
        guard let bundleID = bundleIDResolver.bundleIdentifier(for: senderPID) else {
            AppLogger.info("No running application bundle ID was found for sender PID \(senderPID)", category: .routing)
            return nil
        }

        AppLogger.info("Resolved source bundle ID \(bundleID) for sender PID \(senderPID)", category: .routing)
        return bundleID
    }
}

extension SourceAppResolver: SourceBundleIDResolving {}

struct AppleEventSenderPIDProvider: SenderPIDProviding {
    private let currentAppleEventProvider: any CurrentAppleEventProviding

    init(currentAppleEventProvider: any CurrentAppleEventProviding = NSAppleEventManagerCurrentEventProvider()) {
        self.currentAppleEventProvider = currentAppleEventProvider
    }

    func senderPID() -> pid_t? {
        guard let currentAppleEvent = currentAppleEventProvider.currentAppleEvent else {
            AppLogger.info("NSAppleEventManager did not expose a current Apple Event", category: .routing)
            return nil
        }

        guard let senderPIDDescriptor = currentAppleEvent.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr)) else {
            AppLogger.info("Current Apple Event did not include a sender PID attribute", category: .routing)
            return nil
        }

        let senderPID = pid_t(senderPIDDescriptor.int32Value)
        guard senderPID > 0 else {
            AppLogger.info("Current Apple Event exposed a non-positive sender PID \(senderPID)", category: .routing)
            return nil
        }

        return senderPID
    }
}

struct RunningApplicationBundleIDResolver: RunningApplicationBundleIDResolving {
    func bundleIdentifier(for processIdentifier: pid_t) -> String? {
        NSRunningApplication(processIdentifier: processIdentifier)?.bundleIdentifier
    }
}

struct NSAppleEventManagerCurrentEventProvider: CurrentAppleEventProviding {
    var currentAppleEvent: (any AppleEventDescriptorReading)? {
        NSAppleEventManager.shared().currentAppleEvent
    }
}

extension NSAppleEventDescriptor: AppleEventDescriptorReading {}
