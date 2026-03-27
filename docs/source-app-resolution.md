# Source App Resolution

## Goal

Determine the source application bundle ID for incoming URL opens so LinkSwitch can apply source-app rules such as `Slack -> Helium`.

## Key constraint

AppKit's `NSApplicationDelegate.application(_:open:)` only gives the app and the URLs. It does not directly provide a sender bundle ID.

That means sender detection is not part of the direct AppKit URL-open API contract and must be derived from the underlying Apple Event path when available.

## Current implementation

LinkSwitch now resolves sender metadata synchronously inside `AppDelegate.application(_:open:)` before it hops into the async URL-intake pipeline.

Current behavior:

1. treat incoming URL opens as the Apple Event-backed `kAEGetURL` path
2. read the current Apple Event from `NSAppleEventManager.shared().currentAppleEvent`
3. read `keySenderPIDAttr` when available
4. map the PID to `NSRunningApplication`
5. read `bundleIdentifier`
6. pass the resolved bundle ID, or `nil`, into `URLIntakeController`

Implementation files:

- `LinkSwitch/LinkSwitch/Core/Routing/SourceAppResolver.swift`
- `LinkSwitch/LinkSwitch/AppDelegate.swift`
- `LinkSwitch/LinkSwitchTests/SourceAppResolverTests.swift`
- `LinkSwitch/LinkSwitchTests/AppDelegateTests.swift`

## Why this direction

- It aligns with the plan's single routing pipeline and explicit sender-detection spike.
- It matches Apple's Apple Event handling model for URL events.
- It does not invent fallback heuristics when sender data is unavailable.

## Known limits

- `application(_:open:)` itself does not expose the sender, which is why resolution has to happen against the current Apple Event before async work begins.
- Apple Event access may be unavailable or incomplete in some launch paths.
- The sending PID may represent an intermediary process rather than the human-visible app.
- The sender process may exit before mapping succeeds.

## What this means for LinkSwitch

- `IncomingOpenContext.sourceBundleID` must stay optional.
- Rule matching should cleanly fall back to the configured fallback browser when the sender cannot be resolved.
- Unsupported or missing sender metadata should be documented, not guessed around.

## References

- Plan: `.cursor/plans/native-macos-link-router.plan.md`
- Apple Event handling guide:
  - <https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/ScriptableCocoaApplications/SApps_handle_AEs/SAppsHandleAEs.html>
- Launch Services Concepts:
  - <https://developer.apple.com/library/archive/documentation/Carbon/Conceptual/LaunchServicesConcepts/LSCConcepts/LSCConcepts.html>
