// What: TiledRenderer paints cached tiles, ready splats missing from stale
// tile images, and the current in-progress chunk. It falls back to other
// resolutions for tiles that are not ready, classifies them for debug stats,
// and builds the gaussian sprite that every splat samples.
// Why: painting has to be fast and must never wait on rasterization, so the
// slow work lives in tile_cache.dart and this file only reads cached content
// and asks for what is missing. It owns the sprite, cache, and active-chunk
// stream because those share one lifetime (docs/decisions/0005-tiled-texture-
// cache.md; it replaced the old PencilRenderer). The system overview,
// including how this file and tile_cache.dart, tile_grid.dart and tile_stats.dart
// divide the work, is in tile_cache.dart.

import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'canvas_controller.dart';
import 'pencil_splats.dart';
import 'splat_worker.dart';
import 'tile_cache.dart';
import 'tile_grid.dart';
import 'tile_stats.dart';

/// Paints cached tiles, ready missing splats over stale images, and the
/// current in-progress chunk live.
///
/// The steady-state frame path draws a bounded number of visible tile images
/// instead of replaying every stroke. While replacement images are pending,
/// ready splats missing from each image are clipped to that image's region.
/// Missing tiles fall back to the closest cached resolution scaled to fit
/// while the right one builds in the background.
///
/// Created and disposed by `_CanvasViewState` (canvas_view.dart), whose
/// `_CanvasPainter.paint` calls [paint] every frame and repaints whenever
/// [cache] notifies. The debug pane reaches it through `CanvasView.onRenderer`
/// and reads [frame], [recordHistory] and [cache].
class TiledRenderer {
  TiledRenderer() : sprite = _buildSprite() {
    cache = TileCache(sprite: sprite);
  }

  /// The gaussian sprite every splat samples, shared with [cache] and the
  /// active chunk. Its size must match `PencilSplats.spritePixels`.
  final ui.Image sprite;
  late final TileCache cache;

  // The current live chunk is not tiled; see _paintActive. Its stream keeps
  // splats generated so far, keyed by seed and source-list identity.
  SplatStream? _activeStream;
  List<CanvasPoint>? _activeSource;
  int _activeSeed = 0;

  CanvasDocument? _activeDocument;
  final ui.Paint _atlasPaint = ui.Paint()
    ..isAntiAlias = true
    ..filterQuality = ui.FilterQuality.medium;
  // Source rectangles for drawRawAtlas; see _rectsFor.
  Float32List? _rects;

  /// Level of detail last used by [paint]; exposed for tests.
  int lastLevel = 0;

  /// What the most recent [paint] drew, for diagnostics.
  final TileFrameStats frame = TileFrameStats();

  /// Recent per-frame recording times in milliseconds, oldest first.
  final Queue<double> recordHistory = Queue<double>();

