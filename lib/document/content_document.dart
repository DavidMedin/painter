// What: ContentDocument, which holds a document's content in a CRDT document
//   (../crdt/crdt_document.dart) with the content schema, and keeps the
//   CanvasDocument that is drawn in step with it in both directions; and
//   StrokeEngineMismatch, the error for content from another engine version.
// Why: the content must be shared and merged between peers and saved with
//   its change history (DOCF-1), while the canvas, tile cache and renderer
//   work on the immutable CanvasDocument. This file is the only place that
//   knows how strokes are stored in the CRDT.
// Coupled to: ../canvas/canvas_controller.dart (CanvasDocument, CanvasStroke,
//   CanvasController.replaceDocument / insertStrokes / removeStrokes),
//   undo_history.dart (edits in one commit through [ContentDocument.transact]),
//   document_file_format.dart (section kind 1 holds [ContentDocument.save]),
//   ../canvas/pencil_splats.dart (strokeEngineVersion), and ../main.dart.
//
// ---------------------------------------------------------------------------
// Content document overview
//
// What it is: the document's content as a CRDT document of nested maps
// (docs/decisions/007-crdt-automerge.md), plus the CanvasDocument mirror the
// app draws. Schema (docs/decisions/008-document-file-format.md PNT-A0014-03,
// PNT-A0014-04): the root holds `format` = "painter-document", `version` = 2,
// `engine` = strokeEngineVersion and `strokes`, a map from stroke id to
// {points: bytes of little-endian float64 triples x, y, weight; seed: int;
// z: int; gesture: string}. The creator writes the root keys and the empty
// `strokes` map before the document is shared (PNT-A0013-04); every stroke
// id embeds its creator's actor, so peers never write the same key.
//
// Why mirror instead of reading the CRDT when drawing: the renderer and tile
// cache need immutable strokes in (z, id) order with change kinds
// (CanvasDocument), and the port reports no diffs (PNT-A0013-05). Reading the
// CRDT per frame through FFI was not an option.
//
// How it works:
//   - Local edits: the CanvasDocument's observer writes each inserted stroke
//     and deletes each removed one in the CRDT, then commits, so peers see
//     chunks live. [ContentDocument.transact] groups several edits into one
//     commit (undo and redo, PNT-A0018-02).
//   - Remote changes: the CRDT listener (origin remote) diffs the `strokes`
//     keys against the CanvasDocument and inserts or removes strokes through
//     the attached CanvasController, so the canvas repaints. Those writes are
//     flagged so the observer does not echo them back. New strokes are
//     inserted in (z, id) order, so a batch above the top is appended.
//   - Unreadable stroke entries (PNT-A0014-10: a field missing or of the
//     wrong type, `z` outside 0..2^53-1, `seed` outside 0..2^31-1, or bad
//     points) are deleted in one commit by the replica that reads them, on
//     load and on remote changes; they are never shown and never make a file
//     unopenable. Only the root keys and the container refuse a file
//     (DOCF-7).
//   - A joined Session's document may be empty until sync brings the root
//     keys; they are validated once they arrive. Strokes drawn before then
//     get new `z` values above every stroke that arrived, in their own order
//     (PNT-A0014-05), and are written in one commit; [onRestamped] tells the
//     undo history (undo_history.dart) their new data.
// All calls run on the UI isolate (PNT-A0013-06).
// ---------------------------------------------------------------------------

import 'dart:typed_data';
import 'dart:ui' show Offset;

import '../canvas/canvas_controller.dart';
import '../canvas/pencil_splats.dart' show strokeEngineVersion;
import '../crdt/crdt_document.dart';

/// Content whose strokes were made by another stroke engine version than
/// this build's [strokeEngineVersion]; it is refused (DOCF-6, PNT-A0014-07).
class StrokeEngineMismatch implements Exception {
  const StrokeEngineMismatch({
    required this.documentVersion,
    required this.systemVersion,
  });

  /// The engine version the content records.
  final int documentVersion;

  /// This build's [strokeEngineVersion].
  final int systemVersion;

