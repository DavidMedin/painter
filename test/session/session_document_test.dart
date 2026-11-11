// What: Tests of SessionDocument (lib/session/session_document.dart) on real
//   Automerge documents synced locally, without sockets.
// Why: every Participant reads and writes the session document's schema
//   (docs/decisions/009-shared-workspaces.md PNT-A0015-02) and runs the
//   workspace membership rules (PNT-A0015-03/04, WKSP-21, WKSP-31..38) on
//   it; a wrong key or rule would diverge between peers.
// Behavior verified: creation writes every root key, the Host and the
//   creator's entry; node tables round-trip with nested maps; joiners take
//   `joined` one more than the largest seen; malformed entries are ignored;
//   joining a workspace records the previous one, which stays as it is
//   still named; a workspace no Participant still in the Session names as
//   `workspace` or `previousWorkspace` is discarded, whoever is connected;
//   leaving returns to the previous workspace or, if it is gone, to a copy
//   of the one left; marking a Participant left discards its workspaces;
//   the local Participant never discards its own, even when marked left;
//   it can clear its `left` and restore a missing workspace; the local name
//   and the stored workspace can be set and cleared before a Session starts
//   and reach a joiner; listeners hear commits.

import 'package:flutter_test/flutter_test.dart';
import 'package:painter/crdt/crdt_document.dart';
import 'package:painter/session/session_document.dart';

import 'session_test_support.dart';

SessionDocument _creator() {
  final session = SessionDocument.create(
    backend.create(),
    name: 'Ann',
    engine: 4,
    nodes: paneNodes(0),
    addresses: ['10.0.0.1:47800', '10.0.0.2:47800'],
    storedWorkspace: '{"version": 2}',
  );
  addTearDown(session.document.dispose);
  return session;
}

/// A replica that synced from [via] and then added itself.
SessionDocument _joiner(SessionDocument via, String name, double x) {
  final session = SessionDocument(backend.create());
  addTearDown(session.document.dispose);
  syncLocally(via.document, session.document);
  session.addLocalParticipant(
    name: name,
    addresses: const [],
    nodes: paneNodes(x),
  );
  return session;
}

void _syncAll(List<SessionDocument> replicas) {
  for (var i = 0; i < replicas.length; i++) {
    for (var j = i + 1; j < replicas.length; j++) {
      syncLocally(replicas[i].document, replicas[j].document);
    }
  }
}

String _workspaceOf(SessionDocument session) =>
    session.localParticipant!.workspace;

