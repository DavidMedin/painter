# Non-compliance

This document describes what about the current state of the project is not in compliance with the documentation.
This document is not append-only, and should always be reevaluated by the human after changes have been made.
Each non-compliance item shall be given a unique id, like NON-000, that may be referenced in plan.md
This section of the document must not change. Everything after here may.
Next id: NON-012
## Code

### NON-002: Tabs not implemented
**Spec**: docs/spec/tabs.md
**Status**: Not implemented
**Details**: No tab bar, tab switching, or tab reordering. Only single document supported (via CanvasController in main.dart).

### NON-003: Keybinds not configurable
**Spec**: docs/spec/keybinds.md (KEY-1, KEY-2)
**Status**: Partial
**Details**: F1 (help) and F3 (debug) shortcuts exist in main.dart but:
- User cannot change any keybind (KEY-1 not met)
- No settings UI for keybind configuration (KEY-2 not met)

### NON-004: Headless CLI export not implemented
**Spec**: docs/spec/headless.md
**Status**: Not implemented
**Details**: No command-line interface for PNG export. No argparse or CLI entry point.

### NON-010: Pane toolbar is not compliant
spec: docs/spec/panes.md
status: non-compliant
details: the current toolbar implementation is using an old spec that is not present in the repo.

### NON-011: UNDO-6 memory-pressure warning not implemented
**Spec**: docs/spec/undo-redo.md (UNDO-6)
**Status**: Not implemented
**Details**: Undo history (docs/decisions/012-undo-per-participant.md) holds stroke ids and removed stroke data in memory; nothing detects memory pressure or warns that an edit cannot be undone.

## Tests

### NON-006: No tab tests
**Spec**: docs/spec/tabs.md
**Status**: Missing
**Details**: No test files for tab functionality.

### NON-007: No keybind configuration tests
**Spec**: docs/spec/keybinds.md
**Status**: Missing
**Details**: No tests for keybind settings or changes.

## Documentation

### NON-008: brush-engine.md has no requirements
**Spec**: docs/spec/brush-engine.md
**Status**: Empty
**Details**: Spec file exists but contains no requirements or acceptance criteria.

### NON-009: composite-engine.md has no requirements
**Spec**: docs/spec/composite-engine.md
**Status**: Empty
**Details**: Spec file exists but contains no requirements or acceptance criteria.
