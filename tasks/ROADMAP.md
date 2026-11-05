# Roadmap

The [task workflow](README.md) defines the canonical backlog rules and required fields. Acceptance criteria are EARS+ requirements (see [notation](../docs/design/README.md#requirement-notation-ears)); IDs are `PNT-T<task>-<NN>`, for example `PNT-T001-01`.

## T-001 — Define the macOS MVP

- **Priority:** P0
- **Status:** done
- **Dependencies:** none
- **Outcome:** A product brief that resolves the first user workflow, MVP canvas interactions, document/file lifecycle, and measurable acceptance scenarios.
- **Acceptance criteria:**
  - **PNT-T001-01** The project shall record the T-001 decisions and scenarios in the behavioral documents under `docs/design/`, indexed from `docs/project-brief.md`.
  - **PNT-T001-02** The behavioral documents shall distinguish the first painting workflow (T-004, `docs/design/canvas/behavior.md`) from save/open/export behavior (T-005, `docs/design/document/behavior.md`).
  - **PNT-T001-03** WHERE file operations are in the MVP, the behavioral documents shall state the expected observable behavior of a failed file operation.
  - **PNT-T001-04** IF an item is unresolved, THEN the behavioral document of the affected system shall list it explicitly as an open question and shall not assume it silently.

## T-002 — Bootstrap and run the macOS Flutter application

- **Priority:** P0
- **Status:** done
- **Dependencies:** none
- **Outcome:** A runnable Flutter/Dart app targeting macOS.
- **Acceptance criteria:**
  - **PNT-T002-01** WHEN the app is launched on macOS, the Painter shall start.
  - **PNT-T002-02** The baseline automated checks shall pass.
  - **PNT-T002-03** The project shall document the exact commands and observed results in `docs/status.md`.

## T-003 — Select and record the canvas architecture

- **Priority:** P0
- **Status:** done
- **Dependencies:** T-001, T-002
- **Outcome:** Evidence-backed choices for rendering/canvas, state management, document representation, and platform integration.
- **Acceptance criteria:**
  - **PNT-T003-01** A runnable focused prototype or equivalent direct evidence shall exercise the selected canvas approach against the T-001 scenarios.
  - **PNT-T003-02** The project shall record the choices and consequences in a design document under `docs/design/`.
  - **PNT-T003-03** The project shall summarize the choices in `docs/design/architecture-overview.md`.

## T-004 — Deliver the first macOS painting workflow

- **Priority:** P0
- **Status:** done
- **Dependencies:** T-001, T-002, T-003
- **Outcome:** An end-to-end implementation of the first painting workflow specified by T-001, excluding the save/open/export behaviors assigned to T-005.
- **Acceptance criteria:**
  - **PNT-T004-01** The Painter shall pass each T-001 first-workflow scenario on the macOS app.
  - **PNT-T004-02** The project shall smoke-test the specific user-visible path.

## T-005 — Implement saved-document behavior

- **Priority:** P1
- **Status:** blocked
- **Dependencies:** T-001, T-003, T-004
- **Outcome:** The save/open behavior specified by T-001 works in the macOS app; export is explicitly out of MVP scope.
- **Acceptance criteria:**
  - **PNT-T005-01** The Painter shall pass the T-001 document round-trip scenario.
  - **PNT-T005-02** IF a T-001 file-operation failure scenario occurs, THEN the Painter shall produce that scenario's specified observable behavior.

## T-006 — Assess cross-platform readiness

- **Priority:** P1
- **Status:** todo
- **Dependencies:** T-004
- **Outcome:** An evidence-backed recommendation for the rollout order of Linux, Windows, and Android after the macOS workflow exists.
- **Acceptance criteria:**
  - **PNT-T006-01** The project shall document platform-specific constraints and a recommended next target in `docs/design/architecture-overview.md`.
  - **PNT-T006-02** WHEN the rollout order is decided, the project shall create follow-up roadmap task(s) for concrete validation work.
  - **PNT-T006-03** The project shall not create follow-up validation tasks before the rollout order is decided.
  - **PNT-T006-04** The project shall not claim support for, or begin implementation on, a future target within this assessment task.

## T-007 — Implement theme settings and saved palettes

- **Priority:** P1
- **Status:** done
- **Dependencies:** none
- **Outcome:** App-wide theme mode, independent light/dark palettes, and persistent user-created themes in selectable Settings pane content.
- **Acceptance criteria:**
  - **PNT-T007-01** The Settings shall support System, Light, and Dark modes, Gruvbox Light and Gruvbox Dark defaults, independent brightness-specific selection, and custom named palettes with editable color roles.
  - **PNT-T007-02** The settings store shall persist the mode and the independent palette choices and shall restore them.
  - **PNT-T007-03** IF the stored settings JSON is malformed, THEN the settings store shall fall back to defaults.
  - **PNT-T007-04** WHILE a theme is selected, the Painter shall draw program UI and diagnostics colors from that theme and shall keep painting independent of it.
  - **PNT-T007-05** The Canvas shall draw its paper as fixed white. This supersedes the original canvas-paper requirement per [theme-and-palettes](../docs/design/settings/theme-and-palettes.md).
  - **PNT-T007-06** Headless tests shall cover selection, custom palette creation and editing, serialization, persistence, and the themed tile-state colors.
  - **PNT-T007-07** `flutter analyze` and the macOS Release build shall pass.

## T-008 — Implement structured application logging

- **Priority:** P1
- **Status:** done
- **Dependencies:** T-002
- **Outcome:** The macOS app records structured file-backed logs, exposes them in the shell, and can optionally mirror readable records to stdout.
- **Acceptance criteria:**
  - **PNT-T008-01** The Logger shall write JSONL records containing a UTC timestamp, a severity, a message-catalog ID, formatting arguments, and an optional stack trace.
  - **PNT-T008-02** The Logger shall not store rendered message prose in a record.
  - **PNT-T008-03** IF a file operation fails, a settings load fails, a Flutter framework error occurs, or an unhandled platform error occurs, THEN the Painter shall report it through the shared Logger.
  - **PNT-T008-04** WHERE `--log-to-stdout` is present, the Logger shall mirror readable records to stdout without replacing persistence.
  - **PNT-T008-05** The Painter shall show the latest record in a bottom status bar.
  - **PNT-T008-06** The selectable Log pane shall display chronological history with the newest entry at the bottom.
  - **PNT-T008-07** Focused tests shall verify persistence and reload, formatting, optional stdout, file-operation logging, status updates, and pane ordering.
  - **PNT-T008-08** `flutter analyze` and a headless app smoke scenario shall pass.

## T-009 — Install EARS+ specification skills

- **Priority:** P1
- **Status:** done
- **Dependencies:** none
- **Outcome:** Project-local agent skills that guide EARS+ requirement authoring and specification-driven changes using Painter's existing design and roadmap conventions.
- **Acceptance criteria:**
  - **PNT-T009-01** The project shall provide an agent skill for creating and reviewing EARS+ requirements that follows the notation and document rules in `docs/design/README.md` and `tasks/README.md`.
    Source: project owner.
  - **PNT-T009-02** WHEN non-trivial implementation work begins, the project shall provide an agent skill that uses the canonical roadmap task and system design documents to drive implementation and verification.
    Source: project owner.
  - **PNT-T009-03** The project shall keep the roadmap as its single canonical task list and shall not require a parallel spec, plan, or task artifact chain.
    Source: project owner.

## T-010 — Close verified conformance gaps in implemented systems

- **Priority:** P1
- **Status:** done
- **Dependencies:** T-004, T-007, T-008
- **Outcome:** The implemented Canvas cache, settings, document error reporting, contextual help, touch targets, and diagnostic controls conform to their accepted behavioral and engineering requirements.
- **Acceptance criteria:**
  - **PNT-T010-01** WHEN a document is replaced or the tile cache is invalidated while splat generation is pending, THEN the TileCache shall ignore the completion from the prior cache revision.
    Source: PNT-A0005-31; PNT-DGN-008.
  - **PNT-T010-02** IF settings persistence or a document operation fails, or a splat-worker error occurs, THEN the shared Logger shall record the error even when its UI context is unmounted, and the Painter shall continue running.
    Source: PNT-ERR-004; PNT-A0014-07.
  - **PNT-T010-03** The Settings pane shall let users create, edit, and save custom palettes without changing built-in palettes.
    Source: PNT-THM-004.
  - **PNT-T010-04** WHEN an interactive Manual or Log pane control is hovered or focused, THEN it shall provide a concise hint and resolve its contextual help topic.
    Source: PNT-UX-017.
  - **PNT-T010-05** WHEN enlarged touch targets are enabled, THEN Manual navigation and pane menu/dropdown targets shall be at least 56 logical pixels high.
    Source: PNT-UX-008.
  - **PNT-T010-06** Every button in the custom-palette dialog shall have a leading action icon.
    Source: PNT-UX-002.
  - **PNT-T010-07** Comments changed by this task shall remain accurate, wrap at 80 columns, and cite design decisions by repository paths under `docs/design/`.
    Source: PNT-A0007-11; PNT-A0007-12; PNT-A0007-13.

