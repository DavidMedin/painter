// What: Unit tests of ContentDocument: the content schema it writes, local
//   strokes reaching the CRDT, two replicas converging through sync, remote
//   strokes landing in (z, id) order without echo, validation of adopted
//   content, deletion of unreadable strokes, (z, id) order on load and on
//   remote batches, a joined document that fills in later with its early
//   strokes moved on top, and the earlier-format import.
// Why: docs/decisions/008-document-file-format.md fixes the schema
//   (PNT-A0014-03..06, PNT-A0014-08, PNT-A0014-10) and
//   docs/spec/document-file.md requires stable stroke ids (DOCF-2), old files
//   rendering as before (DOCF-3) and refusing other engine versions or
//   unreadable root keys (DOCF-6, DOCF-7); multiplayer needs every replica
//   to converge (MPLY-7).
// Covers: lib/document/content_document.dart, with the controller hooks in
//   lib/canvas/canvas_controller.dart (replaceDocument id source,
//   insertStrokes, removeStrokes) and EditHistory's restamp handling in
//   lib/document/undo_history.dart.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:painter/canvas/canvas_controller.dart';
import 'package:painter/canvas/pencil_splats.dart' show strokeEngineVersion;
import 'package:painter/crdt/crdt_document.dart';
import 'package:painter/document/content_document.dart';
import 'package:painter/document/undo_history.dart';

import 'content_test_support.dart';

/// An earlier-format document with [count] two-point strokes.
Map<String, Object?> _earlier(int count) => {
  'format': 'painter-document',
  'version': 1,
  'strokes': [
    for (var i = 0; i < count; i++)
      [
        {'x': i * 10.0, 'y': 1.0, 'weight': 0.5},
        {'x': i * 10.0 + 4, 'y': 3.0, 'weight': 0.7},
      ],
  ],
};

/// A CRDT document with the content root keys, [engine] as its engine.
CrdtDocument _rootDocument({int engine = strokeEngineVersion}) {
  final crdt = testBackend.create();
  crdt
    ..put(['format'], ContentDocument.formatIdentifier)
    ..put(['version'], ContentDocument.formatVersion)
    ..put(['engine'], engine)
    ..putMap(['strokes'])
    ..commit();
  return crdt;
}

