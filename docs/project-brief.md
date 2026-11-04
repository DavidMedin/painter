# Project Brief

## Purpose

Create painting software using Flutter and Dart.

## Confirmed Scope

- Flutter/Dart is the intended application technology.
- macOS is the current target. Linux, Windows, and Android are future targets; their rollout order is undecided.
- The initial user is an artist.
- On launch without a file, the app opens directly to a blank canvas ready for painting; there is no splash screen.
- Appearance supports System, Light, and Dark modes. Light and dark palettes are
  selected independently; Gruvbox Light and Gruvbox Dark are built in, and the
  user can create and save custom palettes.
- Program UI colors, including canvas paper and diagnostics, follow the active
  palette. Canvas marks remain painting content rather than UI theme colors.
- Appearance controls are available in selectable Settings pane content.

## First Painting Workflow (T-004)

- The canvas supports mouse and stylus drawing with a pencil-like brush: each stroke is rendered as many small gaussian splats (specks) that read as a pencil line from a distance. See [ADR 0004](decisions/0004-pencil-splat-stroke-rendering.md).
- Mouse drawing uses a fixed weight of `1.0`.
- Stylus drawing uses a weight relative to stylus pressure.
- Weight controls brush size only. There are no other brush settings in the MVP.
- The mouse can pan, zoom, and rotate the canvas.

## Document and File Lifecycle (T-005)

- The MVP supports opening and saving files; it does not support export.
- The user can open or save through a UI element.
- A launch without a file creates a blank, unsaved canvas. Opening a file replaces the current canvas/document.
	- Saving persists the current document. The exact behavior for saving a document that has no associated file is not yet specified.

## Killer Features

These features distinguish Painter and require deliberate design.

### Node Graph Brushes

Every brush, from hard digital to oil and pencil, is defined by a node graph.

Graphs may need compilation to sustain thousands of evaluations per second. The technology is undecided; start with the simplest runnable evaluator. Initially, only brushes use graphs; magic wand and lasso behavior is undecided.

### Node Graph Composition

Painter has no conventional layers. Canvas nodes can be layered, modified, and connected to a render/output node. Selecting a node shows its output in a preview; the selected canvas node is editable in the Canvas window.

### Everything is a vector

Brushes create mathematical marks, such as gaussian splats or tiny textures, which the Canvas Cache renders lazily. This supports arbitrary resolution and editing or undoing past strokes.

### Undo Undo Undo

Use an append-only database*: strokes, including eraser strokes, overlay existing content to preserve vector editability.

*Old data may be discarded when no longer relevant.

## Errors

- A failed file operation displays a popup explaining the error, with an expandable area for more detailed information. The failure is also recorded in the application log.
- Failed file operations, internal errors, and exceptions are logged to the persistent application log and do not terminate the program. `--log-to-stdout` optionally mirrors readable lines to stdout; JSONL records retain message-catalog IDs and formatting arguments rather than rendered prose.
- The latest record appears in the bottom status bar; the selectable Log pane shows records chronologically with the newest at the bottom.
- Fatal errors terminate the program only after the error, stack trace, and other relevant information have been successfully logged.

## Acceptance and Verification Scenarios

- Launching without a file shows a blank, paint-ready canvas directly, with no splash screen.
- A mouse stroke changes the canvas with a pencil-speck brush using weight `1.0`; a stylus stroke changes it with a pencil-speck brush whose size responds to pressure. Pressure changes size only.
- Mouse input can pan, zoom, and rotate the canvas.
- Opening a file replaces the current canvas/document with the opened content. Saving and reopening a document preserves its content.
- Theme mode follows the system or stays explicitly light/dark; separate light
  and dark palette selections and custom palette colors survive an app restart.
- A failed file operation shows the described popup and expandable details, is logged, and leaves the app running. A non-fatal internal error or exception is logged without terminating the app. A fatal error is logged with its stack trace and relevant information before termination.
- Unit tests cover applicable isolated behavior. Integration tests cover interactions between modular components, including drawing a stroke and verifying the resulting canvas/document change. The finished macOS build must also demonstrate the user-visible scenarios; tests alone are insufficient.

## UX

Accessibility is a core requirement; document any temporary gaps.

- Buttons have text, a leading action icon, and visible pressed feedback.
- Interactive elements have concise hover hints that add to, rather than repeat, their labels.
- Give distinct panes borders.
- Windows are modular: choose each window's content from a top-left selector, as in Blender.
- Make help available in-app for every interactive element; F1 opens help for the hovered control.

## UI

Keep the UI compact, useful, and configurable for touch. Blender is a visual reference.


## Open Product and Technical Questions

- What is the default brush size, and what exact pressure-to-size mapping should the stylus use?
- Which mouse gestures or controls perform pan, zoom, and rotation?
- What should happen when opening another file would discard unsaved changes?
- Which errors are classified as fatal? The logging implementation is recorded in ADR 0012; fatal classification and termination policy remain undecided.
