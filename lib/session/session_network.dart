// What: SessionNetwork, which joins the local Participant to a Session: it
//   listens for and opens WebSocket connections, runs Automerge sync of the
//   content and session documents on each, tracks presence and the Host,
//   and leaves; plus SessionJoinRefused and SessionConnectionFailed.
// Why: docs/decisions/013-session-networking.md (PNT-A0019-01..08) and
//   docs/spec/multiplayer.md (MPLY-1..18) define a serverless Session; this
//   file is the only place that touches sockets, so the documents and the
//   UI stay free of networking.
// Coupled to: session_protocol.dart (frames), session_document.dart (schema
//   writes: joining, addresses, left, host, discarding workspaces),
//   session_roster.dart (presence and the Host rule),
//   ../crdt/crdt_document.dart (sync messages and listeners),
//   ../logging/painter_log.dart (records of Participants joining, leaving
//   and timing out, Host changes, refusals and malformed messages,
//   docs/spec/logging.md LOG-13, LOG-15 to LOG-18).
//
// ---------------------------------------------------------------------------
// Session overview
//
// What: a Session is a set of Participants that each hold a replica of two
// Automerge documents, the content document (strokes) and the session
// document (participants, Host, workspaces; docs/decisions/009-shared-
// workspaces.md). Every pair of Participants holds one WebSocket connection
// (a full mesh, PNT-A0019-05) and runs Automerge sync for both documents on
// it, so every change reaches everyone without a server (MPLY-5, MPLY-6).
//
// Why a mesh: a relay or a star around the Host is a server or a single
// point of failure, and the Session must outlive any Participant (MPLY-18);
// docs/decisions/013-session-networking.md rejects both.
//
// How: start() listens on port 47800 (else one the OS picks) and reports the
// Session addresses. join() connects to one address, says hello, gets
// welcome or refuse (Engine versions differ, MPLY-8), syncs from empty
// documents until it has the joined peer's state, then adds its own
// participant entry and dials every listed Participant. On each
// connection, a sync message is generated after every local commit and
// every received message (PNT-A0019-04), sent in pieces of at most 64 KiB
// so a large one never silences the connection (PNT-A0019-02); a remote
// change is also forwarded to the other connections, so a Participant not
// yet in the mesh still converges. Every ping interval (2 s) each peer
// pings its connections and repairs the mesh: it dials each listed,
// not-left Participant it has no connection to that joined before it (ties:
// the larger id dials), so exactly one side of each pair keeps retrying
// (PNT-A0019-05). 10 s of silence drops a connection (PNT-A0019-06,
// MPLY-17).
//
// Presence and Host: a Participant is present while it has a live
// connection here, or is the local one; session_roster.dart computes the
// Host from presence and `host` (PNT-A0019-07). When a connection is lost
// without bye, this peer marks that Participant left; whenever a
// Participant's `left` becomes true, it discards the workspaces no
// Participant still in the Session names (PNT-A0015-04, which ignores
// presence so a newcomer still connecting keeps its workspace). An active
// peer marked left by another clears its own `left`. If it computes itself
// Host while `host` names a Participant marked left or not listed, it writes
// its own id; `host` naming someone merely absent here is left alone, so
// two partitioned peers cannot overwrite each other forever through a
// third. Those writes run in a microtask, never inside a document listener,
// because they commit and so notify listeners again.
//
// Threading: every CRDT call runs on the isolate that created the network,
// where dart:io delivers socket events (PNT-A0013-06). Invariant: at most
// one registered connection per remote Participant (PNT-A0019-08).
// ---------------------------------------------------------------------------

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;

import '../crdt/crdt_document.dart';
import '../logging/painter_log.dart';
import '../workspace/layout_tree.dart' show LayoutNodes;
import 'session_document.dart';
import 'session_protocol.dart';
import 'session_roster.dart';

/// The Session refused a join because the protocol or Engine version
/// differs (PNT-A0019-03); the user is shown both Engine versions (MPLY-8).
final class SessionJoinRefused implements Exception {
  const SessionJoinRefused({
    required this.reason,
    required this.localEngine,
    required this.sessionEngine,
  });

