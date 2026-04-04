import Foundation

/// Shared mode for which kind of browser identity LinkSwitch lists as selectable cards
/// (Helium Chromium profiles, Firefox-family profiles, or Zen containers).
enum BrowserProfileRouteSelectionMode: Equatable {
    case none
    case heliumProfile
    case defaultHeliumProfile
    case defaultFirefoxProfile
    case defaultZenContainer

    /// Rule row: depends on target kind and the configured default browser.
    static func mode(
        targetKind: PreferencesRuleTargetKind,
        defaultBrowserBundleID: String
    ) -> BrowserProfileRouteSelectionMode {
        switch targetKind {
        case .helium:
            return .heliumProfile
        case .defaultBrowser:
            return mode(forDefaultBrowserBundleID: defaultBrowserBundleID)
        }
    }

    /// Default browser card: only the configured browser bundle ID matters.
    static func mode(forDefaultBrowserBundleID bundleID: String) -> BrowserProfileRouteSelectionMode {
        switch DefaultBrowserProfileSupport.forBundleID(bundleID) {
        case .plainOnly:
            return .none
        case .heliumProfile:
            return .defaultHeliumProfile
        case .firefoxProfile:
            return .defaultFirefoxProfile
        case .zenContainer:
            return .defaultZenContainer
        }
    }

    var sectionTitle: String {
        switch self {
        case .defaultZenContainer:
            return "Container"
        case .none, .heliumProfile, .defaultHeliumProfile, .defaultFirefoxProfile:
            return "Profile"
        }
    }

    var emptyMessage: String {
        switch self {
        case .heliumProfile, .defaultHeliumProfile, .defaultFirefoxProfile:
            return "No profiles were found."
        case .defaultZenContainer:
            return "No containers were found."
        case .none:
            return ""
        }
    }

    var readFailurePrefix: String {
        switch self {
        case .heliumProfile, .defaultHeliumProfile, .defaultFirefoxProfile:
            return "Could not read profiles"
        case .defaultZenContainer:
            return "Could not read containers"
        case .none:
            return "Could not read options"
        }
    }

    var includesBrowserDefaultCard: Bool {
        switch self {
        case .defaultHeliumProfile, .defaultFirefoxProfile, .defaultZenContainer:
            return true
        case .none, .heliumProfile:
            return false
        }
    }

    /// The empty key selects the plain browser open path (no profile/container targeting).
    static func browserDefaultCard(for mode: BrowserProfileRouteSelectionMode) -> BrowserProfile {
        let displayName: String
        switch mode {
        case .defaultZenContainer:
            displayName = "No Container"
        case .defaultHeliumProfile, .defaultFirefoxProfile:
            displayName = "No Profile"
        case .none, .heliumProfile:
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
        defaultBrowserBundleID: String
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
        case .defaultHeliumProfile:
            logContext = "Helium default-browser profile row"
            let factory = BrowserProfileDiscoveryFactory()
            guard let discoverer = factory.makeDiscoverer(forBundleID: defaultBrowserBundleID) else {
                AppLogger.error(
                    "No Helium discoverer available for default-browser bundle ID \(defaultBrowserBundleID)",
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
                return BrowserProfileCardLoadResult(
                    displayedProfiles: [BrowserProfileRouteSelectionMode.browserDefaultCard(for: mode)],
                    errorMessage: "\(mode.readFailurePrefix): \(error.localizedDescription)",
                    logContext: logContext
                )
            }
        case .defaultFirefoxProfile:
            logContext = "Firefox-family default-browser profile row"
            let factory = BrowserProfileDiscoveryFactory()
            guard let discoverer = factory.makeDiscoverer(forBundleID: defaultBrowserBundleID) else {
                AppLogger.error(
                    "No Firefox-family discoverer available for default-browser bundle ID \(defaultBrowserBundleID)",
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
        case .defaultZenContainer:
            logContext = "Zen container default-browser row"
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
