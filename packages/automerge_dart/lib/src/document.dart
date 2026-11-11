// What: AutomergeDoc (an Automerge document), ObjId (a handle to an object
//   in it) and SyncState (per-peer sync bookkeeping), over automerge-c.
// Why: these three share native pointers (an AMdoc, AMobjId or AMsyncState
//   lives inside the AMresult its owner holds), so they live in one library
//   and reach each other's pointers through library-private members.
// Coupled to: lib/src/native.dart (NativeResult, result checks, spans),
//   lib/src/value.dart (values returned by AutomergeDoc.get),
//   lib/src/third_party/automerge.g.dart (bindings; add any newly called
//   function to tool/ffigen.dart).
//   See lib/automerge_dart.dart for the system overview.

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'exception.dart';
import 'native.dart';
import 'third_party/automerge.g.dart';
import 'value.dart';

/// An Automerge document: a CRDT whose root is a string-keyed map.
///
/// Edits made through [put], [putMap] and [delete] are pending until
/// [commit]; [save], [merge], [fork] and the sync methods commit pending
/// edits first (automerge-c wraps an auto-committing document).
///
/// Holds native memory: call [dispose] when done. A [NativeFinalizer] frees
/// it if the document is garbage collected first.
///
/// Not thread-safe: use one document from one isolate only (the UI isolate
/// in Painter, docs/decisions/007-crdt-automerge.md PNT-A0013-06).
final class AutomergeDoc implements Finalizable {
  AutomergeDoc._(this._result) : _doc = _docOf(_result);

  /// Creates an empty document.
  ///
  /// [actorId] is the hexadecimal actor id its changes are attributed to;
  /// when omitted Automerge picks a random one. Throws
  /// [AutomergeException] if [actorId] is not valid hexadecimal.
  factory AutomergeDoc.create({String? actorId}) {
    if (actorId == null) {
      return AutomergeDoc._(NativeResult(checkResult(AMcreate(nullptr))));
    }
    return _withActorId(
      actorId,
      (actor) => AutomergeDoc._(NativeResult(checkResult(AMcreate(actor)))),
    );
  }

  /// Loads a document from bytes produced by [save].
  ///
  /// Throws [AutomergeException] if [bytes] are not an Automerge document.
  /// The loaded document gets a new random actor id.
  factory AutomergeDoc.load(Uint8List bytes) => using((arena) {
    final span = bytesToSpan(bytes, arena);
    return AutomergeDoc._(
      NativeResult(checkResult(AMload(span.src, span.count))),
    );
  });

  final NativeResult _result;
  final Pointer<AMdoc> _doc;

  static Pointer<AMdoc> _docOf(NativeResult result) => using((arena) {
    final out = arena<Pointer<AMdoc>>();
    AMitemToDoc(AMresultItem(result.pointer('AutomergeDoc')), out);
    return out.value;
  });

  /// The document pointer; throws [StateError] after [dispose].
  Pointer<AMdoc> get _ptr {
    _result.pointer('AutomergeDoc');
    return _doc;
  }

  /// Whether [dispose] has run.
  bool get isDisposed => _result.isDisposed;

  /// Frees the document's native memory. Any later call on this document
  /// throws [StateError]. [ObjId]s taken from it stay valid.
  void dispose() => _result.dispose();

  /// The root map of every document.
  ObjId get root => ObjId.root;

  /// The full document, including its change history, as bytes for [load].
  Uint8List save() =>
      useResult(AMsave(_ptr), (r) => _itemBytes(AMresultItem(r)));

  /// This document's actor id, in lowercase hexadecimal.
  String get actorId => useResult(AMgetActorId(_ptr), (r) {
    return using((arena) {
      final out = arena<Pointer<AMactorId>>();
      AMitemToActorId(AMresultItem(r), out);
      return spanToString(AMactorIdStr(out.value));
    });
  });

  /// Attributes this document's later changes to the actor [hex].
  ///
  /// Throws [AutomergeException] if [hex] is not valid hexadecimal.
  set actorId(String hex) {
    final doc = _ptr;
    _withActorId(hex, (actor) => useResult(AMsetActorId(doc, actor), _noop));
  }

  /// Commits pending edits as one change, with an optional [message].
  ///
  /// Returns the new change's hash in hexadecimal, or null if nothing was
  /// pending.
  String? commit({String? message}) => using((arena) {
    final span = message == null
        ? nullSpan(arena)
        : stringToSpan(message, arena);
    return useResult(AMcommit(_ptr, span, nullptr), (r) {
      final item = AMresultItem(r);
      if (AMitemValType(item) != AMvalType.AM_VAL_TYPE_CHANGE_HASH) {
        return null;
      }
      return toHex(_changeHash(item, arena));
    });
  });

