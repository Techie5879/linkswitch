import XCTest
@testable import LinkSwitch

@MainActor
final class NSWorkspaceLauncherTests: XCTestCase {
    func testLaunchApplicationExecutableRunsBundleExecutableAndActivatesProcess() async throws {
        let applicationURL = URL(fileURLWithPath: "/Applications/Helium.app")
        let processRunner = ProcessRunnerSpy(processIdentifier: 4242)
        let activator = RunningApplicationActivatorSpy()
        let launcher = NSWorkspaceLauncher(
            processRunner: processRunner,
            runningApplicationActivator: activator
        )

        try await launcher.launchApplicationExecutable(
            at: applicationURL,
            arguments: ["--profile-directory=Profile 1", "https://example.com"]
        )

        XCTAssertEqual(processRunner.calls.count, 1)
        XCTAssertEqual(processRunner.calls.first?.executableURL.path, "/Applications/Helium.app/Contents/MacOS/Helium")
        XCTAssertEqual(processRunner.calls.first?.arguments, ["--profile-directory=Profile 1", "https://example.com"])
        XCTAssertEqual(activator.activatedBundleIdentifiers, ["net.imput.helium"])
    }
}

private final class ProcessRunnerSpy: ProcessRunning {
    struct Call: Equatable {
        let executableURL: URL
        let arguments: [String]
    }

    private(set) var calls: [Call] = []
    private let processIdentifier: pid_t

    init(processIdentifier: pid_t) {
        self.processIdentifier = processIdentifier
    }

    func run(executableURL: URL, arguments: [String]) throws -> pid_t {
        calls.append(Call(executableURL: executableURL, arguments: arguments))
        return processIdentifier
    }
}

private final class RunningApplicationActivatorSpy: RunningApplicationActivating {
    private(set) var activatedBundleIdentifiers: [String] = []

    func activate(bundleIdentifier: String) async throws {
        activatedBundleIdentifiers.append(bundleIdentifier)
    }
}
