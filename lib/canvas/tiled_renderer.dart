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
class TiledRenderer {
  TiledRenderer() : sprite = _buildSprite() {
    cache = TileCache(sprite: sprite);
  }

  final ui.Image sprite;
  late final TileCache cache;

  SplatStream? _activeStream;
  List<CanvasPoint>? _activeSource;
  int _activeSeed = 0;
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
  void paint(
    ui.Canvas canvas, {
    required CanvasDocument document,
    required List<CanvasPoint> active,
    required ui.Rect visible,
    required double pixelsPerUnit,
  }) {
    final clock = Stopwatch()..start();
    cache.attach(document);
    final level = TileGrid.levelFor(pixelsPerUnit);
    lastLevel = level;
    frame
      ..reset()
      ..level = level
      ..visibleRect = visible;

    final wanted = <TileKey>{};
    final paint = ui.Paint()..filterQuality = ui.FilterQuality.medium;
    for (final key in TileGrid.tilesIn(visible, level)) {
      wanted.add(key);
      frame.visible++;
      final tile = cache.tile(key);
      final current = tile != null && cache.isCurrent(key, tile);
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
    cache.setWanted(wanted);

    _paintActive(canvas, document, active);
    frame.activeSplats = _activeStream?.batch.count ?? 0;
    frame.recordMillis = clock.elapsedMicroseconds / 1000;
    recordHistory.addLast(frame.recordMillis);
    while (recordHistory.length > TileCacheCounters.historyLength) {
      recordHistory.removeFirst();
    }
  }

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

  void dispose() {
    cache.dispose();
    sprite.dispose();
  }

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
