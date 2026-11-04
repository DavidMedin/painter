// What: Controller tests for long pointer gestures, including chunk boundary
// interpolation and limits on the live tail.
// Why: long live splat batches make each frame increasingly expensive; completed
// chunks must enter the document so TileCache can rasterize the trail while the
// pointer gesture continues.
// Covers: lib/canvas/canvas_controller.dart (CanvasController active chunks,
// CanvasDocument append order, and chunk boundaries).

import 'package:flutter_test/flutter_test.dart';
import 'package:painter/canvas/canvas_controller.dart';

void main() {
  test('long pointer segments commit bounded continuous chunks', () {
    final controller = CanvasController();
    addTearDown(controller.dispose);
    const start = Offset(0, 10);
    const end = Offset(10000, 10);

    controller.beginStroke(start, 1);
    controller.extendStroke(end, 0.5);

    expect(controller.document.strokeCount, greaterThan(1));
    for (var i = 0; i < controller.document.strokeCount; i++) {
      final stroke = controller.document.strokeAt(i);
      expect(
        stroke.points.length,
        lessThanOrEqualTo(CanvasController.activeStrokeChunkPoints),
      );
      expect(
        _pathLength(stroke.points),
        lessThanOrEqualTo(CanvasController.activeStrokeChunkLength + 1e-9),
      );
      expect(stroke.seed, i + 1);
      if (i + 1 < controller.document.strokeCount) {
        expect(
          stroke.points.last.position,
          controller.document.strokeAt(i + 1).points.first.position,
        );
      }
    }
    expect(
      _pathLength([
        for (final stroke in controller.document.strokes) ...stroke.points,
        ...controller.activePoints,
      ]),
      closeTo(end.dx - start.dx, 1e-6),
    );
    expect(
      controller.activePoints.length,
      lessThanOrEqualTo(CanvasController.activeStrokeChunkPoints),
    );
    expect(
      _pathLength(controller.activePoints),
      lessThanOrEqualTo(CanvasController.activeStrokeChunkLength + 1e-9),
    );
    expect(controller.activePoints.last.position, end);
    expect(controller.activePoints.last.weight, 0.5);

    controller.endStroke();
    expect(controller.activePoints, isEmpty);
    expect(
      _pathLength([
        for (final stroke in controller.document.strokes) ...stroke.points,
      ]),
      closeTo(end.dx - start.dx, 1e-6),
    );
  });

  test(
    'repeated stationary pointer events cannot grow the live point list',
    () {
      final controller = CanvasController();
      addTearDown(controller.dispose);
      const position = Offset(4, 9);

      controller.beginStroke(position, 1);
      for (var i = 0; i < CanvasController.activeStrokeChunkPoints * 3; i++) {
        controller.extendStroke(position, 1);
      }

      expect(controller.document.strokeCount, greaterThan(1));
      for (final stroke in controller.document.strokes) {
        expect(
          stroke.points.length,
          lessThanOrEqualTo(CanvasController.activeStrokeChunkPoints),
        );
      }
      expect(
        controller.activePoints.length,
        lessThanOrEqualTo(CanvasController.activeStrokeChunkPoints),
      );
    },
  );
}

/// Returns the sum of segment lengths in [points].
double _pathLength(List<CanvasPoint> points) {
  var length = 0.0;
  for (var i = 1; i < points.length; i++) {
    length += (points[i].position - points[i - 1].position).distance;
  }
  return length;
}
