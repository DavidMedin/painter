// What: TileCache (stores and builds the tile textures the canvas is drawn
// from) and CachedTile (one cache entry). This file is also the primary home
// of the tile-cache system overview below.
// Why: painting must never wait on rasterization, so building, scheduling,
// staleness tracking and eviction live here, apart from the per-frame drawing
// in tiled_renderer.dart. Pure geometry is in tile_grid.dart and the
// counters the debug pane reads are in tile_stats.dart, so this file imports
// no UI and nothing from lib/debug/.
//
// ===========================================================================
// SYSTEM OVERVIEW: the multi-resolution tiled texture cache
// (decision record: docs/decisions/0005-tiled-texture-cache.md; debug
// boundary: docs/decisions/0006-debug-pane.md)
// ===========================================================================
//
// What it is
//   The canvas is drawn from cached textures ("tiles"), not by replaying
//   strokes. A tile is a 512x512 device-pixel texture (TileGrid.texturePixels)
//   of one square of document space. Each tile has a level of detail (LOD):
//   level L rasterizes 2^L pixels per document unit, so it covers
//   512 / 2^L units per side. Levels run TileGrid.minLevel..maxLevel (-4..5)
//   and a tile is identified by TileKey(x, y, level). Every tile costs the
//   same memory (1 MiB) at any zoom.
//
// Why it exists
//   The earlier design (ADR 0004) drew every stroke's splats every frame, so
//   frame cost grew with the document (ADR 0005 measured 4.3 / 22 / 79 ms of
//   UI-thread recording at 100 / 500 / 2000 strokes), even while panning.
//   With tiles a frame draws only the visible textures, so cost follows
//   screen area, not stroke count.
//
// How it works
//   * Lazy and asynchronous. TiledRenderer.paint never builds anything: it
//     draws what tile() returns and calls request() for tiles that are
//     missing or stale. request() queues; _pump() starts at most maxInFlight
//     builds; _build() generates splats, rasterizes, stores the image and
//     calls notifyListeners(), which repaints the canvas on its own
//     (_CanvasPainter in canvas_view.dart listens to this cache).
//   * Splat generation runs in the SplatWorker isolate (splat_worker.dart),
//     since it is the CPU-heavy part. Splats are document-space, so one
//     stroke is generated once (_splatsFor) and reused by every tile and
//     level that stroke touches. Rasterization (_rasterize) runs on the
//     UI isolate via Picture.toImage, which completes asynchronously.
//   * Incremental update. Strokes are append-only and pencil ink only adds
//     alpha, so a CachedTile records appliedStrokes: strokes [0, applied) are
//     already in its image. When strokes are added, _build draws only the
//     new ones that touch the tile over the old image. If none touch it, the
//     counter just advances (TileBuildKind.skipped) with no GPU work.
//   * Stale or wrong-resolution tiles stay visible. A stale tile (isCurrent
//     is false) is still drawn from its old image until the replacement
//     lands. A tile missing at the target level is drawn by TiledRenderer
//     from a cached coarser ancestor scaled up, else cached finer children
//     scaled down, so panning or zooming never shows a hole where something
//     is cached at some level.
//   * Eviction is least-recently-used (_recency), but tiles in the working
//     set (_wanted: what the last frame drew or fell back to, supplied by
//     setWanted) and tiles mid-build are never evicted, and the budget is
//     max(maxTiles, 2 * working set) (_evictExcess). A constant maxTiles was
//     a real bug: the working set reaches about 270 tiles when zoomed far
//     out with a rotated view (docs/status.md), more than the default 256, so
//     on-screen tiles would have been evicted and rebuilt every frame.
//   * Invalidation. _revision is bumped when a different CanvasDocument is
//     attached or invalidateAll() runs. Each tile and each in-flight build
//     remembers the revision it started under; a mismatch means the image is
//     garbage and is discarded, which is how a build that finishes after the
//     document was replaced is safely dropped.
//
// Division of labor (and what must stay in sync)
//   * TileCache (this file): builds and stores tiles; owns the worker, the
//     per-stroke splat buffers, the queue, and eviction. Never draws to the
//     screen.
//   * TiledRenderer (tiled_renderer.dart): the per-frame side. paint() picks
//     the level (TileGrid.levelFor), walks the visible tiles
//     (TileGrid.tilesIn), calls attach/tile/isCurrent/request/setWanted on
//     this cache, draws images, picks fallbacks, and classifies each tile
//     for TileFrameStats. It also owns the sprite and the (untiled) active
//     stroke.
//   * TileGrid (tile_grid.dart): pure geometry (key <-> document rectangle,
//     level choice, ancestors). Both sides depend on it agreeing with itself:
//     _rasterize maps document space into a tile texture with
//     scale(TileGrid.scaleOf(level)) and translate(-rectOf(key).topLeft);
//     TiledRenderer._drawTile and _drawFallback map texture pixels back with
//     rectOf(key) and texturePixels. Change one mapping and you must change
//     the other or tiles drift or blur.
//   * TileStats (tile_stats.dart): plain counters and per-frame records.
//     TileCache writes `counters` (TileCacheCounters) and TiledRenderer
//     writes `frame` (TileFrameStats). The debug pane (lib/debug/) only reads
//     them and the cache's accessors; the core never imports debug UI.
//   * "Does this tile still need strokes?" is decided in two places that
//     must agree: _hasPending (used by request/isCurrent) and the `needed`
//     loop in _build. Both use _touches with TileGrid.bleed. If they
//     disagreed, a tile would be requested forever or never updated.

