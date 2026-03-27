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
