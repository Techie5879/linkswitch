# Install Guide

This document covers how LinkSwitch should be installed for:

- development testing
- internal handoff builds
- real release distribution

It also explains what each signing/distribution mode entails and which one is recommended.

## Current app behavior

Before choosing an install path, keep these current project details in mind:

- The app registers itself as the `http` / `https` handler from Preferences.
- The app now launches as a menu bar utility and hides its Dock icon by default.
- The saved router config lives at `~/Library/Application Support/LinkSwitch/router-config.json`.
- The current development logger also writes to `logs/runtime.log` in the repo checkout.
- App Sandbox is currently disabled for development so repo-local logging works.
- The app uses its own current bundle path when registering itself as the default handler.

That last point matters: if you register a build directly out of Xcode `DerivedData`, Launch Services may point at a transient build product path that later disappears.

## Recommendation Summary

Use these defaults:

- Development on your own Mac: use Xcode automatic/local signing.
- Full local handler testing: copy the built app to a stable path like `~/Applications/LinkSwitch Dev.app` before registering it as the handler.
- Internal one-off build sharing: ad hoc signing is acceptable only for trusted technical testers who understand Gatekeeper friction.
- Real release: use `Developer ID Application` signing plus notarization, then distribute a notarized `.dmg` or zipped `.app`.

## Signing And Distribution Modes

| Mode | Good for | Other Macs | Gatekeeper UX | Apple developer account needed | Recommended |
| --- | --- | --- | --- | --- | --- |
| Xcode automatic/local signing | Running from source during development | No, not as a real distribution story | Fine on the build machine | No | Yes, for dev |
| Ad hoc signing | Narrow internal smoke testing | Sometimes, with manual bypass/quarantine handling | Rough | No | Only as a temporary internal option |
| Developer ID signed + notarized | Normal direct download release | Yes | Good | Yes | Yes, for release |
| Mac App Store | Store distribution | Yes | Good | Yes | No current recommendation |

## What Each Mode Entails

### Xcode automatic/local signing

This is the normal development mode.

What it entails:

- Build and run from `LinkSwitch/LinkSwitch.xcodeproj`.
- Best for coding, debugging, XCTest, and Preferences-level launch testing.
- No notarization.
- No installer packaging.
- The resulting app path is usually under `DerivedData`, which is not a stable place to register as the long-term URL handler.

Recommendation:

- Use this for day-to-day development.
- Do not rely on a raw `DerivedData` build as your persistent registered handler.

### Ad hoc signing

Ad hoc signing is basically a minimally signed bundle without a real Developer ID identity.

What it entails:

- No Apple-trusted developer identity.
- No notarization.
- Gatekeeper may block or warn on other machines, especially if the app was downloaded and carries quarantine metadata.
- Testers may need to right-click `Open` or manually strip quarantine.
- Not suitable for broad or polished distribution.

Recommendation:

- Use only for narrow internal handoff when the tester is technical and the goal is quick smoke testing.
- Do not use this as the public release path.

### Developer ID signed + notarized

This is the recommended release path for LinkSwitch.

What it entails:

- Requires an Apple Developer Program account.
- Sign the app with a `Developer ID Application` certificate.
- Notarize the exported app or container with Apple.
- Staple the notarization ticket to the shipped artifact.
- Distribute as a notarized `.dmg` or zipped `.app`.

Why this is recommended:

- Installs cleanly on other Macs.
- Minimizes Gatekeeper friction.
- Fits a standalone utility app better than the current ad hoc/dev paths.
- Does not force a Mac App Store workflow.

### Mac App Store

This is not the recommended path right now.

Why not:

- It adds extra packaging/review constraints that are not currently part of this project.
- The current project decisions and docs are oriented around direct distribution, not App Store productization.

## Development Install And Test Flow

### Option A: Fast local dev loop

Use this when you are coding or running tests.

1. Open `LinkSwitch/LinkSwitch.xcodeproj` in Xcode.
2. Build and run the app with Xcode's default automatic/local signing.
3. Open LinkSwitch from the LinkSwitch menu bar item. The single window opens directly into preferences.
4. Choose a fallback browser.
5. Add source-app rules as needed.
6. Use `Test Fallback Browser` and `Test Rule` for fast validation.

Use this mode when:

- you are iterating on code
- you do not need LinkSwitch to remain the default handler outside the current debug session

Notes:

- Runtime logs are expected at `logs/runtime.log` in the repo.
- Config is still stored at `~/Library/Application Support/LinkSwitch/router-config.json`.

### Option B: Real local handler testing

Use this when you want to test actual `http` / `https` handler registration on your own machine.