  /// Hashes of the changes no other change depends on, in hexadecimal and
  /// in Automerge's order. Two documents holding the same changes have
  /// equal heads.
  List<String> get heads => useResult(AMgetHeads(_ptr), (r) {
    final hashes = <String>[];
    using((arena) {
      forEachItem(r, (item) => hashes.add(toHex(_changeHash(item, arena))));
    });
    return hashes;
  });

  /// Sets [key] of the map [obj] to [value], which must be null, a [bool],
  /// [int], [double], [String] or [Uint8List].
  ///
  /// Throws [ArgumentError] for any other type and [AutomergeException] if
  /// [obj] is not a map of this document.
  void put(ObjId obj, String key, Object? value) {
    final doc = _ptr;
    final target = obj._ptr;
    using((arena) {
      final k = stringToSpan(key, arena);
      final result = switch (value) {
        null => AMmapPutNull(doc, target, k),
        bool() => AMmapPutBool(doc, target, k, value),
        int() => AMmapPutInt(doc, target, k, value),
        double() => AMmapPutF64(doc, target, k, value),
        String() => AMmapPutStr(doc, target, k, stringToSpan(value, arena)),
        Uint8List() => AMmapPutBytes(doc, target, k, bytesToSpan(value, arena)),
        _ => throw ArgumentError.value(
          value,
          'value',
          'must be null, bool, int, double, String or Uint8List',
        ),
      };
      useResult(result, _noop);
    });
  }

  /// Sets [key] of the map [obj] to a new empty map and returns its id.
  ///
  /// Two peers that create a map at the same key concurrently create two
  /// maps; after merging only one survives (see
  /// docs/decisions/007-crdt-automerge.md PNT-A0013-04).
  ObjId putMap(ObjId obj, String key) {
    final doc = _ptr;
    final target = obj._ptr;
    final result = using(
      (arena) => checkResult(
        AMmapPutObject(
          doc,
          target,
          stringToSpan(key, arena),
          AMobjType.AM_OBJ_TYPE_MAP,
        ),
      ),
    );
    return ObjId._fromItem(NativeResult(result));
  }

  /// The value at [key] of the map [obj], or null if [key] is absent.
  ///
  /// Throws [AutomergeException] if [obj] is not a map of this document, or
  /// if the value is of a kind [AutomergeValue] does not model (counter,
  /// timestamp, unsigned int, text object or an unknown type).
  AutomergeValue? get(ObjId obj, String key) {
    final doc = _ptr;
    final target = obj._ptr;
    final result = using(
      (arena) =>
          checkResult(AMmapGet(doc, target, stringToSpan(key, arena), nullptr)),
    );
    // Freed here unless an ObjId takes it over.
    var owned = true;
    try {
      final item = AMresultItem(result);
      final type = AMitemValType(item);
      if (type != AMvalType.AM_VAL_TYPE_OBJ_TYPE) {
        return using((arena) => _scalar(item, type, key, arena));
      }
      final native = NativeResult(result);
      owned = false;
      final id = ObjId._fromItem(native);
      final kind = AMobjObjType(doc, id._ptr);
      if (kind == AMobjType.AM_OBJ_TYPE_MAP) return AutomergeMap(id);
      if (kind == AMobjType.AM_OBJ_TYPE_LIST) return AutomergeList(id);
      id.dispose();
      throw AutomergeException('Unsupported object type $kind at $key.');
    } finally {
      if (owned) AMresultFree(result);
    }
  }

  /// The keys of the map [obj], in Automerge's (sorted) order.
  ///
  /// Throws [AutomergeException] if [obj] is not an object of this
  /// document.
  List<String> keys(ObjId obj) {
    final doc = _ptr;
    return useResult(AMkeys(doc, obj._ptr, nullptr), (r) {
      final keys = <String>[];
      using((arena) {
        final out = arena<AMbyteSpan>();
        forEachItem(r, (item) {
          AMitemToStr(item, out);
          keys.add(spanToString(out.ref));
        });
      });
      return keys;
    });
  }

  /// Removes [key] from the map [obj].
  ///
  /// Throws [AutomergeException] if [obj] is not a map of this document.
  void delete(ObjId obj, String key) {
    final doc = _ptr;
    final target = obj._ptr;
    using((arena) {
      useResult(AMmapDelete(doc, target, stringToSpan(key, arena)), _noop);
    });
  }

