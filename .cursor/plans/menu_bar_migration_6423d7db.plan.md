---
name: Menu Bar Migration
overview: Convert LinkSwitch from a main-window-first AppKit app into a status-item-first macOS app that hides from the Dock by default, while preserving a reliable path to reopen windows and accommodating the Dock 'Keep in Dock' user option.
todos:
  - id: design-status-item
    content: Define the status item menu and decide whether the current main window remains as an optional setup window.
    status: pending
  - id: dockless-activation
    content: Plan the Dockless app change with LSUIElement and centralized window activation/show logic.
    status: pending
  - id: reopen-regression
    content: Add an explicit reopen path for Dock clicks and window restoration after close.
    status: pending
  - id: test-strategy
    content: Adjust UI test strategy for a status-item-first app so regressions remain covered.
    status: pending
isProject: false
---

# Menu Bar App Plan

## Current State

- The app is an AppKit + nib app, not SwiftUI. Startup is centered in `[/Users/helios/linkswitch/LinkSwitch/LinkSwitch/AppDelegate.swift](/Users/helios/linkswitch/LinkSwitch/LinkSwitch/AppDelegate.swift)`.
- The main window is loaded from `[/Users/helios/linkswitch/LinkSwitch/LinkSwitch/Base.lproj/MainMenu.xib](/Users/helios/linkswitch/LinkSwitch/LinkSwitch/Base.lproj/MainMenu.xib)`, then populated in `configureMainWindowContent()`.
- Preferences already exists as a separate programmatic window in `[/Users/helios/linkswitch/LinkSwitch/LinkSwitch/UI/PreferencesWindowController.swift](/Users/helios/linkswitch/LinkSwitch/LinkSwitch/UI/PreferencesWindowController.swift)`.
- The Dock-click reopen bug is caused by missing `applicationShouldHandleReopen(_:hasVisibleWindows:)` in `AppDelegate`. The main window is not released on close, so it can be shown again, but nothing currently does that.

## Proposed End State

- LinkSwitch launches as a status bar app with an `NSStatusItem` in the macOS menu bar.
- By default it does not appear in the Dock via `LSUIElement` in `[/Users/helios/linkswitch/LinkSwitch/LinkSwitch/Info.plist](/Users/helios/linkswitch/LinkSwitch/LinkSwitch/Info.plist)`.
- The primary user entry point becomes the status item menu with at least:
  - `Preferences…`
  - `Show Window` or `Show Setup` if the current main window remains useful
  - `Quit`
- The preferences window remains the main configuration surface; the current onboarding/main window can either be kept as a lightweight setup/about window or retired if it becomes redundant.

## Keep In Dock

- The Dock `Options > Keep in Dock` behavior in your screenshot should be treated as a user-level override, not the app's primary design.
- Plan for LinkSwitch to be usable with no Dock presence at all.
- If the user pins it in the Dock anyway, Dock clicks should still reopen the relevant window correctly. That means the reopen fix is still worth doing even in a status-only design.

## Implementation Steps

1. Add a status item in `[/Users/helios/linkswitch/LinkSwitch/LinkSwitch/AppDelegate.swift](/Users/helios/linkswitch/LinkSwitch/LinkSwitch/AppDelegate.swift)`.
  - Create and retain an `NSStatusItem` during `applicationDidFinishLaunching`.
  - Build an `NSMenu` that reuses existing actions like `showPreferencesWindow(_:)`.
  - Add logging for status-item setup, menu actions, and window presentation.
2. Hide the app from the Dock by default in `[/Users/helios/linkswitch/LinkSwitch/LinkSwitch/Info.plist](/Users/helios/linkswitch/LinkSwitch/LinkSwitch/Info.plist)`.
  - Add `LSUIElement = true`.
  - Verify the app still accepts `http`/`https` opens and can bring preferences forward when invoked from the status item.
3. Refactor window presentation into explicit helpers in `[/Users/helios/linkswitch/LinkSwitch/LinkSwitch/AppDelegate.swift](/Users/helios/linkswitch/LinkSwitch/LinkSwitch/AppDelegate.swift)`.
  - Introduce one path for showing the main/setup window and one for showing preferences.
  - Stop relying on launch-time main-window visibility as the only way the user can reach settings.
  - Decide whether the current main window remains part of the product or whether preferences becomes the only window.
4. Fix the current reopen behavior in `[/Users/helios/linkswitch/LinkSwitch/LinkSwitch/AppDelegate.swift](/Users/helios/linkswitch/LinkSwitch/LinkSwitch/AppDelegate.swift)`.
  - Implement `applicationShouldHandleReopen(_:hasVisibleWindows:)`.
  - When there are no visible windows, bring back the intended window with `makeKeyAndOrderFront` and activate the app.
  - Add close/reopen logging so future lifecycle bugs are visible in `logs/runtime.log`.
5. Rework launch UX.
  - If status-item-first is the goal, do not auto-present the current main window on every launch.
  - Prefer opening no window at startup, then let the menu bar item open `Preferences…` or `Show Setup` on demand.
  - If you still want first-run guidance, gate that intentionally instead of showing the main window unconditionally.
6. Update tests in `[/Users/helios/linkswitch/LinkSwitch/LinkSwitchUITests/LinkSwitchUITests.swift](/Users/helios/linkswitch/LinkSwitch/LinkSwitchUITests/LinkSwitchUITests.swift)`.
  - The current UI test assumes a visible launch window and clicks `Open Preferences…` there.
  - Replace that with tests around explicit window-showing helpers, or add a test-specific launch mode that keeps the app in regular Dock mode for automation.
  - Add at least one regression test for the reopen path so closing a window does not strand the app.

## Recommended Product Decision

- The lowest-churn path is: keep AppKit, add `NSStatusItem`, set `LSUIElement`, keep `PreferencesWindowController`, and make the existing main window optional instead of launch-default.
- I would not rewrite this to SwiftUI `MenuBarExtra`; the current architecture already fits an AppKit menu bar app well.

## Risks To Expect

- Agent apps are slightly harder to UI test than regular Dock apps.
- Activation/focus behavior can feel inconsistent if window showing is spread across multiple code paths; centralizing it in `AppDelegate` avoids that.
- If the main window stays, there must be a clear product rule for when users see it versus preferences, otherwise the app will feel ambiguous.

## Definition Of Done

- Launching LinkSwitch shows a menu bar item.
- The app is hidden from the Dock by default.
- `Preferences…` can always be opened from the menu bar item.
- Closing all windows never strands the app; the window can be restored either from the menu bar item or from the Dock when pinned via `Keep in Dock`.
- UI tests no longer depend on the current always-visible launch window.

