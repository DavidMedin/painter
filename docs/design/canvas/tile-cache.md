# Tile Cache and Bounded Active Chunks

Design for how the Canvas caches rendered strokes as multi-resolution tiles and keeps long gestures responsive. Observable behavior is in [behavior](behavior.md). How splats are generated is in [pencil-splats](pencil-splats.md). Notation: [EARS+](../README.md#requirement-notation-ears).

## Status

Accepted and implemented. Combines the former ADRs 0005 (tile cache) and 0009 (bounded active chunks). Replaces per-frame replay of every stroke.

## Context

Drawing every stroke every frame, with one `drawRawAtlas` call per stroke, made frame cost grow with the total splat count (about 13 per document unit of stroke), including during pan, zoom, and rotate. Measured with a throwaway benchmark (`flutter test` debug binding, 1920×1080 view, strokes of 40 points), UI-thread display-list recording took 4.3 ms, 22 ms, and 79 ms per frame at 100, 500, and 2000 strokes.

A long pointer gesture that stays entirely live also grows its active splat batch without bound, even though the cache can already process strokes appended to `CanvasDocument`. The app has no undo behavior, and the saved document stores an ordered list of strokes without gesture identity.

## Decision

### Tiles

- **PNT-A0005-01** The Canvas shall compose the visible canvas from square textures (tiles) in a document-space grid.
- **PNT-A0005-02** Every tile shall be 512×512 device pixels.
- **PNT-A0005-03** A tile at level of detail (LOD) `L` shall rasterize `2^L` pixels per document unit and cover `512 / 2^L` document units per side.
- **PNT-A0005-04** The Canvas shall use LODs from -4 to 5, which spans the `0.1`–`16` zoom limits at device pixel ratios up to about 4.
- **PNT-A0005-05** The Canvas shall compute the LOD as `ceil(log2(zoom × devicePixelRatio) - 0.5)`, so that a tile is never magnified by more than √2.
- **PNT-A0005-06** The Canvas shall key tiles `(x, y, level)`, with geometry in the pure-Dart `lib/canvas/tile_grid.dart`.
- **PNT-A0005-07** Tile memory (1 MiB per tile) and raster cost per tile shall not depend on zoom.

Non-normative estimate: a viewport needs roughly 40 tiles at any zoom, and up to about 270 tiles at the lowest zoom with a rotated 1920×1080 viewport.

### Drawing over tiles

- **PNT-A0005-08** Each tile shall record how many document strokes it already contains.
- **PNT-A0005-09** WHEN a stroke is added, the `TileCache` shall draw only the strokes a tile has not applied, and that touch the tile, over the tile's previous image and shall not redraw earlier strokes.
- **PNT-A0005-10** WHEN no new stroke touches a tile, the `TileCache` shall leave that tile unchanged with no GPU work.
- **PNT-A0005-11** WHEN a splat straddles a tile edge, the `TileCache` shall draw it into both tiles, using a 2-unit bleed plus the splat extent in `PencilSplats.inkMargin`, so that tile seams are invisible.

### Lazy and asynchronous building

- **PNT-A0005-12** The `paint` method shall not build anything; it shall draw what is cached and call `TileCache.request` for what is missing or stale.
- **PNT-A0005-13** The `TileCache` shall queue requests and limit tile rasters in flight to 2.
- **PNT-A0005-14** WHEN a later frame no longer wants a queued request (such as after panning away), the `TileCache` shall drop it.
- **PNT-A0005-15** WHEN a tile finishes, the `TileCache` shall call `notifyListeners` so that the canvas repaints on its own.
- **PNT-A0005-16** The `SplatWorker` (in `lib/canvas/splat_worker.dart`) shall run splat generation in one long-lived worker isolate, with stroke points sent as a flat `Float64List` and the result returned as `TransferableTypedData`.
- **PNT-A0005-17** The Canvas shall generate each stroke's document-space splats once and reuse them for every tile and level.
- **PNT-A0005-18** The `TileCache` shall rasterize with `Picture.toImage`, which completes asynchronously.

### Stale and wrong-resolution tiles

- **PNT-A0005-19** WHILE a tile is stale, the Canvas shall draw it from its old image until its update lands.
- **PNT-A0005-20** WHILE a tile is missing at the target level, the Canvas shall draw it from the nearest cached coarser level, cropped and scaled up.
- **PNT-A0005-21** IF no coarser level is cached, THEN the Canvas shall draw from cached finer tiles scaled down.
- **PNT-A0005-22** The Canvas shall use one source per area so that ink is not doubled.
- **PNT-A0005-23** WHEN a replacement tile finishes, the Canvas shall swap it in.

### Eviction

- **PNT-A0005-24** The `TileCache` shall evict least-recently-used tiles, with a floor of 256 tiles that grows to twice the last frame's working set.
- **PNT-A0005-25** The `TileCache` shall not evict tiles that the last frame drew or fell back to, or tiles being built.

### Ownership and replacement

- **PNT-A0005-31** WHEN a different `CanvasDocument` is attached, the `TileCache` shall discard all tiles and generated splats.
- **PNT-A0005-32** The `TiledRenderer` (in `lib/canvas/tiled_renderer.dart`) shall own the sprite, the cache, and the active-stroke stream.
- **PNT-A0005-33** `CanvasController.activePoints` shall return the live read-only view instead of a copy, with a new instance per stroke.

### Bounded active chunks

- **PNT-A0009-01** The Canvas shall keep only a bounded tail live: at most 64 document units of accumulated path length and at most 64 sampled points.
- **PNT-A0009-02** The Canvas shall interpolate long pointer segments at the path-length limit.
- **PNT-A0009-03** WHEN either bound is reached, the Canvas shall append the completed chunk to the `CanvasDocument` with its next document seed and start a new active chunk at the shared endpoint.
- **PNT-A0009-04** The `TiledRenderer` shall keep the latest bounded chunk live.
- **PNT-A0009-05** WHEN a chunk rolls over, the `TiledRenderer` shall reuse that chunk's generated splat buffers as a temporary overlay wherever cached tile images lack the committed stroke, while the `TileCache` processes it through the normal asynchronous append path.
- **PNT-A0009-06** WHEN the pointer is released, the Canvas shall commit the final chunk.
- **PNT-A0009-07** The Painter shall keep the saved-document format unchanged, each committed chunk being an ordinary immutable `CanvasStroke`.

Retired requirement IDs for this document are recorded in the [retired ID registry](../README.md#retired-requirement-ids).

## Consequences

- Steady-state frame recording measured 0.03 ms, 0.01 ms, and 0.006 ms at 100, 500, and 2000 strokes (about 12 tiles drawn). A pan frame is at most 0.2 ms, and an active-stroke pointer move is about 0.06–0.08 ms median on a 300-point stroke. These are debug-binding UI-thread recording times, not on-screen frame or GPU times.
- Work moved to the background: warming every tile of a 2000-stroke document took about 1.5 s in the test binding. Until a tile lands, the user sees a scaled lower-resolution version or, for a region never drawn at any level, blank paper for a moment.
- Memory is about 1 MiB per cached tile (about 40 MiB for a typical viewport, more when rotated or zoomed far out, plus retained off-screen tiles up to the budget). Generated splat buffers are kept per stroke for the session and not evicted, so memory grows with total splat count (24 bytes per splat).
- A tile rebuilt after eviction is rebuilt from all strokes touching it, so panning back to an evicted region costs a full tile build.
- Drawing an incremental stroke over an old tile image re-samples it once per update. At LOD 0 the draw is 1:1 and matches direct drawing. Repeated updates at non-integer magnification were not measured for accumulated blur.
- Tiles are anchored to document space, so a stroke far from the origin still maps to ordinary tile indices (negative indices are covered by tests). Documents with very large extents were not tested.
- Splat completions belong to the cache revision and attached document: late
  results cannot repopulate splat buffers or counters after replacement,
  invalidation, or disposal. A worker failure is reported through the app's
  shared logger; affected tiles stay suppressed until the next cache revision,
  when invalidation or replacement permits a retry.
- The live splat batch is bounded for both long sparse segments and repeated zero-distance pointer events.
- One physical pointer gesture is stored as multiple document strokes. Chunk seeds are independent, so grain restarts at each boundary, and the shared endpoint is present in both adjacent chunks and may receive overlapping splats. Undo, if added, needs gesture grouping or must operate per chunk.
- Not verified: behavior in the running macOS window, raster-thread and GPU time and texture memory on real hardware, how the scaled-fallback transition looks to an artist, and physical stylus latency.

## Regression Notes

Bugs found while testing, each now covered by a regression test:

- `SynchronousFuture` inside `Future.wait` returned an empty list, so a tile whose strokes were already generated (the first zoom after drawing) was recorded blank.
- A constant `maxTiles` smaller than the working set (up to about 270 tiles when zoomed out and rotated) would have evicted on-screen tiles every frame. `maxTiles` is therefore only the floor of the budget `max(maxTiles, 2 × working set)`. The eviction test was confirmed to fail (2 of 6 tiles survive) with the protection disabled and to pass with it.
