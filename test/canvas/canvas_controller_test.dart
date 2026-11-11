// What: Tests for the canvas document model and the active-stroke controller:
//   bounded chunks of long pointer gestures, stroke ids, seeds and z order,
//   ordered inserts and removals with their change notifications, removal and
//   re-insertion by id, and loading the earlier JSON format.
// Why: Long live splat batches make each frame increasingly expensive, so
//   completed chunks must enter the document while the gesture continues
//   (docs/decisions/004-tile-cache.md). Strokes need ids and stored seeds
//   that survive saving and interleaving with other peers' strokes (DOCF-2,
//   docs/decisions/008-document-file-format.md PNT-A0014-04 to PNT-A0014-06),
//   and files in the earlier format must render as before (DOCF-3).
// Covers: lib/canvas/canvas_controller.dart (CanvasController, CanvasDocument,
//   CanvasStroke, ActorIdSource, strokeSeedOf).

import 'package:flutter_test/flutter_test.dart';
import 'package:painter/canvas/canvas_controller.dart';

/// A controller whose ids come from actor `ab`, disposed at teardown.
CanvasController _controller() {
  final controller = CanvasController(newId: ActorIdSource('ab').next);
  addTearDown(controller.dispose);
  return controller;
}

/// A one-point stroke with the given order fields.
CanvasStroke _stroke(String id, int z, {int seed = 1}) => CanvasStroke(
  const [CanvasPoint(position: Offset(1, 2), weight: 1)],
  id: id,
  seed: seed,
  z: z,
  gesture: 'g:$id',
);

