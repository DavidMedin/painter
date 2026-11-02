# Roadmap

The [task workflow](README.md) defines the canonical backlog rules and required fields.

## T-001 — Define the macOS MVP

- **Priority:** P0
- **Status:** done
- **Dependencies:** none
- **Outcome:** A product brief that resolves the first user workflow, MVP canvas interactions, document/file lifecycle, and measurable acceptance scenarios.
- **Acceptance criteria:**
  - Write the decisions and scenarios in `docs/project-brief.md`.
  - Distinguish the first painting workflow (T-004) from save/open/export behavior (T-005).
  - Include expected observable behavior for a failed file operation if file operations are in the MVP.
  - Leave unresolved items explicitly listed rather than silently assumed.

## T-002 — Bootstrap and run the macOS Flutter application

- **Priority:** P0
- **Status:** done
- **Dependencies:** none
- **Outcome:** A runnable Flutter/Dart app targeting macOS.
- **Acceptance criteria:**
  - The app launches on macOS.
  - Baseline automated checks pass.
  - Document the exact commands and observed result in `docs/status.md`.

## T-003 — Select and record the canvas architecture

- **Priority:** P0
- **Status:** done
- **Dependencies:** T-001, T-002
- **Outcome:** Evidence-backed choices for rendering/canvas, state management, document representation, and platform integration.
- **Acceptance criteria:**
  - A runnable focused prototype or equivalent direct evidence exercises the selected canvas approach against T-001 scenarios.
  - Record choices and consequences in an ADR.
  - Summarize the choices in `docs/architecture.md`.

## T-004 — Deliver the first macOS painting workflow

- **Priority:** P0
- **Status:** done
- **Dependencies:** T-001, T-002, T-003
- **Outcome:** An end-to-end implementation of the first painting workflow specified by T-001, excluding the save/open/export behaviors assigned to T-005.
- **Acceptance criteria:**
  - Each T-001 first-workflow scenario passes on the macOS app.
  - Smoke-test the specific user-visible path.

## T-005 — Implement saved-document and export behavior

- **Priority:** P1
- **Status:** todo
- **Dependencies:** T-001, T-003, T-004
- **Outcome:** The save/open/export behavior specified by T-001 works in the macOS app.
- **Acceptance criteria:**
  - T-001 round-trip and export scenarios pass.
  - Any T-001 file-operation failure scenario produces its specified observable behavior.

## T-006 — Assess cross-platform readiness

- **Priority:** P1
- **Status:** todo
- **Dependencies:** T-004
- **Outcome:** An evidence-backed recommendation for the rollout order of Linux, Windows, and Android after the macOS workflow exists.
- **Acceptance criteria:**
  - Document platform-specific constraints and a recommended next target in `docs/architecture.md`.
  - Create follow-up roadmap task(s) for concrete validation work only after the rollout order is decided.
  - Do not claim support for or begin implementation on a future target in this assessment task.
