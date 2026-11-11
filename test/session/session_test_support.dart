// What: Shared helpers for the Session tests: a node table fixture, local
//   (socketless) sync between documents, condition polling, a Participant
//   harness over real loopback sockets, and a TCP proxy that can go silent.
// Why: the document, roster and network tests need the same fixtures; the
//   proxy lets a test make a connection silent without closing it, which is
//   the only way to exercise the 10 s rule (MPLY-17) rather than a close.
// Coupled to: lib/session/session_document.dart,
//   lib/session/session_network.dart, lib/crdt/automerge_crdt_document.dart,
//   and the tests in this folder that import it.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:painter/crdt/automerge_crdt_document.dart';
import 'package:painter/crdt/crdt_document.dart';
import 'package:painter/session/session_document.dart';
import 'package:painter/session/session_network.dart';
import 'package:painter/workspace/layout_tree.dart' show LayoutNodes;

const backend = AutomergeBackend();

/// A one-pane workspace whose canvas is centered at [x], with a nested
/// `state` map like PNT-A0016-01's.
LayoutNodes paneNodes(double x) => {
  'root': {'kind': 'split', 'axis': 'row', 'order': 'a', 'share': 1.0},
  'pane': {
    'parent': 'root',
    'kind': 'pane',
    'order': 'a',
    'share': 1.0,
    'mode': 'canvas',
    'deleted': false,
    'state': {
      'canvas': {
        'center': {'x': x, 'y': 0.0},
        'extent': 2.0,
        'rotation': 0.0,
      },
    },
  },
};

/// Exchanges sync messages between [a] and [b] until neither has any.
void syncLocally(CrdtDocument a, CrdtDocument b) {
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

/// Waits until [condition] holds, polling, and fails with [reason] after
/// [timeout].
Future<void> eventually(
  bool Function() condition, {
  String reason = 'condition',
  Duration timeout = const Duration(seconds: 5),
}) async {
  final watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > timeout) fail('Timed out waiting for $reason.');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// A Participant with its own documents and network on 127.0.0.1, disposed
/// at the end of the test.
final class TestParticipant {
  TestParticipant._(this.content, this.session, this.network);

  /// Creates the Session's documents, as its creator, and listens.
  static Future<TestParticipant> host(
    String name, {
    int engine = 1,
    Duration pingInterval = const Duration(seconds: 2),
    Duration peerTimeout = const Duration(seconds: 10),
  }) async {
    final content = backend.create();
    final session = SessionDocument.create(
      backend.create(),
      name: name,
      engine: engine,
      nodes: paneNodes(0),
    );
    final participant = TestParticipant._register(
      content,
      session,
      name,
      engine,
      pingInterval,
      peerTimeout,
    );
    await participant.network.start(
      bindAddress: InternetAddress.loopbackIPv4,
      port: 0,
    );
    return participant;
  }

  /// A Participant with empty documents, not yet joined.
  static TestParticipant joiner(
    String name, {
    int engine = 1,
    Duration pingInterval = const Duration(seconds: 2),
    Duration peerTimeout = const Duration(seconds: 10),
  }) => TestParticipant._register(
    backend.create(),
    SessionDocument(backend.create()),
    name,
    engine,
    pingInterval,
    peerTimeout,
  );

  static TestParticipant _register(
    CrdtDocument content,
    SessionDocument session,
    String name,
    int engine,
    Duration pingInterval,
    Duration peerTimeout,
  ) {
    final participant = TestParticipant._(
      content,
      session,
      SessionNetwork(
        content: content,
        session: session,
        name: name,
        engine: engine,
        pingInterval: pingInterval,
        peerTimeout: peerTimeout,
      ),
    );
    addTearDown(participant._dispose);
    return participant;
  }

  final CrdtDocument content;
  final SessionDocument session;
  final SessionNetwork network;

  String get id => session.localId;

  String get address => network.addresses.first;

  /// Joins the Session at [address] with a workspace centered at 1.
  Future<void> join(String address) => network.join(
    address,
    nodes: () => paneNodes(1),
    bindAddress: InternetAddress.loopbackIPv4,
    port: 0,
  );

  /// Writes [value] at content key [key] and commits.
  void write(String key, Object? value) {
    content.put([key], value);
    content.commit(message: 'test');
  }

  /// Whether this Participant sees [id] as present.
  bool sees(String id) => network.roster.value.member(id)?.present ?? false;

  String? get hostId => network.roster.value.hostId;

  Future<void> _dispose() async {
    await network.leave();
    content.dispose();
    session.document.dispose();
  }
}

/// Forwards TCP connections to 127.0.0.1:[targetPort]; [pause] silently
/// drops all traffic from then on while keeping the sockets open, and
/// [bytesPerSecond], when set, slows each direction to that rate.
final class SilenceableProxy {
  SilenceableProxy._(this._server, this._targetPort, this.bytesPerSecond) {
    _server.listen(_accept);
    addTearDown(close);
  }

  static Future<SilenceableProxy> start(
    int targetPort, {
    int? bytesPerSecond,
  }) async => SilenceableProxy._(
    await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
    targetPort,
    bytesPerSecond,
  );

  final ServerSocket _server;
  final int _targetPort;
  final int? bytesPerSecond;
  final List<Socket> _sockets = [];
  bool _paused = false;

  String get address => '127.0.0.1:${_server.port}';

  void pause() => _paused = true;

  /// Closes every forwarded connection abruptly, as a crash would.
  void kill() {
    for (final socket in _sockets) {
      socket.destroy();
    }
  }

  Future<void> close() async {
    kill();
    await _server.close();
  }

  Future<void> _accept(Socket client) async {
    final Socket upstream;
    try {
      upstream = await Socket.connect(
        InternetAddress.loopbackIPv4,
        _targetPort,
      );
    } on SocketException {
      client.destroy();
      return;
    }
    _sockets
      ..add(client)
      ..add(upstream);
    void pipe(Socket from, Socket to) {
      // Forwarding is chained so throttled data stays in order.
      var forwarded = Future<void>.value();
      void forward(Future<void> Function() step) {
        forwarded = forwarded.then((_) => step()).catchError((Object _) {});
      }

      from.listen(
        (data) => forward(() async {
          final rate = bytesPerSecond;
          if (rate == null) {
            if (!_paused) to.add(data);
            return;
          }
          const slice = 16 * 1024;
          for (var start = 0; start < data.length; start += slice) {
            if (_paused) return;
            final end = start + slice < data.length
                ? start + slice
                : data.length;
            to.add(data.sublist(start, end));
            await Future<void>.delayed(
              Duration(microseconds: (end - start) * 1000000 ~/ rate),
            );
          }
        }),
        onDone: () => forward(() async {
          if (!_paused) to.destroy();
        }),
        onError: (Object _) => to.destroy(),
      );
    }

    pipe(client, upstream);
    pipe(upstream, client);
  }
}