  @override
  String toString() =>
      'StrokeEngineMismatch: the document uses stroke engine version '
      '$documentVersion, but this Painter has stroke engine version '
      '$systemVersion.';
}

/// A document's content in a [CrdtDocument], mirrored into [canvas]. See the
/// overview at the top of this file.
class ContentDocument {
  ContentDocument._(this.crdt);

  /// Value of the root `format` key.
  static const String formatIdentifier = 'painter-document';

  /// Value of the root `version` key.
  static const int formatVersion = 2;

  /// Largest `z` a readable stroke has: 2^53 - 1 (PNT-A0014-10).
  static const int maxZ = 0x1fffffffffffff;

  /// Largest `seed` a readable stroke has: 2^31 - 1 (PNT-A0014-10).
  static const int maxSeed = 0x7fffffff;

  /// Bytes per stored point: three little-endian float64s.
  static const int _pointBytes = 24;

  /// The CRDT document holding the content. Owned: [dispose] frees it.
  final CrdtDocument crdt;

  /// The strokes as drawn, kept equal to the CRDT's `strokes` map.
  final CanvasDocument canvas = CanvasDocument.empty();

  CanvasController? _controller;
  bool _ready = false;
  bool _applyingRemote = false;
  int _transactionDepth = 0;
  Object? _rejection;

  /// Every stroke drawn locally before the root keys arrived, by id, whether
  /// or not it is still in [canvas]; given a new `z` by [_becomeReady]. Only
  /// non-empty for a joined document that is not yet [isReady].
  final Map<String, CanvasStroke> _drawnBeforeReady = {};

  /// Called once when content arriving from peers turns out to be unusable:
  /// a [StrokeEngineMismatch] or a [FormatException] about the root keys.
  /// The document stops following remote changes; [rejection] holds the
  /// same error.
  void Function(Object error)? onRejected;

  /// Called when the root keys of a joined document arrive, with every
  /// stroke drawn before then, by id, as it now is: same id, seed, gesture
  /// and points, and a new `z` above every stroke that arrived. `EditHistory`
  /// (undo_history.dart) sets it so redo puts back the new data.
  void Function(Map<String, CanvasStroke> restamped)? onRestamped;

  /// A new content document with the root keys and no strokes, committed as
  /// its first change (PNT-A0013-04).
  factory ContentDocument.create(CrdtBackend backend) {
    final content = ContentDocument._(backend.create());
    content._writeRoot();
    content.crdt.commit(message: 'Create document');
    content._start(ready: true);
    return content;
  }

  /// A new content document holding [json], an earlier-format document
  /// (docs/spec/document-file.md), written as one change with its root keys
  /// (PNT-A0014-08). Stroke i keeps `seed` = `z` = i + 1 (DOCF-3); ids and
  /// gesture ids come from the new document's [newId]. Throws
  /// [FormatException] for anything `CanvasDocument.fromJson` rejects.
  factory ContentDocument.importEarlier(CrdtBackend backend, Object? json) {
    final content = ContentDocument._(backend.create());
    try {
      final imported = CanvasDocument.fromJson(json, newId: content.newId);
      content._writeRoot();
      for (final stroke in imported.strokes) {
        content.canvas.insert(stroke);
        content._writeStroke(stroke);
      }
      content.crdt.commit(message: 'Import earlier format');
    } catch (_) {
      content.crdt.dispose();
      rethrow;
    }
    content._start(ready: true);
    return content;
  }

  /// Wraps [crdt], an existing content document, and takes ownership of it.
  ///
  /// When [crdt] has root keys they are validated: a stroke engine other
  /// than [strokeEngineVersion] throws [StrokeEngineMismatch]; a wrong
  /// format or version throws [FormatException] naming the reason (DOCF-6,
  /// DOCF-7). Readable strokes are shown; unreadable ones are deleted in one
  /// commit (PNT-A0014-10). When it has none, [requireRoot] decides: a file
  /// must have them (throws [FormatException]); a joined Session's document
  /// may receive them later by sync (`requireRoot: false`), when they are
  /// validated in turn. [crdt] is not disposed when this throws.
  factory ContentDocument.adopt(CrdtDocument crdt, {bool requireRoot = true}) {
    final content = ContentDocument._(crdt);
    if (!content._hasRoot()) {
      if (requireRoot) {
        throw const FormatException(
          'The content has no Painter document format.',
        );
      }
      content._start(ready: false);
      return content;
    }
    content._validateRoot();
    final (strokes, unreadable) = content._readStrokes(
      crdt.keys(const ['strokes']),
    );
    // Sorted first, every insert is an append (PNT-A0014-05).
    for (final stroke in strokes) {
      content.canvas.insert(stroke);
    }
    content._deleteUnreadable(unreadable);
    content._start(ready: true);
    return content;
  }

