import Foundation

enum FirefoxLaunchArgumentsError: Error, Equatable {
    case unsupportedBrowser(bundleID: String)
    case unresolvedProfilePath(bundleID: String, profileKey: String)
    case profilePathNotFound(URL)
}

struct FirefoxLaunchArguments {
    static func make(
        url: URL,
        profileKey: String,
        browserBundleID: String,
        appSupportURL: URL,
        homeDirectoryURL: URL
    ) throws -> [String] {
        AppLogger.info(
            "Building Firefox-family launch arguments for bundle ID \(browserBundleID), profile key \(profileKey), and URL \(url.absoluteString)",
            category: .launch
        )

        guard FirefoxBrowserAppSupportPath.supportsFallbackProfileRouting(forBundleID: browserBundleID) else {
            AppLogger.error(
                "FirefoxLaunchArguments does not support bundle ID \(browserBundleID)",
                category: .launch
            )
            throw FirefoxLaunchArgumentsError.unsupportedBrowser(bundleID: browserBundleID)
        }

        guard let absoluteProfileURL = FirefoxBrowserAppSupportPath.absoluteProfileURL(
            forBundleID: browserBundleID,
            profileKey: profileKey,
            appSupportURL: appSupportURL,
            homeDirectoryURL: homeDirectoryURL
        ) else {
            AppLogger.error(
                "FirefoxLaunchArguments could not resolve profile key \(profileKey) for bundle ID \(browserBundleID)",
                category: .launch
            )
            throw FirefoxLaunchArgumentsError.unresolvedProfilePath(bundleID: browserBundleID, profileKey: profileKey)
        }

        guard FileManager.default.fileExists(atPath: absoluteProfileURL.path(percentEncoded: false)) else {
            AppLogger.error(
                "FirefoxLaunchArguments profile directory not found at \(absoluteProfileURL.path(percentEncoded: false))",
                category: .launch
            )
            throw FirefoxLaunchArgumentsError.profilePathNotFound(absoluteProfileURL)
        }

        let arguments = [
            "-new-instance",
            "-profile",
            absoluteProfileURL.path(percentEncoded: false),
            url.absoluteString,
        ]

        AppLogger.info(
            "FirefoxLaunchArguments resolved arguments \(arguments)",
            category: .launch
        )
        return arguments
    }
}
