# Undo / Redo

Scope: reversing and reapplying edits to the active document.
Out of scope: undo across documents; collaborative undo.

## Definitions
- **Edit**: one user gesture that changes the document, such as a stroke from pointer-down to pointer-up.
- **History**: the ordered list of edits since the document was opened or last saved-and-closed.

## Requirements

UNDO-1  When the user triggers undo and history is non-empty,
        the system shall revert the most recent edit and move it to the redo stack.

UNDO-2  When the user triggers undo and history is empty,
        the system shall leave the document unchanged and give no error.

UNDO-3  When the user performs a new edit while the redo stack is non-empty,
        the system shall discard the redo stack.

UNDO-4  While a stroke is in progress,
        the system shall not apply undo or redo.

UNDO-5  The system shall retain at least 100 edits of history per document.
        When the limit is exceeded, the system shall drop the oldest edit first.

UNDO-6  If memory pressure prevents recording an edit,
        then the system shall still apply the edit and warn the user that
        it cannot be undone.

## Acceptance examples
- Draw A, draw B, undo → only A visible. Redo → A and B visible.
- Draw A, undo, draw C, redo → no effect (redo stack was discarded by C).
- Hold pointer down mid-stroke, press undo → nothing happens; stroke completes normally.

## Open questions
- Should undo of a layer deletion restore the layer's position in the stack? (Proposed: yes.)
