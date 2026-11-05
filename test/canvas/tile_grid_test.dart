// What: unit tests of TileGrid's pure geometry: choosing a level of detail
//   from zoom, tile sizes per level, which tiles cover a region, a tile's
//   coarser ancestor, and the document-space bounds of a rotated viewport.
// Why: design/canvas/tile-cache.md puts all tile geometry in tile_grid.dart as
// pure Dart (no
//   GPU, no async) because both the scheduler (TileCache) and the painter
//   (TiledRenderer) depend on it. Off-by-one errors here (an edge tile
//   double-counted or dropped, negative indices rounded toward zero, a
//   rotated view cut short) would show as missing or wrongly scaled tiles.
// Covers: lib/canvas/tile_grid.dart (TileKey, TileGrid.levelFor, tileSize,
//   tilesIn, rectOf, ancestor, visibleDocumentRect).

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:painter/canvas/tile_grid.dart';

void main() {
  group('level of detail', () {
    // Level L serves pixelsPerUnit in (2^(L-0.5), 2^(L+0.5)]
    // (design/canvas/tile-cache.md: LOD = ceil(log2(zoom * devicePixelRatio) -
    // 0.5)), so a tile is never magnified by more than sqrt(2). Called once per
    // frame by TiledRenderer.paint.
    test('picks the level whose resolution is closest, rounding up', () {
      expect(TileGrid.levelFor(1), 0);
      expect(TileGrid.levelFor(2), 1);
      expect(TileGrid.levelFor(4), 2);
      expect(TileGrid.levelFor(0.5), -1);
      // Between 1x and 2x: never magnify a tile more than sqrt(2) (~1.414).
      expect(TileGrid.levelFor(1.3), 0);
      expect(TileGrid.levelFor(1.5), 1);
    });

    // design/canvas/tile-cache.md: levels run from -4 to 5, spanning zoom
    // 0.1-16 at device pixel ratios up to about 4.
    test('clamps to the supported range', () {
      expect(TileGrid.levelFor(1e-9), TileGrid.minLevel);
      expect(TileGrid.levelFor(1e9), TileGrid.maxLevel);
    });

    test('tile edge in document units halves per level', () {
      expect(TileGrid.tileSize(0), 512);
      expect(TileGrid.tileSize(1), 256);
      expect(TileGrid.tileSize(-1), 1024);
    });
  });

  group('tilesIn', () {
    // Tiles are anchored to document space, so indices can be negative
    // (design/canvas/tile-cache.md Consequences: "negative indices are covered by tests").
    // Rounding toward zero instead of flooring would mis-index x < 0.
    test('covers a region exactly, including negative coordinates', () {
      final keys = TileGrid.tilesIn(
        const Rect.fromLTRB(-10, -10, 600, 20),
        0,
      ).toList();
      expect(keys.map((k) => (k.x, k.y)).toSet(), {
        (-1, -1),
        (0, -1),
        (1, -1),
        (-1, 0),
        (0, 0),
        (1, 0),
      });
    });

    // Regions are half-open on the right/bottom: a view ending exactly on a
    // tile edge must not request the next tile (tilesIn uses ceil() - 1).
    test(
      'a region ending exactly on an edge does not include the next tile',
      () {
        final keys = TileGrid.tilesIn(const Rect.fromLTRB(0, 0, 512, 512), 0);
        expect(keys.toList(), [const TileKey(0, 0, 0)]);
      },
    );

    test('empty region yields nothing', () {
      expect(TileGrid.tilesIn(Rect.zero, 0), isEmpty);
    });

    test('every point of the region lies in some yielded tile', () {
      const region = Rect.fromLTRB(-300.5, 77.25, 1300, 900);
      for (final level in [-2, 0, 3]) {
        final tiles = TileGrid.tilesIn(region, level).map(TileGrid.rectOf);
        for (final p in [
          region.topLeft,
          region.center,
          region.bottomRight - const Offset(0.001, 0.001),
        ]) {
          expect(
            tiles.any((r) => r.contains(p)),
            isTrue,
            reason: '$p @ $level',
          );
        }
      }
    });
  });

  // TileGrid.ancestor is what TiledRenderer._drawFallback uses to find a
  // coarser cached tile to draw scaled up while the right level builds.
  group('ancestor', () {
    test('is the coarser tile containing the finer one', () {
      const key = TileKey(5, -3, 2);
      final parent = TileGrid.ancestor(key, 1)!;
      expect(
        TileGrid.rectOf(parent).contains(TileGrid.rectOf(key).center),
        isTrue,
      );
      final root = TileGrid.ancestor(key, -1)!;
      expect(
        TileGrid.rectOf(root).contains(TileGrid.rectOf(key).center),
        isTrue,
      );
      expect(TileGrid.rectOf(root).width, TileGrid.tileSize(-1));
    });

    test('is null for the same or a finer level', () {
      expect(TileGrid.ancestor(const TileKey(0, 0, 1), 1), isNull);
      expect(TileGrid.ancestor(const TileKey(0, 0, 1), 2), isNull);
    });
  });

  // A rotated view needs a larger document-space box than the screen size
  // (design/canvas/tile-cache.md: up to about 270 tiles when zoomed out and
  // rotated). All four screen corners are mapped to document space and bounded.
  test('visibleDocumentRect bounds a rotated viewport', () {
    const screen = Size(100, 50);
    const angle = math.pi / 4;
    Offset toDocument(Offset p) => Offset(
      p.dx * math.cos(angle) - p.dy * math.sin(angle),
      p.dx * math.sin(angle) + p.dy * math.cos(angle),
    );

    final rect = TileGrid.visibleDocumentRect(screen, toDocument);

    for (final corner in [
      Offset.zero,
      const Offset(100, 0),
      const Offset(100, 50),
      const Offset(0, 50),
    ]) {
      expect(rect.inflate(1e-9).contains(toDocument(corner)), isTrue);
    }
    // A rotated rectangle's box is larger than the unrotated one.
    expect(rect.width, greaterThan(100));
  });
}
