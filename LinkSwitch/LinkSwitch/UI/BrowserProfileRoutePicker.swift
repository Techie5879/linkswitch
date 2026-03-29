import Foundation

/// Shared mode for which kind of browser identity LinkSwitch lists as selectable cards
/// (Helium Chromium profiles, Firefox-family profiles, or Zen containers).
enum BrowserProfileRouteSelectionMode: Equatable {
    case none
    case heliumProfile
    case fallbackFirefoxProfile
    case fallbackZenContainer

    /// Rule row: depends on target kind and the configured fallback browser.
    static func mode(
        targetKind: PreferencesRuleTargetKind,
        fallbackBrowserBundleID: String
    ) -> BrowserProfileRouteSelectionMode {
        switch targetKind {
        case .helium:
            return .heliumProfile
        case .fallbackBrowser:
            return mode(forFallbackBrowserBundleID: fallbackBrowserBundleID)
        }
    }

    /// Default fallback browser card: only the fallback browser bundle ID matters.
    static func mode(forFallbackBrowserBundleID bundleID: String) -> BrowserProfileRouteSelectionMode {
        if bundleID == FirefoxBrowserAppSupportPath.zenBrowserBundleID {
            return .fallbackZenContainer
        }
        if FirefoxBrowserAppSupportPath.supportsFallbackProfileRouting(forBundleID: bundleID) {
            return .fallbackFirefoxProfile
        }
        return .none
    }

    var sectionTitle: String {
        switch self {
        case .fallbackZenContainer:
            return "Container"
        case .none, .heliumProfile, .fallbackFirefoxProfile:
            return "Profile"
        }
    }

    var emptyMessage: String {
        switch self {
        case .heliumProfile, .fallbackFirefoxProfile:
            return "No profiles were found."
        case .fallbackZenContainer:
            return "No containers were found."
        case .none:
            return ""
        }
    }

    var readFailurePrefix: String {
        switch self {
        case .heliumProfile, .fallbackFirefoxProfile:
            return "Could not read profiles"
        case .fallbackZenContainer:
            return "Could not read containers"
        case .none:
            return "Could not read options"
        }
    }

    var includesBrowserDefaultCard: Bool {
        switch self {
        case .fallbackFirefoxProfile, .fallbackZenContainer:
            return true
        case .none, .heliumProfile:
            return false
        }
    }

    /// The empty key selects the plain browser open path (no profile/container targeting).
    static func browserDefaultCard() -> BrowserProfile {
        BrowserProfile(profileKey: "", displayName: "Browser Default")
    }
}

/// Result of loading options for profile/container cards in preferences.
struct BrowserProfileCardLoadResult {
    let displayedProfiles: [BrowserProfile]
    let errorMessage: String?
    /// Short label for logging (e.g. "fallback browser profile row", "default fallback browser card").
    let logContext: String
}

enum BrowserProfileRoutePicker {
    /// Loads discoverable profile/container options for the given mode. Mirrors the logic
    /// previously embedded in `PreferencesRuleRowView.refreshProfileCards()`.
    static func loadProfileCards(
        mode: BrowserProfileRouteSelectionMode,
        fallbackBrowserBundleID: String
    ) -> BrowserProfileCardLoadResult {
        let logContext: String
        switch mode {
        case .none:
            return BrowserProfileCardLoadResult(displayedProfiles: [], errorMessage: nil, logContext: "none")
        case .heliumProfile:
            logContext = "Helium profile row"
            let factory = BrowserProfileDiscoveryFactory()
            guard let discoverer = factory.makeDiscoverer(forBundleID: BrowserLauncher.heliumBundleID) else {
                AppLogger.error(
                    "No profile discoverer available for Helium (\(BrowserLauncher.heliumBundleID))",
                    category: .app
                )
                return BrowserProfileCardLoadResult(
                    displayedProfiles: [],
                    errorMessage: "Profile discovery is not available for this browser.",
                    logContext: logContext
                )
            }
            do {
                let options = try discoverer.discoverProfiles()
                return finishLoad(mode: mode, discoveredOptions: options, logContext: logContext)
            } catch {
                AppLogger.error("\(logContext) discovery failed: \(error)", category: .app)
                return BrowserProfileCardLoadResult(
                    displayedProfiles: [],
                    errorMessage: "\(mode.readFailurePrefix): \(error.localizedDescription)",
                    logContext: logContext
                )
            }
        case .fallbackFirefoxProfile:
            logContext = "Firefox-family fallback profile row"
            let factory = BrowserProfileDiscoveryFactory()
            guard let discoverer = factory.makeDiscoverer(forBundleID: fallbackBrowserBundleID) else {
                AppLogger.error(
                    "No Firefox-family discoverer available for fallback bundle ID \(fallbackBrowserBundleID)",
                    category: .app
                )
                return BrowserProfileCardLoadResult(
                    displayedProfiles: [BrowserProfileRouteSelectionMode.browserDefaultCard()],
                    errorMessage: "Profile discovery is not available for this browser.",
                    logContext: logContext
                )
            }
            do {
                let options = try discoverer.discoverProfiles()
                return finishLoad(mode: mode, discoveredOptions: options, logContext: logContext)
            } catch {
                AppLogger.error("\(logContext) discovery failed: \(error)", category: .app)
                let displayed = mode.includesBrowserDefaultCard
                    ? [BrowserProfileRouteSelectionMode.browserDefaultCard()]
                    : []
                return BrowserProfileCardLoadResult(
                    displayedProfiles: displayed,
                    errorMessage: "\(mode.readFailurePrefix): \(error.localizedDescription)",
                    logContext: logContext
                )
            }
        case .fallbackZenContainer:
            logContext = "Zen container fallback row"
            do {
                let options = try ZenContainerDiscovery().discoverProfiles()
                return finishLoad(mode: mode, discoveredOptions: options, logContext: logContext)
            } catch {
                AppLogger.error("\(logContext) discovery failed: \(error)", category: .app)
                let displayed = mode.includesBrowserDefaultCard
                    ? [BrowserProfileRouteSelectionMode.browserDefaultCard()]
                    : []
                return BrowserProfileCardLoadResult(
                    displayedProfiles: displayed,
                    errorMessage: "\(mode.readFailurePrefix): \(error.localizedDescription)",
                    logContext: logContext
                )
            }
        }
    }

    private static func finishLoad(
        mode: BrowserProfileRouteSelectionMode,
        discoveredOptions: [BrowserProfile],
        logContext: String
    ) -> BrowserProfileCardLoadResult {
        let displayedProfiles = mode.includesBrowserDefaultCard
            ? [BrowserProfileRouteSelectionMode.browserDefaultCard()] + discoveredOptions
            : discoveredOptions

        if discoveredOptions.isEmpty {
            AppLogger.info("\(logContext): no discoverable options found for mode \(String(describing: mode))", category: .app)
            return BrowserProfileCardLoadResult(
                displayedProfiles: displayedProfiles,
                errorMessage: mode.emptyMessage,
                logContext: logContext
            )
        }

        return BrowserProfileCardLoadResult(
            displayedProfiles: displayedProfiles,
            errorMessage: nil,
            logContext: logContext
        )
    }
}