  /// Loads content saved by [save]: [backend] loads the bytes (a new actor,
  /// PNT-A0014-09), then [ContentDocument.adopt] validates them. Throws
  /// [FormatException] or [StrokeEngineMismatch]; nothing leaks on failure.
  factory ContentDocument.load(CrdtBackend backend, Uint8List bytes) {
    final crdt = backend.load(bytes);
    try {
      return ContentDocument.adopt(crdt);
    } catch (_) {
      crdt.dispose();
      rethrow;
    }
  }

  /// Whether the root keys are present and valid, so strokes are written to
  /// the CRDT as they are made.
  bool get isReady => _ready;

  /// The error that made this document stop following peers, or null; see
  /// [onRejected].
  Object? get rejection => _rejection;

  /// A new id `<actorHex>:<counter>` of this document's actor, for strokes
  /// and gestures (PNT-A0013-04).
  String newId() => crdt.newId();

  /// The whole content with its change history, for section kind 1 of a
  /// document file (document_file_format.dart).
  Uint8List save() => crdt.save();

  /// Makes [controller] draw this document: it gets [canvas] and takes new
  /// ids from [newId]. Remote changes then go through [controller], which
  /// notifies its listeners so every Canvas pane repaints.
  void attach(CanvasController controller) {
    _controller = controller;
    controller.replaceDocument(canvas, newId: newId);
  }

  /// Runs [edits], which change [canvas] (normally through the attached
  /// CanvasController), and records all their CRDT writes as one commit.
  /// Undo and redo use it (docs/decisions/012-undo-per-participant.md
  /// PNT-A0018-02). Nests.
  void transact(void Function() edits, {String? message}) {
    _transactionDepth++;
    try {
      edits();
    } finally {
      if (--_transactionDepth == 0) crdt.commit(message: message);
    }
  }

  /// Stops mirroring and frees [crdt]. The attached controller keeps showing
  /// [canvas] until it is given another document.
  void dispose() {
    canvas.removeObserver(_onCanvasChange);
    crdt.removeListener(_onCrdtChange);
    _controller = null;
    crdt.dispose();
  }

  /// Begins mirroring in both directions.
  void _start({required bool ready}) {
    _ready = ready;
    canvas.addObserver(_onCanvasChange);
    crdt.addListener(_onCrdtChange);
  }

  void _writeRoot() {
    crdt.put(const ['format'], formatIdentifier);
    crdt.put(const ['version'], formatVersion);
    crdt.put(const ['engine'], strokeEngineVersion);
    crdt.putMap(const ['strokes']);
  }

  bool _hasRoot() => crdt.get(const ['format']) != null;

  /// Throws [FormatException] or [StrokeEngineMismatch] when the root keys
  /// are not this schema's.
  void _validateRoot() {
    final root = crdt.entries(const []);
    final format = root['format'];
    if (format != formatIdentifier) {
      throw FormatException('Not a Painter document: format is "$format".');
    }
    final version = root['version'];
    if (version != formatVersion) {
      throw FormatException(
        'Unsupported Painter content version $version; '
        'this Painter reads version $formatVersion.',
      );
    }
    final engine = root['engine'];
    if (engine is! int) {
      throw FormatException('The stroke engine version "$engine" is invalid.');
    }
    if (engine != strokeEngineVersion) {
      throw StrokeEngineMismatch(
        documentVersion: engine,
        systemVersion: strokeEngineVersion,
      );
    }
    if (root['strokes'] is! CrdtMap) {
      throw const FormatException('The document has no stroke map.');
    }
  }