void main() {
  test('a new document holds the root keys and no strokes', () {
    final replica = Replica.create();
    final crdt = replica.content.crdt;
    expect(crdt.get(['format']), 'painter-document');
    expect(crdt.get(['version']), 2);
    expect(crdt.get(['engine']), strokeEngineVersion);
    expect(crdt.get(['strokes']), isA<CrdtMap>());
    expect(crdt.keys(['strokes']), isEmpty);
    expect(replica.content.isReady, isTrue);
  });

  test('each committed chunk is written as a stroke map at once', () {
    final replica = Replica.create();
    final commits = <CrdtChangeOrigin>[];
    replica.content.crdt.addListener(commits.add);

    // A long gesture commits several chunks before it ends.
    replica.controller
      ..beginStroke(Offset.zero, 0.5)
      ..extendStroke(const Offset(300, 0), 1);
    final chunks = replica.canvas.strokeCount;
    expect(chunks, greaterThan(1));
    expect(replica.content.crdt.keys(['strokes']), hasLength(chunks));
    expect(commits, hasLength(chunks));
    replica.controller.endStroke();

    final crdt = replica.content.crdt;
    for (final stroke in replica.canvas.strokes) {
      // Ids embed the content document's actor (PNT-A0013-04).
      expect(stroke.id, startsWith('${crdt.actorId}:'));
      final entry = crdt.entries(['strokes', stroke.id]);
      expect(entry['seed'], stroke.seed);
      expect(entry['seed'], strokeSeedOf(stroke.id));
      expect(entry['z'], stroke.z);
      expect(entry['gesture'], stroke.gesture);
      final points = entry['points'] as Uint8List;
      expect(points, hasLength(stroke.points.length * 24));
      final data = ByteData.sublistView(points);
      expect(data.getFloat64(0, Endian.little), stroke.points[0].position.dx);
      expect(data.getFloat64(8, Endian.little), stroke.points[0].position.dy);
      expect(data.getFloat64(16, Endian.little), stroke.points[0].weight);
    }
  });

  test('save and load keep every stroke with its id, seed and z', () {
    final source = Replica.create();
    source
      ..draw(Offset.zero)
      ..draw(const Offset(20, 20));
    final loaded = ContentDocument.load(testBackend, source.content.save());
    addTearDown(loaded.dispose);

    expect(loaded.crdt.actorId, isNot(source.content.crdt.actorId));
    expect(loaded.canvas.strokeCount, 2);
    for (var i = 0; i < 2; i++) {
      final a = source.canvas.strokeAt(i);
      final b = loaded.canvas.strokeAt(i);
      expect([b.id, b.seed, b.z, b.gesture], [a.id, a.seed, a.z, a.gesture]);
      expect(b.points.map((p) => (p.position, p.weight)), [
        for (final p in a.points) (p.position, p.weight),
      ]);
    }
  });

  group('two replicas', () {
    test('converge, and a remote stroke below a local one lands in order', () {
      final a = Replica.create();
      final b = Replica.copyOf(a);
      a.draw(Offset.zero);
      a.syncWith(b);
      expect(b.ids, a.ids);

      // Concurrently A draws one stroke (z 2) while B draws three (z 2-4):
      // A's stroke sorts below B's later ones on B.
      final fromA = a.draw(const Offset(5, 5));
      for (var i = 0; i < 3; i++) {
        b.draw(Offset(30.0 * i, 40));
      }
      final changesOnB = <(CanvasStrokeChangeKind, String)>[];
      b.canvas.addObserver(
        (change) => changesOnB.add((change.kind, change.stroke.id)),
      );
      a.syncWith(b);

      expect(a.ids, b.ids);
      expect(a.canvas.strokeCount, 5);
      expect(changesOnB, [(CanvasStrokeChangeKind.inserted, fromA)]);
      final strokes = b.canvas.strokes;
      for (var i = 1; i < strokes.length; i++) {
        expect(strokes[i - 1].compareOrder(strokes[i]), lessThan(0));
      }
      expect(b.canvas.strokeById(fromA)!.z, 2);
    });

    test('applying remote strokes writes nothing back', () {
      final a = Replica.create();
      final b = Replica.copyOf(a);
      final heardOnB = <CrdtChangeOrigin>[];
      b.content.crdt.addListener(heardOnB.add);
      a
        ..draw(Offset.zero)
        ..draw(const Offset(9, 9));

      a.syncWith(b);

      expect(b.canvas.strokeCount, 2);
      expect(heardOnB, isNot(contains(CrdtChangeOrigin.local)));
    });

    test('remote changes notify the controller so panes repaint', () {
      final a = Replica.create();
      final b = Replica.copyOf(a);
      var notified = 0;
      b.controller.addListener(() => notified++);
      a.draw(Offset.zero);
      a.syncWith(b);
      expect(notified, greaterThan(0));
    });

    test('an unreadable peer stroke is deleted by the reader (PNT-A0014-10)',
        () {
      final a = Replica.create();
      final b = Replica.copyOf(a);
      final crdt = a.content.crdt;
      final id = crdt.newId();
      crdt
        ..putMap(['strokes', id])
        ..put(['strokes', id, 'points'], Uint8List(5))
        ..put(['strokes', id, 'seed'], 1)
        ..put(['strokes', id, 'z'], 1)
        ..put(['strokes', id, 'gesture'], 'g')
        ..commit();
      a.draw(Offset.zero);
      final heardOnB = <CrdtChangeOrigin>[];
      b.content.crdt.addListener(heardOnB.add);

      a.syncWith(b);

      expect(b.canvas.strokeCount, 1);
      expect(b.canvas.strokeById(id), isNull);
      expect(b.content.crdt.keys(['strokes']), b.ids);
      expect(
        heardOnB.where((o) => o == CrdtChangeOrigin.local),
        hasLength(1),
        reason: 'one commit deletes it',
      );
      // The deletion syncs back, so a's saved content opens cleanly.
      expect(a.content.crdt.keys(['strokes']), a.ids);
      final reopened = ContentDocument.load(testBackend, a.content.save());
      addTearDown(reopened.dispose);
      expect(reopened.canvas.strokeCount, 1);
    });

    test('a batch of remote strokes on top is appended in (z, id) order', () {
      final a = Replica.create();
      final b = Replica.copyOf(a);
      // Twelve strokes: their ids do not sort as their z (":10" < ":2").
      for (var i = 0; i < 12; i++) {
        a.draw(Offset(i * 5.0, 0));
      }
      final changes = <CanvasStrokeChangeKind>[];
      b.canvas.addObserver((change) => changes.add(change.kind));

      a.syncWith(b);

      expect(b.ids, a.ids);
      expect(changes, List.filled(12, CanvasStrokeChangeKind.appended));
    });
  });

  group('adopt', () {
    test('refuses another engine version, naming both versions', () {
      const other = strokeEngineVersion + 1;
      final crdt = _rootDocument(engine: other);
      addTearDown(crdt.dispose);
      expect(
        () => ContentDocument.adopt(crdt),
        throwsA(
          isA<StrokeEngineMismatch>()
              .having((e) => e.documentVersion, 'documentVersion', other)
              .having(
                (e) => e.systemVersion,
                'systemVersion',
                strokeEngineVersion,
              )
              .having(
                (e) => e.toString(),
                'message',
                allOf(
                  contains('version $other'),
                  contains('version $strokeEngineVersion'),
                ),
              ),
        ),
      );
    });

    test('refuses content without the root keys or of another format', () {
      final empty = testBackend.create();
      addTearDown(empty.dispose);
      expect(() => ContentDocument.adopt(empty), throwsFormatException);

      final other = testBackend.create()
        ..put(['format'], 'something else')
        ..commit();
      addTearDown(other.dispose);
      expect(
        () => ContentDocument.adopt(other),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('something else'),
          ),
        ),
      );
    });

    test('deletes unreadable strokes in one commit and opens the rest', () {
      final crdt = _rootDocument();
      void stroke(String id, Map<String, Object?> fields) {
        crdt.putMap(['strokes', id]);
        for (final MapEntry(:key, :value) in fields.entries) {
          crdt.put(['strokes', id, key], value);
        }
      }

      final good = ContentDocument.encodePoints(const [
        CanvasPoint(position: Offset(1, 2), weight: 0.5),
      ]);
      Map<String, Object?> fields({
        Object? points,
        Object? seed = 1,
        Object? z = 1,
        Object? gesture = 'g',
      }) => {
        'points': points ?? good,
        'seed': seed,
        'z': z,
        'gesture': gesture,
      };
      stroke('ok:1', fields(z: ContentDocument.maxZ));
      stroke('bad:1', fields(seed: 'not a number'));
      stroke('bad:2', fields(z: ContentDocument.maxZ + 1));
      stroke('bad:3', fields(z: -1));
      stroke('bad:4', fields(seed: ContentDocument.maxSeed + 1));
      stroke('bad:5', fields(points: Uint8List(23)));
      stroke('bad:6', {'seed': 1, 'z': 1, 'gesture': 'g'});
      crdt
        ..put(['strokes', 'bad:7'], 3)
        ..commit();
      final heard = <CrdtChangeOrigin>[];
      crdt.addListener(heard.add);

      final content = ContentDocument.adopt(crdt);
      addTearDown(content.dispose);

      expect([for (final s in content.canvas.strokes) s.id], ['ok:1']);
      expect(crdt.keys(['strokes']), ['ok:1']);
      expect(heard, [CrdtChangeOrigin.local]);
    });

    test('loads strokes in (z, id) order', () {
      final source = Replica.create();
      for (var i = 0; i < 12; i++) {
        source.draw(Offset(i * 5.0, 0));
      }
      final loaded = ContentDocument.load(testBackend, source.content.save());
      addTearDown(loaded.dispose);
      expect([for (final s in loaded.canvas.strokes) s.id], source.ids);
    });

    test('a joined empty document fills in by sync and puts early strokes '
        'on top', () {
      final host = Replica.create();
      for (var i = 0; i < 3; i++) {
        host.draw(Offset(i * 9.0, 0));
      }
      final joined = Replica(
        ContentDocument.adopt(testBackend.create(), requireRoot: false),
      );
      final history = EditHistory(
        controller: joined.controller,
        content: joined.content,
      );
      addTearDown(history.dispose);
      expect(joined.content.isReady, isFalse);
      final first = joined.draw(const Offset(50, 50));
      final second = joined.draw(const Offset(60, 50));
      final undone = joined.draw(const Offset(70, 50));
      history.undo();
      final hostTop = host.canvas.strokes.last.z;

      host.syncWith(joined);

      expect(joined.content.isReady, isTrue);
      expect(joined.ids, host.ids);
      expect(joined.ids.sublist(3), [first, second]);
      expect(
        [for (final s in joined.canvas.strokes.skip(3)) s.z],
        [hostTop + 1, hostTop + 2],
      );
      expect(joined.content.crdt.get(['strokes', second, 'z']), hostTop + 2);

      // Redo of a stroke undone before the root arrived lands on top too.
      expect(history.redo(), isTrue);
      expect(joined.ids.last, undone);
      expect(joined.canvas.strokeById(undone)!.z, hostTop + 3);
      history
        ..undo()
        ..undo();
      expect(history.redo(), isTrue);
      expect(joined.canvas.strokeById(second)!.z, hostTop + 2);
    });

    test('a joined document rejects a host with another engine', () {
      final host = _rootDocument(engine: 99);
      addTearDown(host.dispose);
      final joined = Replica(
        ContentDocument.adopt(testBackend.create(), requireRoot: false),
      );
      final rejected = <Object>[];
      joined.content.onRejected = rejected.add;

      syncReplicas(host, joined.content.crdt);

      expect(rejected.single, isA<StrokeEngineMismatch>());
      expect(joined.content.rejection, same(rejected.single));
      expect(joined.content.isReady, isFalse);
    });
  });

  test('earlier-format import gives seed = z = i + 1 and new ids', () {
    final content = ContentDocument.importEarlier(testBackend, _earlier(3));
    addTearDown(content.dispose);
    final actor = content.crdt.actorId;

    expect(content.canvas.strokeCount, 3);
    for (var i = 0; i < 3; i++) {
      final stroke = content.canvas.strokeAt(i);
      expect(stroke.seed, i + 1);
      expect(stroke.z, i + 1);
      expect(stroke.id, startsWith('$actor:'));
      expect(stroke.points.first.position, Offset(i * 10.0, 1));
      final entry = content.crdt.entries(['strokes', stroke.id]);
      expect([entry['seed'], entry['z']], [i + 1, i + 1]);
    }
    expect(content.crdt.get(['version']), 2);

    expect(
      () => ContentDocument.importEarlier(testBackend, {'format': 'x'}),
      throwsFormatException,
    );
  });

  test('points round-trip through their byte encoding', () {
    final points = [
      const CanvasPoint(position: Offset(1.5, -2), weight: 0.05),
      const CanvasPoint(position: Offset(1e6, 3), weight: 1),
    ];
    final decoded = ContentDocument.decodePoints(
      ContentDocument.encodePoints(points),
    )!;
    expect(decoded.map((p) => (p.position, p.weight)), [
      for (final p in points) (p.position, p.weight),
    ]);
    expect(ContentDocument.decodePoints(Uint8List(0)), isNull);
    expect(ContentDocument.decodePoints(Uint8List(25)), isNull);
    // Weight 0 is outside 0.05-1.
    expect(ContentDocument.decodePoints(Uint8List(24)), isNull);
  });
}