  /// A [RefuseReason] value.
  final String reason;

  /// The joining build's Engine version.
  final int localEngine;

  /// The refusing Participant's Engine version.
  final int sessionEngine;

  @override
  String toString() =>
      'SessionJoinRefused($reason: local engine $localEngine, '
      'session engine $sessionEngine)';
}

/// A connection ended before it was usable: closed or silent before
/// welcome, or before the first sync of a join completed.
final class SessionConnectionFailed implements Exception {
  const SessionConnectionFailed(this.message);

  final String message;

  @override
  String toString() => 'SessionConnectionFailed($message)';
}

/// The local Participant's side of a Session. See the Session overview at
/// the top of this file.
///
/// Lifecycle: the creator fills its session document with
/// SessionDocument.create and calls [start]; a joiner passes empty documents
/// and calls [join]. [leave] ends both. The documents stay usable after
/// [leave] and are never disposed here.
final class SessionNetwork {
  SessionNetwork({
    required this.content,
    required this.session,
    required this.name,
    required this.engine,
    this.pingInterval = const Duration(seconds: 2),
    this.peerTimeout = const Duration(seconds: 10),
    this.log,
  });

  /// The content document.
  final CrdtDocument content;

  /// The session document.
  final SessionDocument session;

  /// The local Participant's shown name (MPLY-10).
  final String name;

  /// The local build's Engine version; hellos with another are refused.
  final int engine;

  /// How often each connection is pinged (PNT-A0019-06).
  final Duration pingInterval;

  /// Silence after which a peer is gone (MPLY-17); also bounds connecting
  /// and the wait for welcome.
  final Duration peerTimeout;

  /// Receives this peer's view of the Session as records: other
  /// Participants joining and leaving, timeouts, the Host changing, joins
  /// it refused and messages it could not read. Never one per message
  /// (LOG-20).
  final PainterLog? log;

  /// The local participant id.
  String get localId => session.localId;

  /// The Session addresses, `host:port`, once [start] completed
  /// (PNT-A0019-01, MPLY-2).
  List<String> get addresses => _addresses;

  /// The Participants with presence and the Host; changes whenever either
  /// does.
  ValueListenable<SessionRoster> get roster => _roster;

  /// The participant ids present to this peer: itself and every Participant
  /// with a live connection (PNT-A0019-07).
  Set<String> get presentIds => {localId, ..._connections.keys};

  /// Whether the local Participant is in a Session: started as creator, or
  /// joined, and not left.
  bool get isActive => _active;

  /// Whether [leave] ran or a [join] failed; the network is then unusable.
  bool get isClosed => _closed;

  final ValueNotifier<SessionRoster> _roster = ValueNotifier(
    SessionRoster.empty,
  );

  /// Live connections after welcome, by remote participant id.
  final Map<String, _Peer> _connections = {};

  /// Every open connection, including those still in hello/welcome.
  final Set<_Peer> _open = {};

  HttpServer? _server;
  HttpClient? _client;
  Timer? _pingTimer;
  List<String> _addresses = const [];
  bool _active = false;
  bool _joining = false;
  bool _closed = false;

  /// The connection whose sync message is being applied; its own reply is
  /// generated after the apply, so the listener skips it.
  _Peer? _receivingFrom;

  /// Counts remote changes, so a receive can tell whether it changed a
  /// document.
  int _remoteChanges = 0;

  bool _maintenanceDue = false;
  bool _discardDue = false;

  /// Participants whose connection was lost without bye, to mark left.
  final Set<String> _lost = {};

  /// Participants being dialed by [_repairMesh].
  final Set<String> _dialing = {};

  /// How many participant entries were marked left at the last roster;
  /// a rise means a Participant left, so workspaces may need discarding.
  int _leftCount = 0;

  /// The other listed, not-left Participants at the last roster, or null
  /// until this peer is active; the first active roster sets it without a
  /// record, so a joiner does not report everyone already there (LOG-15).
  Set<String>? _loggedMembers;

  /// The Host at the last roster (LOG-18).
  String? _loggedHost;