  /// Mirrors a local [canvas] change into the CRDT and commits it unless a
  /// [transact] is running. Changes made by [_applyRemote] and
  /// [_becomeReady] are skipped: they came from the CRDT or write it
  /// themselves.
  void _onCanvasChange(CanvasStrokeChange change) {
    if (_applyingRemote) return;
    final stroke = change.stroke;
    final removed = change.kind == CanvasStrokeChangeKind.removed;
    if (!_ready) {
      // No `strokes` map yet (a joined document before sync): remember the
      // stroke for _becomeReady, which reads presence from [canvas].
      if (!removed) _drawnBeforeReady[stroke.id] = stroke;
      return;
    }
    if (removed) {
      crdt.delete(['strokes', stroke.id]);
    } else {
      _writeStroke(stroke);
    }
    if (_transactionDepth == 0) crdt.commit();
  }

  void _onCrdtChange(CrdtChangeOrigin origin) {
    if (origin != CrdtChangeOrigin.remote || _rejection != null) return;
    if (!_ready && !_hasRoot()) return;
    try {
      _validateRoot();
    } catch (error) {
      _reject(error);
      return;
    }
    if (_ready) {
      _applyRemote();
    } else {
      _becomeReady();
    }
  }

  /// Takes the strokes drawn before the root keys arrived off [canvas],
  /// shows the arrived strokes, then puts the drawn ones back above all of
  /// them with new `z` values in their old order (PNT-A0014-05), writing
  /// them in one commit, and reports the new data to [onRestamped].
  void _becomeReady() {
    final drawn = _drawnBeforeReady.values.toList()
      ..sort((a, b) => a.compareOrder(b));
    _drawnBeforeReady.clear();
    final shown = [
      for (final stroke in drawn)
        if (canvas.strokeById(stroke.id) != null) stroke.id,
    ];
    _applyingRemote = true;
    try {
      _removeFromCanvas(shown);
    } finally {
      _applyingRemote = false;
    }
    _ready = true;
    _applyRemote();

    final base = canvas.nextZ;
    final restamped = <String, CanvasStroke>{
      for (var i = 0; i < drawn.length; i++)
        drawn[i].id: CanvasStroke(
          drawn[i].points,
          id: drawn[i].id,
          seed: drawn[i].seed,
          z: base + i,
          gesture: drawn[i].gesture,
        ),
    };
    _applyingRemote = true;
    try {
      _insertIntoCanvas([for (final id in shown) restamped[id]!]);
    } finally {
      _applyingRemote = false;
    }
    for (final id in shown) {
      _writeStroke(restamped[id]!);
    }
    crdt.commit(message: 'Strokes drawn before joining');
    if (restamped.isNotEmpty) onRestamped?.call(restamped);
  }

  void _reject(Object error) {
    _rejection = error;
    crdt.removeListener(_onCrdtChange);
    onRejected?.call(error);
  }

  /// Brings [canvas] in line with the CRDT's `strokes` map after a remote
  /// change. Strokes are immutable, so only added and removed ids matter.
  /// Added strokes are inserted in (z, id) order, so a batch on top is
  /// reported as appends; unreadable entries are deleted (PNT-A0014-10).
  void _applyRemote() {
    final ids = crdt.keys(const ['strokes']).toSet();
    final removed = [
      for (final stroke in canvas.strokes)
        if (!ids.contains(stroke.id)) stroke.id,
    ];
    final (added, unreadable) = _readStrokes([
      for (final id in ids)
        if (canvas.strokeById(id) == null) id,
    ]);
    _applyingRemote = true;
    try {
      _removeFromCanvas(removed);
      _insertIntoCanvas(added);
    } finally {
      _applyingRemote = false;
    }
    _deleteUnreadable(unreadable);
  }

  /// Removes [ids] through the attached controller, so panes repaint, or
  /// from [canvas] directly when none is attached.
  void _removeFromCanvas(List<String> ids) {
    if (ids.isEmpty) return;
    final controller = _controller;
    if (controller != null) {
      controller.removeStrokes(ids);
    } else {
      ids.forEach(canvas.remove);
    }
  }