import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'canvas_controller.dart';
import 'pencil_splats.dart';
import 'splat_worker.dart';
import 'tile_grid.dart';
import 'tile_stats.dart';

/// One cached tile and the document strokes already drawn into it.
///
/// The cache keeps stale entries on purpose (see the overview at the top of
/// this file): [TileCache.isCurrent] compares [appliedStrokes] with the
/// document to decide whether an update is pending.
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
/// them up to date lazily and asynchronously. See the system overview at the
/// top of this file.
///
/// Painting never waits on this class: [tile] returns whatever is cached, and
/// [request] only enqueues work. A tile is rebuilt in the background and
/// listeners are notified ([ChangeNotifier]) when a new image lands so the
/// painter can redraw. When a stroke is appended to the document, a tile that
/// already holds earlier strokes is updated by drawing just the new strokes
/// over its old image.
///
/// Main caller: `TiledRenderer.paint` (tiled_renderer.dart), through
/// [attach], [tile], [isCurrent], [request] and [setWanted]. Diagnostics
/// readers (lib/debug/) use [counters] and the read-only accessors below.
class TileCache extends ChangeNotifier {
  TileCache({
    required this.sprite,
    SplatWorker? worker,
    this.maxInFlight = 2,
    this.maxTiles = 256,
  }) : _worker = worker ?? SplatWorker();

  /// The gaussian sprite every splat samples.
  final ui.Image sprite;
  // Generates splats off the UI isolate; see _splatsFor. Disposed with this
  // cache.
  final SplatWorker _worker;

  /// Tile rasters allowed to run at once (checked in [_pump]). Mutable so the
  /// debug pane can tune it; the change applies on the next pump.
  int maxInFlight;

  /// Floor of the eviction budget, not a hard cap: [_evictExcess] keeps
  /// max([maxTiles], 2 * working set) tiles, and never evicts working-set
  /// tiles. Mutable so the debug pane can tune it; lowering it evicts on the
  /// next completed build, not immediately.
  int maxTiles;

  /// Cumulative activity counters, for diagnostics.
  final TileCacheCounters counters = TileCacheCounters();

  // State per tile key. _tiles holds built images; _recency orders them for
  // eviction; _queue/_queued are one waiting list (the set is a fast
  // membership test for the list, keep them in sync); _building are keys with
  // a build running. A key can be in _tiles and in _queue or _building at the
  // same time: that is a stale tile being updated.
  final Map<TileKey, CachedTile> _tiles = {};
  // Insertion order == recency (oldest first); re-inserted on use by tile().
  final LinkedHashSet<TileKey> _recency = LinkedHashSet<TileKey>();
  final Set<TileKey> _queued = {};
  final List<TileKey> _queue = [];
  final Set<TileKey> _building = {};

