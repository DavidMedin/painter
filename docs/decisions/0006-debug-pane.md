# An ImGui-style debug pane for the tile cache

## Status

Accepted. A developer tool; it adds no artist-facing behavior. Builds on [ADR 0005](0005-tiled-texture-cache.md).

## Context

The tile cache of ADR 0005 is asynchronous and keeps most of its state private (what is cached, queued, building, stale, or drawn from a scaled fallback). Its correctness claims (a stale tile stays visible, a coarser level is shown scaled until the right one lands, only touched tiles rebuild) could be checked only through pixel tests. There was no way to see them in a running app, to compare tuning values (`maxInFlight`, `maxTiles`), or to attach a snapshot to a bug report.

## Decision

- **Dense, flat, monospace "immediate-mode look".** `lib/debug/imgui.dart` is a small widget kit modeled on Dear ImGui, written with ordinary Flutter widgets. It has tree-style collapsible sections; label/value rows; checkbox, button, integer slider; line plot; stacked bar; legend. It is **not** an immediate-mode engine and takes no dependency: widgets are retained and rebuild normally. It knows nothing about the painter.
- **Data flows one way.** The core records facts and the pane only reads them:
  - `TileCache.counters` (`TileCacheCounters`): requests, builds split into full/incremental/skipped, evictions, queue drops, splats generated and rastered, and a bounded history of build milliseconds.
  - `TiledRenderer.frame` (`TileFrameStats`): per frame, how every visible tile was drawn (`TileDraw`: current, stale, coarser fallback, finer fallback, missing, blank) and the draw-recording time, plus a bounded history of it.
  - `TileCache` read accessors (`queued`, `wantedTiles`, `imageTiles`, `generatedStrokes`, `splatBytes`, `describeTiles()`, `peek()`), and two writes: `maxInFlight` and `maxTiles` are now mutable, and `invalidateAll()` discards tiles and splats while keeping the document.
  - `CanvasController.resetViewport()`.
- **Overlays draw in the canvas.** `CanvasDebugOptions` (a `ChangeNotifier`) holds overlay switches. `CanvasView` takes optional `debugOptions` and `onRenderer`; with options set it calls `paintTileOverlay` inside the document transform, so tints, grid, tile coordinates, and the visible rectangle follow pan, zoom, and rotation.
- **Frozen snapshot.** The pane reads one `_Reading` copy per refresh (250 ms timer, not per canvas frame) so the readouts, the Pause control, and the copied text report cannot disagree.
- **Hidden by default.** The app opens to the blank Canvas. F3 toggles a docked Diagnostics pane; see [ADR 0010](0010-pane-system.md) for pane layout and renderer ownership.

## Consequences

- Cost while no Diagnostics pane is visible: counters and per-frame classification still run (a few integer increments and one map entry per visible tile per frame). While visible: one snapshot every 250 ms.
- `maxInFlight` and `maxTiles` changes take effect immediately; lowering `maxTiles` evicts on the next completed build, not instantly.
- Diagnostics occupies a pane beside the Canvas rather than overlapping it. Canvas input remains available in its own pane.
- The pane's numbers are UI-thread recording times, not raster or GPU time; counter overhead has not been benchmarked.
- Not verified: appearance in the running macOS window (no windowed run was permitted by [testing.md](../testing.md)), the Menlo font (test renders use Ahem), and behavior with a very large document or extreme zoom.
- [ADR 0010](0010-pane-system.md) supersedes this ADR's former floating-window placement; this ADR remains authoritative for diagnostics data, controls, overlays, and refresh behavior.
