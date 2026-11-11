// What: SessionDocument, a typed view of the session CrdtDocument (the schema
//   of docs/decisions/009-shared-workspaces.md PNT-A0015-02), with
//   SessionParticipant (one well-formed `participants` entry) and SessionKey
//   (the schema's key names). It creates the document, adds the local
//   Participant, sets its name and the Session's stored workspace, stores
//   and reads workspace node tables, and runs workspace membership:
//   joining, leaving a joined workspace, marking Participants left (and
//   clearing the local mark), restoring a missing local workspace, and
//   discarding workspaces no Participant still in the Session names.
// Why: the session document is shared by every Participant, so every write
//   must keep the schema and the rules of PNT-A0013-04
//   (docs/decisions/007-crdt-automerge.md) and PNT-A0015-03/04. Keeping them
//   here leaves the network (session_network.dart) and the workspace model
//   free of key names. See the Session overview in session_network.dart.
// Coupled to: ../crdt/crdt_document.dart (the port), session_network.dart
//   (marking lost peers left, host repair, joining), session_roster.dart
//   (reads SessionParticipant), ../workspace/layout_tree.dart (LayoutNodes,
//   the node table format of docs/decisions/010-pane-layout-tree.md).

import 'dart:typed_data';

import '../crdt/crdt_document.dart';
import '../workspace/layout_tree.dart' show LayoutNodes;

/// Key names of the session document (PNT-A0015-02).
abstract final class SessionKey {
  static const String participants = 'participants';
  static const String host = 'host';
  static const String workspaces = 'workspaces';
  static const String engine = 'engine';
  static const String storedWorkspace = 'storedWorkspace';

  /// Under a workspace: its node table.
  static const String nodes = 'nodes';

  // Fields of a `participants` entry.
  static const String name = 'name';
  static const String joined = 'joined';
  static const String workspace = 'workspace';
  static const String previousWorkspace = 'previousWorkspace';
  static const String addresses = 'addresses';
  static const String left = 'left';
}

/// One well-formed `participants` entry (PNT-A0015-02).
final class SessionParticipant {
  const SessionParticipant({
    required this.id,
    required this.name,
    required this.joined,
    required this.workspace,
    required this.addresses,
    required this.left,
    this.previousWorkspace,
  });

  /// The participant id, the entry's key.
  final String id;

  final String name;

  /// Join order: the creator has 0, every joiner one more than the largest
  /// it saw (PNT-A0019-05). Breaks Host ties (PNT-A0019-07).
  final int joined;

  /// The id of the workspace this Participant is a Member of (PNT-A0015-03).
  final String workspace;

  /// The workspace it was a Member of before joining [workspace] (WKSP-37);
  /// null when it has not joined another's.
  final String? previousWorkspace;

  /// Session addresses, each `host:port`.
  final List<String> addresses;

  /// Whether this Participant has left the Session (PNT-A0019-06).
  final bool left;

