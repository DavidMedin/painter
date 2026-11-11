// What: Unit tests for PaneLayout: add, neighbor, join, splitters, splitter
//   moves with the 100 px clamp, and reading stored layouts.
// Why: Every pane operation reduces to this geometry. The tests protect the
//   invariant that panes always tile the workspace without overlap (PANE-1),
//   the exact-edge rules for join and swap (PANE-14, PANE-15), and the pixel
//   limits (PANE-18, PANE-19).
// Covers: lib/workspace/pane_layout.dart.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:painter/workspace/pane_layout.dart';

/// Sum of pane areas; 1 for a layout that tiles the unit square.
double _totalArea(PaneLayout layout) => [
  for (final id in layout.ids) layout.rect(id).width * layout.rect(id).height,
].fold(0.0, (a, b) => a + b);

/// Four panes in a 2x2 grid: 0 top left, 1 top right, 2 bottom left, 3 bottom
/// right.
PaneLayout _grid() {
  var layout = PaneLayout.single(0);
  layout = layout.add(0, PaneEdge.right, 1);
  layout = layout.add(0, PaneEdge.bottom, 2);
  return layout.add(1, PaneEdge.bottom, 3);
}

/// Pane 0 on the left, panes 1 (top) and 2 (bottom) stacked on the right.
PaneLayout _tee() {
  final layout = PaneLayout.single(0).add(0, PaneEdge.right, 1);
  return layout.add(1, PaneEdge.bottom, 2);
}

const _area = Size(1000, 800);