  /// Listens for connections (PNT-A0019-01) on [bindAddress] (all IPv4
  /// interfaces by default) and [port] (47800, or an OS-chosen port if that
  /// is taken, by default), and fills [addresses]: the non-loopback IPv4
  /// addresses with the port, or just [bindAddress] when one is given. As
  /// creator, also writes the addresses to the local entry and becomes
  /// active. Does nothing when already listening, or when [leave] runs
  /// before it finishes.
  Future<void> start({InternetAddress? bindAddress, int? port}) async {
    if (_closed) throw StateError('The session network is closed.');
    if (_server != null) return;
    final address = bindAddress ?? InternetAddress.anyIPv4;
    final server = await _bind(address, port);
    // leave() may have run during either await; it found no server to close.
    if (_closed) {
      await server.close(force: true);
      return;
    }
    _server = server;
    server.listen(_onRequest);
    final addresses = await _sessionAddresses(address, server.port);
    if (_closed) return;
    _addresses = List.unmodifiable(addresses);
    content.addListener(_onContentChange);
    session.addListener(_onSessionChange);
    _pingTimer = Timer.periodic(pingInterval, (_) => _onTick());
    if (session.localParticipant != null) {
      _active = true;
      session.setLocalAddresses(_addresses);
    }
    _updateRoster();
  }

  /// Joins the Session at [address] (`host:port`, MPLY-3), listening first
  /// as [start] does with [bindAddress] and [port]. Requires empty
  /// documents (PNT-A0019-05): after welcome it syncs until it has the
  /// joined peer's state, then calls [nodes] and adds the local entry with a
  /// new workspace holding its result (WKSP-31), then dials every listed
  /// Participant it has no connection to, all addresses at once, returning
  /// when each is connected or failed; the mesh repair retries failures.
  /// [nodes] runs only after that first sync, so it can read the Session's
  /// `storedWorkspace` (WKSP-9) and must take ids from [session]'s document.
  ///
  /// Throws [SessionJoinRefused] when refused (MPLY-8),
  /// [SessionConnectionFailed] when the peer closes or goes silent first,
  /// or the socket's own exception. On failure the network is closed;
  /// retry with a new network and new empty documents.
  Future<void> join(
    String address, {
    required LayoutNodes Function() nodes,
    InternetAddress? bindAddress,
    int? port,
  }) async {
    if (_closed || _active || _joining) {
      throw StateError('The session network cannot join now.');
    }
    _joining = true;
    try {
      await start(bindAddress: bindAddress, port: port);
      final peer = await _connect(address, trackFirstSync: true);
      await peer.firstSync!.future;
      session.addLocalParticipant(
        name: name,
        addresses: _addresses,
        nodes: nodes(),
      );
      _active = true;
      _updateRoster();
    } catch (_) {
      await _shutdown(sayBye: false);
      rethrow;
    } finally {
      _joining = false;
    }
    await _repairMesh();
  }

  /// Makes [participantId] the Host (MPLY-11). Throws [StateError] unless
  /// the local Participant is the Host, and [ArgumentError] unless
  /// [participantId] is a present Participant.
  void promote(String participantId) {
    if (!_active || _roster.value.hostId != localId) {
      throw StateError('Only the Host can promote.');
    }
    if (!_connections.containsKey(participantId) ||
        session.participant(participantId) == null) {
      throw ArgumentError.value(
        participantId,
        'participantId',
        'is not a present Participant',
      );
    }
    session.setHost(participantId);
  }

  /// Leaves the Session (MPLY-15): sets the local `left`, which the
  /// document listener sends to every peer, then sends bye, closes every
  /// connection and stops listening (PNT-A0019-06). The documents keep
  /// everything received until then (MPLY-16).
  Future<void> leave() async {
    if (_closed) return;
    if (_active) session.setLocalLeft();
    await _shutdown(sayBye: true);
  }

