// What: Unit tests for CanvasViewportController: a view is a center, an
//   extent across the pane's shorter side and a rotation, mapped to any pane
//   size; pan, zoom and rotate about a point; extent limits; and the stored
//   Canvas state.
// Why: docs/spec/canvas.md CNVS-7 to CNVS-9 and
//   docs/decisions/011-relative-canvas-view.md promise that one stored view
//   frames the same region in panes of different sizes, that resizing keeps
//   center and extent, and that extent stays within 64..10240. Workspace
//   members see one view in windows of different sizes, so these are checked
//   directly on the model.
// Covers: lib/canvas/canvas_viewport.dart.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:painter/canvas/canvas_viewport.dart';

/// Expects [actual] within [tolerance] of [expected] on both axes.
void _expectNear(Offset actual, Offset expected, {double tolerance = 1e-6}) {
  expect(actual.dx, closeTo(expected.dx, tolerance), reason: 'x of $actual');
  expect(actual.dy, closeTo(expected.dy, tolerance), reason: 'y of $actual');
}

/// A view away from every default, so no check passes by accident.
CanvasViewportController _view() {
  final view = CanvasViewportController()
    ..setView(center: const Offset(300, -40), extent: 500, rotation: 0.3);
  addTearDown(view.dispose);
  return view;
}

void main() {
  test('one view frames the same point and extent in panes of any size', () {
    final view = _view();
    // 800x600: the shorter side is vertical. 300x900: it is horizontal.
    const wide = Size(800, 600);
    const tall = Size(300, 900);

    _expectNear(view.toDocument(wide.center(Offset.zero), wide), view.center);
    _expectNear(view.toDocument(tall.center(Offset.zero), tall), view.center);
    final acrossWide =
        view.toDocument(const Offset(400, 0), wide) -
        view.toDocument(const Offset(400, 600), wide);
    final acrossTall =
        view.toDocument(const Offset(0, 450), tall) -
        view.toDocument(const Offset(300, 450), tall);
    expect(acrossWide.distance, closeTo(500, 1e-9));
    expect(acrossTall.distance, closeTo(500, 1e-9));
  });

  // docs/spec/canvas.md acceptance example: halving a pane's width while it is
  // the shorter side keeps the drawing centered and shows it half as large.
  test('resizing a pane keeps center and extent and rescales the drawing', () {
    final view = _view();
    const before = Size(600, 900);
    const after = Size(300, 900);
    final mark = view.center + const Offset(40, 0);
    final sizeBefore =
        (view.toScreen(mark, before) - view.toScreen(view.center, before))
            .distance;

    _expectNear(view.toScreen(view.center, after), after.center(Offset.zero));
    final sizeAfter =
        (view.toScreen(mark, after) - view.toScreen(view.center, after))
            .distance;
    expect(sizeAfter, closeTo(sizeBefore / 2, 1e-9));
    expect(view.center, const Offset(300, -40));
    expect(view.extent, 500);
  });

  test('the default view maps a 1024-pixel square pane 1:1', () {
    final view = CanvasViewportController();
    addTearDown(view.dispose);
    const pane = Size(1024, 1024);

    expect(view.center, const Offset(512, 512));
    expect(view.extent, 1024);
    expect(view.rotation, 0);
    _expectNear(
      view.toScreen(const Offset(100, 700), pane),
      const Offset(100, 700),
    );
  });

  test('zoom and rotate keep the document point under the pointer', () {
    final view = _view();
    const pane = Size(640, 480);
    const pointer = Offset(90, 410);
    final anchored = view.toDocument(pointer, pane);

    view.zoomAt(pointer, pane, 2.5);
    expect(view.extent, closeTo(200, 1e-9));
    _expectNear(view.toScreen(anchored, pane), pointer);

    view.rotateAt(pointer, pane, -1.1);
    expect(view.rotation, closeTo(0.3 - 1.1, 1e-12));
    _expectNear(view.toScreen(anchored, pane), pointer);
  });

  test('panning moves the grabbed document point with the pointer', () {
    final view = _view();
    const pane = Size(640, 480);
    const pointer = Offset(200, 100);
    final grabbed = view.toDocument(pointer, pane);

    view.panBy(const Offset(-35, 18), pane);

    _expectNear(view.toScreen(grabbed, pane), pointer + const Offset(-35, 18));
    expect(view.extent, 500);
  });

  test('extent stays between 64 and 10240 (CNVS-9)', () {
    final view = _view();
    const pane = Size(400, 400);

    view.zoomAt(Offset.zero, pane, 1000);
    expect(view.extent, CanvasViewportController.minimumExtent);
    view.zoomAt(Offset.zero, pane, 1e-6);
    expect(view.extent, CanvasViewportController.maximumExtent);
    view.setView(center: Offset.zero, extent: 1, rotation: 0);
    expect(view.extent, CanvasViewportController.minimumExtent);
  });

  test('an empty pane leaves the view unchanged', () {
    final view = _view();

    view
      ..panBy(const Offset(10, 10), Size.zero)
      ..zoomAt(Offset.zero, Size.zero, 2)
      ..rotateAt(Offset.zero, Size.zero, 1);

    expect(view.center, const Offset(300, -40));
    expect(view.extent, 500);
    expect(view.rotation, 0.3);
  });

  group('stored Canvas state', () {
    test('round-trips center, extent and rotation', () {
      final view = _view();
      final json = view.toJson();

      expect(json, {
        'center': {'x': 300.0, 'y': -40.0},
        'extent': 500.0,
        'rotation': 0.3,
      });
      final restored = CanvasViewportController.fromJson(json)!;
      addTearDown(restored.dispose);
      expect(restored.center, view.center);
      expect(restored.extent, view.extent);
      expect(restored.rotation, view.rotation);
    });

    const valid = {
      'center': {'x': 1.0, 'y': 2.0},
      'extent': 1024.0,
      'rotation': 0.0,
    };
    final unusable = <String, Object?>{
      'not a map': 'view',
      'missing center': {...valid}..remove('center'),
      'missing extent': {...valid}..remove('extent'),
      'non-finite center': {
        ...valid,
        'center': {'x': double.nan, 'y': 2.0},
      },
      'non-finite rotation': {...valid, 'rotation': double.infinity},
      'extent below 64': {...valid, 'extent': 63.0},
      'extent above 10240': {...valid, 'extent': 10241.0},
      'earlier pan and zoom': {
        'pan': {'dx': 0.0, 'dy': 0.0},
        'zoom': 1.0,
        'rotation': 0.0,
      },
    };
    for (final entry in unusable.entries) {
      test('rejects ${entry.key}', () {
        expect(CanvasViewportController.fromJson(entry.value), isNull);
      });
    }
  });
}
