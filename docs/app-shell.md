# App Shell

## Current shell contract

LinkSwitch now behaves as a status-item-first macOS app.

- The primary entry point is the menu bar status item.
- The Dock icon is hidden by default through `LSUIElement` in `LinkSwitch/LinkSwitch/Info.plist`.
- The app now has a single window.
- That main window is the preferences surface.
- The installed app in `/Applications/LinkSwitch Dev.app` is the preferred day-to-day instance.

## Single-instance policy

LinkSwitch now enforces a single active app instance at startup.

Current product rule:

- The preferred resident copy is an installed app bundle under `/Applications` or `~/Applications`.
- Build artifacts in repo-local `build/DerivedData/...` or Xcode `~/Library/Developer/Xcode/DerivedData/...` are treated as inferior copies.
- If an inferior copy launches while a preferred installed copy already exists, the inferior copy terminates itself before installing a status item.
- If the preferred installed copy launches while inferior copies are alive, the preferred copy asks those inferior copies to terminate.

Why this exists:

- macOS can catalog multiple physical app bundles with the same bundle identifier in Launch Services.
- During development, `xcodebuild` and Xcode runs can leave extra `LinkSwitch.app` bundles on disk under DerivedData.
- Without an explicit singleton guard, multiple physical bundles can stay resident at the same time and each install its own menu bar item.

Current operational expectation:

- normal day-to-day use should leave exactly one running `dev.helios.LinkSwitch` process
- that process should be `/Applications/LinkSwitch Dev.app`
- the current `http` / `https` handler should also resolve to `/Applications/LinkSwitch Dev.app`

## Install workflow

`scripts/install-dev.sh` is the supported development install path for day-to-day use.

Current behavior:

- kills any running `LinkSwitch` process before reinstalling
- builds a fresh debug app
- installs that app to `/Applications/LinkSwitch Dev.app`
- re-registers the installed app with Launch Services
- unregisters non-installed `LinkSwitch` bundles that Spotlight currently finds
- removes the repo-local `build/DerivedData/.../LinkSwitch.app` artifact after copying
- relaunches only `/Applications/LinkSwitch Dev.app`

Notes:

- Xcode's own DerivedData app bundle can still reappear on disk after IDE/test runs, because that output is owned by Xcode.
- The singleton guard is the safety net that keeps those extra build products from becoming duplicate resident menu bar apps.

## Status item menu

The status item is installed from `LinkSwitch/LinkSwitch/AppDelegate.swift` and currently exposes:

- `Preferences…`
- `Quit LinkSwitch`

The visible status item is a monochrome template icon derived from the routing shape in `app-icon.svg`, not a text title. Tooltip and accessibility label stay present so the extra remains discoverable.

That menu is now the normal way to reach UI after launch.

## Window lifecycle

LinkSwitch still loads its main window from `Base.lproj/MainMenu.xib`, then replaces the content in `AppDelegate.configureMainWindowContent()`.

Current behavior:

- On a normal launch, the app configures the main window and immediately hides it.
- The user can use `Preferences…` from the status item to present the main window.
- When the window is shown, preferences are already visible without any extra click.

## Reopen behavior

`AppDelegate.applicationShouldHandleReopen(_:hasVisibleWindows:)` is the explicit reopen path for cases where the app is asked to reopen and no windows are visible.

Current product rule:

- Reopen restores the single main window.
- The status item exposes only `Preferences…` for opening that window.

This keeps the app from getting stranded after its windows are closed.

## Dock behavior

The default product behavior is Dockless.

If the app is launched in a context where a Dock icon exists, Dock reopen should still restore the main window through the same reopen hook used elsewhere. The Dock is not the primary UI contract.

## UI automation

UI tests use the launch argument `--ui-test-show-main-window`.

That launch mode:

- switches the app to a regular activation policy for the test run
- shows the main window on launch
- skips the production single-instance enforcement so repeated XCTest launches can run normally
- preserves a stable UI entry point without changing the default product behavior

This keeps the production app status-item-first while giving XCTest a deterministic window to drive.
