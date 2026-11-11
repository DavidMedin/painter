// What: AutomergeBackend and AutomergeCrdtDocument, the implementation of the
//   CRDT port (crdt_document.dart) on the automerge_dart binding.
// Why: docs/decisions/007-crdt-automerge.md chose Automerge and confines the
//   binding to lib/crdt/ (PNT-A0013-03). See the port overview in
//   crdt_document.dart.
// Coupled to: crdt_document.dart (the interface implemented here) and
//   packages/automerge_dart (AutomergeDoc, ObjId, SyncState).

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:automerge_dart/automerge_dart.dart';

import 'crdt_document.dart';

/// Creates [AutomergeCrdtDocument]s.
final class AutomergeBackend implements CrdtBackend {
  const AutomergeBackend();

  @override
  CrdtDocument create() =>
      AutomergeCrdtDocument._(AutomergeDoc.create(actorId: _randomActor()));

  @override
  CrdtDocument load(Uint8List bytes) {
    // Automerge loads empty input as a new empty document; the port promises
    // a FormatException for anything that is not a saved document.
    if (bytes.isEmpty) throw const FormatException('Empty document bytes.');
    final AutomergeDoc doc;
    try {
      doc = AutomergeDoc.load(bytes);
    } on AutomergeException catch (error) {
      throw FormatException('Not an Automerge document: ${error.message}');
    }
    // A new actor per open (docs/decisions/008-document-file-format.md
    // PNT-A0014-09), so two processes never write as one actor.
    doc.actorId = _randomActor();
    return AutomergeCrdtDocument._(doc);
  }

  static final math.Random _random = math.Random.secure();

