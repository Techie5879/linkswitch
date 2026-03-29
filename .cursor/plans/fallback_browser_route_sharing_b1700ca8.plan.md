---
name: Fallback browser route sharing
overview: Add a `FallbackBrowserRoute` to `RouterConfig` so the fallback browser supports the same profile/container targeting that source-app rules already support, and extract shared profile-card logic so the fallback browser card and rule rows use the same discovery + selection code.
todos:
  - id: config-route
    content: "Add `fallbackBrowserRoute: FallbackBrowserRoute` to `RouterConfig` and add `FallbackBrowserRoute.browserTarget` computed property"
    status: completed
  - id: rule-engine
    content: Update `RuleEngine` to return `config.fallbackBrowserRoute.browserTarget` instead of hardcoded `.fallbackBrowser`
    status: completed
  - id: prefs-model
    content: "Update `PreferencesModel`: add fallback route property, wire load/save/test/normalize"
    status: completed
  - id: extract-cards
    content: Extract shared profile/container card discovery + rendering helper from `PreferencesRuleRowView`
    status: completed
  - id: fallback-card-ui
    content: Add profile/container card selection to the fallback browser card in `PreferencesWindowController`
    status: completed
  - id: tests
    content: "Update all tests: RouterConfigCoding, RuleEngine, PreferencesModel, RoutingPipelineIntegration"
    status: completed
  - id: docs
    content: Add doc comments to BrowserProfile and ZenContainerDiscovery; update implementation-log.md
    status: completed
isProject: false
---

# Fallback Browser Route Sharing

## Problem

`RouterConfig` stores only `fallbackBrowserBundleID` + `fallbackBrowserAppURL`. Firefox-profile and Zen-container routing only works through explicit source-app rules. Unmatched links always get `.fallbackBrowser` (plain open). The fallback browser should support the same profile/container selection that rules already have.

## Data layer

### Add `fallbackBrowserRoute` to `RouterConfig`

In [RouterConfig.swift](LinkSwitch/LinkSwitch/Core/Config/RouterConfig.swift), add the route field:

```swift
struct RouterConfig: Codable, Equatable {
    var fallbackBrowserBundleID: String
    var fallbackBrowserAppURL: URL
    var fallbackBrowserRoute: FallbackBrowserRoute
    var rules: [SourceAppRule]
}
```

`FallbackBrowserRoute` already exists with `.plain`, `.firefoxProfile(profileKey:)`, `.zenContainer(containerName:)`.

### Add `BrowserTarget` conversion on `FallbackBrowserRoute`

Add a computed property to centralize the `FallbackBrowserRoute -> BrowserTarget` conversion (currently duplicated in `PreferencesModel.makeTarget` and will be needed in `RuleEngine`):

```swift
extension FallbackBrowserRoute {
    var browserTarget: BrowserTarget {
        switch self {
        case .plain:
            return .fallbackBrowser
        case let .firefoxProfile(profileKey):
            return .fallbackBrowserFirefoxProfile(profileKey: profileKey)
        case let .zenContainer(containerName):
            return .fallbackBrowserZenContainer(containerName: containerName)
        }
    }
}
```

## Routing layer

### Update `RuleEngine` to use the fallback route

In [RuleEngine.swift](LinkSwitch/LinkSwitch/Core/Routing/RuleEngine.swift), both fallback returns currently hardcode `.fallbackBrowser`. Change them to use the config's route:

```swift
return config.fallbackBrowserRoute.browserTarget
```

This is the single change that makes profile/container routing work for all unmatched links.

## Preferences model layer

### Update `PreferencesModel`

In [PreferencesModel.swift](LinkSwitch/LinkSwitch/UI/PreferencesModel.swift):

