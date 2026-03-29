# Zen Fallback Research

## Goal

Figure out why the fallback-browser rule UI does not show the expected Zen entries `personal` and `work`, and determine whether LinkSwitch can route to them through a supported macOS launch path.

## Local findings

### Zen profile registry does not contain `personal` or `work`

On this machine, `~/Library/Application Support/zen/profiles.ini` contains only two Firefox-style profiles:

- `Default Profile`
- `Default (release)`

Those are the only discoverable profile names in Zen's normal Gecko profile registry.

### `personal` and `work` exist in Zen containers, not profiles

The active Zen profile has `~/Library/Application Support/zen/Profiles/5wng7prr.Default (release)/containers.json` with public identities:

- `Personal` via `l10nId: user-context-personal`
- `Work` via explicit `name: "Work"`

That means the user-visible `personal/work` entries are container identities, not profile entries from `profiles.ini`.

### The installed Zen build is not using Firefox's selectable profile groups here

The active profile's `targeting.snapshot.json` currently reports:

- `canCreateSelectableProfiles: false`
- `hasSelectableProfiles: false`

So there is no evidence on this machine that Zen's newer selectable-profile storage is active for the expected `personal/work` entries.

### Zen workspace state is present separately

The active profile's `prefs.js` includes Zen workspace preferences such as:

- `zen.workspaces.active`
- `zen.workspaces.continue-where-left-off`
- `zen.workspaces.force-container-workspace`

This supports the same conclusion: Zen workspaces/containers are separate from Firefox-style browser profiles.

## Public research

### Zen uses Firefox-style profile discovery on macOS

Public Zen and community sources point to the normal Gecko layout:

- `~/Library/Application Support/zen/profiles.ini`
- `~/Library/Application Support/zen/installs.ini`
- `~/Library/Application Support/zen/Profiles/...`

That matches the current LinkSwitch `FirefoxProfileDiscovery` approach for true Zen profiles.

### Workspaces and containers are distinct from profiles

Zen's own workspace documentation describes workspaces as in-browser organization tied to containers and tab behavior, not as separate browser profiles.

### No documented first-party external API was found for container/workspace targeting

Research did not find a supported Zen command-line flag or URL contract for:

- opening a URL in a specific Zen workspace
- opening a URL in a specific Zen container

The only documented external container handoff found was Firefox's third-party `ext+container:` workflow from the `Open external links in a container` add-on. That is extension-dependent, not a built-in browser contract, and it is not currently installed in the inspected Zen profiles on this machine.

## Implications for LinkSwitch

### Safe, supportable path

LinkSwitch can safely add fallback-browser profile discovery for real Firefox-family profiles from `profiles.ini`. On a Firefox-family fallback browser that means exposing the actual `Name=` entries from `profiles.ini` and launching through the browser executable with an absolute `-profile` path.

If Zen is treated as a plain Firefox-profile browser, this machine would expose:

- `Default Profile`
- `Default (release)`

### Unsupported path

LinkSwitch should not pretend that Zen container identities `personal` and `work` are browser profiles. Routing to those would require one of:

- a documented Zen container/workspace launch API, which was not found
- an extension-dependent `ext+container:` flow, which is not installed locally and is not a stable first-party contract
- browser automation, which is outside the current product scope

## Implemented direction

The implemented fallback-browser behavior now intentionally splits Firefox-family and Zen handling:

- Firefox-family fallback browsers use `profiles.ini` discovery and store the selected `Path=` key on the rule target.
- Zen fallback browsers use `containers.json` discovery and surface the public container identities from the active/default Zen profile.
- Zen container launches are routed through the documented extension-style `ext+container:name=...&url=...` handoff, which keeps the implementation aligned with the only public external mechanism found during research.
- The rule UI keeps a `Browser Default` card alongside the discovered Firefox profile or Zen container cards so a fallback rule can still target the plain browser open path.

## Current limitation

Zen container routing is implemented against the extension-based `ext+container:` contract, but this machine does not currently have that helper installed in the inspected Zen profile. The code path is documented and wired, but the local extension-dependent runtime behavior was not validated here.

## References

- Zen workspaces docs: <https://docs.zen-browser.app/user-manual/workspaces>
- Zen profile migration guide: <https://docs.zen-browser.app/guides/manage-profiles>
- Zen community path example: <https://github.com/zen-browser/desktop/discussions/5535>
- Zen backup/path discussion: <https://github.com/zen-browser/desktop/discussions/9731>
- Firefox command-line options: <https://wiki.mozilla.org/Firefox/CommandLineOptions>
- Firefox profile service docs: <https://firefox-source-docs.mozilla.org/toolkit/profile/>
- Firefox profile service changes: <https://firefox-source-docs.mozilla.org/toolkit/profile/changes.html>
- Firefox container CLI enhancement request: <https://bugzilla.mozilla.org/show_bug.cgi?id=1726634>
- Multi-Account Containers FAQ: <https://github.com/mozilla/multi-account-containers/wiki/Frequently-asked-questions>
- `Open external links in a container` add-on: <https://addons.mozilla.org/en-US/firefox/addon/open-url-in-container/>
