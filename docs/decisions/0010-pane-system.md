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

- `PaneSystem` owns pane identities, content kinds, a binary split tree, focus, and dividers. Each split chooses side-by-side or top-and-bottom and keeps independent child weights; its visibly marked 12-logical-pixel handle resizes only those children and clamps to the split extent when space is tighter. Right-clicking a handle offers split and close actions for the panes next to it. Each pane has a visibly emphasized top-left content selector, a Split menu with both directions, and a Close action when another pane remains. Focused borders are 2 logical pixels in the primary color; inactive borders use `outlineVariant`. Pane content sits on the active theme surface while Canvas paper remains fixed white. Headers use labeled actions at 180 logical pixels or wider, a compact action menu from 48 to 180 pixels, and no header control below 48 pixels. Closing a leaf collapses its parent into the sibling.
- Diagnostics is ordinary content inside its pane, not a floating window. F3 adds Diagnostics beside a Canvas pane using a side-by-side split and removes it on the next press; if Diagnostics is the sole pane, F3 changes it back to Canvas.
- The app shell owns one `TiledRenderer` per pane and one `CanvasViewportController` per Canvas pane; all Canvas panes share the same document controller. Diagnostics reads the first Canvas pane's renderer and viewport, or its own retained renderer and viewport when no Canvas is visible.
- Pane layout state is runtime-only. The document model and saved-document
  format are unchanged.

## Consequences

- Canvas and Diagnostics can be visible at the same time without overlapping; users can resize or close a pane while at least one pane remains.
- Splits can be nested on either axis. Pane sizes and layout are not persisted.
- [ADR 0006](0006-debug-pane.md) remains the decision for diagnostics data,
  controls, overlays, and snapshot refresh behavior. This ADR supersedes its
  floating-window placement and the workspace-selector behavior from
  [ADR 0008](0008-discoverable-controls-workspaces-and-touch-targets.md).
- Verification uses headless widget tests. A macOS window was not opened, in
  accordance with [testing.md](../testing.md).