  Future<void> _shutdown({required bool sayBye}) async {
    _closed = true;
    _active = false;
    content.removeListener(_onContentChange);
    session.removeListener(_onSessionChange);
    _pingTimer?.cancel();
    final closing = <Future<void>>[];
    for (final peer in List.of(_open)) {
      if (sayBye && identical(_connections[peer.remoteId], peer)) {
        _send(peer, const ByeFrame());
      }
      closing.add(_disconnect(peer));
    }
    await _server?.close(force: true);
    _client?.close(force: true);
    await Future.wait(closing)
        .timeout(peerTimeout, onTimeout: () => const <void>[]);
  }

  static Future<HttpServer> _bind(InternetAddress address, int? port) async {
    if (port != null) return HttpServer.bind(address, port);
    try {
      return await HttpServer.bind(address, defaultSessionPort);
    } on SocketException {
      // Normal flow, not a failure: PNT-A0019-01 falls back to an OS-chosen
      // port when 47800 is taken.
      return HttpServer.bind(address, 0);
    }
  }

  static Future<List<String>> _sessionAddresses(
    InternetAddress bound,
    int port,
  ) async {
    if (bound != InternetAddress.anyIPv4) return ['${bound.address}:$port'];
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    return [
      for (final interface in interfaces)
        for (final address in interface.addresses)
          if (!address.isLoopback) '${address.address}:$port',
    ];
  }

  void _onRequest(HttpRequest request) {
    if (_closed || !WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.badRequest;
      unawaited(request.response.close());
      return;
    }
    WebSocketTransformer.upgrade(request).then(
      (socket) {
        if (_closed) {
          unawaited(socket.close());
        } else {
          _adopt(socket, outgoing: false);
        }
      },
      onError: (Object error) =>
          _warn('session.connection.failed', {'error': error.toString()}),
    );
  }

  /// Opens a connection to [address], sends hello and waits for welcome.
  /// [expectedId] rejects a welcome from anyone else (a mesh connection to
  /// a listed Participant); [trackFirstSync] makes the returned peer report
  /// the end of a join's first sync.
  Future<_Peer> _connect(
    String address, {
    String? expectedId,
    bool trackFirstSync = false,
  }) async {
    final client = _client ??= HttpClient()..connectionTimeout = peerTimeout;
    final pending = WebSocket.connect('ws://$address', customClient: client);
    final WebSocket socket;
    try {
      socket = await pending.timeout(peerTimeout);
    } on TimeoutException {
      // The connection may still succeed later; close it then.
      unawaited(pending.then((orphan) => orphan.close(), onError: (_) {}));
      rethrow;
    }
    if (_closed) {
      unawaited(socket.close());
      throw const SessionConnectionFailed('The session network is closed.');
    }
    final peer = _adopt(
      socket,
      outgoing: true,
      expectedId: expectedId,
      trackFirstSync: trackFirstSync,
    );
    _send(
      peer,
      HelloFrame(
        protocol: sessionProtocolVersion,
        engine: engine,
        participant: localId,
        name: name,
        addresses: _addresses,
      ),
    );
    await peer.welcomed.future;
    return peer;
  }

  /// Dials every listed, not-left Participant without a connection or a
  /// dial in progress that this peer is the one to dial: its own `joined` is
  /// larger, ties broken by the larger id (PNT-A0019-05). Completes when
  /// every dial started here has connected or failed.
  Future<void> _repairMesh() {
    final local = session.localParticipant;
    if (!_active || local == null) return Future<void>.value();
    final dials = <Future<void>>[];
    for (final participant in session.participants) {
      if (participant.id == localId ||
          participant.left ||
          _connections.containsKey(participant.id) ||
          _dialing.contains(participant.id)) {
        continue;
      }
      final dialsFirst =
          local.joined > participant.joined ||
          (local.joined == participant.joined &&
              localId.compareTo(participant.id) > 0);
      if (dialsFirst) dials.add(_dial(participant));
    }
    return Future.wait(dials);
  }