- Add a `var fallbackBrowserRoute: FallbackBrowserRoute = .plain` property.
- `load()`: read the route from the loaded config.
- `makeRouterConfig()`: include the route in the built config.
- `testFallbackBrowser()`: use `fallbackBrowserRoute.browserTarget` instead of hardcoded `.fallbackBrowser`.
- `normalizeFallbackRuleTargetsForCurrentBrowser()`: also normalize `fallbackBrowserRoute` itself (e.g. switching from Zen to Firefox should reset a stale `.zenContainer` route to `.plain`).
- `makeTarget(for:)`: use the `FallbackBrowserRoute.browserTarget` computed property instead of duplicating the switch.

## UI layer

### Extract shared profile/container card logic

In [PreferencesWindowController.swift](LinkSwitch/LinkSwitch/UI/PreferencesWindowController.swift), the profile discovery + card rendering logic in `PreferencesRuleRowView` (lines ~1450-1525) needs to be reusable. Extract a helper that:

- Takes a browser bundle ID and current selection key.
- Determines the route selection mode (Firefox profile, Zen container, or none) -- the logic currently in `routeSelectionMode()`.
- Runs discovery via `BrowserProfileDiscoveryFactory` (or `ZenContainerDiscovery` for Zen).
- Prepends a "Browser Default" card when appropriate.
- Returns the discovered profiles and any error message.

Both `PreferencesRuleRowView.refreshProfileCards()` and the new fallback card code call this shared helper.

### Add profile/container cards to the fallback browser card

In the `makeFallbackBrowserCard()` method (line ~289), add a profile/container cards section below the browser popup. It should:

- Show profile cards when the selected fallback browser supports profiles/containers (Firefox-family or Zen).
- Include a "Browser Default" card for the `.plain` route.
- Update `model.fallbackBrowserRoute` when a card is selected.
- Be hidden when the fallback browser has no profile/container support.
- Refresh when the fallback browser selection changes (already triggered by `refreshUI()`).

### Update `testFallbackBrowser` button

The test button already calls `model.testFallbackBrowser()`. Once the model change is in place, this will automatically use the selected route. No UI change needed here.

## Tests

### `RouterConfigCodingTests`

- Update existing round-trip tests to include `fallbackBrowserRoute` in the config.
- Add a test that round-trips a config with a non-plain fallback route.

### `RuleEngineTests`

- `testNilSourceBundleIDReturnsFallbackBrowser` and `testUnknownSourceBundleIDReturnsFallbackBrowser`: update to verify the engine returns the config's `fallbackBrowserRoute.browserTarget`, not hardcoded `.fallbackBrowser`.
- Add tests with `.firefoxProfile` and `.zenContainer` fallback routes.

### `PreferencesModelTests`

- Test that `load()` populates `fallbackBrowserRoute` from stored config.
- Test that `save()` persists the fallback route.
- Test that `testFallbackBrowser()` uses the configured route.
- Test that changing the fallback browser normalizes the fallback route.

### `RoutingPipelineIntegrationTests`

- Update `testSavedPreferencesConfigRoutesUnknownSourceToFallbackBrowser` to include the fallback route in the expected config.
- Add an integration test where the fallback route is non-plain and verify the full pipeline uses it.

### `BrowserLauncherTests`

- No changes needed; it already tests all `BrowserTarget` cases.

## Documentation

### `BrowserProfile` terminology

Add a brief note to [BrowserProfile.swift](LinkSwitch/LinkSwitch/Core/Discovery/BrowserProfile.swift) doc comment clarifying the design intent: "profile" in LinkSwitch means the browser-native identity a link is routed to, which includes Chromium profiles, Firefox profiles, and Zen containers.

### Zen container discovery as an explicit override

Add a brief note to [ZenContainerDiscovery.swift](LinkSwitch/LinkSwitch/Core/Discovery/ZenContainerDiscovery.swift) explaining that Zen container discovery is intentionally separate from `BrowserProfileDiscoveryFactory` because Zen containers are the primary user-facing identity in Zen, distinct from the underlying Firefox-style profiles that Zen inherits but most users do not interact with.

### Update `docs/implementation-log.md`

Record the fallback-route-sharing change and the documentation decisions.
