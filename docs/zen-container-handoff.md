# Zen container handoff

LinkSwitch can route the default browser to a **named Zen container** by rewriting the URL into Firefox’s extension-style `ext+container:name=…&url=…` form and opening that with Zen. This is the only public mechanism the project found for “open this external URL in container X” without browser automation.

## Caveats

- **Not a first-party Zen API.** Zen exposes containers and workspaces inside the app; there is no documented stable macOS launch contract for “open this link from another app in container Personal/Work.” Public Zen discussions (for example workspace launch from the CLI) describe gaps rather than a supported external container URL scheme.
- **Extension-dependent.** The `ext+container:` flow comes from the ecosystem around Firefox Multi-Account Containers and add-ons such as [Open external links in a container](https://addons.mozilla.org/firefox/addon/open-url-in-container/). Zen must actually handle that custom protocol in your profile. If nothing registers it, the handoff can fail or behave oddly (e.g. treated like search text).
- **Optional Firefox-family pref.** Some Firefox versions prompt or block external `ext+container:` opens unless you set `network.protocol-handler.external.ext+container` to `true` in `about:config`. Setting it only relaxes protocol handling; it does not replace an extension handler.
- **Routing can use domains or source apps.** A matching domain rule wins over a source-app rule. LinkSwitch does not match URL paths, queries, or fragments; see `routing-rules.md`.

Deeper background and local research notes: `zen-default-browser-research.md`.
