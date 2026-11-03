import 'dart:collection';
import 'dart:ui' show Rect;

import 'tile_grid.dart';

/// What happened to a tile the last time a build for it finished.
enum TileBuildKind {
  /// Rasterized from scratch (no previous image).
  full,

  /// A previous image was updated by drawing newly added strokes over it.
  incremental,

  /// Nothing new touched the tile; only its applied-stroke counter advanced.
  skipped,
}

/// Cumulative counters kept by `TileCache`. Cheap to update; read by tooling.
class TileCacheCounters {
  int requests = 0;
  int builds = 0;
  int fullBuilds = 0;
  int incrementalBuilds = 0;
  int skippedBuilds = 0;
  int evictions = 0;
  int droppedFromQueue = 0;
  int splatsGenerated = 0;

  /// Sum of splat counts drawn into tiles (a splat drawn into two tiles counts
  /// twice).
  int splatsRastered = 0;

  /// Recent build durations in milliseconds (generation + raster, per tile),
  /// oldest first. Bounded by [historyLength].
  final Queue<double> buildMillis = Queue<double>();

  /// Longest history kept in [buildMillis].
  static const int historyLength = 120;

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

/// Per-frame facts recorded by `TiledRenderer.paint`.
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

  /// Splats in the in-progress stroke.
  int activeSplats = 0;

  /// Time spent recording the frame's draw calls on the UI thread (ms).
  double recordMillis = 0;

  /// Rectangle of document space covered by the frame.
  Rect visibleRect = Rect.zero;

  /// How each visible tile at [level] was drawn this frame.
  final Map<TileKey, TileDraw> draws = {};

  void reset() {
    level = visible = drawnCurrent = drawnStale = 0;
    fallbackCoarser = fallbackFiner = missing = blank = activeSplats = 0;
    recordMillis = 0;
    draws.clear();
  }
}

/// How a visible tile was drawn in the last frame.
enum TileDraw { current, stale, coarser, finer, missing, blank }

/// Read-only description of one tile for the debug UI.
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
