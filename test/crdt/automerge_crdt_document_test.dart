// What: Tests of the CRDT port implemented on Automerge
//   (lib/crdt/automerge_crdt_document.dart).
// Why: content and workspace sync rely on the port's contract
//   (docs/decisions/007-crdt-automerge.md PNT-A0013-03..05): path access,
//   listener origins, convergence of concurrent edits through sync messages,
//   and a fresh actor per load.
// Behavior verified: values round-trip by path; absent paths read as null;
//   commits notify listeners only when something changed; sync between two
//   replicas converges, including concurrent writes to one key, and reports
//   remote changes; a reload keeps content but not the actor; garbage bytes
//   are rejected with FormatException.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:painter/crdt/automerge_crdt_document.dart';
import 'package:painter/crdt/crdt_document.dart';

const _backend = AutomergeBackend();

/// Exchanges sync messages between [a] and [b] until neither has any.
void _sync(CrdtDocument a, CrdtDocument b) {
  final ab = a.createSyncPeer();
  final ba = b.createSyncPeer();
  try {
    for (var round = 0; round < 20; round++) {
      final toB = a.generateSyncMessage(ab);
      if (toB != null) b.receiveSyncMessage(ba, toB);
      final toA = b.generateSyncMessage(ba);
      if (toA != null) a.receiveSyncMessage(ab, toA);
      if (toB == null && toA == null) return;
    }
    fail('sync did not settle');
  } finally {
    ab.dispose();
    ba.dispose();
  }
}

void main() {
  test('values round-trip by path and absent paths read as null', () {
    final doc = _backend.create();
    addTearDown(doc.dispose);
    doc.putMap(['strokes']);
    doc.putMap(['strokes', 's1']);
    doc.put(['strokes', 's1', 'seed'], 7);
    doc.put(['strokes', 's1', 'points'], Uint8List.fromList([1, 2, 3]));
    doc.put(['name'], 'x');
    doc.put(['scale'], 1.5);
    doc.put(['on'], true);
    doc.commit();

    expect(doc.get(['strokes']), isA<CrdtMap>());
    expect(doc.get(['strokes', 's1', 'seed']), 7);
    expect(doc.get(['strokes', 's1', 'points']), [1, 2, 3]);
    expect(doc.get(['missing', 'deep']), isNull);
    expect(doc.keys(['strokes']), ['s1']);
    expect(doc.entries(['strokes', 's1']), {
      'points': [1, 2, 3],
      'seed': 7,
    });
    expect(doc.entries(['name']), isEmpty);
    expect([doc.get(['name']), doc.get(['scale']), doc.get(['on'])], [
      'x',
      1.5,
      true,
    ]);

    doc.delete(['strokes', 's1']);
    expect(doc.keys(['strokes']), isEmpty);
  });

  test('commit notifies local listeners only when edits were made', () {
    final doc = _backend.create();
    addTearDown(doc.dispose);
    final heard = <CrdtChangeOrigin>[];
    doc.addListener(heard.add);
    doc.commit();
    expect(heard, isEmpty);
    doc.put(['a'], 1);
    doc.commit();
    expect(heard, [CrdtChangeOrigin.local]);
  });

  test('commit still notifies when a save already closed the edits', () {
    final doc = _backend.create();
    addTearDown(doc.dispose);
    final heard = <CrdtChangeOrigin>[];
    doc.addListener(heard.add);
    doc.put(['a'], 1);
    doc.save();
    doc.commit();
    expect(heard, [CrdtChangeOrigin.local]);
  });

  test('sync converges concurrent edits and reports remote changes', () {
    final a = _backend.create();
    addTearDown(a.dispose);
    a.putMap(['m']);
    a.commit();
    final b = _backend.load(a.save());
    addTearDown(b.dispose);

    a.put(['m', 'shared'], 'from a');
    a.put(['m', 'onlyA'], 1);
    a.commit();
    b.put(['m', 'shared'], 'from b');
    b.put(['m', 'onlyB'], 2);
    b.commit();

    final heardByB = <CrdtChangeOrigin>[];
    b.addListener(heardByB.add);
    _sync(a, b);

    expect(a.entries(['m']), b.entries(['m']));
    expect(a.get(['m', 'onlyA']), 1);
    expect(a.get(['m', 'onlyB']), 2);
    expect(a.get(['m', 'shared']), anyOf('from a', 'from b'));
    expect(heardByB, contains(CrdtChangeOrigin.remote));
  });

  test('load keeps content, takes a new actor, and rejects garbage', () {
    final a = _backend.create();
    addTearDown(a.dispose);
    a.put(['k'], 'v');
    a.commit();
    final b = _backend.load(a.save());
    addTearDown(b.dispose);
    expect(b.get(['k']), 'v');
    expect(b.actorId, isNot(a.actorId));
    expect(a.newId(), isNot(b.newId()));
    expect(
      () => _backend.load(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
    expect(() => _backend.load(Uint8List(0)), throwsFormatException);
  });
}