1. Build the app in Xcode.
2. Copy the built app bundle to a stable location before registering it:
   `~/Applications/LinkSwitch Dev.app` is a good choice.
3. Launch that copied app directly.
4. Open LinkSwitch from the LinkSwitch menu bar item. The single window opens directly into preferences.
5. Choose the fallback browser.
6. Save the config.
7. Click `Set LinkSwitch as HTTP/HTTPS Handler`.
8. Run real sender-app tests.

Why copy it first:

- The registration button uses the running app's bundle path.
- A `DerivedData` path is disposable and may break later after a clean build or Xcode cache change.

Recommendation:

- Keep dev-handler builds separate from any future release build.
- Name the copied dev build something explicit like `LinkSwitch Dev.app`.

## Current Dev Caveats

These are important if you plan to test beyond Xcode:

- App Sandbox is currently off because dev logging writes to the repo.
- The repo-local log path is development-oriented, not release-oriented.
- If a build is moved to another machine without the same source checkout path, file-log appends may fail even though unified logging still exists.

That means the current build setup is good for development, but it is not yet the ideal final production packaging posture.

## Internal Handoff Build

If you want to hand a build to a trusted tester before doing full release packaging:

- Prefer a stable copied build, not a raw `DerivedData` path.
- Ad hoc signing is acceptable only for quick internal testing.
- Tell the tester to install the app to `/Applications` or `~/Applications`.
- Tell the tester to launch the app once before trying handler registration.
- Expect possible Gatekeeper/quarantine friction.

What the tester should do after install:

1. Move the app to `/Applications` or `~/Applications`.
2. Open it once manually.
3. Open LinkSwitch from the LinkSwitch menu bar item. The single window opens directly into preferences.
4. Choose the fallback browser.
5. Add any source-app rule such as `Slack -> Helium(profile)`.
6. Save.
7. Click `Set LinkSwitch as HTTP/HTTPS Handler`.

What this path does not give you:

- smooth first-run trust on arbitrary Macs
- a polished public install experience
- a notarized artifact

## Recommended Release Path

For a real release, use direct distribution with Developer ID signing and notarization.

### Maintainer-side release steps

1. Build a Release archive from `LinkSwitch/LinkSwitch.xcodeproj`.
2. Sign the app with `Developer ID Application`.
3. Export the app as either a `.dmg` for the cleanest manual install flow or a zipped `.app` for the simplest packaging.
4. Submit the exported artifact for notarization.
5. Staple the notarization ticket.
6. Distribute the stapled artifact.

### End-user release install steps

1. Download the notarized release artifact.
2. Move `LinkSwitch.app` to `/Applications`.
3. Launch LinkSwitch.
4. Open LinkSwitch from the LinkSwitch menu bar item. The single window opens directly into preferences.
5. Choose the fallback browser.
6. Add any source-app rules you want.
7. Save.
8. Click `Set LinkSwitch as HTTP/HTTPS Handler`.

## Release recommendations

- Prefer installing into `/Applications`, not running from Downloads.
- Prefer shipping a `.dmg` if you want a conventional drag-to-Applications experience.
- Keep Helium as an external prerequisite; LinkSwitch should not bundle it.
- Expect the fallback browser and Helium to already be installed on the target Mac.

## Release caveats for this repo's current state

Before a polished public release, the following should be revisited:

- repo-local file logging should move to a real app/runtime location
- App Sandbox should be reconsidered together with that logging change
- release verification should confirm Launch Services registration still behaves correctly after any sandbox/logging changes

Those are productization tasks, not required for day-to-day dev testing.

## Recommended Packaging Choice

If you want one concrete recommendation:

- Dev: Xcode automatic/local signing
- Internal tester handoff: ad hoc only if absolutely needed and only for technical testers
- Release: `Developer ID Application` signed, notarized, stapled `.dmg`

## Post-Install Setup Checklist

After any successful install, the setup flow is:

1. Launch LinkSwitch.
2. Open LinkSwitch from the LinkSwitch menu bar item. The single window opens directly into preferences.
3. Choose the fallback browser.
4. Add source-app rules.
5. Save.
6. Click `Set LinkSwitch as HTTP/HTTPS Handler`.
7. Verify a matching sender opens the intended browser target.
8. Verify a non-matching sender opens the configured fallback browser.

## Rollback / Uninstall

If you want to stop using LinkSwitch:

1. Change the default web handler away from LinkSwitch in macOS or by setting another browser as default.
2. Delete `LinkSwitch.app`.
3. Optionally remove `~/Library/Application Support/LinkSwitch/router-config.json`.

If you were using a dev build copied to `~/Applications/LinkSwitch Dev.app`, remove that app bundle specifically and restore your normal browser as the default handler.
