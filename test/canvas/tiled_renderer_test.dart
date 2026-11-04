// What: end-to-end pixel checks of the tiled pencil renderer: strokes are
//   painted through TiledRenderer (and its TileCache) into an offscreen image
//   and the resulting pixels are measured.
// Why: the tile cache replaced per-frame replay of every stroke (ADR 0005).
//   These tests keep ADR 0004's pencil look (grainy specks, pressure, stable
//   grain) and pin the cache's behavior: incremental tile updates, stale or
//   scaled tiles shown until replacements land, no eviction of on-screen
//   tiles. docs/status.md ("Tiled Texture Cache Verification") lists bugs
//   found by these scenarios.
// Covers: lib/canvas/ tiled_renderer.dart (TiledRenderer.paint),
//   tile_cache.dart (TileCache), tile_grid.dart, pencil_splats.dart,
//   and via the cache splat_worker.dart (SplatWorker).

// Overview of the system under test and the testing strategy
//
// TiledRenderer draws the canvas from 512x512-pixel textures ("tiles") laid
// out in a document-space grid at power-of-two levels of detail. paint() never
// builds anything: it draws cached tiles, falls back to scaled tiles of other
// levels for missing ones, and asks TileCache.request for what is missing or
// stale. The cache builds tiles in the background (splats generated in a
// worker isolate, rasterized with Picture.toImage), so a tile appears some
// frames after it is first requested. Only the current active chunk stays
// live; completed chunks are ordinary document strokes in the tile cache.
//
// Strategy: offscreen rasterization plus pixel statistics. Each test records
// the renderer into a PictureRecorder, rasterizes it to a small 200x40 image
// and counts or compares pixels (ink is black on white, so the red channel is
// the tone). Pencil grain is pseudo-random, so assertions are statistical
// (fraction of dark/light pixels, ink counts within a tolerance) except where
// determinism is the point (same seed -> byte-identical frames). Because
// tiles land asynchronously, tests use real timers: _settled() repaints,
// yielding to the event loop, until TileCache.idle.
//
// Deliberately NOT verified here (see ADR 0005 and docs/status.md "Not
// verified"): the running macOS window (docs/testing.md forbids windowed runs
// without permission, so everything is headless), raster-thread/GPU time and
// texture memory on real hardware, how the scaled-fallback transition looks
// to an artist, accumulated blur from repeated incremental updates at
// non-integer magnification, and very large document extents. That a landing
// tile schedules a repaint of the real CanvasView is also not covered here;
// the notifyListeners path was only checked by a throwaway widget test.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:painter/canvas/canvas_controller.dart';
import 'package:painter/canvas/pencil_splats.dart';
import 'package:painter/canvas/tile_cache.dart';
import 'package:painter/canvas/tile_grid.dart';
import 'package:painter/canvas/tiled_renderer.dart';

/// Size in pixels of every offscreen frame the helpers below render. Small
/// enough to scan every pixel; wide enough to hold a 160-unit stroke.
const _width = 200;
const _height = 40;

/// Builds a [CanvasDocument] by driving a real [CanvasController] through
/// beginStroke / extendStroke / endStroke for each point list, so strokes get
/// the seeds (1-based index) the app assigns on commit. The controller is
/// disposed at test teardown; the returned document stays usable until then.
CanvasDocument _documentOf(List<List<CanvasPoint>> strokes) {
  final controller = CanvasController();
  addTearDown(controller.dispose);
  for (final points in strokes) {
    controller.beginStroke(points.first.position, points.first.weight);
    for (final point in points.skip(1)) {
      controller.extendStroke(point.position, point.weight);
    }
    controller.endStroke();
  }
  return controller.document;
}

/// A two-point horizontal stroke from x=20 to x=180 at height [y] with a
/// constant pressure [weight].
List<CanvasPoint> _horizontal(double weight, {double y = 20}) => [
  CanvasPoint(position: Offset(20, y), weight: weight),
  CanvasPoint(position: Offset(180, y), weight: weight),
];