  /// The type of the object [obj].
  ///
  /// Throws [AutomergeException] if [obj] is not an object of this
  /// document.
  AutomergeObjectType objectType(ObjId obj) =>
      switch (AMobjObjType(_ptr, obj._ptr)) {
        AMobjType.AM_OBJ_TYPE_MAP => AutomergeObjectType.map,
        AMobjType.AM_OBJ_TYPE_LIST => AutomergeObjectType.list,
        AMobjType.AM_OBJ_TYPE_TEXT => AutomergeObjectType.text,
        AMobjType.AM_OBJ_TYPE_DEFAULT => throw AutomergeException(
          'Object $obj is not in this document.',
        ),
      };

  /// Applies every change of [other] that this document lacks. [other] is
  /// not changed except that its pending edits are committed. Merging a
  /// document into itself changes nothing.
  void merge(AutomergeDoc other) {
    if (identical(other, this)) return;
    useResult(AMmerge(_ptr, other._ptr), _noop);
  }

  /// A new document holding the same changes as this one, with a new random
  /// actor id.
  AutomergeDoc fork() =>
      AutomergeDoc._(NativeResult(checkResult(AMfork(_ptr, nullptr))));

  /// The next sync message to send to the peer that [state] tracks, or null
  /// when that peer is known to have everything this document has.
  ///
  /// Repeat with [receiveSyncMessage] on both sides until both return null.
  Uint8List? generateSyncMessage(SyncState state) {
    final doc = _ptr;
    return useResult(AMgenerateSyncMessage(doc, state._ptr), (r) {
      final item = AMresultItem(r);
      if (AMitemValType(item) != AMvalType.AM_VAL_TYPE_SYNC_MESSAGE) {
        return null;
      }
      final message = using((arena) {
        final out = arena<Pointer<AMsyncMessage>>();
        AMitemToSyncMessage(item, out);
        return out.value;
      });
      return useResult(
        AMsyncMessageEncode(message),
        (encoded) => _itemBytes(AMresultItem(encoded)),
      );
    });
  }

  /// Applies a [message] produced by the peer's [generateSyncMessage] and
  /// updates [state].
  ///
  /// Throws [AutomergeException] if [message] cannot be decoded.
  void receiveSyncMessage(SyncState state, Uint8List message) {
    final doc = _ptr;
    final sync = state._ptr;
    using((arena) {
      final span = bytesToSpan(message, arena);
      useResult(AMsyncMessageDecode(span.src, span.count), (r) {
        final out = arena<Pointer<AMsyncMessage>>();
        AMitemToSyncMessage(AMresultItem(r), out);
        useResult(AMreceiveSyncMessage(doc, sync, out.value), _noop);
      });
    });
  }

  /// Converts a scalar [item] of [type] read from [key].
  static AutomergeValue? _scalar(
    Pointer<AMitem> item,
    AMvalType type,
    String key,
    Arena arena,
  ) {
    switch (type) {
      case AMvalType.AM_VAL_TYPE_VOID:
        return null;
      case AMvalType.AM_VAL_TYPE_NULL:
        return const AutomergeNull();
      case AMvalType.AM_VAL_TYPE_BOOL:
        final out = arena<Bool>();
        AMitemToBool(item, out);
        return AutomergeBool(out.value);
      case AMvalType.AM_VAL_TYPE_INT:
        final out = arena<Int64>();
        AMitemToInt(item, out);
        return AutomergeInt(out.value);
      case AMvalType.AM_VAL_TYPE_F64:
        final out = arena<Double>();
        AMitemToF64(item, out);
        return AutomergeDouble(out.value);
      case AMvalType.AM_VAL_TYPE_STR:
        final out = arena<AMbyteSpan>();
        AMitemToStr(item, out);
        return AutomergeString(spanToString(out.ref));
      case AMvalType.AM_VAL_TYPE_BYTES:
        return AutomergeBytes(_itemBytes(item));
      default:
        throw AutomergeException('Unsupported value type $type at $key.');
    }
  }
}

/// A handle to an object (map, list or text) in an Automerge document.
///
/// Object ids are global: an id read from one document names the same
/// object in its forks and in documents it was merged with. Two [ObjId]s
/// are equal when they name the same object.
///
/// Ids other than [root] hold native memory: call [dispose] when done; a
/// [NativeFinalizer] frees it otherwise. Not thread-safe, like
/// [AutomergeDoc].
final class ObjId implements Finalizable {
  ObjId._root() : _result = null, _pointer = nullptr, _text = '_root';

