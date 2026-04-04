# LinkSwitch

**Route links to the right browser, automatically.**

Didn't wanna pay for Velja - so made my own equivalent.
LinkSwitch is a native macOS URL handler that intercepts `http` and `https` links and opens them in the browser of your choosing — based on which app opened the link. Send Slack links to your work browser profile, let everything else go to your personal default. No manual copy-paste, no chooser popup.

Rules and your default browser are stored in an explicit config file. LinkSwitch never silently infers browser preferences from the system.

Built with Swift and AppKit.

## How it works

1. Set LinkSwitch as your default browser in macOS System Settings.
2. Open Preferences, pick your default browser, and add per-source rules (e.g. Slack → Helium with a specific profile).
3. Every link you open routes automatically from there.

## Screenshots

<img src="docs/images/menubar-icon.png" alt="LinkSwitch in the menu bar" width="120">

![Preferences window with a Slack-to-Helium routing rule](docs/images/preferences-window.png)

## Features

- **Source-based routing** — rules match on the bundle ID of the app that opened the link
- **Profile support** — route to specific Chromium-style work profiles or Firefox/Zen profiles
- **Zen container support** — hand off to a named Zen container via the `ext+container:` protocol
- **Menu bar app** — lightweight, always available, out of your way
- **Explicit config** — plain config file, no magic inference

## Project structure

- `App/` — app lifecycle and UI
- `Core/` — routing, config, launch
- `Tests/` — unit tests
- `Fixtures/` — harness apps
