# Implementation Log

## Current plan baseline

Primary source of truth: `.cursor/plans/native-macos-link-router.plan.md`

Current Xcode layout from the plan:

- Project: `LinkSwitch/LinkSwitch.xcodeproj`
- App target root: `LinkSwitch/LinkSwitch/`
- Unit tests: `LinkSwitch/LinkSwitchTests/`
- UI tests: `LinkSwitch/LinkSwitchUITests/`

## Decisions

### Use the generated Xcode project as the source tree

Reason:

- The plan now explicitly says to keep working from the generated Xcode layout.
- The Xcode project uses filesystem-synchronized groups, so new `.swift` files added under the target folders are picked up without hand-editing `project.pbxproj`.

### Start with a pure-core TDD slice

Reason:

- The plan calls out unit tests first for config parsing/persistence, rule matching, and Helium launch argument generation.
- Sender detection and Launch Services are the highest-risk macOS-specific parts, so the first implementation slice should lock down the data model and routing decisions before OS integration.

First slice:

- `Core/Config/RouterConfig.swift`
- `Core/Config/RouterConfigStore.swift`
- `Core/Routing/IncomingOpenContext.swift`
- `Core/Routing/RuleEngine.swift`
- `Core/Launch/HeliumLaunchArguments.swift`
- matching unit tests in `LinkSwitch/LinkSwitchTests/`

### Keep AppKit-first, but delay URL-handler registration until the core is stable

Reason:

- Registering `http` and `https` changes system behavior and is not needed to test the pure routing model.
- The plan expects handler registration, preferences UI, and source-app intake, but those can come after the core contracts are covered.

### Logging-first observability is now a project rule

Reason:

- Early logging makes routing, persistence, and launch behavior debuggable before the harder Launch Services and Apple Event work lands.
- Mirroring logs to standard output helps local runs, and a persistent runtime log file covers the cases where XCTest does not surface stdout directly.

Implemented in:

- `AGENTS.md`
- `.cursor/rules/logging-first.mdc`
- `docs/observability.md`
- shared runtime logger in `LinkSwitch/LinkSwitch/Support/AppLogger.swift`

Current development choice:

- runtime log artifact should live at `logs/runtime.log` in the repo
- production log destination is deferred in `docs/deferred-user-gated-todos.md`
- App Sandbox is disabled during the current development phase so repo-local logging works

### Add a Launch Services and browser-launch TDD slice

Reason:

- The next planned milestone after the pure-core model is to bridge real macOS app resolution and browser launching without taking on URL-handler registration or sender-resolution work yet.
- The launch layer needs a test seam around `NSWorkspace` so fallback-browser forwarding and Helium-specific profile launching can be verified without launching real apps during unit tests.

Implemented in:

- `LinkSwitch/LinkSwitch/Core/Launch/LaunchServicesBridge.swift`
- `LinkSwitch/LinkSwitch/Core/Launch/BrowserLauncher.swift`
- `LinkSwitch/LinkSwitchTests/LaunchServicesBridgeTests.swift`
- `LinkSwitch/LinkSwitchTests/BrowserLauncherTests.swift`

Current shape:

- `LaunchServicesBridge` resolves the current handler bundle ID for a URL scheme, resolves installed app URLs by bundle ID, and wraps default-handler registration for URL schemes.
- `BrowserLauncher` forwards fallback-browser opens through `NSWorkspace.open(_:withApplicationAt:configuration:completionHandler:)`.
- Helium launching stays browser-specific and uses `NSWorkspace.openApplication(at:configuration:completionHandler:)` with the generated Chromium-style profile arguments.
- The launch layer logs important inputs, resolved app paths, launch arguments, and registration failures, and those log lines are visible in `logs/runtime.log` during tests.

### Add a URL-intake controller slice

Reason:

- The app now has enough config, routing, and launch infrastructure to connect AppKit's incoming URL hook to the single routing pipeline without taking on sender-resolution yet.
- The pipeline should fail explicitly when no saved router config exists rather than guessing a browser or silently dropping the open.

Implemented in:

- `LinkSwitch/LinkSwitch/Core/Routing/URLIntakeController.swift`
- `LinkSwitch/LinkSwitch/AppDelegate.swift`
- `LinkSwitch/LinkSwitchTests/URLIntakeControllerTests.swift`

Current shape:

