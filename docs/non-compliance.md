# Non-compliance

This document describes what about the current state of the project is not in compliance with the documentation.
This document is not append-only, and should always be reevaluated by the human after changes have been made.
Each non-compliance item shall be given a unique id, like NON-000, that may be referenced in plan.md
This section of the document must not change. Everything after here may.
Next id: NON-011
## Code

### NON-001: Undo/Redo not implemented
**Spec**: docs/spec/undo-redo.md (UNDO-1 through UNDO-6)
**Status**: Not implemented
**Details**: Decision 001-undo-redo.md was accepted but no implementation exists. No undo/redo commands, history stack, or redo functionality. Requirement EDIT-1 in nondestructive-editing.md also depends on this.

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

## Tests

### NON-005: No undo/redo tests
**Spec**: docs/spec/undo-redo.md
**Status**: Missing
**Details**: No test files for undo/redo functionality.

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
