// What: The CRDT port: CrdtDocument (a replicated document of nested
//   string-keyed maps), CrdtSyncPeer, CrdtMap, CrdtChangeOrigin, and
//   CrdtBackend, which creates and loads documents.
// Why: docs/decisions/007-crdt-automerge.md (PNT-A0013-03) keeps every
//   system outside lib/crdt/ independent of the Automerge binding, so they
//   use only this interface.
// Coupled to: automerge_crdt_document.dart (the only implementation),
//   ../document/content_document.dart (content document),
//   ../session/session_document.dart (session document and workspaces).
//
// ---------------------------------------------------------------------------
// CRDT port overview
//
// What it is: a document is a tree of maps addressed by paths of keys from
// the root map. Leaves are null, bool, int, double, String or Uint8List.
// Edits (put, putMap, delete) collect until commit(), which records them as
// one change. Two replicas exchange changes through sync messages: each keeps
// one CrdtSyncPeer per remote replica and calls generateSyncMessage /
// receiveSyncMessage until neither has anything to send. Concurrent writes to
// the same key converge to one value on every replica.
//
// Why a narrow port: the content and workspace systems need exactly this, and
// it maps onto Automerge, Yjs and Loro alike. Anything more (lists, text,
// history access) would tie callers to one backend.
//
// How callers learn about changes: listeners run after each commit that
// recorded something (local) and after each received sync message that
// changed the document (remote). The port reports no diff (PNT-A0013-05):
// a listener re-reads what it shows.
//
// Rules callers must keep (PNT-A0013-04): only the replica that creates a
// document creates maps at keys others could also create; every other entry
// uses an id embedding the actor, `<actorHex>:<counter>` (newId does this).
// Threading: one isolate per document (PNT-A0013-06).
// ---------------------------------------------------------------------------

import 'dart:typed_data';

/// Where a change a listener hears about came from.
enum CrdtChangeOrigin {
  /// A commit on this replica.
  local,

  /// A sync message from another replica.
  remote,
}

/// Called after a document changed; see the overview at the top of this file.
typedef CrdtListener = void Function(CrdtChangeOrigin origin);

/// The value [CrdtDocument.get] returns for a map.
final class CrdtMap {
  const CrdtMap();

  @override
  String toString() => 'CrdtMap()';
}

/// A replicated document of nested maps. See the overview at the top of this
/// file.
abstract interface class CrdtDocument {
  /// The id, in hexadecimal, that this replica's changes are attributed to.
  String get actorId;

  /// The value at [path]: null, bool, int, double, String, Uint8List, or a
  /// [CrdtMap]. Null also when [path] or any map on it is absent.
  Object? get(List<String> path);

  /// The entries of the map at [path], nested maps given as [CrdtMap].
  /// Empty when [path] is not a map. Reads the map once, so it is the cheap
  /// way to read several keys of one map.
  Map<String, Object?> entries(List<String> path);

  /// The keys of the map at [path], or an empty list when it is not a map.
  List<String> keys(List<String> path);

  /// Sets the leaf at [path] to [value] (null, bool, int, double, String or
  /// Uint8List). Every map on the way must exist.
  void put(List<String> path, Object? value);

  /// Sets [path] to a new empty map, replacing what was there. Every map on
  /// the way must exist.
  void putMap(List<String> path);

  /// Removes the last key of [path] from its map; nothing if it is absent.
  void delete(List<String> path);

  /// Records the edits since the last commit as one change and tells
  /// listeners ([CrdtChangeOrigin.local]) if there were any.
  void commit({String? message});

  /// The whole document, with its change history, for [CrdtBackend.load].
  Uint8List save();

  /// A new id `<actorHex>:<counter>` unique across replicas.
  String newId();

  /// State tracking what one remote replica has; one per connection.
  CrdtSyncPeer createSyncPeer();

  /// The next message for [peer], or null when [peer] has everything.
  Uint8List? generateSyncMessage(CrdtSyncPeer peer);

  /// Applies a message from [peer]'s replica and tells listeners
  /// ([CrdtChangeOrigin.remote]) if the document changed. Throws
  /// [FormatException] if [message] cannot be read.
  void receiveSyncMessage(CrdtSyncPeer peer, Uint8List message);

  void addListener(CrdtListener listener);

  void removeListener(CrdtListener listener);

  /// Frees the document. No method may be called afterwards.
  void dispose();
}

/// Tracks what one remote replica of a [CrdtDocument] has.
abstract interface class CrdtSyncPeer {
  void dispose();
}

/// Creates and loads [CrdtDocument]s of one implementation.
abstract interface class CrdtBackend {
  /// A new empty document with a new random actor id.
  CrdtDocument create();

  /// A document from bytes produced by [CrdtDocument.save], with a new
  /// random actor id. Throws [FormatException] if [bytes] are not one.
  CrdtDocument load(Uint8List bytes);
}
