import Foundation

enum HeliumLaunchArgumentsError: Error, Equatable {
    case emptyProfileDirectory
}

/// Builds Chromium-style profile launch arguments. The type name is historical:
/// LinkSwitch first added this for Helium, but the same `--profile-directory`
/// argument also works for supported Chromium-family browsers.
struct HeliumLaunchArguments {
    static func make(url: URL, profileDirectory: String) throws -> [String] {
        AppLogger.info(
            "Building Helium launch arguments for URL \(url.absoluteString) and profile directory \(profileDirectory)",
            category: .launch
        )
        let trimmedProfileDirectory = profileDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedProfileDirectory.isEmpty else {
            AppLogger.error("Helium profile directory was empty after trimming", category: .launch)
            throw HeliumLaunchArgumentsError.emptyProfileDirectory
        }

        let arguments = [
            "--profile-directory=\(trimmedProfileDirectory)",
            url.absoluteString,
        ]
        AppLogger.info("Built Helium launch arguments: \(arguments)", category: .launch)
        return arguments
    }
}