  /// Inserts [strokes] like [_removeFromCanvas] removes.
  void _insertIntoCanvas(List<CanvasStroke> strokes) {
    if (strokes.isEmpty) return;
    final controller = _controller;
    if (controller != null) {
      controller.insertStrokes(strokes);
    } else {
      strokes.forEach(canvas.insert);
    }
  }

  /// Reads the strokes under [ids]: the readable ones sorted bottom to top,
  /// and the ids of the unreadable ones.
  (List<CanvasStroke>, List<String>) _readStrokes(Iterable<String> ids) {
    final strokes = <CanvasStroke>[];
    final unreadable = <String>[];
    for (final id in ids) {
      final stroke = _readStroke(id);
      if (stroke == null) {
        unreadable.add(id);
      } else {
        strokes.add(stroke);
      }
    }
    strokes.sort((a, b) => a.compareOrder(b));
    return (strokes, unreadable);
  }

  /// Deletes the stroke entries under [ids] in one commit (PNT-A0014-10).
  void _deleteUnreadable(List<String> ids) {
    if (ids.isEmpty) return;
    for (final id in ids) {
      crdt.delete(['strokes', id]);
    }
    crdt.commit(message: 'Delete unreadable strokes');
  }

  /// Writes [stroke] as a stroke map under its id (PNT-A0014-04). Does not
  /// commit.
  void _writeStroke(CanvasStroke stroke) {
    final path = ['strokes', stroke.id];
    crdt.putMap(path);
    crdt.put([...path, 'points'], encodePoints(stroke.points));
    crdt.put([...path, 'seed'], stroke.seed);
    crdt.put([...path, 'z'], stroke.z);
    crdt.put([...path, 'gesture'], stroke.gesture);
  }

  /// The stroke stored under [id], or null when the entry is unreadable
  /// (PNT-A0014-10).
  CanvasStroke? _readStroke(String id) {
    final entry = crdt.entries(['strokes', id]);
    final points = entry['points'];
    final seed = entry['seed'];
    final z = entry['z'];
    final gesture = entry['gesture'];
    if (points is! Uint8List ||
        seed is! int ||
        z is! int ||
        gesture is! String ||
        seed < 0 ||
        seed > maxSeed ||
        z < 0 ||
        z > maxZ) {
      return null;
    }
    final decoded = decodePoints(points);
    if (decoded == null) return null;
    return CanvasStroke(decoded, id: id, seed: seed, z: z, gesture: gesture);
  }

  /// [points] as stored: little-endian float64 triples x, y, weight
  /// (PNT-A0014-04). Inverse of [decodePoints].
  static Uint8List encodePoints(List<CanvasPoint> points) {
    final data = ByteData(points.length * _pointBytes);
    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      final offset = i * _pointBytes;
      data
        ..setFloat64(offset, point.position.dx, Endian.little)
        ..setFloat64(offset + 8, point.position.dy, Endian.little)
        ..setFloat64(offset + 16, point.weight, Endian.little);
    }
    return data.buffer.asUint8List();
  }

  /// The points in [bytes], or null when they are empty, not a whole number
  /// of triples, non-finite, or have a weight outside 0.05-1 (the range
  /// `CanvasDocument.fromJson` and `CanvasController` keep).
  static List<CanvasPoint>? decodePoints(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length % _pointBytes != 0) return null;
    final data = ByteData.sublistView(bytes);
    final points = <CanvasPoint>[];
    for (var offset = 0; offset < bytes.length; offset += _pointBytes) {
      final x = data.getFloat64(offset, Endian.little);
      final y = data.getFloat64(offset + 8, Endian.little);
      final weight = data.getFloat64(offset + 16, Endian.little);
      if (!x.isFinite || !y.isFinite || !(weight >= 0.05 && weight <= 1)) {
        return null;
      }
      points.add(CanvasPoint(position: Offset(x, y), weight: weight));
    }
    return points;
  }
}