  /// Dials all of [participant]'s addresses at once, completing at the
  /// first welcome or when every attempt failed, so an unreachable address
  /// costs at most one [peerTimeout] in all. A second success loses the
  /// duplicate rule in [_register] and closes.
  Future<void> _dial(SessionParticipant participant) async {
    if (participant.addresses.isEmpty) return;
    _dialing.add(participant.id);
    final done = Completer<void>();
    var failures = 0;
    for (final address in participant.addresses) {
      unawaited(
        _connect(address, expectedId: participant.id).then(
          (_) {
            if (!done.isCompleted) done.complete();
          },
          // Any error, including a malformed address, only fails this attempt.
          onError: (Object _) {
            failures++;
            if (failures == participant.addresses.length && !done.isCompleted) {
              done.complete();
            }
          },
        ),
      );
    }
    try {
      await done.future;
    } finally {
      _dialing.remove(participant.id);
    }
  }

  _Peer _adopt(
    WebSocket socket, {
    required bool outgoing,
    String? expectedId,
    bool trackFirstSync = false,
  }) {
    final peer = _Peer(
      socket,
      outgoing: outgoing,
      expectedId: expectedId,
      firstSync: trackFirstSync ? (Completer<void>()..future.ignore()) : null,
    );
    _open.add(peer);
    socket.listen(
      (data) => _onMessage(peer, data),
      onDone: () => _disconnect(peer),
      onError: (Object _) => _disconnect(peer),
      cancelOnError: true,
    );
    _armSilence(peer);
    return peer;
  }

  void _onMessage(_Peer peer, Object? data) {
    if (peer.closed) return;
    peer.heard.reset();
    final SessionFrame frame;
    try {
      if (data is! List<int>) throw const FormatException('Text frame.');
      frame = SessionFrame.decode(
        data is Uint8List ? data : Uint8List.fromList(data),
      );
    } on FormatException catch (error) {
      _warnMalformed(peer, error);
      _disconnect(peer);
      return;
    }
    switch (frame) {
      case HelloFrame():
        _onHello(peer, frame);
      case WelcomeFrame():
        _onWelcome(peer, frame);
      case RefuseFrame():
        _onRefuse(peer, frame);
      case SyncPartFrame():
        if (_isSyncing(peer)) peer.reassembler.addPart(frame);
      case SyncFrame():
        if (_isSyncing(peer)) {
          _onSync(peer, frame.document, peer.reassembler.finish(frame));
        }
      case PingFrame():
        break;
      case ByeFrame():
        peer.saidBye = true;
        _disconnect(peer);
    }
  }

  /// The accepting side of PNT-A0019-03.
  void _onHello(_Peer peer, HelloFrame hello) {
    if (peer.outgoing ||
        peer.remoteId != null ||
        hello.participant == localId) {
      _disconnect(peer);
    } else if (hello.protocol != sessionProtocolVersion) {
      _refuse(
        peer,
        hello,
        RefuseReason.protocol,
        'their protocol version ${hello.protocol} differs from '
        '$sessionProtocolVersion',
      );
    } else if (hello.engine != engine) {
      _refuse(
        peer,
        hello,
        RefuseReason.engine,
        'their Engine version ${hello.engine} differs from $engine',
      );
    } else {
      peer.remoteId = hello.participant;
      _send(peer, WelcomeFrame(participant: localId, name: name));
      _register(peer);
    }
  }

  /// Refuses [hello]'s sender for [reason] (PNT-A0019-03) and records it,
  /// with [explanation], as a warning (LOG-17).
  void _refuse(
    _Peer peer,
    HelloFrame hello,
    String reason,
    String explanation,
  ) {
    _warn('session.join.refused', {
      'participant': hello.name,
      'reason': explanation,
    });
    _send(peer, RefuseFrame(reason: reason, engine: engine));
    _disconnect(peer);
  }

  void _onWelcome(_Peer peer, WelcomeFrame welcome) {
    final expected = peer.expectedId;
    if (!peer.outgoing ||
        peer.remoteId != null ||
        welcome.participant == localId ||
        (expected != null && welcome.participant != expected)) {
      _disconnect(peer);
      return;
    }
    peer.remoteId = welcome.participant;
    peer.welcomed.complete();
    _register(peer);
  }