  static String _randomActor() {
    final buffer = StringBuffer();
    for (var i = 0; i < 16; i++) {
      buffer.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}

/// A [CrdtDocument] backed by one [AutomergeDoc].
///
/// Paths are resolved from the root on every call: map ids can change when a
/// peer replaces a map, so none are cached. Intermediate [ObjId]s are
/// disposed as soon as the call returns.
final class AutomergeCrdtDocument implements CrdtDocument {
  AutomergeCrdtDocument._(this._doc) : actorId = _doc.actorId;

  final AutomergeDoc _doc;
  final List<CrdtListener> _listeners = [];
  int _counter = 0;

  /// Whether put, putMap or delete ran since the last [commit]. Reading
  /// heads, saving and syncing close Automerge's open transaction without
  /// telling us, after which `AutomergeDoc.commit` reports nothing; this flag
  /// keeps [commit] notifying listeners for those edits anyway.
  bool _dirty = false;

  @override
  final String actorId;

  @override
  Object? get(List<String> path) {
    if (path.isEmpty) return const CrdtMap();
    return _withMap(path.sublist(0, path.length - 1), (map) {
      if (map == null) return null;
      return _read(map, path.last);
    });
  }

  @override
  Map<String, Object?> entries(List<String> path) => _withMap(path, (map) {
    if (map == null) return const <String, Object?>{};
    return {for (final key in _doc.keys(map)) key: _read(map, key)};
  });

  @override
  List<String> keys(List<String> path) =>
      _withMap(path, (map) => map == null ? const <String>[] : _doc.keys(map));

  @override
  void put(List<String> path, Object? value) {
    _withParent(path, (map) => _doc.put(map, path.last, value));
    _dirty = true;
  }

  @override
  void putMap(List<String> path) {
    _withParent(path, (map) => _doc.putMap(map, path.last).dispose());
    _dirty = true;
  }

  @override
  void delete(List<String> path) {
    if (path.isEmpty) return;
    _withMap(path.sublist(0, path.length - 1), (map) {
      if (map != null) _doc.delete(map, path.last);
      _dirty = map != null || _dirty;
    });
  }

  @override
  void commit({String? message}) {
    final recorded = _doc.commit(message: message) != null;
    if (!recorded && !_dirty) return;
    _dirty = false;
    _notify(CrdtChangeOrigin.local);
  }

  @override
  Uint8List save() => _doc.save();

  @override
  String newId() => '$actorId:${++_counter}';

  @override
  CrdtSyncPeer createSyncPeer() => _AutomergeSyncPeer(SyncState());

  @override
  Uint8List? generateSyncMessage(CrdtSyncPeer peer) =>
      _doc.generateSyncMessage((peer as _AutomergeSyncPeer).state);

  @override
  void receiveSyncMessage(CrdtSyncPeer peer, Uint8List message) {
    final before = _doc.heads;
    try {
      _doc.receiveSyncMessage((peer as _AutomergeSyncPeer).state, message);
    } on AutomergeException catch (error) {
      throw FormatException('Bad sync message: ${error.message}');
    }
    if (!_sameHeads(before, _doc.heads)) _notify(CrdtChangeOrigin.remote);
  }

  @override
  void addListener(CrdtListener listener) => _listeners.add(listener);

  @override
  void removeListener(CrdtListener listener) => _listeners.remove(listener);

  @override
  void dispose() {
    _listeners.clear();
    _doc.dispose();
  }

  void _notify(CrdtChangeOrigin origin) {
    for (final listener in List.of(_listeners)) {
      listener(origin);
    }
  }

  /// Runs [body] with the map at [path], or null when [path] is not a map,
  /// disposing every id resolved on the way.
  T _withMap<T>(List<String> path, T Function(ObjId? map) body) {
    final owned = <ObjId>[];
    try {
      var current = _doc.root;
      for (final key in path) {
        final value = _getOrNull(current, key);
        if (value is! AutomergeMap) {
          if (value is AutomergeList) value.id.dispose();
          return body(null);
        }
        owned.add(value.id);
        current = value.id;
      }
      return body(current);
    } finally {
      for (final id in owned) {
        id.dispose();
      }
    }
  }

  /// Runs [body] with the map holding the last key of [path]; throws
  /// [StateError] when that map is missing, a caller bug.
  void _withParent(List<String> path, void Function(ObjId map) body) {
    if (path.isEmpty) throw ArgumentError.value(path, 'path', 'is empty');
    _withMap(path.sublist(0, path.length - 1), (map) {
      if (map == null) throw StateError('No map at ${path.join('/')}.');
      body(map);
    });
  }

  /// The value at [key] of [map], or null when it is of a kind the binding
  /// does not model (counter, timestamp, unsigned int, text). Such values
  /// can arrive from a peer or a foreign file; the port only knows its own
  /// value set, and AutomergeException must not escape lib/crdt/.
  AutomergeValue? _getOrNull(ObjId map, String key) {
    try {
      return _doc.get(map, key);
    } on AutomergeException {
      // Normal flow (docs/decisions/014-logging.md PNT-A0020-05): a kind
      // the port does not model reads as absent, as documented above.
      return null;
    }
  }

  /// Reads [key] of [map] as a port value.
  Object? _read(ObjId map, String key) => _convert(_getOrNull(map, key));

  /// Converts a binding value to the port's value set, disposing object ids.
  /// Lists are outside the port and read as null.
  Object? _convert(AutomergeValue? value) {
    switch (value) {
      case null || AutomergeNull():
        return null;
      case AutomergeBool(:final value):
        return value;
      case AutomergeInt(:final value):
        return value;
      case AutomergeDouble(:final value):
        return value;
      case AutomergeString(:final value):
        return value;
      case AutomergeBytes(:final value):
        return value;
      case AutomergeMap(:final id):
        id.dispose();
        return const CrdtMap();
      case AutomergeList(:final id):
        id.dispose();
        return null;
    }
  }

  static bool _sameHeads(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

final class _AutomergeSyncPeer implements CrdtSyncPeer {
  _AutomergeSyncPeer(this.state);

  final SyncState state;

  @override
  void dispose() => state.dispose();
}
