import Foundation

enum HeliumLaunchArgumentsError: Error, Equatable {
    case emptyProfileDirectory
}

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
