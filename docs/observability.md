# Observability

## Logging-first rule

LinkSwitch should add logging as behavior is introduced, not after a failure is hard to reproduce.

Current policy:

- log important inputs, decisions, outputs, and failures
- keep logs around routing, config persistence, browser launching, and tests
- prefer logs that are visible in command output for later reference
- do not silently swallow unexpected states

## Current implementation

The codebase now has a shared logger in `LinkSwitch/LinkSwitch/Support/AppLogger.swift`.

The logger currently:

- writes to Apple unified logging through `Logger`
- mirrors the same messages to standard output with timestamps
- appends the same lines to `logs/runtime.log` in the project root during the current development phase

That standard-output mirroring is intentional so `xcodebuild` and similar command output keeps a readable trace of what happened during tests and local debugging.

The runtime log file exists because XCTest and `xcodebuild` do not always surface test-process stdout directly in the command summary output. The file gives the agent and the user a stable log artifact to inspect later.

## Current development requirement

Because project-local runtime logging writes to the repo checkout, App Sandbox stays disabled during the current development phase. That is a development-time choice so the repo-local `logs/` folder can be used while the app is still being built out.

## Decision: disable App Sandbox during current development phase

Current decision:

- App Sandbox is disabled while the project is in active development.
- This is specifically to allow the app and tests to write runtime logs to the repo-local `logs/runtime.log`.

Why:

- the current development workflow wants logs stored in the project, not in the app container
- a sandboxed macOS app cannot freely write to the repo root
- keeping logs in the repo makes local debugging and agent inspection much simpler right now

Later:

- when the app is productionized, revisit sandboxing and move runtime logs to an appropriate app/runtime location
- that follow-up remains explicitly deferred in `docs/deferred-user-gated-todos.md`

## Current coverage

Logging has been added to:

- app lifecycle in `AppDelegate`
- status item installation and status-item menu actions in `AppDelegate`
- main-window hide/show decisions and reopen handling in `AppDelegate`
- single-window lifecycle close notifications in `AppDelegate`
- config path resolution, load, and save in `RouterConfigStore`
- source-app sender resolution in `SourceAppResolver`
- route selection in `RuleEngine`
- preferences loading, validation, save, and test-launch flows in `PreferencesModel`
- default-handler lookup and registration in `LaunchServicesBridge`
- browser forwarding in `BrowserLauncher`
- URL intake orchestration in `URLIntakeController`
- Helium launch argument generation in `HeliumLaunchArguments`
