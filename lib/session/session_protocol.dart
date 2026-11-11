// What: The frames Participants exchange over a Session connection
//   (SessionFrame and its subtypes HelloFrame, WelcomeFrame, RefuseFrame,
//   SyncFrame, SyncPartFrame, PingFrame, ByeFrame), their binary encoding
//   and decoding, splitting a sync message into frames (syncFrames) and
//   joining them again (SyncReassembler), and the protocol constants.
// Why: docs/decisions/013-session-networking.md fixes the wire format
//   (PNT-A0019-02, PNT-A0019-03). Keeping it apart from the connection logic
//   lets the format be tested without sockets. See the Session overview in
//   session_network.dart.
// Coupled to: session_network.dart (sends and dispatches these frames).

import 'dart:convert';
import 'dart:typed_data';

/// The protocol version a hello carries; peers with another are refused
/// (PNT-A0019-03).
const int sessionProtocolVersion = 1;

/// The TCP port a Participant listens on unless it is taken (PNT-A0019-01).
const int defaultSessionPort = 47800;

/// The values of [RefuseFrame.reason].
abstract final class RefuseReason {
  /// The hello's `protocol` differs from [sessionProtocolVersion].
  static const String protocol = 'protocol';

  /// The hello's `engine` differs from the accepting peer's (MPLY-8).
  static const String engine = 'engine';
}

/// The most bytes of a sync message one [SyncFrame] or [SyncPartFrame]
/// carries (PNT-A0019-02): small enough that a large message never keeps a
/// peer from hearing anything for long (MPLY-17).
const int syncPieceLimit = 64 * 1024;

/// Which document a [SyncFrame] belongs to; [index] is its byte on the wire
/// (PNT-A0019-02).
enum SyncDocument {
  /// The content document (strokes).
  content,

  /// The session document (docs/decisions/009-shared-workspaces.md).
  session,
}

/// One binary WebSocket message: its first byte is its type (PNT-A0019-02).
sealed class SessionFrame {
  const SessionFrame();

  static const int _hello = 0x01;
  static const int _welcome = 0x02;
  static const int _refuse = 0x03;
  static const int _sync = 0x10;
  static const int _syncPart = 0x11;
  static const int _ping = 0x20;
  static const int _bye = 0x30;

  /// The bytes of this frame.
  Uint8List encode();

  /// Reads one frame. Throws [FormatException] when [bytes] are not a frame:
  /// empty, of an unknown type, JSON that is invalid or lacks a field of the
  /// right type, a sync or sync part frame naming no known document or
  /// carrying no bytes or more than [syncPieceLimit], or a ping or bye with
  /// a payload. JSON keys this version does not know are ignored.
  static SessionFrame decode(Uint8List bytes) {
    if (bytes.isEmpty) throw const FormatException('Empty frame.');
    switch (bytes[0]) {
      case _hello:
        final json = _json(bytes);
        return HelloFrame(
          protocol: _field<int>(json, 'protocol'),
          engine: _field<int>(json, 'engine'),
          participant: _field<String>(json, 'participant'),
          name: _field<String>(json, 'name'),
          addresses: _stringList(json, 'addresses'),
        );
      case _welcome:
        final json = _json(bytes);
        return WelcomeFrame(
          participant: _field<String>(json, 'participant'),
          name: _field<String>(json, 'name'),
        );
      case _refuse:
        final json = _json(bytes);
        return RefuseFrame(
          reason: _field<String>(json, 'reason'),
          engine: _field<int>(json, 'engine'),
        );
      case _sync || _syncPart:
        if (bytes.length < 3) {
          throw const FormatException('Sync frame without a message.');
        }
        if (bytes.length - 2 > syncPieceLimit) {
          throw const FormatException('Sync frame over the size limit.');
        }
        final document = bytes[1];
        if (document >= SyncDocument.values.length) {
          throw FormatException('Unknown sync document $document.');
        }
        final piece = Uint8List.sublistView(bytes, 2);
        return bytes[0] == _sync
            ? SyncFrame(SyncDocument.values[document], piece)
            : SyncPartFrame(SyncDocument.values[document], piece);
      case _ping:
        _expectBare(bytes, 'Ping');
        return const PingFrame();
      case _bye:
        _expectBare(bytes, 'Bye');
        return const ByeFrame();
      default:
        throw FormatException('Unknown frame type ${bytes[0]}.');
    }
  }

  /// [type] followed by [json] as UTF-8.
  static Uint8List _encodeJson(int type, Map<String, Object?> json) {
    final body = utf8.encode(jsonEncode(json));
    return Uint8List(body.length + 1)
      ..[0] = type
      ..setRange(1, body.length + 1, body);
  }

  /// The JSON object after the type byte. utf8.decode and jsonDecode throw
  /// [FormatException] themselves on malformed input.
  static Map<String, Object?> _json(Uint8List bytes) {
    final value = jsonDecode(utf8.decode(Uint8List.sublistView(bytes, 1)));
    if (value is! Map<String, Object?>) {
      throw const FormatException('Frame JSON is not an object.');
    }
    return value;
  }

