# Helium Launcher Notes

## Goal

Support a browser-specific routing target for Helium that opens a URL with a configured Chromium-style profile directory.

## Current assumption

Helium is Chromium-based enough that `--profile-directory=<folder>` is a reasonable launch argument to generate for the first implementation.

This is a browser-specific adapter, not a generic browser-profile abstraction.

## Why this is acceptable for now

- The project scope explicitly allows a Helium-specific adapter.
- The plan only needs a Chromium-style work-profile launch path for Helium.
- A current Helium issue references testing with `--user-data-dir`, which is consistent with Chromium-style argument support.

## Risks

- Helium does not present a formal, stable public API for profile launching.
- Multi-profile behavior may be unstable in some Helium versions.
- The configured profile value should be the actual on-disk profile directory name, not a guessed display label.

## Current implementation direction

The first pure-core slice only generates launch arguments.

Initial shape:

- `--profile-directory=<configured profile directory>`
- URL as the final argument

The actual `NSWorkspace` launch adapter will be added later after the pure argument-generation tests pass.

## References

- Plan: `.cursor/plans/native-macos-link-router.plan.md`
- Helium issue:
  - <https://github.com/imputnet/helium/issues/1030>
