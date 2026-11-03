# Project Brief

## Purpose

Create painting software using Flutter and Dart.

## Confirmed Scope

- Flutter/Dart is the intended application technology.
- macOS is the current target. Linux, Windows, and Android are future targets; their rollout order is undecided.
- The initial user is an artist.
- On launch without a file, the app opens directly to a blank canvas ready for painting; there is no splash screen.

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

## Errors

- A failed file operation displays a popup explaining the error, with an expandable area for more detailed information. This is the MVP behavior and may change later.
- Failed file operations, internal errors, and exceptions are logged to the terminal and do not terminate the program.
- Fatal errors terminate the program only after the error, stack trace, and other relevant information have been successfully logged.

## Acceptance and Verification Scenarios

- Launching without a file shows a blank, paint-ready canvas directly, with no splash screen.
- A mouse stroke changes the canvas with a pencil-speck brush using weight `1.0`; a stylus stroke changes it with a pencil-speck brush whose size responds to pressure. Pressure changes size only.
- Mouse input can pan, zoom, and rotate the canvas.
- Opening a file replaces the current canvas/document with the opened content. Saving and reopening a document preserves its content.
- A failed file operation shows the described popup and expandable details, is logged, and leaves the app running. A non-fatal internal error or exception is logged without terminating the app. A fatal error is logged with its stack trace and relevant information before termination.
- Unit tests cover applicable isolated behavior. Integration tests cover interactions between modular components, including drawing a stroke and verifying the resulting canvas/document change. The finished macOS build must also demonstrate the user-visible scenarios; tests alone are insufficient.

## Open Product and Technical Questions

- What is the default brush size, and what exact pressure-to-size mapping should the stylus use?
- Which mouse gestures or controls perform pan, zoom, and rotation?
- What should happen when opening another file would discard unsaved changes?
- Which errors are classified as fatal, and which logging library should be used? These implementation choices require later design/evidence.