  /// Paints [document], ready splat overlays for stale images, and the active
  /// chunk into [canvas].
  ///
  /// [canvas] must already carry the document-to-screen transform. [visible] is
  /// the document-space rectangle on screen and [pixelsPerUnit] the on-screen
  /// size of one document unit (zoom times device pixel ratio).
  ///
  /// Per frame: attach the document to [cache]; choose the level with
  /// `TileGrid.levelFor`; for each visible tile at that level, draw the cached
  /// image (current or stale) or a fallback, ask [cache] for anything not
  /// current, and draw ready splats missing from the image, clipped to its
  /// region. Then record in [frame] how it was drawn; tell the cache which
  /// tiles were used ([TileCache.setWanted], which protects them from eviction
  /// and drops queued work for tiles no longer visible); and draw the active
  /// chunk over the tiles. This method never builds or waits.
  ///
  /// Coupled to: [TileCache.attach], [TileCache.tile], [TileCache.isCurrent],
  /// [TileCache.request], [TileCache.setWanted], [TileCache.splatsIfReady],
  /// [TileCache.cacheLiveSplats]; [_drawTile], [_drawFallback],
  /// [_drawPendingSplats], [_retainCommittedActive], [_paintActive]; and
  /// [TileFrameStats] (every branch below bumps exactly one of its per-tile
  /// counters and sets `draws[key]`).
  void paint(
    ui.Canvas canvas, {
    required CanvasDocument document,
    required List<CanvasPoint> active,
    required ui.Rect visible,
    required double pixelsPerUnit,
  }) {
    final clock = Stopwatch()..start();
    cache.attach(document);
    _retainCommittedActive(document);
    // Level choice must be the same one TileCache's tiles are keyed by; both
    // sides get it from TileGrid so they cannot disagree.
    final level = TileGrid.levelFor(pixelsPerUnit);
    lastLevel = level;
    frame
      ..reset()
      ..level = level
      ..visibleRect = visible;

    // Tiles this frame used, including fallback sources. Handed to the cache
    // at the end so those tiles survive eviction.
    final wanted = <TileKey>{};
    final paint = ui.Paint()..filterQuality = ui.FilterQuality.medium;
    for (final key in TileGrid.tilesIn(visible, level)) {
      wanted.add(key);
      frame.visible++;
      // cache.tile also refreshes the tile's recency. A stale tile is returned
      // as well and drawn below, so ink never blinks off while it updates.
      final tile = cache.tile(key);
      final current = tile != null && cache.isCurrent(key, tile);
      // Request when missing or stale; cheap and idempotent per frame.
      if (!current) cache.request(key);
      if (tile != null) {
        _drawTile(canvas, key, tile, paint);
        if (!current) {
          _drawPendingSplats(
            canvas,
            document,
            TileGrid.rectOf(key),
            tile.appliedStrokes,
          );
        }
        if (tile.image == null) {
          frame.blank++;
          frame.draws[key] = TileDraw.blank;
        } else if (current) {
          frame.drawnCurrent++;
          frame.draws[key] = TileDraw.current;
        } else {
          frame.drawnStale++;
          frame.draws[key] = TileDraw.stale;
        }
      } else {
        final fallback = _drawFallback(canvas, document, key, paint, wanted);
        if (fallback == TileDraw.missing) {
          _drawPendingSplats(canvas, document, TileGrid.rectOf(key), 0);
        }
        frame.draws[key] = fallback;
      }
    }
    // After the loop: fallback tiles were added to `wanted` while drawing.
    cache.setWanted(wanted);

    // Drawn after the tiles so it sits on top; never cached as a tile.
    _paintActive(canvas, document, active);
    frame.activeSplats = _activeStream?.batch.count ?? 0;
    frame.recordMillis = clock.elapsedMicroseconds / 1000;
    recordHistory.addLast(frame.recordMillis);
    while (recordHistory.length > TileCacheCounters.historyLength) {
      recordHistory.removeFirst();
    }
  }

  /// Draws [tile]'s image into the document-space rectangle of [key],
  /// mapping the whole texture onto `TileGrid.rectOf(key)`. This is the
  /// inverse of the mapping `TileCache._rasterize` used to produce the image.
  /// A blank tile (no image) draws nothing.
  void _drawTile(ui.Canvas canvas, TileKey key, CachedTile tile, ui.Paint p) {
    final image = tile.image;
    if (image == null) return;
    canvas.drawImageRect(
      image,
      ui.Rect.fromLTWH(
        0,
        0,
        TileGrid.texturePixels.toDouble(),
        TileGrid.texturePixels.toDouble(),
      ),
      TileGrid.rectOf(key),
      p,
    );
  }

