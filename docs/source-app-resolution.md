# Source App Resolution

## Goal

Determine the source application bundle ID for incoming URL opens so LinkSwitch can apply source-app rules such as `Slack -> Helium`.

## Key constraint

AppKit's `NSApplicationDelegate.application(_:open:)` only gives the app and the URLs. It does not directly provide a sender bundle ID.

That means sender detection is not part of the direct AppKit URL-open API contract and must be derived from the underlying Apple Event path when available.

## Current implementation direction

Use the Apple Event for the URL open path as the authoritative place to inspect sender metadata.

Current recommendation:

1. treat incoming URL opens as `kAEGetURL`
2. read the sender PID from the Apple Event when available
3. map PID to `NSRunningApplication`
4. read `bundleIdentifier`
5. keep `sourceBundleID` optional because metadata can be absent or misleading

## Why this direction

- It aligns with the plan's single routing pipeline and explicit sender-detection spike.
- It matches Apple's Apple Event handling model for URL events.
- It does not invent fallback heuristics when sender data is unavailable.

## Known limits

- `application(_:open:)` itself does not expose the sender.
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