void main() {
  group('add', () {
    test('gives the new pane the half touching the chosen edge', () {
      for (final edge in PaneEdge.values) {
        final layout = PaneLayout.single(0).add(0, edge, 1);
        final added = layout.rect(1);
        final kept = layout.rect(0);
        switch (edge) {
          case PaneEdge.top:
            expect(added, const Rect.fromLTRB(0, 0, 1, 0.5));
            expect(kept, const Rect.fromLTRB(0, 0.5, 1, 1));
          case PaneEdge.bottom:
            expect(added, const Rect.fromLTRB(0, 0.5, 1, 1));
            expect(kept, const Rect.fromLTRB(0, 0, 1, 0.5));
          case PaneEdge.left:
            expect(added, const Rect.fromLTRB(0, 0, 0.5, 1));
            expect(kept, const Rect.fromLTRB(0.5, 0, 1, 1));
          case PaneEdge.right:
            expect(added, const Rect.fromLTRB(0.5, 0, 1, 1));
            expect(kept, const Rect.fromLTRB(0, 0, 0.5, 1));
        }
        expect(_totalArea(layout), closeTo(1, 1e-12));
      }
    });

    test('is allowed only while both halves keep 100 px', () {
      final layout = PaneLayout.single(0);
      expect(layout.canAdd(0, PaneEdge.right, const Size(200, 600)), isTrue);
      expect(layout.canAdd(0, PaneEdge.right, const Size(199.9, 600)), isFalse);
      // The limit follows the axis that the new line cuts across.
      expect(layout.canAdd(0, PaneEdge.top, const Size(1000, 200)), isTrue);
      expect(layout.canAdd(0, PaneEdge.top, const Size(1000, 199)), isFalse);
    });
  });

  group('neighbor', () {
    test('is the pane sharing the whole edge', () {
      final layout = _grid();
      expect(layout.neighbor(0, PaneEdge.right), 1);
      expect(layout.neighbor(1, PaneEdge.left), 0);
      expect(layout.neighbor(0, PaneEdge.bottom), 2);
      expect(layout.neighbor(3, PaneEdge.top), 1);
    });

    test('is null on the workspace boundary', () {
      final layout = _grid();
      expect(layout.neighbor(0, PaneEdge.left), isNull);
      expect(layout.neighbor(0, PaneEdge.top), isNull);
      expect(layout.neighbor(3, PaneEdge.right), isNull);
      expect(layout.neighbor(3, PaneEdge.bottom), isNull);
    });

    test('is null when several panes border the edge', () {
      final layout = _tee();
      expect(layout.neighbor(0, PaneEdge.right), isNull);
      expect(layout.neighbor(1, PaneEdge.left), isNull);
      expect(layout.neighbor(2, PaneEdge.left), isNull);
      expect(layout.neighbor(1, PaneEdge.bottom), 2);
    });
  });

  group('join', () {
    test('extends the pane over its neighbor and keeps the tiling', () {
      final layout = _grid().join(0, PaneEdge.right)!;
      expect(layout.ids, unorderedEquals([0, 2, 3]));
      expect(layout.rect(0), const Rect.fromLTRB(0, 0, 1, 0.5));
      expect(_totalArea(layout), closeTo(1, 1e-12));
    });

    test('returns null without a neighbor', () {
      expect(_tee().join(0, PaneEdge.right), isNull);
      expect(PaneLayout.single(0).join(0, PaneEdge.left), isNull);
    });

    test('can join panes that were never split from each other', () {
      // 0 and 1 sit in different halves of the first split.
      final layout = _grid().join(0, PaneEdge.right)!.join(2, PaneEdge.right)!;
      expect(layout.ids, unorderedEquals([0, 2]));
      expect(layout.neighbor(0, PaneEdge.bottom), 2);
    });
  });

  group('splitters', () {
    test('two panes have one splitter at their shared line', () {
      final splitters = PaneLayout.single(0)
          .add(0, PaneEdge.right, 1)
          .splitters();
      expect(splitters, hasLength(1));
      final splitter = splitters.single;
      expect(splitter.vertical, isTrue);
      expect(splitter.position, 0.5);
      expect([splitter.start, splitter.end], [0, 1]);
      expect(splitter.before, {0});
      expect(splitter.after, {1});
    });

    test('collinear borders that touch are one splitter', () {
      final splitters = _grid().splitters();
      final vertical = splitters.where((s) => s.vertical).single;
      expect(vertical.before, {0, 2});
      expect(vertical.after, {1, 3});
      final horizontal = splitters.where((s) => !s.vertical).single;
      expect(horizontal.before, {0, 1});
      expect(horizontal.after, {2, 3});
    });

    test('a border that ends at another splitter is its own splitter', () {
      final splitters = _tee().splitters();
      final vertical = splitters.singleWhere((s) => s.vertical);
      expect(vertical.after, {1, 2});
      final horizontal = splitters.singleWhere((s) => !s.vertical);
      expect(horizontal.start, 0.5);
      expect(horizontal.end, 1);
    });
  });

  group('moveSplitter', () {
    test('moves every border on the line to the same coordinate', () {
      final layout = _tee();
      final splitter = layout.splitters().singleWhere((s) => s.vertical);
      final moved = layout.moveSplitter(splitter, 0.1, _area);
      expect(moved.rect(0).right, closeTo(0.6, 1e-12));
      expect(moved.rect(1).left, moved.rect(0).right);
      expect(moved.rect(2).left, moved.rect(0).right);
      expect(_totalArea(moved), closeTo(1, 1e-12));
      // Joining still works because the shared borders stayed exactly equal.
      expect(moved.neighbor(1, PaneEdge.bottom), 2);
    });

    test('stops where a pane would drop below 100 px', () {
      final layout = PaneLayout.single(0).add(0, PaneEdge.right, 1);
      final splitter = layout.splitters().single;
      final left = layout.moveSplitter(splitter, -0.9, _area);
      expect(left.rect(0).width * _area.width, closeTo(100, 1e-9));
      final right = layout.moveSplitter(splitter, 0.9, _area);
      expect(right.rect(1).width * _area.width, closeTo(100, 1e-9));
    });

    test('keeps the neighbours of a shared line above 100 px together', () {
      final layout = _grid();
      final splitter = layout.splitters().singleWhere((s) => !s.vertical);
      final moved = layout.moveSplitter(splitter, 0.9, _area);
      expect(moved.rect(2).height * _area.height, closeTo(100, 1e-9));
      expect(moved.rect(3).height * _area.height, closeTo(100, 1e-9));
    });

    test('never moves a splitter whose panes are already below the limit', () {
      final layout = PaneLayout.single(0).add(0, PaneEdge.right, 1);
      final splitter = layout.splitters().single;
      const tiny = Size(150, 600);
      expect(layout.moveSplitter(splitter, 0.2, tiny), same(layout));
      expect(layout.moveSplitter(splitter, -0.2, tiny), same(layout));
    });
  });

  group('fromJson', () {
    test('reads what toJson wrote', () {
      final layout = _grid().join(0, PaneEdge.right)!;
      final read = PaneLayout.fromJson(layout.toJson())!;
      expect(read.ids, unorderedEquals(layout.ids));
      for (final id in layout.ids) {
        expect(read.rect(id), layout.rect(id));
      }
    });

    Map<String, Object?> entry(int id, num l, num t, num r, num b) => {
      'id': id,
      'left': l,
      'top': t,
      'right': r,
      'bottom': b,
    };

    test('rejects layouts that are not a tiling of the unit square', () {
      expect(PaneLayout.fromJson(null), isNull);
      expect(PaneLayout.fromJson([]), isNull);
      // Overlap.
      expect(
        PaneLayout.fromJson([entry(0, 0, 0, 0.6, 1), entry(1, 0.4, 0, 1, 1)]),
        isNull,
      );
      // Gap.
      expect(
        PaneLayout.fromJson([entry(0, 0, 0, 0.4, 1), entry(1, 0.6, 0, 1, 1)]),
        isNull,
      );
      // Outside the square.
      expect(PaneLayout.fromJson([entry(0, 0, 0, 1.5, 1)]), isNull);
      // Duplicate id, negative id, empty rectangle, wrong types.
      expect(
        PaneLayout.fromJson([entry(0, 0, 0, 0.5, 1), entry(0, 0.5, 0, 1, 1)]),
        isNull,
      );
      expect(PaneLayout.fromJson([entry(-1, 0, 0, 1, 1)]), isNull);
      expect(PaneLayout.fromJson([entry(0, 0, 0, 0, 1)]), isNull);
      expect(
        PaneLayout.fromJson([entry(0, 0, 0, 1, 1)..['left'] = 'x']),
        isNull,
      );
    });
  });
}
