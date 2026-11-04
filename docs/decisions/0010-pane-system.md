# Docked pane system

## Status

Accepted and implemented as an out-of-roadmap UI enhancement.

## Context

The project brief requires modular work panes whose content is selected from a
control at each pane's top-left, with distinct pane borders. Painter has two
implemented pane contents: the canvas and the tile-cache diagnostics from
[ADR 0006](0006-debug-pane.md). The earlier workspace selector replaced the
canvas with diagnostics drawn as a floating overlay, which did not provide
multiple independently selected panes.

## Decision

- `PaneSystem` owns pane identities, content kinds, horizontal split weights,
  focus, and dividers. It starts with one Canvas pane. Each pane has a top-left
  content selector, a Split action that adds a neighboring pane with the other
  implemented kind, and a Close action when another pane remains. Dragging a
  divider changes the widths of only its adjacent panes.
- Diagnostics is ordinary content inside its pane, not a floating window. F3
  adds Diagnostics beside a Canvas pane and removes it on the next press; if the
  sole pane is Diagnostics, F3 changes it back to Canvas.
- The app shell owns one `TiledRenderer` per Canvas pane. A Diagnostics pane
  reads the first Canvas pane's renderer; if no Canvas exists, it explains that
  a Canvas pane is needed.
- Pane layout state is runtime-only. The document model and saved-document
  format are unchanged.

## Consequences

- The canvas and diagnostics can be visible at the same time without
  overlapping; users can resize or close a pane while at least one pane remains.
- The layout is a horizontal row of panes; nested or vertical splits and saved
  layouts are not implemented.
- [ADR 0006](0006-debug-pane.md) remains the decision for diagnostics data,
  controls, overlays, and snapshot refresh behavior. This ADR supersedes its
  floating-window placement and the workspace-selector behavior from
  [ADR 0008](0008-discoverable-controls-workspaces-and-touch-targets.md).
- Verification uses headless widget tests. A macOS window was not opened, in
  accordance with [testing.md](../testing.md).
