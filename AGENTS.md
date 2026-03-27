# AGENTS.md

## Scope

Native macOS app that registers as the `http` / `https` URL handler, routes opens by **source app bundle ID** (first-class case: Slack to Helium with a Chromium-style work profile), and sends everything else to a **user-chosen fallback browser** stored in config. Minimal preferences UI for fallback browser and per-source rules; config persisted explicitly (do not infer fallback from Launch Services once this app is the handler). No domain/URL pattern routing, no chooser UI, no Firefox/Zen/Safari profile support, no extensions, no interception outside the normal URL-handler path.

## Stack

`Swift`, `AppKit`, `Foundation`, Launch Services / `CoreServices`, `NSWorkspace`, `XCTest`. Prefer Apple frameworks over third-party deps. Stay AppKit-first unless asked otherwise.

## Layout

`App/` lifecycle and UI, `Core/` routing/config/launch, `Tests/`, `Fixtures/` for harness apps.

## Invariants

Single routing pipeline for incoming URLs. Sender detection is fragile; document real limits. Helium/profile behavior is browser-specific, not generic guessing.

## Workflow

TDD where practical: tests updated with code and must pass before done. Subagents OK for parallel work; primary agent integrates and **verifies** subagent changes.

## Editing

- No fallbacks unless asked. One source of truth per datum. Error handling yes; silent recovery / alternate legacy paths -- no. 
- No need to add legacy support - build for the modern user. 
- Do not worry about backwards compatibility - the only user of this project is me. Breaking/sweeping changes are fine.
- We prefer errors to be surfaced and fixed -- caught by tests instead of handling prematurely - which can introduce silent paths and functionality that is not asked for/that you forget to update all references to.
- Do not duplicate data/types used throughout. There should be a single source of truth for all data/interfaces that are used throughout. Do not define data/interfaces randomly in middle of files.
- Please always type check.
- Prefer asking the user questions when something isn't working as expected/ambiguous as much as possible - do not make random assumptions.
- Minimal diffs, no whitespace-only churn, no deleting comments or unrelated code without ask, no reverting user work without ask.
