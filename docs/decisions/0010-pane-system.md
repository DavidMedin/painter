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

- `PaneSystem` owns pane identities, content modes, horizontal split weights,
  focus, and boundary interactions. It starts with one Canvas pane. Every pane
  has a rounded outlined frame and a visible Pane Mode selector. Dragging an
  inner boundary changes only the widths of its adjacent panes.
- Right-clicking a boundary offers insertion on its outer side or between
  panes, plus deletion of either adjacent pane. The workspace may contain zero
  panes; its centered Open Canvas Pane action inserts a new Canvas pane.
- Diagnostics is ordinary content inside its pane, not a floating window. F3
  adds Diagnostics beside the focused pane and removes it on the next press; if
  the sole pane is Diagnostics, F3 changes it back to Canvas. F3 does nothing
  when the workspace is empty.
- The app shell retains one `TiledRenderer` per stable pane id across content
  mode changes and disposes it when that pane is removed or the app shuts down.
  Diagnostics reads the first visible Canvas renderer, or its own retained
  renderer if no Canvas pane is visible.
- Pane layout state is runtime-only. The document model and saved-document
  format are unchanged.

## Consequences

- Canvas and Diagnostics can be visible at once without overlapping. Boundary
  menus add panes beside or between existing panes and delete the adjacent
  pane; the last pane may be removed and a new Canvas pane opened later.
- The layout is a horizontal row of panes; nested or vertical splits and saved
  layouts are not implemented.
- [ADR 0006](0006-debug-pane.md) remains the decision for diagnostics data,
  controls, overlays, and snapshot refresh behavior. This ADR supersedes its
  floating-window placement and the workspace-selector behavior from
  [ADR 0008](0008-discoverable-controls-workspaces-and-touch-targets.md).
- Verification uses headless widget tests. A macOS window was not opened, in
  accordance with [testing.md](../testing.md).