/// Paints one frame of [document] (plus the live [active] stroke) through
/// [renderer] over a white background and returns its RGBA bytes.
///
/// This is a single paint: tiles not yet built are missing or scaled
/// stand-ins, which is exactly what several tests inspect. Use [_settled] to
/// wait for the cache. The default [visible] rect equals the image, i.e. zoom
/// 1 with the identity transform.
Future<ByteData> _frame(
  TiledRenderer renderer,
  CanvasDocument document, {
  List<CanvasPoint> active = const [],
  double pixelsPerUnit = 1,
  Rect visible = const Rect.fromLTWH(0, 0, _width * 1.0, _height * 1.0),
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(Colors.white, BlendMode.src);
  renderer.paint(
    canvas,
    document: document,
    active: active,
    visible: visible,
    pixelsPerUnit: pixelsPerUnit,
  );
  final image = await recorder.endRecording().toImage(_width, _height);
  addTearDown(image.dispose);
  return (await image.toByteData())!;
}

/// Paints until the cache has nothing left to build, then returns that frame.
///
/// Tiles are built off the UI thread and land after real time passes, so this
/// loops (up to 200 x 10 ms) painting, because paint() is what issues tile
/// requests. The extra paint once the cache first reports idle lets requests
/// made by the previous frame (e.g. for a stale tile) show up as work before
/// trusting idleness. Fails the test if the cache never settles.
Future<ByteData> _settled(
  TiledRenderer renderer,
  CanvasDocument document, {
  List<CanvasPoint> active = const [],
}) async {
  var bytes = await _frame(renderer, document, active: active);
  for (var i = 0; i < 200; i++) {
    if (renderer.cache.idle) {
      // One more paint so requests made by the previous frame are visible.
      bytes = await _frame(renderer, document, active: active);
      if (renderer.cache.idle) return bytes;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
    bytes = await _frame(renderer, document, active: active);
  }
  fail('tile cache never went idle');
}

/// A fresh [TiledRenderer] (own sprite and TileCache) disposed at teardown.
/// Each test gets its own so no cached tiles leak between tests.
TiledRenderer _renderer() {
  final renderer = TiledRenderer();
  addTearDown(renderer.dispose);
  return renderer;
}

/// The red channel of pixel (x, y) in [_frame] output. Ink is black on white,
/// so red alone measures darkness (255 = paper, 0 = full ink).
int _red(ByteData bytes, int x, int y) => bytes.getUint8((y * _width + x) * 4);

/// Counts pixels visibly marked (red below 200) in the whole frame; the
/// measure of "how much ink" for comparing pressure and zoom levels.
int _inked(ByteData bytes) {
  var n = 0;
  for (var y = 0; y < _height; y++) {
    for (var x = 0; x < _width; x++) {
      if (_red(bytes, x, y) < 200) n++;
    }
  }
  return n;
}

/// Reference: the same splats drawn directly, with no tiles or cache.
///
/// Regenerates each stroke with PencilSplats.build (same seed) and draws it
/// with one drawRawAtlas call, the way the pre-tile renderer did (ADR 0004),
/// using [renderer]'s sprite. Used as ground truth for the tile pipeline.
Future<ByteData> _direct(
  CanvasDocument document,
  TiledRenderer renderer,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(Colors.white, BlendMode.src);
  final paint = Paint()
    ..isAntiAlias = true
    ..filterQuality = FilterQuality.medium;
  for (final stroke in document.strokes) {
    final batch = PencilSplats.build(stroke.points, strokeSeed: stroke.seed);
    final rects = Float32List(batch.count * 4);
    for (var i = 0; i < rects.length; i += 4) {
      rects[i + 2] = PencilSplats.spritePixels.toDouble();
      rects[i + 3] = PencilSplats.spritePixels.toDouble();
    }
    canvas.drawRawAtlas(
      renderer.sprite,
      batch.transforms,
      rects,
      batch.colors,
      BlendMode.modulate,
      null,
      paint,
    );
  }
  final image = await recorder.endRecording().toImage(_width, _height);
  addTearDown(image.dispose);
  return (await image.toByteData())!;
}

// The first four tests are the pixel-statistics assertions carried over from
// the former PencilRenderer test (docs/status.md), now through the tile
// pipeline; the rest cover tiling behavior.
void main() {
  test('a stroke renders as grainy specks, not a solid bar', () async {
    final renderer = _renderer();
    final bytes = await _settled(renderer, _documentOf([_horizontal(1)]));
    final radius = CanvasController.brushDiameter / 2;

    var dark = 0, light = 0, total = 0;
    for (var y = 20 - radius.toInt() + 1; y < 20 + radius.toInt(); y++) {
      for (var x = 40; x < 160; x++) {
        final v = _red(bytes, x, y);
        total++;
        if (v < 80) dark++;
        if (v > 200) light++;
      }
    }

    expect(dark, greaterThan(total * 0.05), reason: 'graphite must be visible');
    expect(light, greaterThan(total * 0.05), reason: 'paper must show through');
    expect(dark, lessThan(total * 0.7));
  });

  test('nothing is painted far from the stroke', () async {
    final renderer = _renderer();
    final bytes = await _settled(renderer, _documentOf([_horizontal(1)]));

    for (var x = 0; x < _width; x++) {
      expect(_red(bytes, x, 2), 255, reason: 'row 2, x=$x');
      expect(_red(bytes, x, _height - 3), 255, reason: 'row 37, x=$x');
    }
    expect(_red(bytes, 3, 20), 255);
    expect(_red(bytes, _width - 4, 20), 255);
  });

  test('a long live gesture caches its completed trail', () async {
    final controller = CanvasController();
    addTearDown(controller.dispose);
    final renderer = _renderer();
    controller.beginStroke(const Offset(20, 20), 1);
    controller.extendStroke(const Offset(2000, 20), 1);

    expect(controller.document.strokeCount, greaterThan(1));
    final maxLiveSplats =
        CanvasController.activeStrokeChunkPoints *
        PencilSplats.splatsPerSample *
        4;
    final bytes = await _settled(
      renderer,
      controller.document,
      active: controller.activePoints,
    );
    final tile = renderer.cache.tile(const TileKey(0, 0, 0))!;

    expect(renderer.frame.activeSplats, lessThan(maxLiveSplats));
    expect(tile.appliedStrokes, controller.document.strokeCount);
    expect(_red(bytes, 100, 20), lessThan(255));
  });

  test('lighter pressure marks fewer pixels than full pressure', () async {
    final light = _inked(
      await _settled(_renderer(), _documentOf([_horizontal(0.2)])),
    );
    final full = _inked(
      await _settled(_renderer(), _documentOf([_horizontal(1)])),
    );

    expect(light, greaterThan(0));
    expect(light, lessThan(full));
  });

  // This short stroke stays within one chunk. Its live stream and committed
  // tile use the same nextSeed (CanvasStroke.seed, ADR 0005), so the frames
  // compare byte for byte.
  test('committing a stroke does not change its grain', () async {
    final points = [
      const CanvasPoint(position: Offset(80, 20), weight: 1),
      const CanvasPoint(position: Offset(120, 20), weight: 1),
    ];
    final renderer = _renderer();

    final drawing = await _frame(
      renderer,
      CanvasDocument.empty(),
      active: points,
    );
    final committed = await _settled(renderer, _documentOf([points]));

    expect(
      committed.buffer.asUint8List(),
      drawing.buffer.asUint8List(),
      reason: 'grain must not visibly re-roll on pointer-up',
    );
  });

  // Ground-truth test for the whole tile pipeline: tile build, level-0 1:1
  // rasterization and compositing must not change the picture vs. drawing
  // the same splats with a plain drawRawAtlas (_direct).
  test('tiled output matches drawing the splats directly', () async {
    final document = _documentOf([_horizontal(1), _horizontal(0.5, y: 28)]);
    final renderer = _renderer();

    final tiled = await _settled(renderer, document);
    final direct = await _direct(document, renderer);

    var maxDiff = 0, differing = 0;
    for (var i = 0; i < _width * _height; i++) {
      final d = (tiled.getUint8(i * 4) - direct.getUint8(i * 4)).abs();
      if (d > maxDiff) maxDiff = d;
      if (d > 8) differing++;
    }
    // Tile rasterization at level 0 is 1:1, so only sampling noise remains.
    expect(differing, lessThan(_width * _height * 0.01));
    expect(_inked(tiled), closeTo(_inked(direct), _inked(direct) * 0.05));
  });

  // Splats straddling a tile edge are drawn into both tiles through
  // TileGrid.bleed plus PencilSplats.inkMargin (TileCache._rasterize,
  // _touches). Without that bleed a pale stripe would appear at the edge.
  // The nested settle() and the translate below are a workaround: _frame
  // always shows document x in [0, 200), but the edge is at x = 512, so the
  // view is offset instead. settle() paints (with visible = view, output
  // discarded) until the tiles exist; the final paint then translates the
  // canvas by -460 so the edge lands at screen x = 52.
  test('a stroke crossing a tile edge shows no seam', () async {
    // Tile edge at x = 512 at level 0; draw across it.
    final points = [
      const CanvasPoint(position: Offset(480, 20), weight: 1),
      const CanvasPoint(position: Offset(544, 20), weight: 1),
    ];
    final document = _documentOf([points]);
    final renderer = _renderer();
    const view = Rect.fromLTWH(460, 0, 100, 40);

    Future<ByteData> settle() async {
      for (var i = 0; i < 200; i++) {
        final bytes = await _frame(renderer, document, visible: view);
        if (renderer.cache.idle && i > 0) return bytes;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      fail('never idle');
    }

    // Render with the document translated so the view starts at 0.
    final recorder = ui.PictureRecorder();
    await settle();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.white, BlendMode.src);
    canvas.translate(-460, 0);
    renderer.paint(
      canvas,
      document: document,
      active: const [],
      visible: view,
      pixelsPerUnit: 1,
    );
    final image = await recorder.endRecording().toImage(_width, _height);
    addTearDown(image.dispose);
    final bytes = (await image.toByteData())!;

    // Average ink in the columns straddling x=512 (screen x=52) must match
    // neighbouring columns: a missing bleed would leave a pale stripe.
    double columnInk(int x) {
      var sum = 0.0;
      for (var y = 17; y < 24; y++) {
        sum += 255 - _red(bytes, x, y);
      }
      return sum / 7;
    }

    final seam = (columnInk(51) + columnInk(52) + columnInk(53)) / 3;
    final left = (columnInk(40) + columnInk(41) + columnInk(42)) / 3;
    final right = (columnInk(62) + columnInk(63) + columnInk(64)) / 3;
    final neighbours = (left + right) / 2;
    expect(neighbours, greaterThan(10));
    expect(seam, greaterThan(neighbours * 0.6));
  });

  // Each 160-unit gesture becomes three bounded document chunks. TileCache
  // incrementally adds those chunks over the old image; both gestures must
  // remain visible after the second update.
  test('adding a stroke updates a tile without redrawing old strokes', () async {
    final controller = CanvasController();
    addTearDown(controller.dispose);
    final renderer = _renderer();

    controller.beginStroke(const Offset(20, 12), 1);
    controller.extendStroke(const Offset(180, 12), 1);
    controller.endStroke();
    await _settled(renderer, controller.document);
    final before = renderer.cache.tile(const TileKey(0, 0, 0))!;
    final firstGestureChunks = controller.document.strokeCount;
    expect(before.appliedStrokes, firstGestureChunks);

    controller.beginStroke(const Offset(20, 28), 1);
    controller.extendStroke(const Offset(180, 28), 1);
    controller.endStroke();
    final after = await _settled(renderer, controller.document);
    final tile = renderer.cache.tile(const TileKey(0, 0, 0))!;

    expect(tile.appliedStrokes, controller.document.strokeCount);
    expect(tile.appliedStrokes, greaterThan(firstGestureChunks));
    // Both strokes are visible: the first survived, the second was drawn over.
    double rowInk(int y) {
      var n = 0;
      for (var x = 40; x < 160; x++) {
        if (_red(after, x, y) < 200) n++;
      }
      return n.toDouble();
    }

    expect(rowInk(12), greaterThan(0));
    expect(rowInk(28), greaterThan(0));
  });

  // Pins the "stale tile stays visible" rule of ADR 0005: TiledRenderer.paint
  // draws a tile that is behind the document (TileCache.isCurrent false) from
  // its old image while TileCache.request queues the update.
  test('stale tiles keep showing the old image until the update lands', () async {
    final controller = CanvasController();
    addTearDown(controller.dispose);
    final renderer = _renderer();

    controller.beginStroke(const Offset(20, 20), 1);
    controller.extendStroke(const Offset(180, 20), 1);
    controller.endStroke();
    final settled = await _settled(renderer, controller.document);

    controller.beginStroke(const Offset(20, 30), 1);
    controller.extendStroke(const Offset(180, 30), 1);
    controller.endStroke();
    // First frame after the commit: the new stroke is not rastered yet, but the
    // old content must not vanish.
    final immediately = await _frame(renderer, controller.document);

    expect(_inked(immediately), greaterThanOrEqualTo(_inked(settled)));
    await _settled(renderer, controller.document);
  });

  // Pins the scaled-fallback path (TiledRenderer._drawFallback): at 4x
  // TileGrid.levelFor picks level 2, whose tile does not exist yet, so the
  // cached level-0 tile is drawn scaled up in its place. The loop then
  // repaints (zoomed() paints through a scaled canvas) until the real
  // level-2 tile lands. This is the "first zoom after drawing" scenario
  // docs/status.md names for a bug where a tile whose strokes were already
  // generated was recorded blank (a SynchronousFuture inside Future.wait
  // returned an empty list); a blank level-2 tile would fail the final ink
  // comparison.
  test('zooming in scales the old tile at once, then replaces it', () async {
    final document = _documentOf([_horizontal(1)]);
    final renderer = _renderer();
    final level0 = await _settled(renderer, document);

    // Zoom 4x about the stroke's centre (100, 20): screen = (doc - c) * 4 + c.
    const zoom = 4.0;
    const centre = Offset(100, 20);
    Future<ByteData> zoomed() async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawColor(Colors.white, BlendMode.src);
      canvas
        ..translate(centre.dx, centre.dy)
        ..scale(zoom)
        ..translate(-centre.dx, -centre.dy);
      renderer.paint(
        canvas,
        document: document,
        active: const [],
        visible: const Rect.fromLTWH(
          100 - 100 / zoom,
          20 - 20 / zoom,
          _width / zoom,
          _height / zoom,
        ),
        pixelsPerUnit: zoom,
      );
      final image = await recorder.endRecording().toImage(_width, _height);
      addTearDown(image.dispose);
      return (await image.toByteData())!;
    }

    final first = await zoomed();
    expect(renderer.lastLevel, 2);
    // The level-2 tile cannot exist yet (it is built in the background), but
    // the level-0 tile must already be standing in for it.
    expect(_inked(first), greaterThan(_inked(level0)));

    for (var i = 0; i < 200; i++) {
      if (renderer.cache.tile(const TileKey(0, 0, 2)) != null) break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await zoomed();
    }
    expect(renderer.cache.tile(const TileKey(0, 0, 2)), isNotNull);
    // Replacement keeps the stroke covering a similar amount of screen.
    final settled = await zoomed();
    expect(_inked(settled), closeTo(_inked(first), _inked(first) * 0.25));
  });

  // Regression for the eviction bug in docs/status.md: a constant maxTiles
  // smaller than the on-screen working set would evict visible tiles every
  // frame. TileCache._evictExcess now uses max(maxTiles, 2 x wanted) and
  // skips wanted tiles. Confirmed in status.md to fail (2 of 6 tiles
  // survive) with that protection disabled. This test drives TileCache
  // directly (setWanted + request, as paint() does each frame) with
  // maxTiles: 2 and six wanted tiles; the renderer is only borrowed for its
  // sprite.
  test('a working set larger than the tile budget is never evicted', () async {
    // Stroke spans many tiles; budget (maxTiles) is smaller than the view.
    final points = [
      const CanvasPoint(position: Offset(10, 10), weight: 1),
      const CanvasPoint(position: Offset(3000, 10), weight: 1),
    ];
    final document = _documentOf([points]);
    final cache = TileCache(sprite: _renderer().sprite, maxTiles: 2);
    addTearDown(cache.dispose);
    cache.attach(document);

    final wanted = {for (var x = 0; x < 6; x++) TileKey(x, 0, 0)};
    cache.setWanted(wanted);
    wanted.forEach(cache.request);
    for (var i = 0; i < 300 && !(cache.idle && cache.cachedTiles >= 6); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      wanted.forEach(cache.request);
    }

    expect(
      cache.cachedTiles,
      6,
      reason: 'wanted tiles must survive maxTiles=2',
    );
    for (final key in wanted) {
      expect(cache.tile(key), isNotNull, reason: '$key');
    }
  });

  // TileCache.attach discards every tile when given a different document
  // instance (ADR 0005 "Document replacement"); painting an empty document
  // afterwards must show no leftover ink.
  test('replacing the document discards cached tiles', () async {
    final renderer = _renderer();
    await _settled(renderer, _documentOf([_horizontal(1)]));
    expect(renderer.cache.cachedTiles, greaterThan(0));

    final blank = CanvasDocument.empty();
    final bytes = await _settled(renderer, blank);

    expect(_inked(bytes), 0);
  });
}