- `URLIntakeController` loads the saved router config, creates `IncomingOpenContext` values, runs each URL through `RuleEngine`, and delegates the actual open to `BrowserLauncher`.
- `AppDelegate.application(_:open:)` now logs incoming AppKit URL opens and routes them through `URLIntakeController`.
- That initial intake slice was built with `sourceBundleID = nil`; the later Apple Event sender-resolution slice now fills that value before async intake begins.
- Missing config is surfaced as an explicit intake error and logged, which keeps the current no-fallback rule intact.

### Add the Apple Event sender-resolution slice

Reason:

- The core behavior depends on real sender metadata so source-app rules can differentiate `Slack -> Helium` from normal fallback forwarding.
- `NSApplicationDelegate.application(_:open:)` does not expose a sender directly, so the app must resolve sender metadata from the current Apple Event before the async intake task starts.

Implemented in:

- `LinkSwitch/LinkSwitch/Core/Routing/SourceAppResolver.swift`
- `LinkSwitch/LinkSwitch/AppDelegate.swift`
- `LinkSwitch/LinkSwitchTests/SourceAppResolverTests.swift`
- `LinkSwitch/LinkSwitchTests/AppDelegateTests.swift`

Current shape:

- `SourceAppResolver` reads the current Apple Event, extracts `keySenderPIDAttr`, maps that PID to `NSRunningApplication`, and returns an optional bundle ID.
- `AppDelegate.application(_:open:)` now resolves the sender synchronously before it enters the async intake pipeline, which avoids losing Apple Event metadata after the stack unwinds.
- Missing sender metadata stays explicit and logged; the routing layer still treats `sourceBundleID` as optional and falls back only through the configured fallback-browser rule path.

### Add a preferences and registration slice

Reason:

- The app now needs an actual operator-facing surface to choose the fallback browser, manage source-app rules, test launches, and request default-handler registration without editing config files by hand.
- URL-handler registration also needs real bundle URL declarations for `http` and `https` so Launch Services can recognize LinkSwitch as a web handler.

Implemented in:

- `LinkSwitch/LinkSwitch/UI/PreferencesModel.swift`
- `LinkSwitch/LinkSwitch/UI/PreferencesWindowController.swift`
- `LinkSwitch/LinkSwitch/AppDelegate.swift`
- `LinkSwitch/LinkSwitch/Info.plist`
- `LinkSwitch/LinkSwitch.xcodeproj/project.pbxproj`
- `LinkSwitch/LinkSwitchTests/PreferencesModelTests.swift`
- `LinkSwitch/LinkSwitchTests/AppBundleConfigurationTests.swift`
- `LinkSwitch/LinkSwitchUITests/LinkSwitchUITests.swift`

Current shape:

- The main window now exposes an `Open Preferences…` action, and the app menu Preferences item is wired programmatically.
- `PreferencesWindowController` is code-built and supports fallback-browser selection, source-app rule CRUD, sample-URL test launches, current `http` / `https` handler inspection, and a button that calls `LaunchServicesBridge` to request LinkSwitch as the default web handler.
- `PreferencesModel` is the testable logic layer behind that UI and owns config loading, validation, persistence, test launches, and default-handler registration requests.
- The app bundle now declares `http` and `https` in `CFBundleURLTypes`, and a host-bundle test verifies those schemes are present.

### Add in-process routing integration coverage

Reason:

- The plan's eventual fixture-app harness still needs extra Xcode targets, but the current project can already add stronger automated coverage by persisting real config and running the saved router pipeline in-process.

Implemented in:

- `LinkSwitch/LinkSwitchTests/RoutingPipelineIntegrationTests.swift`

Current shape:

- The integration tests save config through `PreferencesModel`, reload that same file through a real `RouterConfigStore`, and drive `URLIntakeController` with spy launchers.
- The current automated coverage now exercises the persistence -> intake -> rule engine -> launch selection path without mutating the machine's real browser defaults during test runs.

## Source references

- Plan: `.cursor/plans/native-macos-link-router.plan.md`
- Apple Launch Services Concepts:
  - <https://developer.apple.com/library/archive/documentation/Carbon/Conceptual/LaunchServicesConcepts/LSCConcepts/LSCConcepts.html>
- Apple Scriptable Cocoa Applications, Apple Event handling:
  - <https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/ScriptableCocoaApplications/SApps_handle_AEs/SAppsHandleAEs.html>
- Helium multi-profile issue:
  - <https://github.com/imputnet/helium/issues/1030>

## Pending Xcode-driven steps

These should prefer Xcode UI over hand-editing if needed:

- confirm app capabilities and signing choices when Launch Services integration begins
- add fixture app targets later if the project grows beyond the three generated targets
- run fixture-app target creation for `SenderHarness.app` / `CaptureBrowser.app` if we want the full multi-process harness described in the plan
