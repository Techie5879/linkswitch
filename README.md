# LinkSwitch

macOS app that handles `http` / `https` links and routes them by **which app opened the URL** (e.g. Slack vs. everything else). Unmatched traffic goes to a **fallback browser** you pick in preferences; rules and fallback are stored in config, not inferred from the system default after LinkSwitch is the handler.

Built with Swift and AppKit. Project: `LinkSwitch/LinkSwitch.xcodeproj`.

## Layout

- `App/` — app lifecycle and UI  
- `Core/` — routing, config, launch  
- `Tests/` — unit tests  
- `Fixtures/` — harness apps  

See `AGENTS.md` for invariants/coding guidelines
