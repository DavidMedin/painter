import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'canvas_controller.dart';
import 'pencil_splats.dart';
import 'splat_worker.dart';
import 'tile_grid.dart';

/// One cached tile and the document strokes already drawn into it.
class CachedTile {
  CachedTile(this.image, this.appliedStrokes, this.revision);

  /// The rasterized tile, or null when no stroke touches it (blank).
  final ui.Image? image;

  /// Strokes `[0, appliedStrokes)` of the document are in [image].
  final int appliedStrokes;

  /// Document revision the image was built against; a mismatch means the
  /// document was replaced and the image is garbage.
  final int revision;
}

/// Caches the canvas as document-space tiles at several resolutions and keeps
/// them up to date lazily and asynchronously.
///
/// Painting never waits on this class: [tile] returns whatever is cached, and
/// [request] only enqueues work. A tile is rebuilt in the background and
/// [onChanged] fires when a new image lands so the painter can redraw. When a
/// stroke is appended to the document, a tile that already holds earlier
/// strokes is updated by drawing just the new strokes over its old image.
class TileCache extends ChangeNotifier {
  TileCache({
    required this.sprite,
    SplatWorker? worker,
    this.maxInFlight = 2,
    this.maxTiles = 256,
  }) : _worker = worker ?? SplatWorker();

  /// The gaussian sprite every splat samples.
  final ui.Image sprite;
  final SplatWorker _worker;

  /// Tile rasters allowed to run at once.
  final int maxInFlight;

  /// Cached tiles kept before the least recently used are evicted.
  final int maxTiles;

  final Map<TileKey, CachedTile> _tiles = {};
  // Insertion order == recency; re-inserted on use.
  final LinkedHashSet<TileKey> _recency = LinkedHashSet<TileKey>();
  final Set<TileKey> _queued = {};
  final List<TileKey> _queue = [];
  final Set<TileKey> _building = {};

  // Tiles the most recent frame drew or asked for; shielded from eviction.
  Set<TileKey> _wanted = const {};

  // Per-stroke splat state, indexed by stroke index in the document.
  final List<StrokeSplats?> _splats = [];
  final List<Future<StrokeSplats>?> _splatFutures = [];

  CanvasDocument? _document;
  int _revision = 0;
  bool _pumpScheduled = false;
  bool _disposed = false;
  Float32List _rects = Float32List(0);

  /// Number of tile rasters currently running (for tests and diagnostics).
  int get building => _building.length;

  /// Number of tiles currently cached.
  int get cachedTiles => _tiles.length;

  /// Whether any requested tile has not been built yet.
  bool get idle => _queue.isEmpty && _building.isEmpty;

  /// Returns the cached tile for [key], or null. Marks it recently used.
  CachedTile? tile(TileKey key) {
    final tile = _tiles[key];
    if (tile == null || tile.revision != _revision) return null;
    _recency
      ..remove(key)
      ..add(key);
    return tile;
  }

  /// Whether [tile] already contains every stroke of the current document that
  /// touches [key].
  bool isCurrent(TileKey key, CachedTile tile) {
    final document = _document;
    if (document == null) return true;
    return !_hasPending(key, tile.appliedStrokes, document);
  }

  /// Points the cache at [document]. A different document instance discards
  /// every tile; appended strokes keep existing tiles and mark them stale.
  void attach(CanvasDocument document) {
    if (!identical(document, _document)) {
      _document = document;
      _revision++;
      _evictAll();
      _splats.clear();
      _splatFutures.clear();
      _queue.clear();
      _queued.clear();
    }
  }

  /// Asks for [key] to be built, or brought up to date if it is stale.
  /// Cheap and idempotent; safe to call every frame.
  void request(TileKey key) {
    final document = _document;
    if (document == null || _disposed) return;
    final existing = _tiles[key];
    final applied = existing != null && existing.revision == _revision
        ? existing.appliedStrokes
        : 0;
    if (existing != null &&
        existing.revision == _revision &&
        !_hasPending(key, applied, document)) {
      // Up to date. A tile that is behind only by strokes elsewhere still has
      // its old, correct image; _build advances its counter without rastering.
      return;
    }
    if (_building.contains(key) || !_queued.add(key)) return;
    _queue.add(key);
    _schedulePump();
  }

  /// Records the tiles the latest frame needs. Queued work outside [wanted] is
  /// dropped, so panning away from a region stops spending time on it, and
  /// [wanted] tiles are never evicted while they are on screen.
  void setWanted(Set<TileKey> wanted) {
    _wanted = wanted;
    if (_queue.isEmpty) return;
    _queue.removeWhere((key) {
      final keep = wanted.contains(key);
      if (!keep) _queued.remove(key);
      return !keep;
    });
  }

  bool _hasPending(TileKey key, int applied, CanvasDocument document) {
    final rect = TileGrid.rectOf(key).inflate(TileGrid.bleed);
    for (var i = applied; i < document.strokeCount; i++) {
      if (_touches(document.strokeAt(i), rect)) return true;
    }
    return false;
  }

