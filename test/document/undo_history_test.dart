// What: Unit tests of EditHistory: the acceptance examples of
//   docs/spec/undo-redo.md (including the two-Participant one), identical
//   redo, one commit per undo and redo, the 256-edit cap, redo of a
//   stroke a peer removed, and one debug log record per finished gesture,
//   undo and redo (docs/spec/logging.md LOG-19, LOG-20).
// Why: docs/decisions/012-undo-per-participant.md makes undo an inverse
//   change on the shared content document that reverts only the local
//   Participant's gestures (UNDO-1..5, UNDO-7..9); these tests pin that
//   behavior on real Automerge replicas synced in process.
// Covers: lib/document/undo_history.dart, with
//   lib/document/content_document.dart (ContentDocument.transact and the
//   CRDT mirror) and the gesture hook in lib/canvas/canvas_controller.dart.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:painter/crdt/crdt_document.dart';
import 'package:painter/document/undo_history.dart';
import 'package:painter/logging/painter_log.dart';

import 'content_test_support.dart';

/// [replica] with an EditHistory, disposed after the test.
EditHistory _historyFor(Replica replica, {int? capacity}) {
  final history = EditHistory(
    controller: replica.controller,
    content: replica.content,
    capacity: capacity ?? EditHistory.defaultCapacity,
  );
  addTearDown(history.dispose);
  return history;
}