  ObjId._(NativeResult result, Pointer<AMobjId> pointer)
    : _result = result,
      _pointer = pointer,
      _text = _describe(pointer);

  /// Wraps the object id of the first item of [result], taking ownership.
  factory ObjId._fromItem(NativeResult result) =>
      ObjId._(result, AMitemObjId(AMresultItem(result.pointer('ObjId'))));

  /// The root map of every document.
  static final ObjId root = ObjId._root();

  /// Owns the result [_pointer] lives in; null for [root].
  final NativeResult? _result;
  final Pointer<AMobjId> _pointer;

  /// `<counter>@<actorHex>`, Automerge's text form of an object id.
  final String _text;

  static String _describe(Pointer<AMobjId> pointer) {
    final actor = spanToString(AMactorIdStr(AMobjIdActorId(pointer)));
    return '${AMobjIdCounter(pointer)}@$actor';
  }

  /// The id pointer (null for [root], which automerge-c reads as the root);
  /// throws [StateError] after [dispose].
  Pointer<AMobjId> get _ptr {
    _result?.pointer('ObjId');
    return _pointer;
  }

  /// Whether [dispose] has run. Always false for [root].
  bool get isDisposed => _result?.isDisposed ?? false;

  /// Frees the id's native memory; using it afterwards throws [StateError].
  /// Does nothing for [root].
  void dispose() => _result?.dispose();

  @override
  bool operator ==(Object other) => other is ObjId && other._text == _text;

  @override
  int get hashCode => _text.hashCode;

  /// `_root`, or `<counter>@<actorHex>`.
  @override
  String toString() => _text;
}

/// What one document knows about one peer during sync: keep one per peer
/// and pass it to every [AutomergeDoc.generateSyncMessage] and
/// [AutomergeDoc.receiveSyncMessage] for that peer.
///
/// Holds native memory: call [dispose] when done; a [NativeFinalizer] frees
/// it otherwise. Not thread-safe, like [AutomergeDoc].
final class SyncState implements Finalizable {
  SyncState._(this._result) : _state = _stateOf(_result);

  /// A fresh state for a peer nothing is known about yet.
  factory SyncState() =>
      SyncState._(NativeResult(checkResult(AMsyncStateInit())));

  /// Restores a state saved by [encode].
  ///
  /// Throws [AutomergeException] if [bytes] are not an encoded sync state.
  factory SyncState.decode(Uint8List bytes) => using((arena) {
    final span = bytesToSpan(bytes, arena);
    return SyncState._(
      NativeResult(checkResult(AMsyncStateDecode(span.src, span.count))),
    );
  });

  final NativeResult _result;
  final Pointer<AMsyncState> _state;

  static Pointer<AMsyncState> _stateOf(NativeResult result) => using((arena) {
    final out = arena<Pointer<AMsyncState>>();
    AMitemToSyncState(AMresultItem(result.pointer('SyncState')), out);
    return out.value;
  });

  Pointer<AMsyncState> get _ptr {
    _result.pointer('SyncState');
    return _state;
  }

  /// Whether [dispose] has run.
  bool get isDisposed => _result.isDisposed;

  /// Frees the state's native memory; using it afterwards throws
  /// [StateError].
  void dispose() => _result.dispose();

  /// The part of the state worth keeping across sessions (the heads both
  /// sides are known to share), for [SyncState.decode].
  Uint8List encode() =>
      useResult(AMsyncStateEncode(_ptr), (r) => _itemBytes(AMresultItem(r)));
}

/// Parses [hex] into an actor id and passes it to [body] while it is alive.
T _withActorId<T>(String hex, T Function(Pointer<AMactorId>) body) =>
    using((arena) {
      return useResult(AMactorIdFromStr(stringToSpan(hex, arena)), (r) {
        final out = arena<Pointer<AMactorId>>();
        AMitemToActorId(AMresultItem(r), out);
        return body(out.value);
      });
    });

/// Copies the bytes held by a bytes [item].
Uint8List _itemBytes(Pointer<AMitem> item) => using((arena) {
  final out = arena<AMbyteSpan>();
  AMitemToBytes(item, out);
  return spanToBytes(out.ref);
});

/// Copies the change hash held by a change-hash [item].
Uint8List _changeHash(Pointer<AMitem> item, Arena arena) {
  final out = arena<AMbyteSpan>();
  AMitemToChangeHash(item, out);
  return spanToBytes(out.ref);
}

/// Result body for calls whose only output is success or failure.
void _noop(Pointer<AMresult> _) {}