  static bool _touches(CanvasStroke stroke, ui.Rect tileRect) =>
      stroke.bounds.inflate(PencilSplats.inkMargin).overlaps(tileRect);

  void _schedulePump() {
    if (_pumpScheduled || _disposed) return;
    _pumpScheduled = true;
    scheduleMicrotask(_pump);
  }

  void _pump() {
    _pumpScheduled = false;
    if (_disposed) return;
    while (_building.length < maxInFlight && _queue.isNotEmpty) {
      final key = _queue.removeAt(0);
      _queued.remove(key);
      _building.add(key);
      unawaited(_build(key));
    }
  }

  Future<void> _build(TileKey key) async {
    final revision = _revision;
    final document = _document!;
    try {
      final existing = _tiles[key];
      final base = existing != null && existing.revision == revision
          ? existing
          : null;
      final applied = base?.appliedStrokes ?? 0;
      final count = document.strokeCount;
      final rect = TileGrid.rectOf(key).inflate(TileGrid.bleed);

      final needed = <int>[];
      for (var i = applied; i < count; i++) {
        if (_touches(document.strokeAt(i), rect)) needed.add(i);
      }
      // Start every generation first so the worker pipelines them, then await.
      final pending = [for (final i in needed) _splatsFor(document, i)];
      final splats = <StrokeSplats>[];
      for (final future in pending) {
        splats.add(await future);
      }
      if (_disposed || revision != _revision) return;

      ui.Image? image;
      if (splats.isEmpty) {
        // Nothing new touches this tile: keep the existing image (or stay
        // blank) and just advance the applied counter. No GPU work.
        image = base?.image;
      } else {
        image = await _rasterize(key, base?.image, splats);
        if (_disposed || revision != _revision) {
          image.dispose();
          return;
        }
        base?.image?.dispose();
      }
      _tiles[key] = CachedTile(image, count, revision);
      _recency
        ..remove(key)
        ..add(key);
      _evictExcess();
      notifyListeners();
    } on StateError {
      // Worker disposed mid-flight; nothing to do.
    } finally {
      _building.remove(key);
      if (!_disposed) {
        // Strokes may have been added while this raster ran.
        request(key);
        _schedulePump();
      }
    }
  }

  Future<StrokeSplats> _splatsFor(CanvasDocument document, int index) {
    while (_splats.length <= index) {
      _splats.add(null);
      _splatFutures.add(null);
    }
    return _splatFutures[index] ??= _worker
        .generate(document.strokeAt(index))
        .then((value) => _splats[index] = value);
  }

  Future<ui.Image> _rasterize(
    TileKey key,
    ui.Image? base,
    List<StrokeSplats> strokes,
  ) {
    final size = TileGrid.texturePixels;
    final scale = TileGrid.scaleOf(key.level);
    final origin = TileGrid.rectOf(key).topLeft;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    if (base != null) {
      canvas.drawImage(base, ui.Offset.zero, ui.Paint());
    }
    canvas
      ..clipRect(ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()))
      ..scale(scale)
      ..translate(-origin.dx, -origin.dy);
    final paint = ui.Paint()
      ..isAntiAlias = true
      ..filterQuality = ui.FilterQuality.medium;
    for (final stroke in strokes) {
      if (stroke.count == 0) continue;
      canvas.drawRawAtlas(
        sprite,
        stroke.transforms,
        _rectsFor(stroke.count),
        stroke.colors,
        ui.BlendMode.modulate,
        null,
        paint,
      );
    }
    final picture = recorder.endRecording();
    final image = picture.toImage(size, size);
    return image.whenComplete(picture.dispose);
  }

  Float32List _rectsFor(int count) {
    if (_rects.length < count * 4) {
      final edge = PencilSplats.spritePixels.toDouble();
      final grown = Float32List(math.max(count * 4, _rects.length * 2));
      for (var i = 0; i < grown.length; i += 4) {
        grown[i] = 0;
        grown[i + 1] = 0;
        grown[i + 2] = edge;
        grown[i + 3] = edge;
      }
      _rects = grown;
    }
    return Float32List.sublistView(_rects, 0, count * 4);
  }

  void _evictExcess() {
    final budget = math.max(maxTiles, _wanted.length * 2);
    if (_tiles.length <= budget) return;
    // Oldest first; never evict what the last frame needed or is mid-build.
    final victims = <TileKey>[];
    var excess = _tiles.length - budget;
    for (final key in _recency) {
      if (excess == 0) break;
      if (_wanted.contains(key) || _building.contains(key)) continue;
      victims.add(key);
      excess--;
    }
    for (final key in victims) {
      _recency.remove(key);
      _tiles.remove(key)?.image?.dispose();
    }
  }

  void _evictAll() {
    for (final tile in _tiles.values) {
      tile.image?.dispose();
    }
    _tiles.clear();
    _recency.clear();
  }

  @override
  void dispose() {
    _disposed = true;
    _evictAll();
    _worker.dispose();
    super.dispose();
  }
}