void main() {
  test('create writes the schema with the creator as Host and Member', () {
    final a = _creator();
    expect(
      a.document.keys(const []),
      containsAll(['participants', 'workspaces', 'engine', 'host']),
    );
    expect(a.host, a.localId);
    expect(a.engine, 4);
    expect(a.storedWorkspace, '{"version": 2}');
    final entry = a.localParticipant!;
    expect(entry.name, 'Ann');
    expect(entry.joined, 0);
    expect(entry.left, isFalse);
    expect(entry.previousWorkspace, isNull);
    expect(entry.addresses, ['10.0.0.1:47800', '10.0.0.2:47800']);
    expect(
      a.document.get(['participants', a.localId, 'addresses']),
      '10.0.0.1:47800 10.0.0.2:47800',
    );
    expect(a.workspaceIds, [entry.workspace]);
    expect(a.workspaceNodes(entry.workspace), paneNodes(0));
  });

  test('node tables round-trip, nested maps stored as maps', () {
    final a = _creator();
    final id = a.createWorkspace(paneNodes(3));
    expect(a.workspaceIds, contains(id));
    expect(
      a.document.get([...SessionDocument.nodesPath(id), 'pane', 'state']),
      isA<CrdtMap>(),
    );
    expect(a.workspaceNodes(id), paneNodes(3));

    a.document.put(SessionDocument.nodeFieldPath(id, 'pane', 'share'), 0.5);
    a.document.commit();
    expect(a.workspaceNodes(id)['pane']!['share'], 0.5);
    expect(
      () => a.createWorkspace({
        'root': {'parts': <Object?>[]},
      }),
      throwsArgumentError,
    );
  });

  test('joiners take joined one more than the largest seen', () {
    final a = _creator();
    final b = _joiner(a, 'Bo', 1);
    final c = _joiner(b, 'Cy', 2);
    expect(b.localParticipant!.joined, 1);
    expect(c.localParticipant!.joined, 2);
    expect(
      c.participants.map((p) => p.name),
      unorderedEquals(['Ann', 'Bo', 'Cy']),
    );
    expect(c.host, a.localId);
    expect(c.engine, 4);
    expect(
      () => c.addLocalParticipant(name: 'Cy', addresses: const [], nodes: {}),
      throwsStateError,
    );

    final empty = SessionDocument(backend.create());
    addTearDown(empty.document.dispose);
    expect(
      () =>
          empty.addLocalParticipant(name: 'D', addresses: const [], nodes: {}),
      throwsStateError,
    );
  });

  test('malformed participant entries are ignored', () {
    final a = _creator();
    a.document
      ..putMap(['participants', 'x:1'])
      ..put(['participants', 'x:1', 'name'], 'No joined')
      ..put(['participants', 'y:1'], 'not a map')
      ..commit();
    expect(a.participants.map((p) => p.id), [a.localId]);
    expect(a.participant('x:1'), isNull);
  });

  test('listeners hear commits', () {
    final a = _creator();
    final heard = <CrdtChangeOrigin>[];
    a.addListener(heard.add);
    a.setHost('someone');
    a.removeListener(heard.add);
    a.setHost(a.localId);
    expect(heard, [CrdtChangeOrigin.local]);
  });

  group('workspace membership', () {
    late SessionDocument a, b, c;
    late String wa, wb, wc;

    setUp(() {
      a = _creator();
      b = _joiner(a, 'Bo', 1);
      c = _joiner(b, 'Cy', 2);
      _syncAll([a, b, c]);
      wa = _workspaceOf(a);
      wb = _workspaceOf(b);
      wc = _workspaceOf(c);
    });

    test('joining records the previous workspace, which stays', () {
      b.joinWorkspace(a.localId);
      expect(_workspaceOf(b), wa);
      expect(b.localParticipant!.previousWorkspace, wb);
      expect(b.workspaceIds, unorderedEquals([wa, wb, wc]));
      _syncAll([a, b, c]);
      expect(a.discardUnnamedWorkspaces(), isEmpty);
    });

    test('the last Member leaving discards the workspace', () {
      b.joinWorkspace(a.localId);
      // wb was named only as Bo's previous workspace, which now becomes wa.
      b.joinWorkspace(c.localId);
      expect(b.localParticipant!.previousWorkspace, wa);
      expect(b.workspaceIds, unorderedEquals([wa, wc]));
      _syncAll([a, b, c]);
      expect(a.workspaceIds, unorderedEquals([wa, wc]));
    });

    test('leaving returns to the previous workspace when it still exists', () {
      b.joinWorkspace(a.localId);
      expect(b.leaveJoinedWorkspace(), isTrue);
      expect(_workspaceOf(b), wb);
      expect(b.localParticipant!.previousWorkspace, isNull);
      expect(b.workspaceIds, unorderedEquals([wa, wb, wc]));
      expect(b.leaveJoinedWorkspace(), isFalse);
    });

    test('leaving makes a copy of the workspace left when the previous one '
        'is gone', () {
      b.joinWorkspace(a.localId);
      // As if a peer that wrongly saw Bo leave had discarded it.
      b.document
        ..delete(['workspaces', wb])
        ..commit();

      expect(b.leaveJoinedWorkspace(), isTrue);
      final copy = _workspaceOf(b);
      expect(copy, isNot(anyOf(wa, wb, wc)));
      expect(b.workspaceNodes(copy), b.workspaceNodes(wa));
      expect(b.workspaceNodes(copy), paneNodes(0));
      expect(b.workspaceIds, unorderedEquals([wa, wc, copy]));
    });

    test('a workspace named by a Participant that has not left stays, '
        'whoever is connected', () {
      // Nothing here knows about connections: Cy keeps wc on every replica.
      expect(a.discardUnnamedWorkspaces(), isEmpty);
      expect(a.workspaceIds, unorderedEquals([wa, wb, wc]));
    });

    test('marking a Participant left discards its workspaces', () {
      c.joinWorkspace(b.localId);
      _syncAll([a, b, c]);

      a.markLeft(b.localId);
      expect(a.participant(b.localId)!.left, isTrue);
      expect(
        a.workspaceIds,
        unorderedEquals([wa, wb, wc]),
        reason: 'Cy is in wb and would return to wc',
      );
      a.markLeft(c.localId);
      expect(a.workspaceIds, [wa]);

      final heard = <CrdtChangeOrigin>[];
      a.addListener(heard.add);
      a.markLeft(c.localId);
      a.markLeft(a.localId);
      a.markLeft('nobody');
      expect(heard, isEmpty, reason: 'nothing to mark');
      expect(a.localParticipant!.left, isFalse);
    });

    test('leaving the Session discards nothing locally; the others discard '
        'the leaver\'s workspace', () {
      b.setLocalLeft();
      expect(b.discardUnnamedWorkspaces(), isEmpty, reason: 'its own');
      expect(b.workspaceIds, unorderedEquals([wa, wb, wc]));
      _syncAll([a, b, c]);
      expect(a.participant(b.localId)!.left, isTrue);
      expect(a.discardUnnamedWorkspaces(), [wb]);
    });

    test('a Participant wrongly marked left clears it and restores its '
        'workspace', () {
      a.markLeft(b.localId);
      syncLocally(a.document, b.document);
      expect(b.localParticipant!.left, isTrue);
      expect(b.hasWorkspace(wb), isFalse);
      expect(b.localWorkspaceMissing, isFalse, reason: 'not in the Session');

      b.setLocalLeft(left: false);
      expect(b.localParticipant!.left, isFalse);
      expect(b.localWorkspaceMissing, isTrue);
      final restored = b.restoreLocalWorkspace(paneNodes(5));
      expect(b.localWorkspaceMissing, isFalse);
      expect(_workspaceOf(b), restored);

      _syncAll([a, b, c]);
      expect(a.participant(b.localId)!.left, isFalse);
      expect(a.workspaceNodes(restored), paneNodes(5));
      expect(a.discardUnnamedWorkspaces(), isEmpty);
    });
  });

  test('the local name and the stored workspace are set, cleared, and '
      'reach a joiner', () {
    final a = _creator();
    a.setLocalName('Annie');
    a.setStoredWorkspace(null);
    expect(a.localParticipant!.name, 'Annie');
    expect(a.storedWorkspace, isNull);

    a.setStoredWorkspace('{"version": 2, "root": {}}');
    final b = _joiner(a, 'Bo', 1);
    expect(b.participant(a.localId)!.name, 'Annie');
    expect(b.storedWorkspace, '{"version": 2, "root": {}}');
  });
}
