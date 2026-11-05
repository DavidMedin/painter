# Diagnostics: Behavior

Behavior of the Diagnostics pane, a developer tool that adds no artist-facing behavior. Notation: [EARS+](../README.md#requirement-notation-ears). Implementation is in [debug-pane](debug-pane.md).

## Visibility

- **PNT-DGN-001** WHEN the Painter launches, the Painter shall hide the Diagnostics pane and show the blank Canvas.
  Source: [debug-pane](debug-pane.md).
- **PNT-DGN-002** WHEN the user presses F3, the Pane System shall toggle a docked Diagnostics pane (see [panes](../panes/behavior.md#shortcuts)).
  Source: [debug-pane](debug-pane.md).
- **PNT-DGN-003** WHILE the Diagnostics pane is visible, the Canvas shall remain usable for input in its own pane.
  Source: [debug-pane](debug-pane.md).

## Readouts

- **PNT-DGN-004** The Diagnostics pane shall show tile-cache counters, per-frame tile classification, and recording-time history for the Canvas it reads.
  Source: [debug-pane](debug-pane.md).
- **PNT-DGN-005** The Diagnostics pane shall provide a Pause control that stops the periodic refresh of its readouts.
  Source: [debug-pane](debug-pane.md).
- **PNT-DGN-012** WHEN the user takes an action in the Diagnostics pane that changes what a readout shows, the Diagnostics pane shall refresh its readouts even while paused.
  Source: [debug-pane](debug-pane.md).
- **PNT-DGN-006** The Diagnostics pane shall provide a copyable text report that agrees with the readouts on screen.
  Source: [debug-pane](debug-pane.md).

## Controls

- **PNT-DGN-007** The Diagnostics pane shall let the user change the maximum number of tile rasters in flight and the tile-cache size floor.
  Source: [debug-pane](debug-pane.md).
- **PNT-DGN-008** WHEN the user invalidates the cache from the Diagnostics pane, the Painter shall discard all tiles and generated splats while keeping the document.
  Source: [debug-pane](debug-pane.md).
- **PNT-DGN-009** WHEN the user resets the viewport from the Diagnostics pane, the Painter shall reset the selected Canvas viewport.
  Source: [debug-pane](debug-pane.md).

## Overlays

- **PNT-DGN-010** WHERE an overlay switch is on, the Canvas shall draw that overlay (tile tints, grid, tile coordinates, or the visible rectangle) so that it follows pan, zoom, and rotation.
  Source: [debug-pane](debug-pane.md).
- **PNT-DGN-011** The Diagnostics pane shall draw its colors from the active theme.
  Source: [theme-and-palettes](../settings/theme-and-palettes.md).
