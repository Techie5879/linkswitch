---
name: Decouple Chromium Support
overview: Separate Chromium profile discovery capability from Chromium profile launch capability without changing current browser behavior. The plan keeps the existing support matrix intact first, then moves callers onto explicit predicates so future browsers can diverge safely.
todos:
  - id: add-capability-seam
    content: Introduce explicit Chromium discovery and launch capability helpers backed by the existing canonical registry
    status: completed
  - id: rewire-discovery
    content: Update discovery factory to use discovery-specific helpers and path lookup
    status: completed
  - id: rewire-launch-and-normalization
    content: Update profile support classification, launcher guards, and preferences normalization to use launch-specific helpers
    status: completed
  - id: lock-in-tests
    content: Add seam-level tests and keep existing Chromium UI/launcher behavior green
    status: completed
isProject: false
---

# Decouple Chromium Support

## Goal
Preserve current Chromium-family browser support while removing the hidden assumption that "has a Chromium profile data path" also means "can be launched with `--profile-directory`".

## Surgical Approach
- Keep the existing browser support working exactly as it does today on the first pass.
- Introduce explicit Chromium capability helpers instead of reusing `ChromiumBrowserAppSupportPath.relativePath(forBundleID:)` as a proxy for everything.
- Move discovery callers to the discovery helper and launch/route-validation callers to the launch helper.
- Initially make both helpers resolve from the same canonical Chromium registry so behavior stays unchanged.
- Leave the actual divergence for later browser-by-browser opt-in; this change is about creating the seam safely.

## Key Files
- [LinkSwitch/LinkSwitch/Core/Discovery/ChromiumProfileDiscovery.swift](LinkSwitch/LinkSwitch/Core/Discovery/ChromiumProfileDiscovery.swift)
  - Current canonical Chromium registry: `ChromiumBrowserAppSupportPath.relativePath(forBundleID:)`
- [LinkSwitch/LinkSwitch/Core/Discovery/BrowserProfileDiscoveryFactory.swift](LinkSwitch/LinkSwitch/Core/Discovery/BrowserProfileDiscoveryFactory.swift)
  - Discovery currently keys directly off the Chromium path registry
- [LinkSwitch/LinkSwitch/Core/Config/DefaultBrowserProfileSupport.swift](LinkSwitch/LinkSwitch/Core/Config/DefaultBrowserProfileSupport.swift)
  - Launch/routing classification currently also keys off the same registry
- [LinkSwitch/LinkSwitch/UI/BrowserProfileRoutePicker.swift](LinkSwitch/LinkSwitch/UI/BrowserProfileRoutePicker.swift)
  - UI mode selection currently depends on `DefaultBrowserProfileSupport`
- [LinkSwitch/LinkSwitch/UI/PreferencesModel.swift](LinkSwitch/LinkSwitch/UI/PreferencesModel.swift)
  - Route normalization depends on browser capability classification
- [LinkSwitch/LinkSwitch/Core/Launch/BrowserLauncher.swift](LinkSwitch/LinkSwitch/Core/Launch/BrowserLauncher.swift)
  - Runtime guards for `.defaultBrowserChromiumProfile` and `.applicationChromiumProfile`

## Planned Refactor
- Add a tiny Chromium capability layer near the existing registry, for example:
  - `chromiumDiscoveryRelativePath(forBundleID:)`
  - `supportsChromiumProfileDiscovery(forBundleID:)`
  - `supportsChromiumProfileLaunch(forBundleID:)`
- Keep one source of truth for bundle IDs and paths; do not duplicate browser lists in multiple files.
- Update `BrowserProfileDiscoveryFactory` to depend only on discovery capability/path.
- Update `DefaultBrowserProfileSupport` to depend on launch capability, not discovery path existence.
- Keep `BrowserProfileRoutePicker` behavior unchanged by preserving the same effective answers during this pass.
- Keep `PreferencesModel` normalization aligned with launch capability so saved routes remain valid.

## Validation
- Add focused unit tests proving discovery and launch are now independently expressible, even if they currently return the same answers for all known Chromium browsers.
- Preserve existing Chromium route picker, launcher, and preferences-model tests.
- Add at least one regression test around the new capability seam so future browser additions cannot accidentally enable both behaviors by touching only the discovery registry.