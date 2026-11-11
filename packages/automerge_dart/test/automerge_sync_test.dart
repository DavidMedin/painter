// What: Tests of AutomergeDoc convergence: two documents with different
//   actors edit concurrently (including the same key), then exchange sync
//   messages, or merge, and must end identical; SyncState encoding.
// Why: peers in a Session must reach the same content after receiving the
//   same changes (MPLY-7, WKSP-35), through the sync protocol the app's CRDT
//   port exposes (docs/decisions/007-crdt-automerge.md PNT-A0013-03).
// Covers: lib/src/document.dart (AutomergeDoc.generateSyncMessage,
//   receiveSyncMessage, merge, fork, heads; SyncState) and the native
//   library built by hook/build.dart.

import 'dart:typed_data';

import 'package:automerge_dart/automerge_dart.dart';
import 'package:test/test.dart';

void main() {
  test('concurrent edits converge through sync messages', () {
    final (a, b) = _divergedPair();
    final stateA = SyncState();
    final stateB = SyncState();
    addTearDown(() {
      for (final d in [a, b]) {
        d.dispose();
      }
      stateA.dispose();
      stateB.dispose();
    });

    _syncUntilQuiet(a, stateA, b, stateB);

    _expectConverged(a, b);
    // Both sides' strokes survive, and one of the concurrent titles wins.
    final strokes = (_snapshot(a)['strokes']! as Map<String, Object?>).keys;
    expect(strokes, unorderedEquals(['aa:1', 'bb:1', 'base']));
    expect(
      a.get(a.root, 'title'),
      anyOf(const AutomergeString('from a'), const AutomergeString('from b')),
    );
  });

  test('merging both ways matches the result of syncing', () {
    final (a, b) = _divergedPair();
    final syncA = a.fork();
    final syncB = b.fork();
    final stateA = SyncState();
    final stateB = SyncState();
    addTearDown(() {
      for (final d in [a, b, syncA, syncB]) {
        d.dispose();
      }
      stateA.dispose();
      stateB.dispose();
    });

    a.merge(b);
    b.merge(a);
    _syncUntilQuiet(syncA, stateA, syncB, stateB);

    _expectConverged(a, b);
    _expectConverged(a, syncA);
  });

  test('a peer that starts empty receives the whole document', () {
    final (a, b) = _divergedPair();
    final empty = AutomergeDoc.create(actorId: 'cc');
    final stateA = SyncState();
    final stateEmpty = SyncState();
    addTearDown(() {
      for (final d in [a, b, empty]) {
        d.dispose();
      }
      stateA.dispose();
      stateEmpty.dispose();
    });

    _syncUntilQuiet(a, stateA, empty, stateEmpty);

    _expectConverged(a, empty);
  });

  test('a decoded sync state resumes syncing after more edits', () {
    final (a, b) = _divergedPair();
    var stateA = SyncState();
    var stateB = SyncState();
    _syncUntilQuiet(a, stateA, b, stateB);

    final savedA = stateA.encode();
    final savedB = stateB.encode();
    stateA.dispose();
    stateB.dispose();
    stateA = SyncState.decode(savedA);
    stateB = SyncState.decode(savedB);
    addTearDown(() {
      a.dispose();
      b.dispose();
      stateA.dispose();
      stateB.dispose();
    });

    b.put(b.root, 'later', 1);
    b.commit();
    _syncUntilQuiet(a, stateA, b, stateB);

    _expectConverged(a, b);
    expect(a.get(a.root, 'later'), const AutomergeInt(1));
  });

  test('undecodable sync bytes throw', () {
    final doc = AutomergeDoc.create();
    final state = SyncState();
    addTearDown(() {
      doc.dispose();
      state.dispose();
    });
    final garbage = Uint8List.fromList([1, 2, 3, 4]);
    expect(
      () => doc.receiveSyncMessage(state, garbage),
      throwsA(isA<AutomergeException>()),
    );
    expect(() => SyncState.decode(garbage), throwsA(isA<AutomergeException>()));
  });
}

/// Two documents sharing one base change, then each with concurrent edits
/// of its own: actor `aa` and `bb` both set `title` and add a stroke.
(AutomergeDoc, AutomergeDoc) _divergedPair() {
  final a = AutomergeDoc.create(actorId: 'aa');
  final strokes = a.putMap(a.root, 'strokes');
  a.putMap(strokes, 'base');
  a.commit(message: 'base');

  final b = AutomergeDoc.load(a.save())..actorId = 'bb';

  a.put(a.root, 'title', 'from a');
  final strokeA = a.putMap(strokes, 'aa:1');
  a.put(strokeA, 'seed', 1);
  a.commit();

  b.put(b.root, 'title', 'from b');
  final strokeB = b.putMap(strokes, 'bb:1');
  b.put(strokeB, 'points', Uint8List.fromList([9, 9]));
  b.commit();

  expect(a.heads, isNot(b.heads));
  return (a, b);
}

/// Exchanges sync messages between [a] and [b] until neither has one to
/// send, failing if that takes more than a few dozen rounds.
void _syncUntilQuiet(
  AutomergeDoc a,
  SyncState stateA,
  AutomergeDoc b,
  SyncState stateB,
) {
  for (var round = 0; round < 50; round++) {
    final toB = a.generateSyncMessage(stateA);
    if (toB != null) b.receiveSyncMessage(stateB, toB);
    final toA = b.generateSyncMessage(stateB);
    if (toA != null) a.receiveSyncMessage(stateA, toA);
    if (toB == null && toA == null) return;
  }
  fail('sync did not settle');
}

/// Expects [a] and [b] to hold the same content and the same heads.
void _expectConverged(AutomergeDoc a, AutomergeDoc b) {
  expect(_snapshot(a), _snapshot(b));
  expect(a.heads, b.heads);
  expect(a.heads, isNotEmpty);
}

/// The content of [obj] in [doc] as nested Dart maps whose leaves are
/// [AutomergeValue]s.
Map<String, Object?> _snapshot(AutomergeDoc doc, [ObjId? obj]) {
  final id = obj ?? doc.root;
  return {
    for (final key in doc.keys(id))
      key: switch (doc.get(id, key)) {
        AutomergeMap(id: final child) => _snapshot(doc, child),
        final value => value,
      },
  };
}
