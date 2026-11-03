// What: TiledRenderer, the per-frame painter of the document. Each frame it
// draws the visible tiles from TileCache, falls back to other resolutions for
// tiles that are not ready, classifies how every tile was drawn for the debug
// stats, and draws the in-progress stroke live. It also builds the gaussian
// sprite that every splat samples.
// Why: painting has to be fast and must never wait on rasterization, so the
// slow work lives in tile_cache.dart and this file only reads what is cached
// and asks for what is missing. It owns the sprite, the cache and the
// active-stroke stream because those share one lifetime (docs/decisions/
// 0005-tiled-texture-cache.md; it replaced the old PencilRenderer). The
// system overview, including how this file and tile_cache.dart, tile_grid.dart
// and tile_stats.dart divide the work, is in tile_cache.dart.

import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'canvas_controller.dart';
import 'pencil_splats.dart';
import 'tile_cache.dart';
import 'tile_grid.dart';
import 'tile_stats.dart';

/// Paints the document from cached tiles and the in-progress stroke live.
///
/// Per frame this draws a bounded number of tile images (only those visible)
/// instead of replaying every stroke, so frame cost tracks screen area, not
/// document size. Missing tiles fall back to the closest cached resolution
/// scaled to fit while the right one builds in the background.
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
  /// active stroke. Its size must match `PencilSplats.spritePixels`.
  final ui.Image sprite;
  late final TileCache cache;

  // The in-progress stroke is not tiled; see _paintActive. The stream keeps
  // the splats built so far, keyed by the seed and the identity of the point
  // list it was fed from.
  SplatStream? _activeStream;
  List<CanvasPoint>? _activeSource;
  int _activeSeed = 0;
  // Source rectangles for drawRawAtlas; see _rectsFor.
  Float32List? _rects;

  /// Level of detail last used by [paint]; exposed for tests.
  int lastLevel = 0;

  /// What the most recent [paint] drew, for diagnostics.
  final TileFrameStats frame = TileFrameStats();

  /// Recent per-frame recording times in milliseconds, oldest first.
  final Queue<double> recordHistory = Queue<double>();

  /// Paints [document] and the in-progress stroke into [canvas].
  ///
  /// [canvas] must already carry the document-to-screen transform. [visible] is
  /// the document-space rectangle on screen and [pixelsPerUnit] the on-screen
  /// size of one document unit (zoom times device pixel ratio).
  ///
  /// Per frame: attach the document to [cache]; choose the level with
  /// `TileGrid.levelFor`; for each visible tile at that level, draw the cached
  /// image (current or stale) or a fallback, ask [cache] for anything not
  /// current, and record in [frame] how it was drawn; finally tell the cache
  /// which tiles were used ([TileCache.setWanted], which protects them from
  /// eviction and drops queued work for tiles no longer visible) and draw the
  /// active stroke over the tiles. This method never builds or waits.
  ///
  /// Coupled to: [TileCache.attach], [TileCache.tile], [TileCache.isCurrent],
  /// [TileCache.request], [TileCache.setWanted]; [_drawTile], [_drawFallback],
  /// [_paintActive]; and [TileFrameStats] (every branch below bumps exactly one
  /// of its per-tile counters and sets `draws[key]`).
  void paint(
    ui.Canvas canvas, {
    required CanvasDocument document,
    required List<CanvasPoint> active,
    required ui.Rect visible,
    required double pixelsPerUnit,
  }) {
    final clock = Stopwatch()..start();
    cache.attach(document);
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
        frame.draws[key] = _drawFallback(canvas, key, paint, wanted);
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
      frame.fallbackCoarser++;
      return TileDraw.coarser;
    }
    final drawn = _drawFinerChildren(canvas, key, p, wanted);
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
      }
      if (found) return TileDraw.finer;
    }
    return TileDraw.missing;
  }

  /// Draws the in-progress stroke straight from the splats of a [SplatStream]
  /// (not through the tile cache), extending it with only the new points each
  /// call. Tiles get the stroke later, when it is committed to the document.
  ///
  /// The stream is reset when no stroke is active, when the seed changes, or
  /// when [active] is a different list instance:
  /// `CanvasController.activePoints` returns a new list per stroke (ADR 0005),
  /// so identity marks a new stroke. `CanvasDocument.nextSeed` equals the seed
  /// (`CanvasStroke.seed`) the stroke gets on commit, which is why the grain
  /// does not change at pointer-up.
  void _paintActive(
    ui.Canvas canvas,
    CanvasDocument document,
    List<CanvasPoint> active,
  ) {
    if (active.isEmpty) {
      _activeStream = null;
      _activeSource = null;
      return;
    }
    // The active stroke will become the next committed stroke; reuse its seed
    // so the grain does not change on pointer-up. A new stroke is a new list.
    final seed = document.nextSeed;
    var stream = _activeStream;
    if (stream == null ||
        _activeSeed != seed ||
        !identical(_activeSource, active)) {
      stream = _activeStream = SplatStream(seed);
      _activeSeed = seed;
      _activeSource = active;
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
      ui.Paint()
        ..isAntiAlias = true
        ..filterQuality = ui.FilterQuality.medium,
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
