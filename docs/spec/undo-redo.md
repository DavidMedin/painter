# Undo / Redo

## Scope
Reversing and reapplying a user's own edits to the active document, alone or in a **Session**.
Out of scope: undo across documents; undo of **Workspace** changes (see workspace.md WKSP-6).

## Definitions
Terms defined in multiplayer.md are used here with the same meaning: **Session**, **Participant**.
- **Edit**: one user gesture that changes the document, such as a stroke from pointer-down to pointer-up.
- **History**: the ordered list of a **Participant**'s own **Edits** to a document since it was opened or joined.

## Requirements

UNDO-1 - When the user triggers undo and their **History** has an **Edit** that is not undone, the system shall revert the most recent such **Edit** and move it to the redo stack.
UNDO-2 - When the user triggers undo and their **History** has no **Edit** that is not undone, the system shall leave the document unchanged and give no error.
UNDO-3 - When the user performs a new **Edit** while the redo stack is non-empty, the system shall discard the redo stack.
UNDO-4 - While a stroke is in progress, the system shall not apply undo or redo.
UNDO-5 - The system shall retain at least 100 **Edits** of **History** per document, dropping the oldest **Edit** first when the limit is exceeded.
UNDO-6 - If memory pressure prevents recording an **Edit**, then the system shall still apply the **Edit** and warn the user that it cannot be undone.
UNDO-7 - When a **Participant** triggers undo or redo, the system shall leave every **Edit** of every other **Participant** in place.
UNDO-8 - When a **Participant** undoes a stroke, the system shall keep every stroke of other **Participants**, including strokes drawn over the undone one.
UNDO-9 - When the user triggers redo and the redo stack is non-empty, the system shall reapply the most recently undone **Edit** and move it back to the **History**.

## Acceptance examples
- Draw A, draw B, undo → only A visible. Redo → A and B visible.
- Draw A, undo, draw C, redo → no effect (redo stack was discarded by C).
- Hold pointer down mid-stroke, press undo → nothing happens; stroke completes normally.
- In a **Session**, P1 draws A, P2 draws B over A, P1 undoes → B stays, A disappears for both. P2 undoes → B disappears.

## Open questions
- Should undo of a layer deletion restore the layer's position in the stack? (Proposed: yes.)