  /// Draws [key]'s area from the nearest cached level: the closest coarser
  /// ancestor first (one image, scaled up), otherwise cached finer children
  /// (scaled down). Only one source is used per area so ink never doubles up.
  ///
  /// Returns how the area was drawn so [paint] can record it. Sources used are
  /// added to [wanted] so the cache will not evict them. The source crop is
  /// the sub-rectangle of the ancestor's texture covering [key]'s area:
  /// `(area - parent origin) * texturePixels / parent.width` (the ancestor's
  /// pixels per unit, `TileGrid.scaleOf(ancestor.level)`). A cached blank
  /// ancestor means no ink there, so it ends the search as [TileDraw.blank].
  /// Calls [_drawFinerChildren] when no coarser level is cached.
  TileDraw _drawFallback(
    ui.Canvas canvas,
    CanvasDocument document,
    TileKey key,
    ui.Paint p,
    Set<TileKey> wanted,
  ) {
    for (var level = key.level - 1; level >= TileGrid.minLevel; level--) {
      final ancestor = TileGrid.ancestor(key, level)!;
      final tile = cache.tile(ancestor);
      if (tile == null) continue;
      wanted.add(ancestor);
      final image = tile.image;
      if (image == null) {
        _drawPendingSplats(
          canvas,
          document,
          TileGrid.rectOf(key),
          tile.appliedStrokes,
        );
        frame.blank++;
        return TileDraw.blank;
      }
      final area = TileGrid.rectOf(key);
      final parent = TileGrid.rectOf(ancestor);
      final scale = TileGrid.texturePixels / parent.width;
      canvas.drawImageRect(
        image,
        ui.Rect.fromLTWH(
          (area.left - parent.left) * scale,
          (area.top - parent.top) * scale,
          area.width * scale,
          area.height * scale,
        ),
        area,
        p,
      );
      _drawPendingSplats(
        canvas,
        document,
        TileGrid.rectOf(key),
        tile.appliedStrokes,
      );
      frame.fallbackCoarser++;
      return TileDraw.coarser;
    }
    final drawn = _drawFinerChildren(canvas, document, key, p, wanted);
    switch (drawn) {
      case TileDraw.finer:
        frame.fallbackFiner++;
      default:
        frame.missing++;
    }
    return drawn;
  }

  /// Draws whichever cached finer tiles cover [key]'s area, scaled down, from
  /// the first finer level that has any (at most two levels deeper, so at most
  /// 16 children). Children that are not cached leave their part blank.
  /// Returns [TileDraw.finer] if anything was drawn, else [TileDraw.missing].
  TileDraw _drawFinerChildren(
    ui.Canvas canvas,
    CanvasDocument document,
    TileKey key,
    ui.Paint p,
    Set<TileKey> wanted,
  ) {
    final area = TileGrid.rectOf(key);
    for (var level = key.level + 1; level <= TileGrid.maxLevel; level++) {
      if (level - key.level > 2) break; // At most 16 children per tile.
      var found = false;
      for (final child in TileGrid.tilesIn(area, level)) {
        final tile = cache.tile(child);
        final image = tile?.image;
        if (image == null) continue;
        found = true;
        wanted.add(child);
        _drawTile(canvas, child, tile!, p);
        _drawPendingSplats(
          canvas,
          document,
          TileGrid.rectOf(child),
          tile.appliedStrokes,
        );
      }
      if (found) return TileDraw.finer;
    }
    return TileDraw.missing;
  }

  /// Retains the just-committed live chunk's already-generated splats in the
  /// cache so stale tiles can draw them while their replacement is rasterized.
  void _retainCommittedActive(CanvasDocument document) {
    final stream = _activeStream;
    final source = _activeSource;
    if (stream == null ||
        source == null ||
        !identical(_activeDocument, document)) {
      return;
    }
    final index = _activeSeed - 1;
    if (index < 0 || index >= document.strokeCount) return;
    if (document.strokeAt(index).seed != _activeSeed) return;

    // The source list is no longer mutated after commit; extend before sharing
    // the stream's buffers in case no frame recorded its final points.
    stream.extend(source);
    final batch = stream.batch;
    cache.cacheLiveSplats(
      index,
      StrokeSplats(batch.count, batch.transforms, batch.colors),
    );
  }

  /// Draws ready splats absent from a tile image, clipped to the exact area
  /// that image covers. Cache replacement makes this overlay unnecessary.
  void _drawPendingSplats(
    ui.Canvas canvas,
    CanvasDocument document,
    ui.Rect region,
    int appliedStrokes,
  ) {
    if (appliedStrokes >= document.strokeCount) return;
    canvas.save();
    canvas.clipRect(region);
    for (var i = appliedStrokes; i < document.strokeCount; i++) {
      final stroke = document.strokeAt(i);
      if (!stroke.bounds.inflate(PencilSplats.inkMargin).overlaps(region)) {
        continue;
      }
      final splats = cache.splatsIfReady(i);
      if (splats == null || splats.count == 0) continue;
      canvas.drawRawAtlas(
        sprite,
        splats.transforms,
        _rectsFor(splats.count),
        splats.colors,
        ui.BlendMode.modulate,
        null,
        _atlasPaint,
      );
    }
    canvas.restore();
  }

