// What: Tests of SessionNetwork (lib/session/session_network.dart) over real
//   WebSockets on 127.0.0.1 with real Automerge documents.
// Why: the Session's guarantees (docs/spec/multiplayer.md MPLY-3..18) hold
//   only if connections, sync, presence and the Host rule work together as
//   docs/decisions/013-session-networking.md PNT-A0019-01..08 describe;
//   only real sockets show that.
// Behavior verified: a joiner gets the host's content before join returns,
//   and edits flow both ways; a third Participant joining through the
//   second ends connected to both and sees everything; an Engine mismatch
//   is refused with both versions and no entry; promotion moves the Host;
//   a Host leaving without promoting passes the role to the earliest-joined
//   remaining Participant everywhere, and its workspace is discarded; a
//   newcomer not yet connected to a peer keeps its workspace when someone
//   else leaves; a peer gone silent is dropped after the timeout, marked
//   left and its sole workspace discarded, while pings keep a quiet peer
//   present; a peer whose socket dies is dropped at once and marked left;
//   workspace joins and leaves reach the other Participant; a multi-MB
//   document joins through a slow link whose transfer outlasts the silence
//   timeout, because sync messages travel in 64 KiB pieces; unreachable and
//   malformed addresses neither fail nor stall a join, and the later joiner
//   keeps dialing until the mesh is complete; two peers that lose each other
//   but share a third stop writing `host` and clear the `left` marks they
//   set on each other; malformed frames, frames out of order and a wrong
//   protocol version are rejected.
//   Conditions are awaited by polling with a deadline, never fixed sleeps,
//   except where a test checks that nothing happens for a while.

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:painter/session/session_network.dart';
import 'package:painter/session/session_protocol.dart';

import 'session_test_support.dart';

const _ping = Duration(milliseconds: 50);
const _timeout = Duration(milliseconds: 600);

int _port(String address) => int.parse(address.split(':').last);