  // Tiles the most recent frame drew or asked for (including tiles used as
  // scaled fallbacks); shielded from eviction. Set by setWanted.
  Set<TileKey> _wanted = const {};

  // Per-stroke splat state, indexed by stroke index in the document. The
  // future entry de-duplicates concurrent requests so each stroke is sent to
  // the worker once; the value entry is kept for the session (not evicted;
  // ADR 0005 lists this as a known memory cost). Cleared by attach() for a
  // new document and by invalidateAll().
  final List<StrokeSplats?> _splats = [];
  final List<Future<StrokeSplats>?> _splatFutures = [];

  CanvasDocument? _document;
  // Bumped whenever every cached image becomes invalid (new document or
  // invalidateAll). Tiles and in-flight builds compare against it.
  int _revision = 0;
  bool _pumpScheduled = false;
  bool _disposed = false;
  // Reused buffer of sprite source rectangles for drawRawAtlas; see _rectsFor.
  Float32List _rects = Float32List(0);

  /// Number of tile rasters currently running (for tests and diagnostics).
  int get building => _building.length;

  /// Number of tiles currently cached.
  int get cachedTiles => _tiles.length;

  /// Tiles waiting for a free raster slot.
  int get queued => _queue.length;

  /// Tiles the last frame drew or fell back to.
  int get wantedTiles => _wanted.length;

  /// Strokes of the attached document whose splats have been generated.
  int get generatedStrokes {
    var n = 0;
    for (final splats in _splats) {
      if (splats != null) n++;
    }
    return n;
  }

  /// Bytes held by generated splat buffers (transforms plus colors).
  int get splatBytes {
    var n = 0;
    for (final splats in _splats) {
      if (splats != null) {
        n += splats.transforms.lengthInBytes + splats.colors.lengthInBytes;
      }
    }
    return n;
  }

  /// Tiles that hold an image (blank tiles hold none).
  int get imageTiles {
    var n = 0;
    for (final tile in _tiles.values) {
      if (tile.image != null) n++;
    }
    return n;
  }

  /// True when nothing is queued or building. This ignores stale tiles that
  /// have not been requested yet, so "idle" means the pipeline is drained for
  /// the tiles asked for so far. Tests poll it to wait for tiles to land.
  bool get idle => _queue.isEmpty && _building.isEmpty;

  /// Describes every cached, queued, or building tile for diagnostics. Builds
  /// one [TileInfo] (tile_stats.dart) per key; intended for tooling, not for
  /// the per-frame path.
  List<TileInfo> describeTiles() {
    final document = _document;
    final keys = <TileKey>{..._tiles.keys, ..._queued, ..._building};
    return [
      for (final key in keys)
        () {
          final tile = _tiles[key];
          final live = tile != null && tile.revision == _revision;
          return TileInfo(
            key: key,
            hasImage: live && tile.image != null,
            appliedStrokes: live ? tile.appliedStrokes : 0,
            current: live && (document == null || isCurrent(key, tile)),
            building: _building.contains(key),
            queued: _queued.contains(key),
          );
        }(),
    ];
  }

  /// Whether [key] is cached for the current revision and already holds every
  /// stroke that touches it. A built blank tile (no image) counts as cached.
  /// Does not touch recency. Unlike [isCurrent] it also checks the revision,
  /// so a tile from before a document replacement or [invalidateAll] reports
  /// false.
  bool isCachedCurrent(TileKey key) {
    final tile = _tiles[key];
    return tile != null && tile.revision == _revision && isCurrent(key, tile);
  }

  /// Discards every tile, queued request, and generated splat buffer, so the
  /// next frame rebuilds from scratch. The document is kept. Called by the
  /// debug pane's invalidate button; the same discard steps as the
  /// different-document branch of [attach], which must be kept in sync.
  void invalidateAll() {
    _revision++;
    _evictAll();
    _splats.clear();
    _splatFutures.clear();
    _queue.clear();
    _queued.clear();
    notifyListeners();
  }

