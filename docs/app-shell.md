# App Shell

## Current shell contract

LinkSwitch now behaves as a status-item-first macOS app.

- The primary entry point is the menu bar status item.
- The Dock icon is hidden by default through `LSUIElement` in `LinkSwitch/LinkSwitch/Info.plist`.
- The app now has a single window.
- That main window is the preferences surface.

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
- preserves a stable UI entry point without changing the default product behavior

This keeps the production app status-item-first while giving XCTest a deterministic window to drive.
