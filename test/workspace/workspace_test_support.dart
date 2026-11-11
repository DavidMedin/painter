// What: Helpers shared by the Workspace and PaneSystem tests: a session
//   document whose creator is the Member of one Default workspace, replicas
//   of it, a Workspace over that workspace, and a sync loop between
//   replicas.
// Why: Workspace now lives in the session document
//   (docs/decisions/009-shared-workspaces.md), so every test needs the same
//   document setup and sync loop; one copy keeps them identical.
// Coupled to: lib/workspace/workspace.dart (Workspace),
//   lib/session/session_document.dart (SessionDocument.create and the
//   workspace's node table), lib/workspace/layout_tree.dart
//   (createDefaultLayout) and lib/crdt/automerge_crdt_document.dart (the real
//   backend); used by workspace_test.dart, workspace_convergence_test.dart
//   and ../ui/pane_system_test.dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:painter/crdt/automerge_crdt_document.dart';
import 'package:painter/crdt/crdt_document.dart';
import 'package:painter/logging/painter_log.dart';
import 'package:painter/session/session_document.dart';
import 'package:painter/workspace/layout_tree.dart';
import 'package:painter/workspace/workspace.dart';

const _backend = AutomergeBackend();

/// A new session document whose creator is the only Member of a Default
/// workspace, disposed at the end of the test.
SessionDocument sessionWithDefaultWorkspace() {
  final document = _backend.create();
  addTearDown(document.dispose);
  return SessionDocument.create(
    document,
    name: 'A',
    engine: 1,
    nodes: createDefaultLayout(newId: document.newId, actor: document.actorId),
  );
}

/// A replica of [session] with its own actor, as a joining peer gets one,
/// disposed at the end of the test.
SessionDocument replicaOf(SessionDocument session) {
  final replica = _backend.load(session.document.save());
  addTearDown(replica.dispose);
  return SessionDocument(replica);
}

/// The workspace the creator of [session] is a Member of; every replica of
/// a session made by [sessionWithDefaultWorkspace] shows this one in tests.
String testWorkspaceOf(SessionDocument session) =>
    session.participants.singleWhere((entry) => entry.joined == 0).workspace;

/// A Workspace over the test workspace of [session] (a new session when
/// null) that adds removed pane ids to [removed] and logs edits to [log];
/// disposed at the end of the test.
Workspace openWorkspace({
  SessionDocument? session,
  List<String>? removed,
  PainterLog? log,
}) {
  final shown = session ?? sessionWithDefaultWorkspace();
  final workspace = Workspace(
    session: shown,
    workspaceId: testWorkspaceOf(shown),
    onPaneRemoved: removed?.add,
    log: log,
  );
  addTearDown(workspace.dispose);
  return workspace;
}

/// The stored node table of the test workspace of [session].
LayoutNodes storedNodes(SessionDocument session) =>
    session.workspaceNodes(testWorkspaceOf(session));

/// Exchanges sync messages between every pair of [sessions] until no
/// replica has anything to send, as a full mesh of peers does.
void syncAll(List<SessionDocument> sessions) {
  for (var round = 0; round < 50; round++) {
    var sent = false;
    for (var i = 0; i < sessions.length; i++) {
      for (var j = i + 1; j < sessions.length; j++) {
        sent = _syncPair(sessions[i].document, sessions[j].document) || sent;
      }
    }
    if (!sent) return;
  }
  fail('sync did not settle');
}

/// Syncs [a] and [b] to quiescence; returns whether a message changed
/// either document.
bool _syncPair(CrdtDocument a, CrdtDocument b) {
  final ab = a.createSyncPeer();
  final ba = b.createSyncPeer();
  var changed = false;
  void listener(CrdtChangeOrigin origin) => changed = true;
  a.addListener(listener);
  b.addListener(listener);
  try {
    for (var round = 0; round < 20; round++) {
      final toB = a.generateSyncMessage(ab);
      if (toB != null) b.receiveSyncMessage(ba, toB);
      final toA = b.generateSyncMessage(ba);
      if (toA != null) a.receiveSyncMessage(ab, toA);
      if (toB == null && toA == null) return changed;
    }
    fail('sync did not settle');
  } finally {
    a.removeListener(listener);
    b.removeListener(listener);
    ab.dispose();
    ba.dispose();
  }
}
