---
name: Default browser route sharing
overview: Add a `DefaultBrowserRoute` to `RouterConfig` so the default browser supports the same profile/container targeting that source-app rules already support, and extract shared profile-card logic so the default browser card and rule rows use the same discovery + selection code.
todos:
  - id: config-route
    content: "Add `defaultBrowserRoute: DefaultBrowserRoute` to `RouterConfig` and add `DefaultBrowserRoute.browserTarget` computed property"
    status: completed
  - id: rule-engine
    content: Update `RuleEngine` to return `config.defaultBrowserRoute.browserTarget` instead of hardcoded `.defaultBrowser`
    status: completed
  - id: prefs-model
    content: "Update `PreferencesModel`: add default-browser route property, wire load/save/test/normalize"
    status: completed
  - id: extract-cards
    content: Extract shared profile/container card discovery + rendering helper from `PreferencesRuleRowView`
    status: completed
  - id: default-browser-card-ui
    content: Add profile/container card selection to the default browser card in `PreferencesWindowController`
    status: completed
  - id: tests
    content: "Update all tests: RouterConfigCoding, RuleEngine, PreferencesModel, RoutingPipelineIntegration"
    status: completed
  - id: docs
    content: Add doc comments to BrowserProfile and ZenContainerDiscovery; update implementation-log.md
    status: completed
isProject: false
---

# Default Browser Route Sharing

## Problem

`RouterConfig` stores `defaultBrowserBundleID` + `defaultBrowserAppURL` + `defaultBrowserRoute`. Firefox-profile, Zen-container, and Helium-profile routing for unmatched links must follow the configured `defaultBrowserRoute`, not only plain opens.

## Data layer

### `defaultBrowserRoute` on `RouterConfig`

In [RouterConfig.swift](LinkSwitch/LinkSwitch/Core/Config/RouterConfig.swift):

```swift
struct RouterConfig: Codable, Equatable {
    var defaultBrowserBundleID: String
    var defaultBrowserAppURL: URL
    var defaultBrowserRoute: DefaultBrowserRoute
    var rules: [SourceAppRule]
}
```

`DefaultBrowserRoute` includes `.plain`, `.heliumProfile`, `.firefoxProfile`, `.zenContainer`.

### `BrowserTarget` conversion on `DefaultBrowserRoute`

```swift
extension DefaultBrowserRoute {
    var browserTarget: BrowserTarget {
        switch self {
        case .plain:
            return .defaultBrowser
        case let .heliumProfile(profileDirectory):
            return .defaultBrowserHeliumProfile(profileDirectory: profileDirectory)
        case let .firefoxProfile(profileKey):
            return .defaultBrowserFirefoxProfile(profileKey: profileKey)
        case let .zenContainer(containerName):
            return .defaultBrowserZenContainer(containerName: containerName)
        }
    }
}
```

## Routing layer

### Update `RuleEngine` to use the default-browser route

In [RuleEngine.swift](LinkSwitch/LinkSwitch/Core/Routing/RuleEngine.swift), no-match / nil-sender paths use:

```swift
return config.defaultBrowserRoute.browserTarget
```

## Preferences model layer

### Update `PreferencesModel`

In [PreferencesModel.swift](LinkSwitch/LinkSwitch/UI/PreferencesModel.swift):

- `var defaultBrowserRoute: DefaultBrowserRoute`
- `load()`: read the route from the loaded config.
- `makeRouterConfig()`: include the route in the built config.
- `testDefaultBrowser()`: use `defaultBrowserRoute.browserTarget`.
- `normalizeDefaultBrowserRuleTargetsForCurrentBrowser()`: also normalize `defaultBrowserRoute` when the selected browser changes (e.g. Zen to Safari clears `.zenContainer`).
- `makeTarget(for:)`: map drafts using `DefaultBrowserRoute` / `BrowserTarget` consistently.

## UI layer

### Extract shared profile/container card logic

In [PreferencesWindowController.swift](LinkSwitch/LinkSwitch/UI/PreferencesWindowController.swift), shared discovery and card rendering is used from `BrowserProfileRoutePicker` for both rule rows and the default browser card.

### Profile/container cards on the default browser card

- Show cards when the selected default browser supports profiles/containers.
- Include a synthetic plain-route card for the `.plain` route.
- Update `model.defaultBrowserRoute` when a card is selected.
- Refresh when the default browser selection changes.

### Test default browser button

Calls `model.testDefaultBrowser()` so the configured route is exercised.

## Tests

### `RouterConfigCodingTests`

- Round-trip tests include `defaultBrowserRoute`.
- Decoding fails when `defaultBrowserRoute` is absent from JSON.

### `RuleEngineTests`

- Nil / unknown source verifies `config.defaultBrowserRoute.browserTarget` for plain and non-plain routes.

### `PreferencesModelTests`

- `load()` / `save()` round-trip the default-browser route.
- `testDefaultBrowser()` uses the configured route.
- Changing the default browser normalizes the default-browser route.

### `RoutingPipelineIntegrationTests`

- Unknown-source opens use the saved `defaultBrowserRoute` in the expected `BrowserTarget` and config.

### `BrowserLauncherTests`

- Covers `BrowserTarget` cases used for default-browser opens.

## Documentation

### `BrowserProfile` terminology

Profile in LinkSwitch means the browser-native identity a link is routed to (Chromium profiles, Firefox profiles, Zen containers).

### Zen container discovery

Zen container discovery stays separate from `BrowserProfileDiscoveryFactory` because containers are the primary user-facing identity in Zen.

### `docs/implementation-log.md`

Records default-browser route sharing and JSON requirements.
