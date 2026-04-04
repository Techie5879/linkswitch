import Foundation

/// Shared mode for which kind of browser identity LinkSwitch lists as selectable cards
/// (Helium Chromium profiles, Firefox-family profiles, or Zen containers).
enum BrowserProfileRouteSelectionMode: Equatable {
    case none
    case browserHeliumProfile
    case defaultHeliumProfile
    case browserFirefoxProfile
    case defaultFirefoxProfile
    case browserZenContainer
    case defaultZenContainer

    /// Rule row: depends on target kind and the configured default browser.
    static func mode(
        targetSelection: PreferencesRuleTargetSelection,
        defaultBrowserBundleID: String
    ) -> BrowserProfileRouteSelectionMode {
        switch targetSelection {
        case .defaultBrowser:
            return mode(forDefaultBrowserBundleID: defaultBrowserBundleID)
        case let .browser(bundleID, _):
            return mode(forBrowserBundleID: bundleID)
        }
    }

    /// Default browser card: only the configured browser bundle ID matters.
    static func mode(forDefaultBrowserBundleID bundleID: String) -> BrowserProfileRouteSelectionMode {
        switch mode(forBrowserBundleID: bundleID) {
        case .browserHeliumProfile:
            return .defaultHeliumProfile
        case .browserFirefoxProfile:
            return .defaultFirefoxProfile
        case .browserZenContainer:
            return .defaultZenContainer
        case .none, .defaultHeliumProfile, .defaultFirefoxProfile, .defaultZenContainer:
            return .none
        }
    }

    static func mode(forBrowserBundleID bundleID: String) -> BrowserProfileRouteSelectionMode {
        switch DefaultBrowserProfileSupport.forBundleID(bundleID) {
        case .plainOnly:
            return .none
        case .heliumProfile:
            return .browserHeliumProfile
        case .firefoxProfile:
            return .browserFirefoxProfile
        case .zenContainer:
            return .browserZenContainer
        }
    }

    var sectionTitle: String {
        switch self {
        case .browserZenContainer, .defaultZenContainer:
            return "Container"
        case .none, .browserHeliumProfile, .defaultHeliumProfile, .browserFirefoxProfile, .defaultFirefoxProfile:
            return "Profile"
        }
    }

    var emptyMessage: String {
        switch self {
        case .browserHeliumProfile, .defaultHeliumProfile, .browserFirefoxProfile, .defaultFirefoxProfile:
            return "No profiles were found."
        case .browserZenContainer, .defaultZenContainer:
            return "No containers were found."
        case .none:
            return ""
        }
    }

    var readFailurePrefix: String {
        switch self {
        case .browserHeliumProfile, .defaultHeliumProfile, .browserFirefoxProfile, .defaultFirefoxProfile:
            return "Could not read profiles"
        case .browserZenContainer, .defaultZenContainer:
            return "Could not read containers"
        case .none:
            return "Could not read options"
        }
    }

    var includesBrowserDefaultCard: Bool {
        switch self {
        case .browserHeliumProfile, .defaultHeliumProfile, .browserFirefoxProfile, .defaultFirefoxProfile, .browserZenContainer, .defaultZenContainer:
            return true
        case .none:
            return false
        }
    }

    /// The empty key selects the plain browser open path (no profile/container targeting).
    static func browserDefaultCard(for mode: BrowserProfileRouteSelectionMode) -> BrowserProfile {
        let displayName: String
        switch mode {
        case .browserZenContainer, .defaultZenContainer:
            displayName = "No Container"
        case .browserHeliumProfile, .defaultHeliumProfile, .browserFirefoxProfile, .defaultFirefoxProfile:
            displayName = "No Profile"
        case .none:
            displayName = "Default Browser"
        }

        return BrowserProfile(profileKey: "", displayName: displayName)
    }
}

/// Result of loading options for profile/container cards in preferences.
struct BrowserProfileCardLoadResult {
    let displayedProfiles: [BrowserProfile]
    let errorMessage: String?
    /// Short label for logging (e.g. "default browser profile row", "default browser card").
    let logContext: String
}

enum BrowserProfileRoutePicker {
    /// Loads discoverable profile/container options for the given mode. Mirrors the logic
    /// previously embedded in `PreferencesRuleRowView.refreshProfileCards()`.
    static func loadProfileCards(
        mode: BrowserProfileRouteSelectionMode,
        browserBundleID: String
    ) -> BrowserProfileCardLoadResult {
        let logContext: String
        switch mode {
        case .none:
            return BrowserProfileCardLoadResult(displayedProfiles: [], errorMessage: nil, logContext: "none")
        case .browserHeliumProfile, .defaultHeliumProfile:
            logContext = mode == .defaultHeliumProfile ? "Chromium default-browser profile row" : "Chromium browser rule profile row"
            let factory = BrowserProfileDiscoveryFactory()
            guard let discoverer = factory.makeDiscoverer(forBundleID: browserBundleID) else {
                AppLogger.error(
                    "No Chromium discoverer available for bundle ID \(browserBundleID)",
                    category: .app
                )
                return BrowserProfileCardLoadResult(
                    displayedProfiles: mode.includesBrowserDefaultCard ? [BrowserProfileRouteSelectionMode.browserDefaultCard(for: mode)] : [],
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
                    ? [BrowserProfileRouteSelectionMode.browserDefaultCard(for: mode)]
                    : []
                return BrowserProfileCardLoadResult(
                    displayedProfiles: displayed,
                    errorMessage: "\(mode.readFailurePrefix): \(error.localizedDescription)",
                    logContext: logContext
                )
            }
        case .browserFirefoxProfile, .defaultFirefoxProfile:
            logContext = mode == .defaultFirefoxProfile
                ? "Firefox-family default-browser profile row"
                : "Firefox-family browser rule profile row"
            let factory = BrowserProfileDiscoveryFactory()
            guard let discoverer = factory.makeDiscoverer(forBundleID: browserBundleID) else {
                AppLogger.error(
                    "No Firefox-family discoverer available for bundle ID \(browserBundleID)",
                    category: .app
                )
                return BrowserProfileCardLoadResult(
                    displayedProfiles: [BrowserProfileRouteSelectionMode.browserDefaultCard(for: mode)],
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
                    ? [BrowserProfileRouteSelectionMode.browserDefaultCard(for: mode)]
                    : []
                return BrowserProfileCardLoadResult(
                    displayedProfiles: displayed,
                    errorMessage: "\(mode.readFailurePrefix): \(error.localizedDescription)",
                    logContext: logContext
                )
            }
        case .browserZenContainer, .defaultZenContainer:
            logContext = mode == .defaultZenContainer
                ? "Zen container default-browser row"
                : "Zen container browser rule row"
            do {
                let options = try ZenContainerDiscovery().discoverProfiles()
                return finishLoad(mode: mode, discoveredOptions: options, logContext: logContext)
            } catch {
                AppLogger.error("\(logContext) discovery failed: \(error)", category: .app)
                let displayed = mode.includesBrowserDefaultCard
                    ? [BrowserProfileRouteSelectionMode.browserDefaultCard(for: mode)]
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
            ? [BrowserProfileRouteSelectionMode.browserDefaultCard(for: mode)] + discoveredOptions
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
