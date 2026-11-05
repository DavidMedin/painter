# ImGui-Style Debug Pane for the Tile Cache

Design for the developer Diagnostics pane that makes the asynchronous tile cache observable. Observable behavior is in [behavior](behavior.md). The cache it observes is in [tile-cache](../canvas/tile-cache.md). Notation: [EARS+](../README.md#requirement-notation-ears).

## Status

Accepted and implemented. A developer tool that adds no artist-facing behavior. Formerly ADR 0006; its floating-window placement was replaced by the docked [pane system](../panes/pane-system.md), and this document remains authoritative for diagnostics data, controls, overlays, and refresh behavior.

## Context

The tile cache is asynchronous and keeps most of its state private (what is cached, queued, building, stale, or drawn from a scaled fallback). Its correctness claims (a stale tile stays visible, a coarser level is shown scaled until the right one lands, only touched tiles rebuild) could be checked only through pixel tests. There was no way to see them in a running app, to compare tuning values (`maxInFlight`, `maxTiles`), or to attach a snapshot to a bug report.

## Decision

### Widget kit

- **PNT-A0006-01** The `lib/debug/imgui.dart` shall be a small widget kit modeled on Dear ImGui, written with ordinary Flutter widgets, providing tree-style collapsible sections, label/value rows, a checkbox, a button, an integer slider, a line plot, a stacked bar, and a legend.
- **PNT-A0006-02** The `lib/debug/imgui.dart` shall not be an immediate-mode engine.
- **PNT-A0006-16** The `lib/debug/imgui.dart` shall take no package dependency.
- **PNT-A0006-17** The `lib/debug/imgui.dart` widgets shall be retained and shall rebuild normally.
- **PNT-A0006-03** The `lib/debug/imgui.dart` shall have no knowledge of the painter.

### Data flow (one way)

- **PNT-A0006-04** The core (`TileCache`, `TiledRenderer`, `lib/canvas/tile_stats.dart`) shall only record facts and shall not import debug UI, and the pane shall only read them.
- **PNT-A0006-05** The `TileCache.counters` (`TileCacheCounters`) shall record requests, builds split into full, incremental, and skipped, evictions, queue drops, splats generated and rastered, and a bounded history of build milliseconds.
- **PNT-A0006-06** The `TiledRenderer.frame` (`TileFrameStats`) shall record, per frame, how every visible tile was drawn (`TileDraw`: current, stale, coarser fallback, finer fallback, missing, blank) and the draw-recording time, plus a bounded history of it.
- **PNT-A0006-07** The `TileCache` shall expose the read accessors `queued`, `wantedTiles`, `imageTiles`, `generatedStrokes`, `splatBytes`, `describeTiles()`, and `peek()`.
- **PNT-A0006-08** The `TileCache` shall make `maxInFlight` and `maxTiles` mutable.
- **PNT-A0006-18** The `TileCache` shall provide `invalidateAll()`, which discards tiles and splats while keeping the document.
- **PNT-A0006-09** The Painter shall provide `CanvasController.resetViewport()`.
- **PNT-ARC-052** The Diagnostics pane shall write only `maxInFlight`, `maxTiles`, `invalidateAll()`, the selected Canvas viewport's `resetViewport()`, and the overlay switches.

### Overlays

- **PNT-A0006-10** The `CanvasDebugOptions` (a `ChangeNotifier`) shall hold the overlay switches.
- **PNT-ARC-049** The `lib/debug/tile_overlay.dart` shall paint the canvas overlays.
- **PNT-A0006-11** The `CanvasView` shall take optional `debugOptions` and `onRenderer` parameters.
- **PNT-A0006-12** WHERE `debugOptions` is set, the `CanvasView` shall call `paintTileOverlay` inside the document transform, so that tints, grid, tile coordinates, and the visible rectangle follow pan, zoom, and rotation.

### Refresh and placement

- **PNT-A0006-13** The Diagnostics pane shall read one `_Reading` copy per refresh, on a 250 ms timer rather than per canvas frame, so that the readouts, the Pause control, and the copied text report cannot disagree.
- **PNT-ARC-047** The `CanvasDebugPane` shall be scrollable pane content and not a floating window.
- **PNT-A0006-14** WHEN the app launches, the Painter shall hide the Diagnostics pane and open to the blank Canvas.

Retired requirement IDs for this document are recorded in the [retired ID registry](../README.md#retired-requirement-ids).

## Consequences

- Cost while no Diagnostics pane is visible: counters and per-frame classification still run (a few integer increments and one map entry per visible tile per frame). While visible: one snapshot every 250 ms.
- `maxInFlight` and `maxTiles` changes take effect immediately. Lowering `maxTiles` evicts on the next completed build, not instantly.
- Diagnostics occupies a pane beside the Canvas rather than overlapping it. Canvas input remains available in its own pane.
- The pane's numbers are UI-thread recording times, not raster or GPU time. Counter overhead has not been benchmarked.
- Not verified: appearance in the running macOS window, the Menlo font (test renders use Ahem), and behavior with a very large document or extreme zoom.

## Regression Notes

- The pane once mixed frozen and live reads, so Pause did not freeze every readout and the copied report could disagree with the screen. The single frozen `_Reading` snapshot (PNT-A0006-13) fixes this, and a regression test covers it.
- The Diagnostics pane was once a floating window. Its drag, clamp, collapse, close, and sizing bugs are historical: the [pane system](../panes/pane-system.md) replaced that presentation, and current behavior is covered by the pane tests.
