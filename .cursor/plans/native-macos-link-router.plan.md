---
name: native-macos-link-router
overview: Build a small AppKit macOS URL-handler app that routes links by source app, forwards most links to a user-chosen fallback browser, and supports a Helium Chromium-profile override for work links.
todos:
  - id: bootstrap-appkit-app
    content: Use the existing Xcode-generated macOS AppKit target as the base, then add Info.plist URL-scheme declarations for http/https and a minimal preferences window.
    status: pending
  - id: define-config-model
    content: Define the scoped config model for fallback browser selection and source-app override rules, persisted as JSON or plist.
    status: pending
  - id: launch-services-bridge
    content: Wrap Launch Services and NSWorkspace APIs for reading the current handler, setting the app as the handler, and resolving browser app URLs.
    status: pending
    dependencies:
      - bootstrap-appkit-app
  - id: url-intake-pipeline
    content: Implement URL intake through NSApplicationDelegate and route each incoming URL through a single routing pipeline.
    status: pending
    dependencies:
      - bootstrap-appkit-app
      - define-config-model
  - id: source-app-resolution-spike
    content: Prove and document the supported sender-identification approach for incoming URL opens, including failure behavior when source metadata is unavailable.
    status: pending
    dependencies:
      - url-intake-pipeline
  - id: browser-launch-adapters
    content: Implement browser launch adapters for fallback-browser forwarding and Helium Chromium-profile forwarding.
    status: pending
    dependencies:
      - launch-services-bridge
      - url-intake-pipeline
  - id: rule-engine
    content: Implement the scoped rule engine for source-app bundle ID matching and fallback forwarding.
    status: pending
    dependencies:
      - define-config-model
      - source-app-resolution-spike
      - browser-launch-adapters
  - id: preferences-ui
    content: Build the AppKit preferences UI to choose the fallback browser, define source-app rules, and test launches.
    status: pending
    dependencies:
      - define-config-model
      - launch-services-bridge
      - rule-engine
  - id: automated-test-harness
    content: Add fixture apps and automated tests for routing, sender detection, and Helium profile launch argument generation.
    status: pending
    dependencies:
      - rule-engine
  - id: manual-e2e-verification
    content: Run manual end-to-end verification with Slack-like sender flows and confirm fallback-browser behavior for non-matching apps.
    status: pending
    dependencies:
      - preferences-ui
      - automated-test-harness
isProject: true
---

# Native macOS Link Router Plan

## Scope right now

- Build a small native `AppKit` macOS app that becomes the `http` and `https` handler.
- Route by source app bundle ID only; the first real rule is `Slack -> Helium work profile`.
- Forward all non-matching links to a user-chosen fallback browser, which is intended to be the user's normal browser.
- Keep the project intentionally narrow: no URL/domain routing, no chooser UI, no Firefox/Zen profile support, no Safari profile support.

## Final product

- A lightweight native macOS app with:
  - a minimal preferences window
  - a stored fallback browser target
  - a small list of source-app override rules
  - a Helium adapter that can launch a specific Chromium profile for work links
- Typical behavior:
  - `Slack` opens links in `Helium` with the configured work profile
  - everything else opens in the configured fallback browser

## Source-of-truth paths and assumptions

- Plan file: `.cursor/plans/native-macos-link-router.plan.md`
- Xcode project: `LinkSwitch/LinkSwitch.xcodeproj`
- App target root: `LinkSwitch/LinkSwitch/`
- Unit tests target root: `LinkSwitch/LinkSwitchTests/`
- UI tests target root: `LinkSwitch/LinkSwitchUITests/`
- Keep working from the generated Xcode layout rather than introducing a parallel repo-root source tree.
- Preferred folders inside the app target:
  - `LinkSwitch/LinkSwitch/App/`
  - `LinkSwitch/LinkSwitch/Core/Config/`
  - `LinkSwitch/LinkSwitch/Core/Routing/`
  - `LinkSwitch/LinkSwitch/Core/Launch/`
  - `LinkSwitch/LinkSwitch/UI/`
  - `LinkSwitch/LinkSwitch/Support/`
- Shared router/config types should live in one place inside `Core/Config/` and be imported elsewhere as needed; do not redefine the same types or interfaces near feature code.
- Keep nesting shallow. Add folders only when they buy clarity in Xcode and in the target, not to mirror an abstract architecture diagram.
- Persist user config under the app container or Application Support as a small JSON/plist file.
- Store the fallback browser explicitly; do not rely on asking Launch Services for the default browser after this app becomes the handler.

## Research-backed macOS APIs to use

- Handler registration and lookup:
  - `CFBundleURLTypes`
  - `LSCopyDefaultHandlerForURLScheme(_:)`
  - `NSWorkspace.setDefaultApplication(at:toOpenURLsWithScheme:completion:)`
  - `NSWorkspace.urlForApplication(toOpen:)`
- URL receipt:
  - `NSApplicationDelegate.application(_:open:)`
  - SwiftUI `onOpenURL(perform:)` exists, but the app should stay AppKit-first
