// What: Tests of the Session wire format (lib/session/session_protocol.dart).
// Why: every Participant must read every other's frames exactly as
//   docs/decisions/013-session-networking.md PNT-A0019-02/03 define them,
//   and a malformed frame must be rejected rather than half-read.
// Behavior verified: each frame type encodes to its type byte and payload
//   and decodes back to the same fields; unknown JSON keys are ignored; a
//   message over 64 KiB splits into sync parts and a final sync frame that
//   reassemble per document even when interleaved; empty frames, unknown
//   types, invalid UTF-8 or JSON, missing or mistyped fields, unknown sync
//   documents, sync frames without bytes or over the limit, and ping or bye
//   frames with a payload throw FormatException.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:painter/session/session_protocol.dart';

Uint8List _bytes(List<int> values) => Uint8List.fromList(values);

Uint8List _json(int type, Object? json) =>
    _bytes([type, ...utf8.encode(jsonEncode(json))]);

void main() {
  test('hello, welcome and refuse carry their fields as JSON', () {
    const hello = HelloFrame(
      protocol: 1,
      engine: 3,
      participant: 'aa:1',
      name: 'Ann',
      addresses: ['10.0.0.2:47800', '10.0.0.3:47800'],
    );
    final helloBytes = hello.encode();
    expect(helloBytes[0], 0x01);
    final decodedHello = SessionFrame.decode(helloBytes) as HelloFrame;
    expect(decodedHello.protocol, 1);
    expect(decodedHello.engine, 3);
    expect(decodedHello.participant, 'aa:1');
    expect(decodedHello.name, 'Ann');
    expect(decodedHello.addresses, hello.addresses);

    final welcome = SessionFrame.decode(
      const WelcomeFrame(participant: 'bb', name: 'Bo').encode(),
    ) as WelcomeFrame;
    expect(const WelcomeFrame(participant: 'bb', name: 'Bo').encode()[0], 2);
    expect((welcome.participant, welcome.name), ('bb', 'Bo'));

    const refuse = RefuseFrame(reason: RefuseReason.engine, engine: 7);
    expect(refuse.encode()[0], 0x03);
    final decodedRefuse = SessionFrame.decode(refuse.encode()) as RefuseFrame;
    expect((decodedRefuse.reason, decodedRefuse.engine), ('engine', 7));
  });

  test('unknown JSON keys are ignored', () {
    final frame = SessionFrame.decode(
      _json(0x02, {'participant': 'p', 'name': 'n', 'future': true}),
    );
    expect(frame, isA<WelcomeFrame>());
  });

  test('sync and sync part frames carry the document byte and a piece', () {
    final frame = SyncFrame(SyncDocument.session, _bytes([9, 8, 7]));
    expect(frame.encode(), [0x10, 1, 9, 8, 7]);
    final decoded = SessionFrame.decode(_bytes([0x10, 0, 5])) as SyncFrame;
    expect(decoded.document, SyncDocument.content);
    expect(decoded.piece, [5]);

    final part = SyncPartFrame(SyncDocument.content, _bytes([4, 2]));
    expect(part.encode(), [0x11, 0, 4, 2]);
    final decodedPart =
        SessionFrame.decode(_bytes([0x11, 1, 6])) as SyncPartFrame;
    expect(decodedPart.document, SyncDocument.session);
    expect(decodedPart.piece, [6]);
  });

  test('a message fitting one piece is one sync frame', () {
    final message = Uint8List(syncPieceLimit)..fillRange(0, 10, 7);
    final frames = syncFrames(SyncDocument.content, message);
    expect(frames.single, isA<SyncFrame>());
    expect(frames.single.encode(), hasLength(syncPieceLimit + 2));
    expect(
      () => syncFrames(SyncDocument.content, Uint8List(0)),
      throwsArgumentError,
    );
  });

  test('large messages split into parts of at most 64 KiB and reassemble '
      'per document', () {
    final big = Uint8List.fromList(
      List.generate(3 * syncPieceLimit + 5, (i) => i * 31 % 251),
    );
    final exact = Uint8List.fromList(
      List.generate(2 * syncPieceLimit, (i) => i % 13),
    );
    final bigFrames = syncFrames(SyncDocument.content, big);
    final exactFrames = syncFrames(SyncDocument.session, exact);
    expect(bigFrames.map((f) => f.runtimeType), [
      SyncPartFrame,
      SyncPartFrame,
      SyncPartFrame,
      SyncFrame,
    ]);
    expect(exactFrames.map((f) => f.runtimeType), [SyncPartFrame, SyncFrame]);

    // Through the wire format, with the two documents' frames interleaved.
    final wire = [
      for (var i = 0; i < 4; i++) ...[
        bigFrames[i].encode(),
        if (i < exactFrames.length) exactFrames[i].encode(),
      ],
    ];
    for (final bytes in wire) {
      expect(bytes.length, lessThanOrEqualTo(syncPieceLimit + 2));
    }
    final reassembler = SyncReassembler();
    final messages = <SyncDocument, Uint8List>{};
    for (final bytes in wire) {
      switch (SessionFrame.decode(bytes)) {
        case final SyncPartFrame part:
          reassembler.addPart(part);
        case final SyncFrame last:
          messages[last.document] = reassembler.finish(last);
        default:
          fail('not a sync frame');
      }
    }
    expect(messages[SyncDocument.content], big);
    expect(messages[SyncDocument.session], exact);

    // The next message starts afresh.
    expect(reassembler.finish(SyncFrame(SyncDocument.content, _bytes([1]))), [
      1,
    ]);
  });

  test('ping and bye are a single type byte', () {
    expect(const PingFrame().encode(), [0x20]);
    expect(const ByeFrame().encode(), [0x30]);
    expect(SessionFrame.decode(_bytes([0x20])), isA<PingFrame>());
    expect(SessionFrame.decode(_bytes([0x30])), isA<ByeFrame>());
  });

  final malformed = <String, Uint8List>{
    'empty': _bytes([]),
    'unknown type': _bytes([0x7f]),
    'invalid UTF-8': _bytes([0x02, 0xff, 0xfe]),
    'invalid JSON': _bytes([0x02, ...utf8.encode('{"participant":')]),
    'JSON not an object': _json(0x02, ['participant']),
    'missing field': _json(0x02, {'participant': 'p'}),
    'mistyped field': _json(0x03, {'reason': 'engine', 'engine': '2'}),
    'mistyped address': _json(0x01, {
      'protocol': 1,
      'engine': 1,
      'participant': 'p',
      'name': 'n',
      'addresses': [1],
    }),
    'unknown sync document': _bytes([0x10, 2, 1]),
    'sync without message': _bytes([0x10, 0]),
    'sync part without bytes': _bytes([0x11, 1]),
    'sync part over the limit': Uint8List(syncPieceLimit + 3)
      ..[0] = 0x11
      ..[1] = 0,
    'sync over the limit': Uint8List(syncPieceLimit + 3)..[0] = 0x10,
    'ping with payload': _bytes([0x20, 0]),
    'bye with payload': _bytes([0x30, 1]),
  };
  for (final MapEntry(key: label, value: bytes) in malformed.entries) {
    test('rejects a malformed frame: $label', () {
      expect(() => SessionFrame.decode(bytes), throwsFormatException);
    });
  }
}