void main() {
  test('draw A, draw B, undo shows only A; redo shows both', () {
    final p = Replica.create();
    final history = _historyFor(p);
    final a = p.draw(Offset.zero);
    final b = p.draw(const Offset(20, 0));

    expect(history.undo(), isTrue);
    expect(p.ids, [a]);
    expect(p.content.crdt.keys(['strokes']), [a]);

    expect(history.redo(), isTrue);
    expect(p.ids, [a, b]);
    expect(p.content.crdt.keys(['strokes']).toSet(), {a, b});
  });

  test('a finished gesture, an undo and a redo each make one debug record; '
      'pointer moves and refused undos make none (LOG-19, LOG-20)', () {
    final p = Replica.create();
    final log = PainterLog.memory();
    addTearDown(log.dispose);
    final history = EditHistory(
      controller: p.controller,
      content: p.content,
      log: log,
    );
    addTearDown(history.dispose);

    p.controller.beginStroke(Offset.zero, 1);
    for (var x = 1; x <= 20; x++) {
      p.controller.extendStroke(Offset(x.toDouble(), 0), 1);
    }
    expect(log.entries, isEmpty, reason: 'nothing per pointer event');
    p.controller.endStroke();
    history.undo();
    history.undo();
    history.redo();
    history.redo();

    expect(
      [for (final entry in log.entries) entry.messageId],
      [
        'document.stroke.finished',
        'document.undo.succeeded',
        'document.redo.succeeded',
      ],
    );
    expect(
      log.entries.every((entry) => entry.level == PainterLogLevel.debug),
      isTrue,
    );
  });

  test('draw A, undo, draw C, redo has no effect (UNDO-3)', () {
    final p = Replica.create();
    final history = _historyFor(p);
    p.draw(Offset.zero);
    history.undo();
    expect(history.canRedo, isTrue);
    final c = p.draw(const Offset(30, 0));

    expect(history.canRedo, isFalse);
    expect(history.redo(), isFalse);
    expect(p.ids, [c]);
  });

  test('undo mid-stroke does nothing and the stroke completes (UNDO-4)', () {
    final p = Replica.create();
    final history = _historyFor(p);
    final a = p.draw(Offset.zero);
    p.controller.beginStroke(const Offset(50, 50), 1);
    p.controller.extendStroke(const Offset(60, 50), 1);

    expect(history.canUndo, isFalse);
    expect(history.undo(), isFalse);
    expect(history.redo(), isFalse);
    expect(p.ids, [a]);

    p.controller.endStroke();
    expect(p.canvas.strokeCount, 2);
    expect(history.undoStack, hasLength(2));
  });

  test('undo and redo with an empty history do nothing (UNDO-2)', () {
    final p = Replica.create();
    final history = _historyFor(p);
    expect(history.canUndo, isFalse);
    expect(history.undo(), isFalse);
    expect(history.redo(), isFalse);
    expect(p.canvas.strokeCount, 0);
  });

  test('a multi-chunk gesture is one edit, undone and redone in one '
      'commit each', () {
    final p = Replica.create();
    final history = _historyFor(p);
    p.controller
      ..beginStroke(Offset.zero, 0.5)
      ..extendStroke(const Offset(400, 0), 1)
      ..endStroke();
    final chunks = p.canvas.strokeCount;
    expect(chunks, greaterThan(1));
    expect(history.undoStack.single.strokes, hasLength(chunks));
    final commits = <CrdtChangeOrigin>[];
    p.content.crdt.addListener(commits.add);

    history.undo();
    expect(p.canvas.strokeCount, 0);
    expect(commits, [CrdtChangeOrigin.local]);

    history.redo();
    expect(p.canvas.strokeCount, chunks);
    expect(commits, [CrdtChangeOrigin.local, CrdtChangeOrigin.local]);
  });

  test('redo restores identical stroke data', () {
    final p = Replica.create();
    final history = _historyFor(p);
    p.draw(Offset.zero, delta: const Offset(37, 11));
    final before = p.canvas.strokes.single;
    final crdt = p.content.crdt;
    final storedBefore = crdt.entries(['strokes', before.id]);

    history
      ..undo()
      ..redo();

    final after = p.canvas.strokes.single;
    expect(
      [after.id, after.seed, after.z, after.gesture],
      [before.id, before.seed, before.z, before.gesture],
    );
    expect(after.points.map((q) => (q.position, q.weight)), [
      for (final q in before.points) (q.position, q.weight),
    ]);
    final storedAfter = crdt.entries(['strokes', before.id]);
    expect(storedAfter.keys.toSet(), storedBefore.keys.toSet());
    expect(storedAfter['points'] as Uint8List, storedBefore['points']);
    expect(
      [storedAfter['seed'], storedAfter['z'], storedAfter['gesture']],
      [storedBefore['seed'], storedBefore['z'], storedBefore['gesture']],
    );
  });

  test('the history keeps the latest 256 edits and drops the oldest', () {
    expect(EditHistory.defaultCapacity, 256);
    final p = Replica.create();
    final history = _historyFor(p);
    for (var i = 0; i < 260; i++) {
      p.draw(Offset(i * 3.0, 0), delta: const Offset(2, 0));
    }
    final oldest = p.ids.take(4).toList();

    var undone = 0;
    while (history.undo()) {
      undone++;
    }

    expect(undone, 256);
    expect(p.ids, oldest);
  });

  group('two Participants', () {
    test('P1 undoing A keeps P2\'s B drawn over it, on both replicas', () {
      final p1 = Replica.create();
      final p2 = Replica.copyOf(p1);
      final h1 = _historyFor(p1);
      final h2 = _historyFor(p2);

      final a = p1.draw(Offset.zero);
      p1.syncWith(p2);
      final b = p2.draw(const Offset(2, 1));
      p2.syncWith(p1);
      expect(p1.ids, [a, b]);
      // Remote strokes never enter a history (UNDO-7, PNT-A0018-03).
      expect(h1.undoStack, hasLength(1));
      expect(h2.undoStack, hasLength(1));

      expect(h1.undo(), isTrue);
      p1.syncWith(p2);
      expect(p1.ids, [b]);
      expect(p2.ids, [b]);

      expect(h2.undo(), isTrue);
      p2.syncWith(p1);
      expect(p1.ids, isEmpty);
      expect(p2.ids, isEmpty);

      expect(h1.redo(), isTrue);
      p1.syncWith(p2);
      expect(p2.ids, [a]);
    });

    test('redo restores a stroke a peer had already removed', () {
      final p1 = Replica.create();
      final p2 = Replica.copyOf(p1);
      final h1 = _historyFor(p1);
      final a = p1.draw(Offset.zero);
      p1.syncWith(p2);

      // A peer removes the stroke (no edit of P2 can do this yet).
      p2.controller.removeStrokes([a]);
      expect(p2.content.crdt.keys(['strokes']), isEmpty);
      p2.syncWith(p1);
      expect(p1.ids, isEmpty);

      expect(h1.undo(), isTrue);
      expect(h1.redo(), isTrue);
      p1.syncWith(p2);

      expect(p1.ids, [a]);
      expect(p2.ids, [a]);
    });
  });

  test('dispose stops recording gestures', () {
    final p = Replica.create();
    final history = EditHistory(controller: p.controller, content: p.content);
    history.dispose();
    expect(p.controller.onGestureCompleted, isNull);
    p.draw(Offset.zero);
    expect(p.canvas.strokeCount, 1);
  });
}
