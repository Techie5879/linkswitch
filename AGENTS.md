# AGENTS.md

## Scope

Native macOS app that registers as the `http` / `https` URL handler, routes opens by **source app bundle ID** (first-class case: Slack to Helium with a Chromium-style work profile), and sends everything else to a **user-chosen fallback browser** stored in config. Minimal preferences UI for fallback browser and per-source rules; config persisted explicitly (do not infer fallback from Launch Services once this app is the handler). Firefox-family fallback browsers may target real `profiles.ini` profiles, and Zen fallback routing may target container identities through the explicit extension-based `ext+container:` flow. No domain/URL pattern routing, no chooser UI, no Safari profile support, no generic extension platform support beyond that explicit Zen container handoff, and no interception outside the normal URL-handler path.

## Stack

`Swift`, `AppKit`, `Foundation`, Launch Services / `CoreServices`, `NSWorkspace`, `XCTest`. Prefer Apple frameworks over third-party deps. Stay AppKit-first unless asked otherwise.

## Layout

`App/` lifecycle and UI, `Core/` routing/config/launch, `Tests/`, `Fixtures/` for harness apps.

## Invariants

Single routing pipeline for incoming URLs. Sender detection is fragile; document real limits. Helium/profile behavior is browser-specific, not generic guessing.

## Workflow

TDD where practical: tests updated with code and must pass before done. Subagents OK for parallel work; primary agent integrates and **verifies** subagent changes.
- After feature changes or bug fixes, always rebuild and reinstall the dev app before finishing the task.
- If the next step requires the user to do something in Xcode UI, stop and ask for that action explicitly, then wait for the user to confirm it is done before continuing implementation.

## Observability

- Add detailed logging early instead of waiting for a bug to force it later.
- Prefer logging the important inputs, decisions, outputs, and failures for routing, config I/O, Launch Services interactions, browser launches, and test/integration flows.
- During the current development phase, keep runtime log artifacts project-local when possible so they are easy to inspect. Production log destination changes must be explicitly requested.
- When running builds or tests, preserve and reference the command output so logs remain available for later debugging. If Xcode swallows test stdout, also use the runtime log artifact produced by the app/code under test.
- Do not hide missing data or unexpected states behind silent behavior. Log them explicitly, then surface the error or route according to the current rules.

## Editing

- No fallbacks unless asked. One source of truth per datum. Error handling yes; silent recovery / alternate legacy paths -- no. 
- No need to add legacy support - build for the modern user. 
- Do not worry about backwards compatibility - the only user of this project is me. Breaking/sweeping changes are fine.
- We prefer errors to be surfaced and fixed -- caught by tests instead of handling prematurely - which can introduce silent paths and functionality that is not asked for/that you forget to update all references to.
- Do not duplicate data/types used throughout. There should be a single source of truth for all data/interfaces that are used throughout. Do not define data/interfaces randomly in middle of files.
- Please always type check.
- Prefer asking the user questions when something isn't working as expected/ambiguous as much as possible - do not make random assumptions.
- Minimal diffs, no whitespace-only churn, no deleting comments or unrelated code without ask, no reverting user work without ask.