  /// Draws the current live chunk from its [SplatStream], extending it with
  /// only the new points each call. Completed chunks enter the tile cache as
  /// document strokes; their generated splats cover stale tiles until the
  /// asynchronous replacement images land.
  ///
  /// The stream is reset when no chunk is active, when the seed changes, or
  /// when [active] is a different list instance. `CanvasController.activePoints`
  /// returns a new list when a chunk is committed, so identity marks rollover.
  /// `CanvasDocument.nextSeed` equals the `CanvasStroke.seed` used on commit,
  /// preserving that chunk's grain while it moves into the cache.
  void _paintActive(
    ui.Canvas canvas,
    CanvasDocument document,
    List<CanvasPoint> active,
  ) {
    if (active.isEmpty) {
      _activeStream = null;
      _activeSource = null;
      _activeDocument = null;
      return;
    }
    // This chunk becomes the next committed stroke; reuse its seed so the
    // grain does not change on commit. A rollover starts a new list and seed.
    final seed = document.nextSeed;
    var stream = _activeStream;
    if (stream == null ||
        _activeSeed != seed ||
        !identical(_activeSource, active) ||
        !identical(_activeDocument, document)) {
      stream = _activeStream = SplatStream(seed);
      _activeSeed = seed;
      _activeSource = active;
      _activeDocument = document;
    }
    stream.extend(active);
    final batch = stream.batch;
    if (batch.count == 0) return;
    canvas.drawRawAtlas(
      sprite,
      batch.transforms,
      _rectsFor(batch.count),
      batch.colors,
      ui.BlendMode.modulate,
      null,
      _atlasPaint,
    );
  }

  // Same logic as TileCache._rectsFor: a reusable list of full-sprite source
  // rectangles for drawRawAtlas, grown geometrically. Keep the two in sync.
  Float32List _rectsFor(int count) {
    var rects = _rects;
    if (rects == null || rects.length < count * 4) {
      final edge = PencilSplats.spritePixels.toDouble();
      rects = Float32List(math.max(count * 4, (rects?.length ?? 0) * 2));
      for (var i = 0; i < rects.length; i += 4) {
        rects[i + 2] = edge;
        rects[i + 3] = edge;
      }
      _rects = rects;
    }
    return Float32List.sublistView(rects, 0, count * 4);
  }

  /// Releases the cache (which disposes its worker isolate) and the sprite.
  /// Called from `_CanvasViewState.dispose`.
  void dispose() {
    cache.dispose();
    sprite.dispose();
  }

  /// Renders the gaussian sprite synchronously (`toImageSync`) so the renderer
  /// is usable right after construction. The image is
  /// `PencilSplats.spritePixels` square, which `TileCache._rectsFor` and
  /// [_rectsFor] rely on when they build source rectangles.
  static ui.Image _buildSprite() {
    const size = PencilSplats.spritePixels;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    // exp(-r^2 / 2) sampled in r = 0..2.2 sigma, so alpha reaches ~0.09 at the
    // sprite edge; the final stop forces it to exactly 0 to avoid a visible
    // square. Eight stops are visually smooth under linear interpolation.
    const stops = 8;
    final colors = <Color>[];
    final offsets = <double>[];
    for (var i = 0; i <= stops; i++) {
      final r = i / stops;
      final a = i == stops ? 0.0 : math.exp(-(r * r * 2.2 * 2.2) / 2);
      colors.add(Color.fromRGBO(0, 0, 0, a));
      offsets.add(r);
    }
    final paint = ui.Paint()
      ..shader = ui.Gradient.radial(
        const ui.Offset(size / 2, size / 2),
        size / 2,
        colors,
        offsets,
      );
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, size * 1.0, size * 1.0),
      paint,
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync(size, size);
    picture.dispose();
    return image;
  }
}