  void _onRefuse(_Peer peer, RefuseFrame refuse) {
    if (peer.outgoing && peer.remoteId == null) {
      peer.welcomed.completeError(
        SessionJoinRefused(
          reason: refuse.reason,
          localEngine: engine,
          sessionEngine: refuse.engine,
        ),
      );
    }
    _disconnect(peer);
  }

  /// Makes [peer] the connection to its Participant, applying the duplicate
  /// rule (PNT-A0019-08): of two connections, keep the one opened by the
  /// smaller participant id. Both ends compute the same answer, so the
  /// loser closes without changing presence. Then starts sync.
  void _register(_Peer peer) {
    final id = peer.remoteId!;
    final existing = _connections[id];
    if (existing != null) {
      final smaller = localId.compareTo(id) < 0 ? localId : id;
      String openerOf(_Peer connection) => connection.outgoing ? localId : id;
      if (openerOf(peer) != smaller || openerOf(existing) == smaller) {
        _disconnect(peer);
        return;
      }
      _connections[id] = peer;
      _disconnect(existing);
    } else {
      _connections[id] = peer;
    }
    peer
      ..contentSync = content.createSyncPeer()
      ..sessionSync = session.document.createSyncPeer();
    _sendSync(peer, SyncDocument.content);
    _sendSync(peer, SyncDocument.session);
    _updateRoster();
  }

  /// Whether [peer] is the registered connection to its Participant, the
  /// only one sync frames may arrive on; closes it otherwise.
  bool _isSyncing(_Peer peer) {
    if (peer.contentSync != null &&
        identical(_connections[peer.remoteId], peer)) {
      return true;
    }
    _disconnect(peer);
    return false;
  }

  /// Applies the whole sync [message] for [document] from [peer] and
  /// answers it (PNT-A0019-04).
  void _onSync(_Peer peer, SyncDocument document, Uint8List message) {
    final sync = peer.syncFor(document)!;
    final changesBefore = _remoteChanges;
    _receivingFrom = peer;
    try {
      _document(document).receiveSyncMessage(sync, message);
    } on FormatException catch (error) {
      _warnMalformed(peer, error);
      _disconnect(peer);
      return;
    } finally {
      _receivingFrom = null;
    }
    final changed = _remoteChanges != changesBefore;
    final replied = _sendSync(peer, document);
    // First sync of a join (PNT-A0019-05). The joiner starts empty, so the
    // first message that changes its document carries every change the peer
    // had when it answered the joiner's first message. A document that does
    // not change is in sync once a received message leaves Automerge with
    // nothing to reply, which happens only when both sides' heads are equal.
    final firstSync = peer.firstSync;
    if (firstSync != null && !firstSync.isCompleted && (changed || !replied)) {
      peer.firstSynced.add(document);
      if (peer.firstSynced.length == SyncDocument.values.length) {
        firstSync.complete();
      }
    }
  }

  void _onContentChange(CrdtChangeOrigin origin) =>
      _onDocumentChange(SyncDocument.content, origin);

  void _onSessionChange(CrdtChangeOrigin origin) {
    _onDocumentChange(SyncDocument.session, origin);
    _updateRoster();
  }

  /// Sends [document]'s change to every connection (PNT-A0019-04),
  /// forwarding remote changes too.
  void _onDocumentChange(SyncDocument document, CrdtChangeOrigin origin) {
    if (origin == CrdtChangeOrigin.remote) _remoteChanges++;
    for (final peer in _connections.values) {
      if (!identical(peer, _receivingFrom)) _sendSync(peer, document);
    }
  }

  /// Sends the next sync message of [document] to [peer], in pieces
  /// (PNT-A0019-02); false when Automerge had none.
  bool _sendSync(_Peer peer, SyncDocument document) {
    final sync = peer.syncFor(document);
    if (peer.closed || sync == null) return false;
    final message = _document(document).generateSyncMessage(sync);
    if (message == null) return false;
    for (final frame in syncFrames(document, message)) {
      _send(peer, frame);
    }
    return true;
  }

  CrdtDocument _document(SyncDocument document) => switch (document) {
    SyncDocument.content => content,
    SyncDocument.session => session.document,
  };

