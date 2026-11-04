# Pane viewports and fixed canvas paper

## Status

Accepted and implemented as an out-of-roadmap canvas and UI enhancement.

## Context

Multiple Canvas panes can show the same document at once. A pan, zoom, or
rotation stored with the shared document controller couples the views, while
canvas paper tied to the app palette changes the painting surface with the UI
theme. Stored custom palettes may already contain the old `canvasBackground`
key.

## Decision

- `CanvasController` owns the shared `CanvasDocument` and active stroke state.
  Each Canvas pane gets a distinct `CanvasViewportController` for pan, zoom,
  rotation, and coordinate conversion. Every view observes the shared document
  but applies its own viewport transform.
- Opening a document resets every current pane viewport. View transforms remain
  transient and do not enter the saved document format.
- `CanvasView` paints paper with fixed white `CanvasView.paperColor`, regardless
  of app theme. `canvasBackground` is not a `PainterTheme` or
  `PainterThemeColors` role; semantic diagnostic colors remain theme-driven.
- Loading custom palettes ignores the legacy extra `canvasBackground` JSON key.
  Newly serialized palettes omit it.

## Consequences

- Canvas panes share document edits while pan, zoom, and rotation remain
  independent. Opening a file returns every existing Canvas pane to its default
  view.
- Light, dark, and custom UI palettes do not recolor canvas paper; existing
  palette records remain loadable without a migration.
- Headless tests cover independent viewport interaction, document-open reset,
  legacy palette loading, and a dark-theme pixel sample of the white canvas.
- This decision supersedes the canvas-paper palette role in
  [ADR 0011](0011-theme-settings-and-saved-palettes.md).
