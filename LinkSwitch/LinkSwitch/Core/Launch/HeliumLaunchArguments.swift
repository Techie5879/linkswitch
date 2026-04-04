import Foundation

enum ChromiumLaunchArgumentsError: Error, Equatable {
    case emptyProfileDirectory
}

/// Builds Chromium-style profile launch arguments for browsers that accept
/// `--profile-directory=<name>`.
struct ChromiumLaunchArguments {
    static func make(url: URL, profileDirectory: String) throws -> [String] {
        AppLogger.info(
            "Building Chromium launch arguments for URL \(url.absoluteString) and profile directory \(profileDirectory)",
            category: .launch
        )
        let trimmedProfileDirectory = profileDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedProfileDirectory.isEmpty else {
            AppLogger.error("Chromium profile directory was empty after trimming", category: .launch)
            throw ChromiumLaunchArgumentsError.emptyProfileDirectory
        }

        let arguments = [
            "--profile-directory=\(trimmedProfileDirectory)",
            url.absoluteString,
        ]
        AppLogger.info("Built Chromium launch arguments: \(arguments)", category: .launch)
        return arguments
    }
}