  void _send(_Peer peer, SessionFrame frame) {
    if (!peer.closed) peer.socket.add(frame.encode());
  }

  /// Every ping interval: pings every connection (PNT-A0019-06) and
  /// repairs the mesh (PNT-A0019-05).
  void _onTick() {
    for (final peer in _connections.values) {
      _send(peer, const PingFrame());
    }
    unawaited(_repairMesh());
  }

  /// Drops [peer] once nothing has arrived from it for [peerTimeout]
  /// (MPLY-17), re-arming for the remainder after each expiry.
  void _armSilence(_Peer peer) {
    if (peer.closed) return;
    final remaining = peerTimeout - peer.heard.elapsed;
    if (remaining <= Duration.zero) {
      final id = peer.remoteId;
      if (_active && id != null && identical(_connections[id], peer)) {
        _warn('session.participant.timed_out', {
          'participant': _nameOf(id),
          'seconds': peerTimeout.inSeconds,
        });
      }
      _disconnect(peer);
      return;
    }
    peer.silence = Timer(remaining, () => _armSilence(peer));
  }

  /// Closes [peer]. If it was the registered connection to its Participant,
  /// that Participant is no longer present; unless it said bye, it is also
  /// queued to be marked left (MPLY-17).
  Future<void> _disconnect(_Peer peer) {
    if (peer.closed) return peer.closing;
    peer.closed = true;
    _open.remove(peer);
    peer.silence?.cancel();
    peer.closing = peer.socket.close().then((_) {}, onError: (Object _) {});
    peer.contentSync?.dispose();
    peer.sessionSync?.dispose();
    peer
      ..contentSync = null
      ..sessionSync = null;
    const failure = SessionConnectionFailed('The connection closed.');
    if (!peer.welcomed.isCompleted) peer.welcomed.completeError(failure);
    final firstSync = peer.firstSync;
    if (firstSync != null && !firstSync.isCompleted) {
      firstSync.completeError(failure);
    }
    final id = peer.remoteId;
    if (id != null && identical(_connections[id], peer)) {
      _connections.remove(id);
      if (_active && !peer.saidBye) _lost.add(id);
      _updateRoster();
    } else if (_lost.isNotEmpty) {
      // A dial [_maintain] was waiting on may have just failed.
      _scheduleMaintenance();
    }
    return peer.closing;
  }

  void _updateRoster() {
    final roster = SessionRoster.compute(
      participants: session.participants,
      hostField: session.host,
      present: presentIds,
    );
    _roster.value = roster;
    _logRosterChanges(roster);
    var leftCount = 0;
    for (final member in roster.members) {
      if (member.participant.left) leftCount++;
    }
    final someoneLeft = leftCount > _leftCount;
    _leftCount = leftCount;
    _scheduleMaintenance(discard: someoneLeft);
  }

  /// Records other Participants joining or leaving (LOG-15) and the Host
  /// changing (LOG-18) since the last roster, once this peer is active.
  void _logRosterChanges(SessionRoster roster) {
    if (!_active) {
      _loggedMembers = null;
      _loggedHost = null;
      return;
    }
    final members = {
      for (final member in roster.members)
        if (!member.participant.left && member.participant.id != localId)
          member.participant.id,
    };
    final previous = _loggedMembers;
    final previousHost = _loggedHost;
    _loggedMembers = members;
    _loggedHost = roster.hostId;
    if (previous == null) return;
    for (final id in members.difference(previous)) {
      _info('session.participant.joined', {'participant': _nameOf(id)});
    }
    for (final id in previous.difference(members)) {
      _info('session.participant.left', {'participant': _nameOf(id)});
    }
    final host = roster.hostId;
    if (host != null && host != previousHost) {
      _info('session.host.changed', {'participant': _nameOf(host)});
    }
  }

  /// The shown name of Participant [id], or [id] when it has none.
  String _nameOf(String id) {
    final participant = session.participant(id);
    if (participant == null || participant.name.isEmpty) return id;
    return participant.name;
  }

