# Canvas

## Scope
The image content of a document and how a **Canvas Pane** shows it.
Out of scope: how strokes are stored in a file (see document-file.md); undo (see undo-redo.md).

## Definitions
- **Canvas**: The image content.
- **View of a canvas**: The portion of a **Canvas** that is rendered within a **Canvas Pane**.
- **Canvas Pane**: A pane that is in canvas mode. This pane shows the **View of a canvas**.
- **View extent**: The length of **Canvas** that a **View of a canvas** spans across its **Canvas Pane**'s shorter side.

## Requirements
CNVS-1 - The system shall allow the canvas to be infinitely sized.
CNVS-2 - The system shall allow the canvas to be finitely sized.
CNVS-3 - The system shall allow the user to pan, rotate, and scroll their view of the canvas within a pane.
CNVS-4 - Each canvas shows some view of a Canvas within the currently active document.
CNVS-5 - Retired.
CNVS-6 - The system shall treat the **View of a canvas** as the Per-mode state of its **Canvas Pane**.
CNVS-7 - The system shall define a **View of a canvas** by the point of the **Canvas** at the center of its **Canvas Pane**, its **View extent**, and its rotation, independent of the **Canvas Pane**'s size in pixels.
CNVS-8 - When a **Canvas Pane** is resized, the system shall keep the same point of the **Canvas** at its center and the same **View extent**.
CNVS-9 - The system shall keep every **View extent** between 64 and 10240 units of the **Canvas**.

## Acceptance Examples
- Two windows of different sizes show the same **View of a canvas**: the same point is at the center of both **Canvas Panes**, and the same stretch of **Canvas** spans each pane's shorter side.
- Drag a **Splitter** to make a **Canvas Pane** half as wide while its width is its shorter side: the drawing at its center stays centered and appears half as large.

## Open Questions
None.
