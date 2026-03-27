# Deferred User-Gated TODOs

This file is a holding area for follow-up work that must not be done autonomously.

Rules for this file:

- Items listed here must only be implemented after the user explicitly asks for them.
- The request should explicitly point to this file or clearly reference the specific deferred item.
- Do not proactively complete these TODOs during normal implementation, even if they seem like the obvious next step.

## Deferred TODOs

### Logging location productionization

Keep logs project-local during the current development phase.

Do later only on explicit user request:

- move runtime logs from project-local development storage to a production-appropriate app/runtime location
- revisit the exact macOS destination when the app is being productionized
- update docs and logging behavior at the same time so the logging path stays a single source of truth

### Re-enable App Sandbox for productionization

App Sandbox is currently disabled during development so the app can write repo-local logs.

Do later only on explicit user request:

- re-enable `App Sandbox` in Xcode when the app is being productionized
- update runtime logging to use a sandbox-compatible destination at the same time
- verify any file access or browser-launch behavior affected by the sandboxed runtime
