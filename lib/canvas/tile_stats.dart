// What: plain data holders for tile-cache diagnostics: TileBuildKind (how a
// build ended), TileCacheCounters (cumulative cache activity), TileFrameStats
// and TileDraw (how each visible tile was drawn in the last frame), and
// TileInfo (a read-only snapshot of one tile).
// Why: the debug pane (docs/design/diagnostics/debug-pane.md) must see
// inside the asynchronous cache, but the core must not depend on debug UI.
// These classes are the one-way boundary: tile_cache.dart writes
// TileCacheCounters,
// tiled_renderer.dart writes TileFrameStats, and lib/debug/ only reads them.
// They hold no logic beyond bookkeeping so recording stays cheap even when
// the pane is closed. The system overview is in tile_cache.dart.

import 'dart:collection';
import 'dart:ui' show Rect;

import 'tile_grid.dart';

/// What happened to a tile the last time a build for it finished. Passed to
/// [TileCacheCounters.recordBuild] by `TileCache._build`.
enum TileBuildKind {
  /// Rasterized from scratch (no previous image).
  full,

  /// A previous image was updated by drawing newly added strokes over it.
  incremental,

  /// Nothing new touched the tile; only its applied-stroke counter advanced.
  skipped,
}

/// Cumulative counters kept by `TileCache` (its `counters` field). Cheap to
/// update; read by tooling (the debug pane) and tests. `TileCache` increments
/// the plain fields directly, except the build totals and [buildMillis],
/// which [recordBuild] updates.
class TileCacheCounters {
  /// Calls to `TileCache.request` that actually queued a tile (duplicates of a
  /// queued or building tile are not counted).
  int requests = 0;

  /// Finished builds of any [TileBuildKind]; updated by [recordBuild].
  int builds = 0;
  int fullBuilds = 0;
  int incrementalBuilds = 0;
  int skippedBuilds = 0;

  /// Tiles removed by `TileCache._evictExcess`.
  int evictions = 0;

  /// Queued requests discarded by `TileCache.setWanted` because the latest
  /// frame no longer wanted them.
  int droppedFromQueue = 0;

  /// Splats produced by the worker isolate (counted once per stroke, in
  /// `TileCache._splatsFor`).
  int splatsGenerated = 0;

  /// Sum of splat counts drawn into tiles (a splat drawn into two tiles counts
  /// twice).
  int splatsRastered = 0;

  /// Recent build durations in milliseconds (generation + raster, per tile),
  /// oldest first. Bounded by [historyLength].
  final Queue<double> buildMillis = Queue<double>();

  /// Longest history kept in [buildMillis].
  static const int historyLength = 120;

  /// Records one finished build. Called by `TileCache._build`. Skipped builds
  /// do no work, so they add no sample to [buildMillis].
  void recordBuild(TileBuildKind kind, Duration elapsed, int splats) {
    builds++;
    switch (kind) {
      case TileBuildKind.full:
        fullBuilds++;
      case TileBuildKind.incremental:
        incrementalBuilds++;
      case TileBuildKind.skipped:
        skippedBuilds++;
    }
    splatsRastered += splats;
    if (kind != TileBuildKind.skipped) {
      buildMillis.addLast(elapsed.inMicroseconds / 1000);
      while (buildMillis.length > historyLength) {
        buildMillis.removeFirst();
      }
    }
  }
}

/// Per-frame facts recorded by `TiledRenderer.paint` (its `frame` field).
/// Rewritten every frame, so a reader that needs a consistent view must copy
/// it (the debug pane does, in `_Reading.of`). The six per-tile counters
/// [drawnCurrent], [drawnStale], [fallbackCoarser], [fallbackFiner],
/// [missing] and [blank] correspond one-to-one to the [TileDraw] values and
/// together add up to [visible].
class TileFrameStats {
  /// Level of detail chosen for the frame.
  int level = 0;

  /// Tiles visible at [level].
  int visible = 0;

  /// Visible tiles drawn from their own, current image.
  int drawnCurrent = 0;

  /// Visible tiles drawn from their own image while an update is pending.
  int drawnStale = 0;

  /// Visible tiles drawn from a coarser ancestor scaled up.
  int fallbackCoarser = 0;

  /// Visible tiles drawn from finer children scaled down.
  int fallbackFiner = 0;

  /// Visible tiles with nothing cached at any level (blank paper).
  int missing = 0;

  /// Visible tiles that are built and known to contain no ink.
  int blank = 0;

  /// Splats in the current in-progress chunk.
  int activeSplats = 0;

  /// Time spent recording the frame's draw calls on the UI thread (ms).
  double recordMillis = 0;

  /// Rectangle of document space covered by the frame.
  Rect visibleRect = Rect.zero;

  /// How each visible tile at [level] was drawn this frame. Keys are the
  /// target-level tiles only; tiles used as fallback sources are not listed.
  /// Read by `paintTileOverlay` to tint tiles.
  final Map<TileKey, TileDraw> draws = {};

  /// Clears the per-frame counters and [draws] at the start of
  /// `TiledRenderer.paint`. [visibleRect] is not cleared; `paint` overwrites
  /// it every frame.
  void reset() {
    level = visible = drawnCurrent = drawnStale = 0;
    fallbackCoarser = fallbackFiner = missing = blank = activeSplats = 0;
    recordMillis = 0;
    draws.clear();
  }
}

/// How a visible tile was drawn in the last frame. Decided by
/// `TiledRenderer.paint` and `_drawFallback`:
/// [current] own image, up to date; [stale] own image with an update pending;
/// [coarser] scaled up from a coarser ancestor; [finer] scaled down from
/// finer children; [missing] nothing cached at any level; [blank] built and
/// known to be empty (own tile or the coarser ancestor used as source).
enum TileDraw { current, stale, coarser, finer, missing, blank }

/// Read-only description of one tile for the debug UI, produced by
/// `TileCache.describeTiles`.
class TileInfo {
  const TileInfo({
    required this.key,
    required this.hasImage,
    required this.appliedStrokes,
    required this.current,
    required this.building,
    required this.queued,
  });

  final TileKey key;

  /// False for a built tile that no stroke touches.
  final bool hasImage;
  final int appliedStrokes;

  /// Whether every touching stroke is already drawn into the tile.
  final bool current;
  final bool building;
  final bool queued;
}