void main() {
  test('long pointer segments commit bounded continuous chunks', () {
    final controller = _controller();
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
      final controller = _controller();
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

  test('each chunk is a stroke with its own id, seeded from that id', () {
    final controller = _controller();

    controller.beginStroke(Offset.zero, 1);
    final firstChunkId = controller.activeStrokeId;
    controller.extendStroke(const Offset(200, 0), 1);
    controller.endStroke();
    controller.beginStroke(const Offset(0, 50), 1);
    controller.endStroke();

    final strokes = controller.document.strokes;
    expect(strokes.length, greaterThan(2));
    expect(strokes.first.id, firstChunkId);
    expect(controller.activeStrokeId, isNull);
    final ids = {for (final s in strokes) s.id};
    expect(ids, hasLength(strokes.length));
    for (final stroke in strokes) {
      expect(stroke.id, matches(RegExp(r'^ab:\d+$')));
      expect(stroke.seed, strokeSeedOf(stroke.id));
      expect(controller.document.strokeById(stroke.id), same(stroke));
    }
    // z grows by one per stroke, so every new stroke lands on top.
    expect(
      [for (final s in strokes) s.z],
      [for (var z = 1; z <= strokes.length; z++) z],
    );
    // All chunks but the last belong to the first gesture.
    final gestures = [for (final s in strokes) s.gesture];
    expect(gestures.toSet(), hasLength(2));
    expect(gestures.sublist(0, strokes.length - 1).toSet(), hasLength(1));
    expect(gestures.last, isNot(gestures.first));
  });

  // The seed must be identical on every peer, so its hash is pinned:
  // FNV-1a 32 of "a" is 0xe40c292c and of "" is the offset basis 0x811c9dc5.
  test('a seed is the FNV-1a hash of the id with the top bit cleared', () {
    expect(strokeSeedOf('a'), 0xe40c292c & 0x7fffffff);
    expect(strokeSeedOf(''), 0x811c9dc5 & 0x7fffffff);
    expect(strokeSeedOf('ab:1'), isNot(strokeSeedOf('ab:2')));
  });

  test('ids carry their actor and count up from 1', () {
    final source = ActorIdSource('00ff');
    expect([source.next(), source.next()], ['00ff:1', '00ff:2']);
    expect(ActorIdSource.random().actorHex, matches(RegExp(r'^[0-9a-f]{32}$')));
  });

  group('CanvasDocument order and changes', () {
    test('orders strokes by z, then id, and reports where they landed', () {
      final document = CanvasDocument.empty();
      final changes = <(CanvasStrokeChangeKind, String)>[];
      document.addObserver((c) => changes.add((c.kind, c.stroke.id)));

      document.insert(_stroke('b:1', 1));
      document.insert(_stroke('b:2', 3));
      document.insert(_stroke('a:9', 3));
      document.insert(_stroke('c:1', 2));
      document.insert(_stroke('c:2', 4));

      expect(
        [for (final s in document.strokes) s.id],
        ['b:1', 'c:1', 'a:9', 'b:2', 'c:2'],
      );
      expect(document.nextZ, 5);
      expect(changes, [
        (CanvasStrokeChangeKind.appended, 'b:1'),
        (CanvasStrokeChangeKind.appended, 'b:2'),
        (CanvasStrokeChangeKind.inserted, 'a:9'),
        (CanvasStrokeChangeKind.inserted, 'c:1'),
        (CanvasStrokeChangeKind.appended, 'c:2'),
      ]);
    });

    test('removes by id and refuses a duplicate id', () {
      final document = CanvasDocument.empty()
        ..insert(_stroke('a:1', 1))
        ..insert(_stroke('a:2', 2));
      final changes = <CanvasStrokeChange>[];
      document.addObserver(changes.add);

      final removed = document.remove('a:1');
      expect(document.remove('a:1'), isNull);

      expect(removed!.id, 'a:1');
      expect([for (final s in document.strokes) s.id], ['a:2']);
      expect(document.strokeById('a:1'), isNull);
      expect(changes.single.kind, CanvasStrokeChangeKind.removed);
      expect(() => document.insert(_stroke('a:2', 9)), throwsArgumentError);
      expect(document.strokeCount, 1);
    });

    test('an empty document puts the first stroke at z 1', () {
      expect(CanvasDocument.empty().nextZ, 1);
    });
  });

  test('removed strokes go back with their ids, seeds and order', () {
    final controller = _controller();
    for (var i = 0; i < 3; i++) {
      controller
        ..beginStroke(Offset(0, i * 20.0), 1)
        ..extendStroke(Offset(30, i * 20.0), 1)
        ..endStroke();
    }
    final before = [...controller.document.strokes];
    var notified = 0;
    controller.addListener(() => notified++);

    final removed = controller.removeStrokes([before[1].id, 'zz:1']);
    expect(removed, [same(before[1])]);
    expect(controller.document.strokes, [before[0], before[2]]);
    expect(notified, 1);

    controller.insertStrokes(removed);
    expect(controller.document.strokes, before);
    expect(controller.document.strokeAt(1).seed, before[1].seed);
    expect(notified, 2);
  });

  // DOCF-3: the earlier format rendered stroke i with seed i + 1, so a loaded
  // document must keep exactly that seed and order.
  test('loading the earlier JSON format gives seeds and z of 1..n', () {
    final source = CanvasController(newId: ActorIdSource('cd').next)
      ..beginStroke(Offset.zero, 1)
      ..extendStroke(const Offset(10, 0), 0.5)
      ..endStroke()
      ..beginStroke(const Offset(0, 9), 1)
      ..endStroke()
      ..beginStroke(const Offset(5, 5), 0.2)
      ..endStroke();
    addTearDown(source.dispose);

    final loaded = CanvasDocument.fromJson(
      source.document.toJson(),
      newId: ActorIdSource('ef').next,
    );

    expect(loaded.strokeCount, 3);
    for (var i = 0; i < 3; i++) {
      final stroke = loaded.strokeAt(i);
      expect(stroke.seed, i + 1);
      expect(stroke.z, i + 1);
      expect(stroke.id, startsWith('ef:'));
      expect(
        [for (final p in stroke.points) (p.position, p.weight)],
        [
          for (final p in source.document.strokeAt(i).points)
            (p.position, p.weight),
        ],
      );
    }
    expect(loaded.nextZ, 4);
    expect(loaded.toJson(), source.document.toJson());
  });
}

/// Returns the sum of segment lengths in [points].
double _pathLength(List<CanvasPoint> points) {
  var length = 0.0;
  for (var i = 1; i < points.length; i++) {
    length += (points[i].position - points[i - 1].position).distance;
  }
  return length;
}
