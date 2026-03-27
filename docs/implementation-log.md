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
- Sender resolution is still intentionally pending, so the AppKit path currently feeds `sourceBundleID = nil` until the Apple Event slice is implemented.
- Missing config is surfaced as an explicit intake error and logged, which keeps the current no-fallback rule intact.

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

- add URL scheme handling for `http` and `https`
- confirm app capabilities and signing choices when Launch Services integration begins
- add fixture app targets later if the project grows beyond the three generated targets