  /// The entry [fields] under [id], or null when a field is missing or of
  /// the wrong type: a peer's entry is never trusted to be well-formed.
  static SessionParticipant? tryRead(String id, Map<String, Object?> fields) {
    final name = fields[SessionKey.name];
    final joined = fields[SessionKey.joined];
    final workspace = fields[SessionKey.workspace];
    final previous = fields[SessionKey.previousWorkspace];
    final addresses = fields[SessionKey.addresses];
    final left = fields[SessionKey.left];
    if (name is! String ||
        joined is! int ||
        workspace is! String ||
        (previous != null && previous is! String) ||
        addresses is! String ||
        left is! bool) {
      return null;
    }
    return SessionParticipant(
      id: id,
      name: name,
      joined: joined,
      workspace: workspace,
      previousWorkspace: previous as String?,
      addresses: List.unmodifiable(
        addresses.split(' ').where((address) => address.isNotEmpty),
      ),
      left: left,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SessionParticipant &&
      other.id == id &&
      other.name == name &&
      other.joined == joined &&
      other.workspace == workspace &&
      other.previousWorkspace == previousWorkspace &&
      other.left == left &&
      _sameList(other.addresses, addresses);

  @override
  int get hashCode => Object.hash(
    id,
    name,
    joined,
    workspace,
    previousWorkspace,
    left,
    Object.hashAll(addresses),
  );

  @override
  String toString() => 'SessionParticipant($id, $name, joined $joined)';

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// The session document of the local Participant, whose id is the
/// document's actor id: unique across replicas and embedding the actor, as
/// PNT-A0013-04 requires of keys several peers create in one map.
///
/// Every public write commits with a short message, so listeners
/// ([addListener]) and the network (session_network.dart) see it at once.
/// Reads re-read the document each time (PNT-A0013-05).
final class SessionDocument {
  /// Wraps [document] as it is: empty for a joiner, which fills it by sync
  /// before [addLocalParticipant] (PNT-A0019-05).
  SessionDocument(this.document) : localId = document.actorId;

  /// Fills the empty [document] as the Session's creator: every root map,
  /// `engine`, `host` (the creator), the optional [storedWorkspace] (the
  /// file's workspace section as JSON text), and the creator's participant
  /// entry (`joined` 0) as the only Member of a new workspace holding
  /// [nodes] (WKSP-31). Only the creator creates the root maps, because
  /// peers creating them concurrently would collide (PNT-A0013-04).
  factory SessionDocument.create(
    CrdtDocument document, {
    required String name,
    required int engine,
    required LayoutNodes nodes,
    List<String> addresses = const [],
    String? storedWorkspace,
  }) {
    final session = SessionDocument(document);
    document
      ..putMap(const [SessionKey.participants])
      ..putMap(const [SessionKey.workspaces])
      ..put(const [SessionKey.engine], engine)
      ..put(const [SessionKey.host], session.localId);
    if (storedWorkspace != null) {
      document.put(const [SessionKey.storedWorkspace], storedWorkspace);
    }
    session._writeLocalParticipant(
      name: name,
      joined: 0,
      workspace: session._writeWorkspace(nodes),
      addresses: addresses,
    );
    document.commit(message: 'Start session');
    return session;
  }

  /// The wrapped document; the network syncs it as is.
  final CrdtDocument document;

  /// The local Participant's id.
  final String localId;

  /// Path of a workspace's node table.
  static List<String> nodesPath(String workspace) => [
    SessionKey.workspaces,
    workspace,
    SessionKey.nodes,
  ];

  /// Path of one field of one node, for the workspace model to put directly.
  static List<String> nodeFieldPath(
    String workspace,
    String node,
    String field,
  ) => [SessionKey.workspaces, workspace, SessionKey.nodes, node, field];

  void addListener(CrdtListener listener) => document.addListener(listener);

  void removeListener(CrdtListener listener) =>
      document.removeListener(listener);

  /// Every well-formed participant entry, including those that left.
  List<SessionParticipant> get participants {
    final result = <SessionParticipant>[];
    for (final id in document.keys(const [SessionKey.participants])) {
      final participant = this.participant(id);
      if (participant != null) result.add(participant);
    }
    return result;
  }

  /// The well-formed entry of [id], or null.
  SessionParticipant? participant(String id) {
    final path = [SessionKey.participants, id];
    if (document.get(path) is! CrdtMap) return null;
    return SessionParticipant.tryRead(id, document.entries(path));
  }

  /// The local Participant's entry; null before it joined or when malformed.
  SessionParticipant? get localParticipant => participant(localId);

  /// The `host` field: the Host while present (PNT-A0019-07). The Host
  /// itself comes from session_roster.dart, which applies presence.
  String? get host => _typed<String>(const [SessionKey.host]);

  /// The Session's Engine version.
  int? get engine => _typed<int>(const [SessionKey.engine]);

  /// The Host's file's workspace section as JSON text, if it had one.
  String? get storedWorkspace =>
      _typed<String>(const [SessionKey.storedWorkspace]);

  /// The ids of every workspace in `workspaces`.
  List<String> get workspaceIds => document.keys(const [SessionKey.workspaces]);

  bool hasWorkspace(String id) =>
      document.get([SessionKey.workspaces, id]) is CrdtMap;

  /// The node table of [workspace] as plain maps, nested maps (`state`) read
  /// recursively. Entries that are not maps are skipped; an absent
  /// workspace reads as empty.
  LayoutNodes workspaceNodes(String workspace) {
    final path = nodesPath(workspace);
    final nodes = <String, Map<String, Object?>>{};
    document.entries(path).forEach((id, value) {
      if (value is CrdtMap) nodes[id] = _readMap([...path, id]);
    });
    return nodes;
  }

  /// Stores [nodes] as a new workspace and returns its id.
  String createWorkspace(LayoutNodes nodes) {
    final id = _writeWorkspace(nodes);
    document.commit(message: 'Create workspace');
    return id;
  }

  /// Adds the local Participant after the first sync of a join
  /// (PNT-A0019-05): `joined` one more than the largest seen, and a new
  /// workspace holding [nodes] with it as the only Member (WKSP-31).
  /// Throws [StateError] when the document lacks the root maps (the sync has
  /// not delivered the Session) or already holds the local entry.
  void addLocalParticipant({
    required String name,
    required List<String> addresses,
    required LayoutNodes nodes,
  }) {
    if (document.get(const [SessionKey.participants]) is! CrdtMap ||
        document.get(const [SessionKey.workspaces]) is! CrdtMap) {
      throw StateError('The session document has no Session yet.');
    }
    if (document.get([SessionKey.participants, localId]) != null) {
      throw StateError('The local participant is already in the Session.');
    }
    var largest = -1;
    for (final participant in participants) {
      if (participant.joined > largest) largest = participant.joined;
    }
    _writeLocalParticipant(
      name: name,
      joined: largest + 1,
      workspace: _writeWorkspace(nodes),
      addresses: addresses,
    );
    document.commit(message: 'Join session');
  }

  /// Writes `host`: promotion (MPLY-11) or a peer repairing an absent Host
  /// (PNT-A0019-07).
  void setHost(String participantId) {
    document.put(const [SessionKey.host], participantId);
    document.commit(message: 'Set host');
  }

  /// Replaces the local entry's `addresses`.
  void setLocalAddresses(List<String> addresses) {
    _requireLocal();
    document.put(_localField(SessionKey.addresses), addresses.join(' '));
    document.commit(message: 'Set addresses');
  }

  /// Replaces the local entry's `name`: the name a user gives when starting
  /// a Session (MPLY-10), shown to every Participant (MPLY-9).
  void setLocalName(String name) {
    _requireLocal();
    document.put(_localField(SessionKey.name), name);
    document.commit(message: 'Set name');
  }

  /// Sets `storedWorkspace` to [json], the workspace section of the file the
  /// starting user has open as JSON text, or deletes it when null; joiners
  /// apply it (WKSP-9).
  void setStoredWorkspace(String? json) {
    if (json == null) {
      document.delete(const [SessionKey.storedWorkspace]);
    } else {
      document.put(const [SessionKey.storedWorkspace], json);
    }
    document.commit(message: 'Set stored workspace');
  }

  /// Sets the local entry's `left`: true when leaving (PNT-A0019-06), which
  /// discards nothing, so the leaver keeps its documents, workspace included
  /// (MPLY-16) and the remaining peers discard it when they see `left`;
  /// false when an active peer finds itself marked left by another
  /// (PNT-A0015-04). Nothing happens when it already has that value.
  void setLocalLeft({bool left = true}) {
    if (_requireLocal().left == left) return;
    document.put(_localField(SessionKey.left), left);
    document.commit(message: left ? 'Leave session' : 'Rejoin session');
  }

  /// Whether the local Participant is in the Session but its workspace is
  /// gone from `workspaces`, so the app must call [restoreLocalWorkspace]
  /// (PNT-A0015-04).
  bool get localWorkspaceMissing {
    final local = localParticipant;
    return local != null && !local.left && !hasWorkspace(local.workspace);
  }

  /// Stores [nodes] (the layout the app last showed) as a new workspace and
  /// names it as the local Participant's, keeping `previousWorkspace`
  /// (PNT-A0015-04). Returns its id. Throws [StateError] when there is no
  /// local entry.
  String restoreLocalWorkspace(LayoutNodes nodes) {
    _requireLocal();
    final id = _writeWorkspace(nodes);
    document.put(_localField(SessionKey.workspace), id);
    document.commit(message: 'Restore workspace');
    return id;
  }

  /// Marks [participantId] as having left, for a peer that lost its
  /// connection to it without bye (MPLY-17,
  /// docs/decisions/013-session-networking.md), and discards the workspaces
  /// that leaves unnamed (PNT-A0015-04), in one commit. Nothing happens when
  /// the entry is missing, malformed, already left, or the local one.
  void markLeft(String participantId) {
    final entry = participant(participantId);
    if (entry == null || entry.left || participantId == localId) return;
    document.put([
      SessionKey.participants,
      participantId,
      SessionKey.left,
    ], true);
    _discard();
    document.commit(message: 'Mark left');
  }

  /// Makes the local Participant a Member of [participantId]'s workspace and
  /// records its own in `previousWorkspace` (PNT-A0015-03, WKSP-32), then
  /// discards the workspaces that leaves unnamed (PNT-A0015-04). Nothing
  /// happens when both already share a workspace. Throws [StateError] when
  /// either entry or the target workspace is missing.
  void joinWorkspace(String participantId) {
    final local = _requireLocal();
    final other = participant(participantId);
    if (other == null || !hasWorkspace(other.workspace)) {
      throw StateError('No workspace to join for $participantId.');
    }
    if (other.workspace == local.workspace) return;
    document
      ..put(_localField(SessionKey.previousWorkspace), local.workspace)
      ..put(_localField(SessionKey.workspace), other.workspace);
    _discard();
    document.commit(message: 'Join workspace');
  }

  /// Leaves a joined workspace (WKSP-36, WKSP-37): back to
  /// `previousWorkspace` if it still exists, else to a new copy of the
  /// workspace being left. Then discards the workspaces that leaves unnamed
  /// (PNT-A0015-04). Returns false, changing nothing, when the local
  /// Participant has not joined another's workspace.
  bool leaveJoinedWorkspace() {
    final local = _requireLocal();
    final previous = local.previousWorkspace;
    if (previous == null) return false;
    final next = previous != local.workspace && hasWorkspace(previous)
        ? previous
        : _writeWorkspace(workspaceNodes(local.workspace));
    document
      ..put(_localField(SessionKey.workspace), next)
      ..delete(_localField(SessionKey.previousWorkspace));
    _discard();
    document.commit(message: 'Leave workspace');
    return true;
  }

  /// Deletes every workspace that no participant whose `left` is false
  /// names as its `workspace` or `previousWorkspace`, and never the local
  /// Participant's own (WKSP-21, WKSP-38, PNT-A0015-04). Presence plays no
  /// part, so a newcomer not yet connected to this peer keeps its
  /// workspace. Returns the deleted ids.
  ///
  /// The network (session_network.dart) calls this when it sees a
  /// Participant's `left` become true; [markLeft], [joinWorkspace] and
  /// [leaveJoinedWorkspace] apply the same rule in their own commits.
  List<String> discardUnnamedWorkspaces() {
    final deleted = _discard();
    if (deleted.isNotEmpty) document.commit(message: 'Discard workspaces');
    return deleted;
  }

  List<String> _discard() {
    final named = <String>{};
    for (final participant in participants) {
      if (participant.left && participant.id != localId) continue;
      named.add(participant.workspace);
      final previous = participant.previousWorkspace;
      if (previous != null) named.add(previous);
    }
    final deleted = [
      for (final id in workspaceIds)
        if (!named.contains(id)) id,
    ];
    for (final id in deleted) {
      document.delete([SessionKey.workspaces, id]);
    }
    return deleted;
  }

  SessionParticipant _requireLocal() =>
      localParticipant ??
      (throw StateError('The local participant is not in the Session.'));

  List<String> _localField(String field) => [
    SessionKey.participants,
    localId,
    field,
  ];

  void _writeLocalParticipant({
    required String name,
    required int joined,
    required String workspace,
    required List<String> addresses,
  }) {
    document
      ..putMap([SessionKey.participants, localId])
      ..put(_localField(SessionKey.name), name)
      ..put(_localField(SessionKey.joined), joined)
      ..put(_localField(SessionKey.workspace), workspace)
      ..put(_localField(SessionKey.addresses), addresses.join(' '))
      ..put(_localField(SessionKey.left), false);
  }

  /// Writes [nodes] under a new workspace id, uncommitted.
  String _writeWorkspace(LayoutNodes nodes) {
    final id = document.newId();
    document
      ..putMap([SessionKey.workspaces, id])
      ..putMap(nodesPath(id));
    nodes.forEach(
      (node, fields) => _writeValue([...nodesPath(id), node], fields),
    );
    return id;
  }

  /// Writes [value] at [path], maps as maps. Throws [ArgumentError] for
  /// values outside the port (lists, non-string keys, other objects).
  void _writeValue(List<String> path, Object? value) {
    switch (value) {
      case Map<Object?, Object?>():
        document.putMap(path);
        value.forEach((key, child) {
          if (key is! String) {
            throw ArgumentError.value(key, 'key', 'is not a String');
          }
          _writeValue([...path, key], child);
        });
      case null || bool() || int() || double() || String() || Uint8List():
        document.put(path, value);
      default:
        throw ArgumentError.value(value, 'value', 'cannot be stored');
    }
  }

  Map<String, Object?> _readMap(List<String> path) {
    final result = <String, Object?>{};
    document.entries(path).forEach((key, value) {
      result[key] = value is CrdtMap ? _readMap([...path, key]) : value;
    });
    return result;
  }

  T? _typed<T>(List<String> path) {
    final value = document.get(path);
    return value is T ? value : null;
  }
}
