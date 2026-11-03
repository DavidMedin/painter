import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:painter/canvas/canvas_controller.dart';
import 'package:painter/canvas/tile_grid.dart';
import 'package:painter/canvas/tile_stats.dart';
import 'package:painter/canvas/tiled_renderer.dart';

CanvasController _controller() {
  final controller = CanvasController();
  addTearDown(controller.dispose);
  return controller;
}

void _stroke(CanvasController c, Offset a, Offset b) {
  c.beginStroke(a, 1);
  c.extendStroke(b, 1);
  c.endStroke();
}

TiledRenderer _renderer() {
  final renderer = TiledRenderer();
  addTearDown(renderer.dispose);
  return renderer;
}

void _paint(
  TiledRenderer renderer,
  CanvasDocument document, {
  Rect visible = const Rect.fromLTWH(0, 0, 200, 40),
  double pixelsPerUnit = 1,
}) {
  final recorder = ui.PictureRecorder();
  renderer.paint(
    Canvas(recorder),
    document: document,
    active: const [],
    visible: visible,
    pixelsPerUnit: pixelsPerUnit,
  );
  recorder.endRecording().dispose();
}

/// Paints until the cache is idle and one further frame has run.
Future<void> _settle(
  TiledRenderer renderer,
  CanvasDocument document, {
  Rect visible = const Rect.fromLTWH(0, 0, 200, 40),
  double pixelsPerUnit = 1,
}) async {
  for (var i = 0; i < 300; i++) {
    _paint(renderer, document, visible: visible, pixelsPerUnit: pixelsPerUnit);
    if (renderer.cache.idle) {
      await Future<void>.delayed(Duration.zero);
      _paint(
        renderer,
        document,
        visible: visible,
        pixelsPerUnit: pixelsPerUnit,
      );
      if (renderer.cache.idle) return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('tile cache never went idle');
}

void main() {
  group('frame classification', () {
    test('an unbuilt tile is missing, then current once it lands', () async {
      final c = _controller();
      _stroke(c, const Offset(20, 20), const Offset(180, 20));
      final renderer = _renderer();

      _paint(renderer, c.document);
      expect(renderer.frame.visible, 1);
      expect(renderer.frame.missing, 1);
      expect(renderer.frame.draws[const TileKey(0, 0, 0)], TileDraw.missing);

      await _settle(renderer, c.document);
      expect(renderer.frame.drawnCurrent, 1);
      expect(renderer.frame.missing, 0);
      expect(renderer.frame.draws[const TileKey(0, 0, 0)], TileDraw.current);
    });

    test('a tile no stroke touches is blank, not missing', () async {
      final c = _controller();
      _stroke(c, const Offset(20, 20), const Offset(180, 20));
      final renderer = _renderer();
      // A far-away region: the stroke never reaches it.
      const far = Rect.fromLTWH(5000, 5000, 100, 40);
      await _settle(renderer, c.document, visible: far);

      expect(renderer.frame.blank, renderer.frame.visible);
      expect(renderer.frame.missing, 0);
      expect(renderer.frame.draws.values, everyElement(TileDraw.blank));
    });

    test('a tile behind a new stroke is stale until it is updated', () async {
      final c = _controller();
      _stroke(c, const Offset(20, 20), const Offset(180, 20));
      final renderer = _renderer();
      await _settle(renderer, c.document);

      _stroke(c, const Offset(20, 30), const Offset(180, 30));
      _paint(renderer, c.document);
      expect(renderer.frame.drawnStale, 1);
      expect(renderer.frame.drawnCurrent, 0);
      expect(renderer.frame.draws[const TileKey(0, 0, 0)], TileDraw.stale);

      await _settle(renderer, c.document);
      expect(renderer.frame.drawnCurrent, 1);
      expect(renderer.frame.drawnStale, 0);
    });

    test(
      'zooming in draws the old level scaled up until the new lands',
      () async {
        final c = _controller();
        _stroke(c, const Offset(20, 20), const Offset(180, 20));
        final renderer = _renderer();
        await _settle(renderer, c.document);

        // 4x zoom wants level 2; only level 0 is cached.
        const zoomed = Rect.fromLTWH(75, 15, 50, 10);
        _paint(renderer, c.document, visible: zoomed, pixelsPerUnit: 4);
        expect(renderer.frame.level, 2);
        expect(renderer.frame.fallbackCoarser, greaterThan(0));
        expect(renderer.frame.missing, 0);
        expect(renderer.frame.draws.values, everyElement(TileDraw.coarser));
      },
    );

    test('every visible tile is counted in exactly one bucket', () async {
      final c = _controller();
      _stroke(c, const Offset(20, 20), const Offset(1500, 900));
      final renderer = _renderer();
      const view = Rect.fromLTWH(0, 0, 1600, 1000);

      for (var i = 0; i < 4; i++) {
        _paint(renderer, c.document, visible: view);
        final f = renderer.frame;
        expect(
          f.drawnCurrent +
              f.drawnStale +
              f.fallbackCoarser +
              f.fallbackFiner +
              f.missing +
              f.blank,
          f.visible,
          reason: 'frame $i',
        );
        expect(f.draws.length, f.visible);
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
    });
  });

  group('cache counters', () {
    test('first build is full, an added stroke is incremental', () async {
      final c = _controller();
      _stroke(c, const Offset(20, 20), const Offset(180, 20));
      final renderer = _renderer();
      await _settle(renderer, c.document);
      final counters = renderer.cache.counters;
      expect(counters.fullBuilds, 1);
      expect(counters.incrementalBuilds, 0);

      _stroke(c, const Offset(20, 30), const Offset(180, 30));
      await _settle(renderer, c.document);
      expect(counters.fullBuilds, 1);
      expect(counters.incrementalBuilds, 1);
      expect(counters.builds, 2);
      expect(
        counters.splatsRastered,
        greaterThan(counters.splatsGenerated ~/ 2),
      );
    });

    test('viewing ink-free paper builds a blank tile without raster work', () async {
      final c = _controller();
      _stroke(c, const Offset(20, 20), const Offset(180, 20));
      final renderer = _renderer();
      final counters = renderer.cache.counters;

      // No stroke reaches this region, so its first build has nothing to draw.
      await _settle(
        renderer,
        c.document,
        visible: const Rect.fromLTWH(5000, 5000, 100, 40),
      );

      expect(counters.skippedBuilds, 1);
      expect(counters.fullBuilds, 0);
      expect(counters.splatsRastered, 0);
      expect(counters.buildMillis, isEmpty);
      expect(renderer.cache.imageTiles, 0);
      expect(renderer.cache.cachedTiles, 1);
    });

    test(
      'a built tile that a distant stroke cannot touch is not rebuilt',
      () async {
        final c = _controller();
        _stroke(c, const Offset(20, 20), const Offset(180, 20));
        final renderer = _renderer();
        await _settle(renderer, c.document);
        final counters = renderer.cache.counters;
        final builds = counters.builds;

        _stroke(c, const Offset(9000, 9000), const Offset(9100, 9000));
        await _settle(renderer, c.document);

        expect(counters.builds, builds);
        expect(renderer.frame.drawnCurrent, 1);
      },
    );

    test('build timing history is bounded', () {
      final counters = TileCacheCounters();
      for (var i = 0; i < TileCacheCounters.historyLength * 2; i++) {
        counters.recordBuild(
          TileBuildKind.full,
          const Duration(milliseconds: 3),
          1,
        );
      }
      expect(counters.buildMillis.length, TileCacheCounters.historyLength);
      expect(counters.builds, TileCacheCounters.historyLength * 2);
    });

    test(
      'lowering maxTiles evicts least recently used tiles and counts them',
      () async {
        final c = _controller();
        _stroke(c, const Offset(10, 10), const Offset(3000, 10));
        final renderer = _renderer();
        // Build tiles across the stroke, one view at a time.
        for (var x = 0.0; x < 3000; x += 512) {
          await _settle(
            renderer,
            c.document,
            visible: Rect.fromLTWH(x, 0, 100, 40),
          );
        }
        final cache = renderer.cache;
        expect(cache.cachedTiles, greaterThanOrEqualTo(6));

        cache.maxTiles = 2;
        // Evict happens on the next completed build; ask for one more tile.
        await _settle(
          renderer,
          c.document,
          visible: const Rect.fromLTWH(5000, 0, 100, 40),
        );
        expect(cache.counters.evictions, greaterThan(0));
        expect(cache.cachedTiles, lessThan(6));
      },
    );

    test('moving away drops queued requests and counts them', () async {
      final c = _controller();
      _stroke(c, const Offset(10, 10), const Offset(5000, 10));
      final renderer = _renderer();
      renderer.cache.maxInFlight = 1;

      // Request many tiles, then look somewhere else before they build.
      _paint(
        renderer,
        c.document,
        visible: const Rect.fromLTWH(0, 0, 4000, 40),
      );
      expect(renderer.cache.queued + renderer.cache.building, greaterThan(2));
      _paint(
        renderer,
        c.document,
        visible: const Rect.fromLTWH(0, 800, 100, 40),
      );

      expect(renderer.cache.counters.droppedFromQueue, greaterThan(0));
    });

    test(
      'invalidateAll empties the cache and rebuilds from the document',
      () async {
        final c = _controller();
        _stroke(c, const Offset(20, 20), const Offset(180, 20));
        final renderer = _renderer();
        await _settle(renderer, c.document);
        expect(renderer.cache.cachedTiles, 1);
        expect(renderer.cache.generatedStrokes, 1);

        renderer.cache.invalidateAll();
        expect(renderer.cache.cachedTiles, 0);
        expect(renderer.cache.generatedStrokes, 0);
        expect(renderer.cache.splatBytes, 0);

        await _settle(renderer, c.document);
        expect(renderer.cache.cachedTiles, 1);
        expect(renderer.cache.imageTiles, 1);
        expect(renderer.cache.counters.fullBuilds, 2);
      },
    );

    test('describeTiles reports built, queued, and stale tiles', () async {
      final c = _controller();
      _stroke(c, const Offset(20, 20), const Offset(180, 20));
      final renderer = _renderer();
      await _settle(renderer, c.document);

      var tiles = renderer.cache.describeTiles();
      expect(tiles, hasLength(1));
      expect(tiles.single.hasImage, isTrue);
      expect(tiles.single.current, isTrue);
      expect(tiles.single.appliedStrokes, 1);

      _stroke(c, const Offset(20, 30), const Offset(180, 30));
      tiles = renderer.cache.describeTiles();
      expect(tiles.single.current, isFalse);
    });

    test('peek does not change eviction order but tile does', () async {
      final c = _controller();
      _stroke(c, const Offset(10, 10), const Offset(1100, 10));
      final renderer = _renderer();
      for (final x in [0.0, 512.0, 1024.0]) {
        await _settle(
          renderer,
          c.document,
          visible: Rect.fromLTWH(x, 0, 100, 40),
        );
      }
      final cache = renderer.cache;
      expect(cache.cachedTiles, 3);

      // Touch the oldest tile with peek: it must remain the eviction victim.
      expect(cache.peek(const TileKey(0, 0, 0)), isNotNull);
      cache.maxTiles = 2;
      // Nothing is wanted now, so the next build evicts down to 2.
      cache.setWanted(const {});
      await _settle(
        renderer,
        c.document,
        visible: const Rect.fromLTWH(1536, 0, 100, 40),
      );
      expect(cache.peek(const TileKey(0, 0, 0)), isNull);
    });
  });
}