- Forwarding to target apps:
  - `NSWorkspace.open(_:)`
  - `NSWorkspace.open(_:withApplicationAt:configuration:completionHandler:)`
- Browser profile handling:
  - no macOS API exists; Helium support is browser-specific and should be implemented as a Chromium-style launch adapter

## Key Apple docs and references

- `https://developer.apple.com/documentation/coreservices/1441725-lscopydefaulthandlerforurlscheme`
- `https://developer.apple.com/documentation/appkit/nsworkspace/setdefaultapplication(at:toopenurlswithscheme:completion:)`
- `https://developer.apple.com/documentation/appkit/nsworkspace/urlforapplication(toopen:)-7qkzf`
- `https://developer.apple.com/documentation/appkit/nsapplicationdelegate/application(_:open:)`
- `https://developer.apple.com/documentation/appkit/nsworkspace/open(_:withapplicationat:configuration:completionhandler:)`
- `https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleurltypes`
- `https://developer.apple.com/library/archive/documentation/Carbon/Conceptual/LaunchServicesConcepts/LSCConcepts/LSCConcepts.html`

## Data model and interfaces

```swift
struct RouterConfig: Codable {
    var fallbackBrowserBundleID: String
    var fallbackBrowserAppURL: URL
    var rules: [SourceAppRule]
}

struct SourceAppRule: Codable, Identifiable {
    var id: UUID
    var sourceBundleID: String
    var target: BrowserTarget
}

enum BrowserTarget: Codable {
    case fallbackBrowser
    case helium(profileDirectory: String)
}

struct IncomingOpenContext {
    var url: URL
    var sourceBundleID: String?
}
```

```swift
protocol SourceAppResolver {
    func resolveSourceBundleID(for event: IncomingEvent) -> String?
}

protocol BrowserLauncher {
    func open(_ url: URL, target: BrowserTarget, config: RouterConfig) throws
}
```

## Routing behavior

```text
Incoming URL
-> capture sender metadata if available
-> map sender to bundle ID
-> first matching source-app rule wins
-> if match is Helium, launch Helium with configured Chromium profile
-> otherwise forward to stored fallback browser
```

## Known pitfalls to design around

- macOS does not expose a first-class OS policy API for `source app -> browser` routing.
- The app must become the URL handler; that is the native extension point on macOS.
- Sender detection is the highest-risk area and needs an explicit spike before committing to the full implementation.
- Browser profiles are not an OS concept; Helium profile support is app-specific and may need process-launch arguments.
- Once the router app becomes the default handler, Launch Services will report this app as the handler, so the original fallback browser must already be saved in config.

## Module design

- Keep the code organized inside `LinkSwitch/LinkSwitch/` and let the Xcode target structure drive the file layout.
- `App/`
  - `AppDelegate`
  - app coordinator / menu wiring / preferences presentation
- `Core/Config/`
  - `RouterConfig`
  - `SourceAppRule`
  - `BrowserTarget`
  - any shared router-facing types kept in one file cluster as the single source of truth
- `Core/Routing/`
  - `IncomingOpenContext`
  - `URLIntakeController`
  - `SourceAppResolver`
  - `RuleEngine`
- `Core/Launch/`
  - `LaunchServicesBridge`
  - `BrowserLauncher`
  - `HeliumLauncher`
- `UI/`
  - `PreferencesWindowController`
  - small AppKit views/controllers for fallback browser selection, rule CRUD, and test launches
- `Support/`
  - narrow helpers only when needed; do not turn this into a dumping ground

## Testing harness

- Unit tests:
  - config parsing and persistence
  - rule matching by source bundle ID
  - Helium launch argument generation
- Fixture apps:
  - add them as extra targets inside `LinkSwitch/LinkSwitch.xcodeproj` only when the core routing tests are already in place
  - source can live under `LinkSwitch/Fixtures/` if and when those targets are added
  - `SenderHarness.app` simulates a Slack-like sender bundle ID and calls URL open APIs
  - `CaptureBrowser.app` records incoming URLs and launch arguments to a temp file
- Integration tests:
  - run the router against a test-only scheme like `linkroutertest://` to avoid mutating the machine's real browser defaults during CI/local automation
  - verify `SenderHarness.app -> router -> CaptureBrowser.app` flow
  - verify non-matching senders route to the configured fallback browser target
- Manual verification:
  - set the router as the real `http/https` handler
  - configure fallback browser to the user's normal browser
  - add `Slack -> Helium(work-profile)`
  - click a Slack link and confirm Helium opens the right profile
  - click a link from another app and confirm fallback-browser forwarding

## Deliverables

- Native AppKit app target in `LinkSwitch/LinkSwitch.xcodeproj`
- Config model and source-app rule engine
- Helium work-profile launcher adapter
- Preferences UI for fallback browser and source-app rules
- Automated fixture-based routing tests
- Short implementation notes documenting sender-detection findings and any unsupported edge cases

## Non-goals

- Firefox, Zen, or Safari profile targeting
- URL/domain-based routing
- Browser chooser UI
- Browser extension integration
- Background interception without being the registered URL handler