  /// Records that [peer] sent a message that could not be read (LOG-13);
  /// the caller drops the connection.
  void _warnMalformed(_Peer peer, FormatException error) {
    final id = peer.remoteId;
    _warn('session.message.malformed', {
      'participant': id == null ? 'a connecting peer' : _nameOf(id),
      'error': error.message,
    });
  }

  void _info(String messageId, Map<String, Object?> arguments) {
    final log = this.log;
    if (log != null) unawaited(log.info(messageId, arguments: arguments));
  }

  void _warn(String messageId, Map<String, Object?> arguments) {
    final log = this.log;
    if (log != null) unawaited(log.warn(messageId, arguments: arguments));
  }

  /// Schedules [_maintain]; [discard] asks it to discard workspaces too,
  /// because a Participant's `left` became true.
  void _scheduleMaintenance({bool discard = false}) {
    if (!_active) return;
    _discardDue |= discard;
    if (_maintenanceDue) return;
    _maintenanceDue = true;
    scheduleMicrotask(_maintain);
  }

  /// The writes presence calls for: marking Participants lost without bye
  /// as left (SessionDocument.markLeft, which also discards), clearing the
  /// local `left` if another peer set it, discarding workspaces after
  /// someone left (PNT-A0015-04), and taking `host` when this peer is the
  /// Host while `host` names a Participant marked left or not listed
  /// (PNT-A0019-07).
  void _maintain() {
    _maintenanceDue = false;
    final discard = _discardDue;
    _discardDue = false;
    if (!_active) return;
    for (final id in List.of(_lost)) {
      if (_connections.containsKey(id)) {
        // A duplicate connection replaced the lost one (PNT-A0019-08).
        _lost.remove(id);
      } else if (!_awaitingWelcome(id)) {
        _lost.remove(id);
        session.markLeft(id);
      }
    }
    if (session.localParticipant?.left ?? false) {
      session.setLocalLeft(left: false);
    }
    if (discard) session.discardUnnamedWorkspaces();
    final hostField = session.host;
    if (_roster.value.hostId == localId && hostField != localId) {
      final named = hostField == null ? null : session.participant(hostField);
      if (named == null || named.left) session.setHost(localId);
    }
  }

  /// Whether an outgoing connection that may reach [id] still awaits
  /// welcome. Of two simultaneous connections the one the smaller id opened
  /// wins (PNT-A0019-08); the other peer may close the losing one before
  /// the winner's welcome arrives here, and that close must not count as
  /// losing a Participant that is in fact still connected.
  bool _awaitingWelcome(String id) => _open.any(
    (peer) =>
        peer.outgoing &&
        peer.remoteId == null &&
        (peer.expectedId == null || peer.expectedId == id),
  );
}

/// One WebSocket connection to another Participant.
final class _Peer {
  _Peer(
    this.socket, {
    required this.outgoing,
    required this.expectedId,
    required this.firstSync,
  });

  final WebSocket socket;

  /// Whether the local peer opened it (PNT-A0019-08).
  final bool outgoing;

  /// For an outgoing mesh connection, the participant id it must reach.
  final String? expectedId;

  /// Completes when welcome arrives; fails on refuse or close. Errors are
  /// marked handled, since only outgoing connections are awaited.
  final Completer<void> welcomed = Completer<void>()..future.ignore();

  /// For a join's connection, completes when its first sync has.
  final Completer<void>? firstSync;

  /// The documents whose first sync has completed.
  final Set<SyncDocument> firstSynced = {};

  /// Time since the last frame arrived.
  final Stopwatch heard = Stopwatch()..start();

  /// Joins the sync parts arriving here (PNT-A0019-02).
  final SyncReassembler reassembler = SyncReassembler();

  Timer? silence;

  /// The remote participant id, known after hello or welcome.
  String? remoteId;

  CrdtSyncPeer? contentSync;
  CrdtSyncPeer? sessionSync;
  bool closed = false;

  /// Whether it ended with bye, so its Participant marked itself left.
  bool saidBye = false;
  Future<void> closing = Future<void>.value();

  CrdtSyncPeer? syncFor(SyncDocument document) => switch (document) {
    SyncDocument.content => contentSync,
    SyncDocument.session => sessionSync,
  };
}