  /// Returns the cached tile for [key], or null. Marks it recently used.
  /// Returns stale tiles too (it does not check [isCurrent]); the caller,
  /// `TiledRenderer.paint`, decides how to treat staleness. Also called for
  /// fallback sources by `TiledRenderer._drawFallback` and
  /// `_drawFinerChildren`, which keeps those tiles recent as well.
  CachedTile? tile(TileKey key) {
    final tile = _tiles[key];
    if (tile == null || tile.revision != _revision) return null;
    _recency
      ..remove(key)
      ..add(key);
    return tile;
  }

  /// Like [tile] but does not change recency, so tools can look without
  /// perturbing eviction order.
  CachedTile? peek(TileKey key) {
    final tile = _tiles[key];
    return tile == null || tile.revision != _revision ? null : tile;
  }

  /// Whether [tile] already contains every stroke of the current document that
  /// touches [key]. A tile that is behind only by strokes elsewhere is still
  /// current; see [_hasPending].
  bool isCurrent(TileKey key, CachedTile tile) {
    final document = _document;
    if (document == null) return true;
    return !_hasPending(key, tile.appliedStrokes, document);
  }

  /// Points the cache at [document]. A different document instance discards
  /// every tile; appended strokes keep existing tiles and mark them stale.
  /// `TiledRenderer.paint` calls this every frame, so the same-instance case
  /// must stay a cheap identity check.
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
  /// Cheap and idempotent; safe to call every frame (`TiledRenderer.paint`
  /// calls it for every visible tile that is not current). Does nothing for a
  /// tile that is already queued or building, or before [attach].
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
    counters.requests++;
    _queue.add(key);
    _schedulePump();
  }

  /// Records the tiles the latest frame needs. Queued work outside [wanted] is
  /// dropped, so panning away from a region stops spending time on it, and
  /// [wanted] tiles are never evicted while they are on screen. Called once
  /// per frame at the end of `TiledRenderer.paint`; [wanted] includes tiles
  /// used as scaled fallbacks, not only the target level.
  void setWanted(Set<TileKey> wanted) {
    _wanted = wanted;
    if (_queue.isEmpty) return;
    _queue.removeWhere((key) {
      final keep = wanted.contains(key);
      if (!keep) {
        _queued.remove(key);
        counters.droppedFromQueue++;
      }
      return !keep;
    });
  }

  /// True if any stroke from index [applied] onward touches [key]'s rectangle
  /// (plus [TileGrid.bleed]). Shared by [request] and [isCurrent]; its
  /// stroke-selection rule must match the `needed` loop in [_build].
  bool _hasPending(TileKey key, int applied, CanvasDocument document) {
    final rect = TileGrid.rectOf(key).inflate(TileGrid.bleed);
    for (var i = applied; i < document.strokeCount; i++) {
      if (_touches(document.strokeAt(i), rect)) return true;
    }
    return false;
  }

  // Conservative bounding-box test: stroke bounds exclude brush radius, so
  // grow them by PencilSplats.inkMargin (brush radius plus the largest splat
  // half-diagonal) before testing overlap.
  static bool _touches(CanvasStroke stroke, ui.Rect tileRect) =>
      stroke.bounds.inflate(PencilSplats.inkMargin).overlaps(tileRect);

  // Coalesces many request() calls in one frame into a single microtask, so
  // the pump runs once the current synchronous work (the paint) is done.
  void _schedulePump() {
    if (_pumpScheduled || _disposed) return;
    _pumpScheduled = true;
    scheduleMicrotask(_pump);
  }

  // Starts queued builds, oldest request first, up to maxInFlight at once.
  // Each build clears its own _building entry and re-pumps when it finishes.
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

  /// Builds or updates one tile: the core of the cache.
  ///
  /// Steps: (1) pick the strokes not yet applied that touch the tile;
  /// (2) get their splats (generated in the worker isolate, cached per
  /// stroke); (3) rasterize them over the old image, or skip rastering when
  /// none touch the tile; (4) store the result, record counters, evict, and
  /// notify listeners. The `finally` re-requests the key because strokes may
  /// have been appended while the raster ran.
  ///
  /// After every `await` the revision is re-checked: if the document was
  /// replaced or the cache invalidated meanwhile, the result is dropped (and
  /// the new image disposed) instead of being stored under the new revision.
  ///
  /// Coupled to: [_hasPending] (same selection rule), [_splatsFor],
  /// [_rasterize], [_evictExcess], and `TileCacheCounters.recordBuild`.
  Future<void> _build(TileKey key) async {
    final revision = _revision;
    final document = _document!;
    final clock = Stopwatch()..start();
    try {
      // Only reuse the old image if it belongs to this revision.
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
      // `splats` ends up in stroke order, which is the order they are drawn.
      final pending = [for (final i in needed) _splatsFor(document, i)];
      final splats = <StrokeSplats>[];
      for (final future in pending) {
        splats.add(await future);
      }
      // Document replaced or cache invalidated while awaiting: stale result.
      if (_disposed || revision != _revision) return;

      ui.Image? image;
      var rastered = 0;
      final TileBuildKind kind;
      if (splats.isEmpty) {
        // Nothing new touches this tile: keep the existing image (or stay
        // blank) and just advance the applied counter. No GPU work.
        image = base?.image;
        kind = TileBuildKind.skipped;
      } else {
        final baseImage = base?.image;
        kind = baseImage == null
            ? TileBuildKind.full
            : TileBuildKind.incremental;
        // The old image is disposed only after the replacement exists, so
        // the stale image stays drawable while the new one is being built.
        image = await _rasterize(key, baseImage, splats);
        if (_disposed || revision != _revision) {
          image.dispose();
          return;
        }
        baseImage?.dispose();
        for (final s in splats) {
          rastered += s.count;
        }
      }
      // Counter is the document's stroke count at build start, not at the
      // end: strokes appended mid-build stay pending and the finally block
      // re-requests them.
      _tiles[key] = CachedTile(image, count, revision);
      _recency
        ..remove(key)
        ..add(key);
      counters.recordBuild(kind, clock.elapsed, rastered);
      _evictExcess();
      notifyListeners();
    } on StateError {
      // Worker disposed mid-flight (SplatWorker.generate throws StateError
      // once disposed); nothing to do.
    } finally {
      _building.remove(key);
      if (!_disposed) {
        // Strokes may have been added while this raster ran.
        request(key);
        _schedulePump();
      }
    }
  }

  /// Returns the splats for stroke [index], asking the [SplatWorker] isolate
  /// at most once per stroke; later callers share the same future. The result
  /// is document-space, so it serves every tile and level.
  Future<StrokeSplats> _splatsFor(CanvasDocument document, int index) {
    while (_splats.length <= index) {
      _splats.add(null);
      _splatFutures.add(null);
    }
    return _splatFutures[index] ??= _worker
        .generate(document.strokeAt(index))
        .then((value) {
          counters.splatsGenerated += value.count;
          return _splats[index] = value;
        });
  }

  /// Rasterizes [strokes] into a new tile texture for [key], over [base] when
  /// given.
  ///
  /// The canvas is set up so document coordinates land on tile pixels:
  /// scale by 2^level, then translate by the tile's document-space origin.
  /// The mapping must match `TiledRenderer._drawTile` / `_drawFallback`,
  /// which map the texture back with [TileGrid.rectOf] and
  /// [TileGrid.texturePixels]. The old image is drawn first, 1:1 in texture
  /// pixels, so an incremental update re-samples it once per update. Splats
  /// outside the tile are clipped, which is how a splat straddling two tiles
  /// ends up in both (the strokes were selected using the bleed margin).
  /// Returns when the asynchronous `Picture.toImage` completes.
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

  // Source rectangles for drawRawAtlas: every splat samples the whole sprite,
  // so the list is [0, 0, edge, edge] repeated. Grown geometrically and
  // re-sliced to avoid per-tile allocation. `TiledRenderer._rectsFor` is the
  // same logic for the active stroke; keep them in sync.
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

  // Enforces the budget after a build. Evicts in recency order (oldest
  // first) but skips tiles in _wanted or _building; if those alone exceed the
  // budget, the cache simply stays over it (see the overview on why).
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
      counters.evictions++;
    }
  }

  // Disposes every image and forgets all tiles. Does not touch the queue or
  // splat buffers; callers (attach, invalidateAll, dispose) handle those.
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