void main() {
  test('a multi-MB document joins through a link slower than the silence '
      'timeout', () async {
    final a = await TestParticipant.host(
      'Ann',
      pingInterval: _ping,
      peerTimeout: _timeout,
    );
    final random = Random(7);
    final payload = Uint8List.fromList(
      List.generate(4 * 1024 * 1024, (_) => random.nextInt(256)),
    );
    a.write('big', payload);
    // 4 MB at 3 MB/s takes over a second, twice the timeout.
    final proxy = await SilenceableProxy.start(
      _port(a.address),
      bytesPerSecond: 3 * 1024 * 1024,
    );
    final b = TestParticipant.joiner(
      'Bo',
      pingInterval: _ping,
      peerTimeout: _timeout,
    );
    final watch = Stopwatch()..start();
    await b.join(proxy.address);
    expect(watch.elapsed, greaterThan(_timeout));
    expect(b.content.get(['big']), payload);
    await eventually(() => b.sees(a.id) && a.sees(b.id), reason: 'presence');
    expect(a.session.participant(b.id)!.left, isFalse);
  });

  test('bad and unreachable addresses neither fail nor stall a join, and '
      'the later joiner keeps dialing until the mesh is complete', () async {
    final a = await TestParticipant.host(
      'Ann',
      pingInterval: _ping,
      peerTimeout: _timeout,
    );
    final b = TestParticipant.joiner(
      'Bo',
      pingInterval: _ping,
      peerTimeout: _timeout,
    );
    await b.join(a.address);
    final real = b.network.addresses.single;
    // 192.0.2.0/24 is reserved for documentation: dials there hang.
    b.session.setLocalAddresses([':1', '%%:1', '192.0.2.1:9']);
    await eventually(
      () => a.session.participant(b.id)?.addresses.length == 3,
      reason: 'bad addresses seen by A',
    );

    final c = TestParticipant.joiner(
      'Cy',
      pingInterval: _ping,
      peerTimeout: _timeout,
    );
    final watch = Stopwatch()..start();
    await c.join(a.address);
    expect(watch.elapsed, lessThan(_timeout * 2), reason: 'one bounded wait');
    expect(c.sees(a.id), isTrue);
    expect(c.sees(b.id), isFalse);

    // C joined after B, so C redials B until it reaches it.
    b.session.setLocalAddresses([':1', real]);
    await eventually(() => c.sees(b.id) && b.sees(c.id), reason: 'mesh');
    expect(b.session.participant(c.id)!.left, isFalse);
    expect(c.session.participant(b.id)!.left, isFalse);
  });

  test('two peers that lose each other but share a third settle on host '
      'and clear their left marks', () async {
    final a = await TestParticipant.host(
      'Ann',
      pingInterval: _ping,
      peerTimeout: _timeout,
    );
    // A's only listed address goes through the proxy, so once it is paused
    // B can never reach A again, while C reaches A directly.
    final proxy = await SilenceableProxy.start(_port(a.address));
    a.session.setLocalAddresses([proxy.address]);
    final b = TestParticipant.joiner(
      'Bo',
      pingInterval: _ping,
      peerTimeout: _timeout,
    );
    await b.join(proxy.address);
    final c = TestParticipant.joiner(
      'Cy',
      pingInterval: _ping,
      peerTimeout: _timeout,
    );
    await c.join(a.address);
    await eventually(
      () => c.sees(a.id) && c.sees(b.id) && a.sees(b.id),
      reason: 'mesh',
    );

    proxy
      ..pause()
      ..kill();
    await eventually(() => !a.sees(b.id) && !b.sees(a.id), reason: 'split');

    bool settled() => [a, b, c].every(
      (peer) =>
          peer.session.participant(a.id)?.left == false &&
          peer.session.participant(b.id)?.left == false &&
          peer.session.host == c.session.host,
    );
    await eventually(settled, reason: 'left marks cleared everywhere');
    final host = c.session.host;
    // A writer fight would change `host` within a few ping intervals.
    await Future<void>.delayed(_timeout * 2);
    expect(settled(), isTrue);
    expect(c.session.host, host);
    expect(a.hostId, a.id, reason: 'A sees only itself and C');
    expect(b.hostId, b.id, reason: 'B sees only itself and C');
    expect(c.hostId, host);
  });

  test('a joiner and the host sync content both ways', () async {
    final a = await TestParticipant.host('Ann');
    final b = TestParticipant.joiner('Bo');
    a.write('fromA', 1);

    await b.join(a.address);
    expect(b.content.get(['fromA']), 1, reason: 'first sync precedes return');
    expect(b.session.localParticipant!.joined, 1);
    expect(b.session.localParticipant!.addresses, b.network.addresses);
    expect(b.session.engine, 1);

    b.write('fromB', 2);
    a.write('later', 3);
    await eventually(
      () => a.content.get(['fromB']) == 2 && b.content.get(['later']) == 3,
      reason: 'content both ways',
    );
    await eventually(() => a.sees(b.id) && b.sees(a.id), reason: 'presence');
    expect(a.hostId, a.id);
    expect(b.hostId, a.id);
    expect(a.session.participant(b.id)!.name, 'Bo');
  });

  test(
    'a third Participant joining through the second connects to both',
    () async {
      final a = await TestParticipant.host('Ann');
      final b = TestParticipant.joiner('Bo');
      a.write('fromA', 1);
      await b.join(a.address);
      b.write('fromB', 2);

      final c = TestParticipant.joiner('Cy');
      await c.join(b.address);
      expect(
        c.sees(a.id) && c.sees(b.id),
        isTrue,
        reason: 'mesh before return',
      );
      expect(c.session.localParticipant!.joined, 2);
      await eventually(() => a.sees(c.id) && b.sees(c.id), reason: 'mesh');
      await eventually(
        () => c.content.get(['fromA']) == 1 && c.content.get(['fromB']) == 2,
        reason: 'C sees all content',
      );

      c.write('fromC', 3);
      await eventually(
        () => a.content.get(['fromC']) == 3 && b.content.get(['fromC']) == 3,
        reason: 'C reaches both',
      );
      for (final peer in [a, b, c]) {
        expect(peer.hostId, a.id);
      }
    },
  );

  test(
    'an Engine mismatch is refused with both versions and no entry',
    () async {
      final a = await TestParticipant.host('Ann', engine: 1);
      final d = TestParticipant.joiner('Dee', engine: 2);

      await expectLater(
        d.join(a.address),
        throwsA(
          isA<SessionJoinRefused>()
              .having((e) => e.reason, 'reason', RefuseReason.engine)
              .having((e) => e.localEngine, 'localEngine', 2)
              .having((e) => e.sessionEngine, 'sessionEngine', 1),
        ),
      );
      expect(d.network.isClosed, isTrue);
      expect(d.session.participants, isEmpty);
      expect(a.session.participants.map((p) => p.id), [a.id]);
      expect(a.network.presentIds, {a.id});
    },
  );

  test('promotion moves the Host', () async {
    final a = await TestParticipant.host('Ann');
    final b = TestParticipant.joiner('Bo');
    await b.join(a.address);
    await eventually(() => a.sees(b.id), reason: 'presence');

    expect(() => b.network.promote(a.id), throwsStateError);
    a.network.promote(b.id);
    await eventually(
      () => a.hostId == b.id && b.hostId == b.id,
      reason: 'B is Host everywhere',
    );
    expect(b.session.host, b.id);
    expect(() => a.network.promote(a.id), throwsStateError);
  });

  test('a Host leaving without promoting passes the role to the '
      'earliest-joined remaining Participant', () async {
    final a = await TestParticipant.host('Ann');
    final b = TestParticipant.joiner('Bo');
    await b.join(a.address);
    final c = TestParticipant.joiner('Cy');
    await c.join(a.address);
    await eventually(
      () => a.sees(c.id) && b.sees(c.id) && c.sees(b.id),
      reason: 'mesh',
    );
    final annWorkspace = a.session.localParticipant!.workspace;

    await a.network.leave();
    await eventually(
      () => b.hostId == b.id && c.hostId == b.id,
      reason: 'B is Host for B and C',
    );
    await eventually(
      () => b.session.host == b.id && c.session.host == b.id,
      reason: 'B wrote host',
    );
    expect(b.sees(a.id) || c.sees(a.id), isFalse);
    expect(b.session.participant(a.id)!.left, isTrue);
    await eventually(
      () =>
          !b.session.hasWorkspace(annWorkspace) &&
          !c.session.hasWorkspace(annWorkspace),
      reason: "A's workspace discarded",
    );
    expect(b.sees(c.id) && c.sees(b.id), isTrue);

    // A keeps its documents, usable alone (MPLY-16).
    a.write('afterLeaving', 1);
    expect(a.content.get(['afterLeaving']), 1);
    expect(a.session.hasWorkspace(annWorkspace), isTrue);
  });

  test('a newcomer not yet connected to a peer keeps its workspace when '
      'someone else leaves', () async {
    final a = await TestParticipant.host('Ann');
    final b = TestParticipant.joiner('Bo');
    await b.join(a.address);
    // Nobody can reach B, so C's mesh connection to B fails and B and C
    // know each other only through A.
    b.session.setLocalAddresses(['127.0.0.1:1']);
    await eventually(
      () => a.session.participant(b.id)?.addresses.join() == '127.0.0.1:1',
      reason: 'unreachable address seen by A',
    );
    final c = TestParticipant.joiner('Cy');
    await c.join(a.address);
    final annWorkspace = a.session.localParticipant!.workspace;
    final cyWorkspace = c.session.localParticipant!.workspace;
    await eventually(
      () => b.session.participant(c.id) != null,
      reason: "C's entry relayed to B",
    );
    expect(b.sees(c.id) || c.sees(b.id), isFalse);

    await a.network.leave();
    await eventually(
      () => !b.session.hasWorkspace(annWorkspace),
      reason: 'B discarded after A left',
    );
    expect(b.session.hasWorkspace(cyWorkspace), isTrue);
    expect(b.session.participant(c.id)!.left, isFalse);
    expect(c.session.hasWorkspace(cyWorkspace), isTrue);
  });

  test('a peer gone silent is dropped after the timeout and the Host '
      'recomputed', () async {
    final a = await TestParticipant.host(
      'Ann',
      pingInterval: _ping,
      peerTimeout: _timeout,
    );
    final proxy = await SilenceableProxy.start(_port(a.address));
    final b = TestParticipant.joiner(
      'Bo',
      pingInterval: _ping,
      peerTimeout: _timeout,
    );
    await b.join(proxy.address);
    await eventually(() => a.sees(b.id) && b.sees(a.id), reason: 'presence');

    // Pings alone keep the connection present past the timeout.
    await Future<void>.delayed(_timeout * 2);
    expect(a.sees(b.id) && b.sees(a.id), isTrue);

    a.network.promote(b.id);
    await eventually(() => a.hostId == b.id, reason: 'promotion');

    proxy.pause();
    await eventually(
      () => !a.sees(b.id) && !b.sees(a.id),
      reason: 'both drop the other',
    );
    expect(a.hostId, a.id);
    expect(b.hostId, b.id);
    await eventually(() => a.session.host == a.id, reason: 'A wrote host');

    // Each marks the other left and discards its sole workspace.
    final annWorkspace = a.session.localParticipant!.workspace;
    final boWorkspace = b.session.localParticipant!.workspace;
    await eventually(
      () =>
          a.session.participant(b.id)!.left &&
          !a.session.hasWorkspace(boWorkspace) &&
          b.session.participant(a.id)!.left &&
          !b.session.hasWorkspace(annWorkspace),
      reason: 'marked left and discarded',
    );
    expect(a.session.hasWorkspace(annWorkspace), isTrue);
    expect(a.session.localParticipant!.left, isFalse);
  });

  test('a peer whose socket dies without bye is dropped at once and marked '
      'left', () async {
    final a = await TestParticipant.host('Ann');
    final proxy = await SilenceableProxy.start(_port(a.address));
    final b = TestParticipant.joiner('Bo');
    await b.join(proxy.address);
    await eventually(() => a.sees(b.id) && b.sees(a.id), reason: 'presence');
    final boWorkspace = b.session.localParticipant!.workspace;

    proxy.kill();
    // Well inside the 10 s silence timeout.
    await eventually(
      () => !a.sees(b.id) && !b.sees(a.id),
      reason: 'both drop the other',
      timeout: const Duration(seconds: 3),
    );
    expect(a.hostId, a.id);
    await eventually(() => b.session.host == b.id, reason: 'B wrote host');
    await eventually(
      () =>
          a.session.participant(b.id)!.left &&
          !a.session.hasWorkspace(boWorkspace),
      reason: 'B marked left and its workspace discarded',
    );
  });

  test('workspace joins and leaves reach the other Participant', () async {
    final a = await TestParticipant.host('Ann');
    final b = TestParticipant.joiner('Bo');
    await b.join(a.address);
    await eventually(() => a.sees(b.id), reason: 'presence');
    final annWorkspace = a.session.localParticipant!.workspace;
    final boWorkspace = b.session.localParticipant!.workspace;

    b.session.joinWorkspace(a.id);
    await eventually(
      () =>
          a.session.participant(b.id)?.workspace == annWorkspace &&
          a.session.participant(b.id)?.previousWorkspace == boWorkspace,
      reason: 'join seen by A',
    );
    expect(a.session.hasWorkspace(boWorkspace), isTrue, reason: 'previous');

    b.session.leaveJoinedWorkspace();
    expect(b.session.localParticipant!.workspace, boWorkspace);
    await eventually(
      () =>
          a.session.participant(b.id)?.workspace == boWorkspace &&
          a.session.participant(b.id)?.previousWorkspace == null,
      reason: 'leave seen by A',
    );
    expect(
      a.session.workspaceIds,
      unorderedEquals([annWorkspace, boWorkspace]),
    );
  });

  test('malformed frames, frames out of order and another protocol are '
      'rejected', () async {
    final a = await TestParticipant.host('Ann');
    final url = 'ws://${a.address}';

    Future<List<Object?>> exchange(List<Object> sent) async {
      final socket = await WebSocket.connect(url);
      sent.forEach(socket.add);
      return socket.toList().timeout(const Duration(seconds: 5));
    }

    // Each of these is closed without an answer.
    for (final frames in <List<Object>>[
      [
        Uint8List.fromList([0x7f]),
      ],
      ['text frame'],
      [
        SyncFrame(SyncDocument.content, Uint8List.fromList([1])).encode(),
      ],
      [const WelcomeFrame(participant: 'zz:1', name: 'Z').encode()],
    ]) {
      expect(await exchange(frames), isEmpty);
    }

    final answer = await exchange([
      const HelloFrame(
        protocol: 2,
        engine: 1,
        participant: 'zz:1',
        name: 'Z',
        addresses: [],
      ).encode(),
    ]);
    final refuse = SessionFrame.decode(
      Uint8List.fromList(answer.single! as List<int>),
    ) as RefuseFrame;
    expect(refuse.reason, RefuseReason.protocol);
    expect(refuse.engine, 1);

    expect(a.session.participants.map((p) => p.id), [a.id]);
    expect(a.network.presentIds, {a.id});
    expect(a.network.isActive, isTrue);
  });
}
