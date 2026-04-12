# LinkSwitch Docs

Implementation notes for the native macOS link-router app live here.

## Files

- `app-shell.md` - menu bar shell, Dockless behavior, window lifecycle, single-instance policy, and UI test launch mode
- `tahoe-menu-bar-reset.md` - Tahoe-specific menu-bar ghost-state failure and the reset procedure that restored the original LinkSwitch identity
- `implementation-log.md` - rolling decisions, progress notes, and plan mapping
- `source-app-resolution.md` - sender-detection approach, limits, and Apple Event notes
- `helium-launcher.md` - Helium-specific launch assumptions and risks
- `zen-default-browser-research.md` - research on Zen profile vs container/workspace discovery for default-browser routing
- `zen-container-handoff.md` - how Zen container routing uses `ext+container:` and what to expect (add-ons, prefs, limits)