  static T _field<T>(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! T) throw FormatException('Frame field "$key" is invalid.');
    return value;
  }

  static List<String> _stringList(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! List<Object?> || value.any((item) => item is! String)) {
      throw FormatException('Frame field "$key" is invalid.');
    }
    return List.unmodifiable(value.cast<String>());
  }

  static void _expectBare(Uint8List bytes, String type) {
    if (bytes.length != 1) throw FormatException('$type frame has a payload.');
  }
}

/// Sent first by the connecting peer (PNT-A0019-03).
final class HelloFrame extends SessionFrame {
  const HelloFrame({
    required this.protocol,
    required this.engine,
    required this.participant,
    required this.name,
    required this.addresses,
  });

  final int protocol;

  /// The sender's Engine version (MPLY-8).
  final int engine;

  /// The sender's participant id.
  final String participant;

  final String name;

  /// The sender's Session addresses, each `host:port`.
  final List<String> addresses;

  @override
  Uint8List encode() => SessionFrame._encodeJson(SessionFrame._hello, {
    'protocol': protocol,
    'engine': engine,
    'participant': participant,
    'name': name,
    'addresses': addresses,
  });
}

/// The accepting peer's answer to an acceptable hello (PNT-A0019-03).
final class WelcomeFrame extends SessionFrame {
  const WelcomeFrame({required this.participant, required this.name});

  /// The accepting peer's participant id.
  final String participant;

  final String name;

  @override
  Uint8List encode() => SessionFrame._encodeJson(SessionFrame._welcome, {
    'participant': participant,
    'name': name,
  });
}

/// The accepting peer's answer to a hello whose protocol or engine differs
/// (PNT-A0019-03); the connection closes after it.
final class RefuseFrame extends SessionFrame {
  const RefuseFrame({required this.reason, required this.engine});

  /// A [RefuseReason] value.
  final String reason;

  /// The accepting peer's Engine version, shown to the refused user (MPLY-8).
  final int engine;

  @override
  Uint8List encode() => SessionFrame._encodeJson(SessionFrame._refuse, {
    'reason': reason,
    'engine': engine,
  });
}

/// The last piece of an Automerge sync message for [document], the whole
/// message when it fits in [syncPieceLimit] (PNT-A0019-02, PNT-A0019-04).
final class SyncFrame extends SessionFrame {
  const SyncFrame(this.document, this.piece);

  final SyncDocument document;

  /// Bytes of a message CrdtDocument.generateSyncMessage produced, after
  /// those of the [SyncPartFrame]s before it.
  final Uint8List piece;

  @override
  Uint8List encode() => _encodePiece(SessionFrame._sync, document, piece);
}

/// A piece of an Automerge sync message for [document] that more pieces
/// follow, ending with a [SyncFrame] (PNT-A0019-02).
final class SyncPartFrame extends SessionFrame {
  const SyncPartFrame(this.document, this.piece);

  final SyncDocument document;

  final Uint8List piece;

  @override
  Uint8List encode() => _encodePiece(SessionFrame._syncPart, document, piece);
}

Uint8List _encodePiece(int type, SyncDocument document, Uint8List piece) =>
    Uint8List(piece.length + 2)
      ..[0] = type
      ..[1] = document.index
      ..setRange(2, piece.length + 2, piece);

/// The frames that carry [message] for [document]: [SyncPartFrame]s of
/// [pieceLimit] bytes, then a [SyncFrame] with the non-empty rest
/// (PNT-A0019-02). The pieces are views of [message], not copies. Throws
/// [ArgumentError] for an empty message, which no frame can carry.
List<SessionFrame> syncFrames(
  SyncDocument document,
  Uint8List message, {
  int pieceLimit = syncPieceLimit,
}) {
  if (message.isEmpty) {
    throw ArgumentError.value(message, 'message', 'is empty');
  }
  final frames = <SessionFrame>[];
  var start = 0;
  while (message.length - start > pieceLimit) {
    frames.add(
      SyncPartFrame(
        document,
        Uint8List.sublistView(message, start, start + pieceLimit),
      ),
    );
    start += pieceLimit;
  }
  frames.add(SyncFrame(document, Uint8List.sublistView(message, start)));
  return frames;
}

/// Joins the pieces of sync messages arriving on one connection (one per
/// connection), keeping each document's pieces apart so the receiver
/// assumes nothing about how the sender orders two documents' frames.
final class SyncReassembler {
  final Map<SyncDocument, BytesBuilder> _pending = {};

  /// Records a [SyncPartFrame]'s piece.
  void addPart(SyncPartFrame frame) => _pending
      .putIfAbsent(frame.document, () => BytesBuilder(copy: true))
      .add(frame.piece);

  /// The whole message [frame] ends: its piece after every part recorded
  /// for its document since the last message.
  Uint8List finish(SyncFrame frame) {
    final parts = _pending.remove(frame.document);
    if (parts == null) return frame.piece;
    return (parts..add(frame.piece)).takeBytes();
  }
}

/// Keeps a connection known to be alive (PNT-A0019-06).
final class PingFrame extends SessionFrame {
  const PingFrame();

  @override
  Uint8List encode() => Uint8List(1)..[0] = SessionFrame._ping;
}

/// Says the sender is leaving the Session (PNT-A0019-06).
final class ByeFrame extends SessionFrame {
  const ByeFrame();

  @override
  Uint8List encode() => Uint8List(1)..[0] = SessionFrame._bye;
}
