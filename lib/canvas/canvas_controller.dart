// What: The shared canvas document (`CanvasDocument`, ordered immutable
//   `CanvasStroke`s with stable ids), the active-stroke model
//   (`CanvasController`), and the ids and seeds new strokes get
//   (`ActorIdSource`, `strokeSeedOf`).
// Why: Document content is shared by every Canvas pane, while view transforms
//   belong to one pane (canvas_viewport.dart). This model stays independent
//   from input, rendering and storage.
// Coupled to: canvas_view.dart (input and painting), tiled_renderer.dart and
//   tile_cache.dart (rendered document; TileCache observes document changes),
//   main.dart (document lifecycle), ../document/content_document.dart (keeps
//   the document in step with the CRDT content document and supplies stroke
//   ids), ../document/undo_history.dart (gesture hook, remove and insert),
//   ../document/document_file_format.dart (earlier-format JSON import), and
//   pencil_splats.dart / splat_worker.dart (derived marks).

import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Canvas state model (overview)
//
// What: Two kinds of state, kept deliberately apart.
//   1. Document (`CanvasDocument`): immutable `CanvasStroke`s ordered bottom
//      to top by (`z`, `id`), each a list of `CanvasPoint`s (document-space
//      position + brush weight) plus its id, seed, z and gesture id. This is
//      the only thing that is saved.
//   2. Active chunk (`CanvasController.activePoints`): the bounded tail of the
//      pointer gesture being drawn right now. Completed chunks are inserted on
//      top of the shared document as immutable strokes, allowing TileCache to
//      rasterize the trail while the latest chunk remains live.
//
// Each Canvas pane owns a `CanvasViewportController` (canvas_viewport.dart)
// for its view, so panning or zooming one pane cannot move another and never
// touches the document; the tile cache (tile_cache.dart) stays valid across
// view changes (docs/decisions/003-vector-canvas.md).
//
// Stroke identity (docs/decisions/008-document-file-format.md PNT-A0014-04 to
// PNT-A0014-06): every stroke has an `id` of the form `<actorHex>:<counter>`
// (docs/decisions/007-crdt-automerge.md PNT-A0013-04), so ids made by
// different peers never collide and survive saving and Sessions (DOCF-2). A
// new stroke's `z` is one more than the largest in the document, and its
// `seed` is `strokeSeedOf(id)`, stored with the stroke so its grain never
// depends on its position: a stroke inserted below it by another peer, or a
// removal, leaves its specks unchanged. Each committed chunk of one pointer
// gesture is its own stroke; all of them share the gesture's `gesture` id,
// which undo will group by (docs/decisions/012-undo-per-participant.md).
// Active chunks are given their id when they start (`activeStrokeId`), so the
// renderer draws them with the seed they keep on commit.
//
// Changes: strokes are added on top (the normal case), inserted at their
// (z, id) position (a remote stroke may sort below existing ones), or removed
// by id. `CanvasDocument` tells observers which kind each change was, because
// TileCache can draw a stroke appended on top over a tile's old image but
// must rebuild the tiles any other change touches
// (docs/decisions/004-tile-cache.md PNT-A0005-09). `ContentDocument`
// (../document/content_document.dart) feeds remote changes through the same
// methods.
//
// Why strokes are immutable: tiles, splat buffers (`SplatWorker`) and
// bounds are derived from a stroke once and reused for the session. A stroke
// that could change would silently invalidate all of them.
// `CanvasStroke` copies its points into an unmodifiable list and caches
// `bounds` at construction.
//
// Why `ChangeNotifier` and no state-management package: the whole state is
// one object with a handful of mutators; widgets and painters just listen
// (`_CanvasPainter` repaints via `Listenable.merge([controller, ...])`).
// docs/decisions/003-vector-canvas.md chose this to avoid a dependency while
// keeping mutation out of widget painting code.
//
// Earlier format (docs/spec/document-file.md): UTF-8 JSON, format identifier
// `painter-document`, integer version 1:
//   {"format": "painter-document", "version": 1,
//    "strokes": [[{"x": 1.0, "y": 2.0, "weight": 0.5}, ...], ...]}
// Only document-space points and weights are stored, bottom stroke first, so
// ids, seeds and gestures are not saved. `CanvasDocument.fromJson` gives the
// stroke at index i `seed` = `z` = i + 1, the seed this format always
// rendered it with (DOCF-3, PNT-A0014-08). Files are now saved as format 2
// (../document/document_file_format.dart); this format is only read.
//
// Prototype values: `brushDiameter` and the weight range 0.05-1 are prototype
// choices, not settled product values (docs/decisions/003-vector-canvas.md).
// ---------------------------------------------------------------------------

/// One sampled input point of a stroke: a document-space [position] and a
/// brush [weight] in 0.05-1 that scales the brush diameter.
///
/// The range is enforced in `CanvasController._clampWeight` for live input,
/// in `CanvasDocument.fromJson` for earlier-format files, and in
/// `ContentDocument.decodePoints` (../document/content_document.dart) for
/// stored strokes; keep the three in sync.
@immutable
class CanvasPoint {
  const CanvasPoint({required this.position, required this.weight});

  final Offset position;
  final double weight;
}

/// The seed a new stroke with [id] gets: the 32-bit FNV-1a hash of the id's
/// UTF-8 bytes with the top bit cleared
/// (docs/decisions/008-document-file-format.md PNT-A0014-06).
int strokeSeedOf(String id) {
  var hash = 0x811c9dc5;
  for (final byte in utf8.encode(id)) {
    hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
  }
  return hash & 0x7fffffff;
}

/// Hands out ids `<actorHex>:<counter>` for one actor, counting from 1
/// (docs/decisions/007-crdt-automerge.md PNT-A0013-04).
///
/// The default id source of `CanvasController` and `CanvasDocument.fromJson`
/// when no other is given. In the app, ids come from the content document's
/// `CrdtDocument.newId` instead (../document/content_document.dart), so they
/// embed its actor.
class ActorIdSource {
  ActorIdSource(this.actorHex);

  /// A source for a new random 16-byte actor.
  ActorIdSource.random([math.Random? random])
    : actorHex = _randomActorHex(random ?? math.Random.secure());

  /// The actor id as lowercase hexadecimal.
  final String actorHex;
  int _counter = 0;

  /// The next unused id of this actor.
  String next() => '$actorHex:${++_counter}';

  static String _randomActorHex(math.Random random) => [
    for (var i = 0; i < 16; i++)
      random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();
}

/// An immutable stroke.
///
/// [id] identifies it across saving and Sessions. [seed] differentiates the
/// deterministic speck pattern of strokes that trace the same path; it is
/// stored, never derived from position. [z] and then [id] order strokes
/// bottom to top ([compareOrder]). [gesture] is the id of the pointer gesture
/// the stroke is a chunk of. [bounds] is the document-space rectangle that
/// contains every point; it does not include brush radius.
///
/// The constructor copies the points into an unmodifiable list and computes
/// [bounds] once. `TileCache` inflates [bounds] by `PencilSplats.inkMargin` to
/// decide which tiles a stroke touches, and `SplatWorker.generate` consumes
/// [points] and [seed] to build the stroke's splats.
@immutable
class CanvasStroke {
  CanvasStroke(
    Iterable<CanvasPoint> points, {
    required this.id,
    required this.seed,
    required this.z,
    required this.gesture,
  }) : points = List<CanvasPoint>.unmodifiable(points) {
    bounds = _boundsOf(this.points);
  }

  final List<CanvasPoint> points;
  final String id;
  final int seed;
  final int z;
  final String gesture;

  /// Document-space rectangle containing every point (no brush radius).
  late final Rect bounds;

  /// Negative when this stroke is drawn below [other]: by [z], then by [id]
  /// (docs/decisions/008-document-file-format.md PNT-A0014-05).
  int compareOrder(CanvasStroke other) {
    final byZ = z.compareTo(other.z);
    return byZ != 0 ? byZ : id.compareTo(other.id);
  }

  static Rect _boundsOf(List<CanvasPoint> points) {
    var left = double.infinity, top = double.infinity;
    var right = -double.infinity, bottom = -double.infinity;
    for (final point in points) {
      final p = point.position;
      if (p.dx < left) left = p.dx;
      if (p.dx > right) right = p.dx;
      if (p.dy < top) top = p.dy;
      if (p.dy > bottom) bottom = p.dy;
    }
    return points.isEmpty ? Rect.zero : Rect.fromLTRB(left, top, right, bottom);
  }
}

/// How a [CanvasStrokeChange] changed the document.
enum CanvasStrokeChangeKind {
  /// The stroke was inserted above every other stroke.
  appended,

  /// The stroke was inserted below at least one other stroke.
  inserted,

  /// The stroke was removed.
  removed,
}

/// One change to a [CanvasDocument], as told to its observers.
@immutable
class CanvasStrokeChange {
  const CanvasStrokeChange(this.kind, this.stroke);

  final CanvasStrokeChangeKind kind;

  /// The stroke that was inserted or removed.
  final CanvasStroke stroke;
}

/// The saved content: immutable [CanvasStroke]s ordered bottom to top by
/// [CanvasStroke.compareOrder], with lookup by id.
///
/// [insert] and [remove] tell observers ([addObserver]) synchronously what
/// changed. `TileCache` relies on the distinction: a stroke appended on top
/// is drawn over a tile's old image, while an insertion below the top or a
/// removal makes it rebuild the tiles that stroke touches. Callers that show
/// the document also listen to `CanvasController`, which notifies after each
/// of its mutations.
class CanvasDocument {
  CanvasDocument.empty();

  final List<CanvasStroke> _strokes = [];
  late final List<CanvasStroke> _strokesView = UnmodifiableListView(_strokes);
  final Map<String, CanvasStroke> _byId = {};
  final List<void Function(CanvasStrokeChange change)> _observers = [];

  /// Every stroke, bottom first. A live read-only view.
  List<CanvasStroke> get strokes => _strokesView;

  int get strokeCount => _strokes.length;

  /// The stroke at [index] in bottom-to-top order.
  CanvasStroke strokeAt(int index) => _strokes[index];

  /// The stroke with [id], or null when the document has none.
  CanvasStroke? strokeById(String id) => _byId[id];

  /// The `z` a new stroke gets so it lands on top: one more than the largest
  /// `z` in the document, or 1 when it is empty
  /// (docs/decisions/008-document-file-format.md PNT-A0014-05).
  int get nextZ => _strokes.isEmpty ? 1 : _strokes.last.z + 1;

  /// Index of the first stroke ordered above [stroke], or 0 when [stroke] is
  /// null. [stroke] need not be in the document. `TileCache` uses it to find
  /// the strokes above the last one a tile has drawn.
  int indexAbove(CanvasStroke? stroke) {
    if (stroke == null) return 0;
    var low = 0, high = _strokes.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (_strokes[middle].compareOrder(stroke) <= 0) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  /// Inserts [stroke] at its (z, id) position and tells observers whether it
  /// landed on top. Throws [ArgumentError] when its id is already present.
  void insert(CanvasStroke stroke) {
    if (_byId.containsKey(stroke.id)) {
      throw ArgumentError.value(stroke.id, 'stroke.id', 'is already present');
    }
    final index = indexAbove(stroke);
    final onTop = index == _strokes.length;
    _strokes.insert(index, stroke);
    _byId[stroke.id] = stroke;
    _notify(
      CanvasStrokeChange(
        onTop
            ? CanvasStrokeChangeKind.appended
            : CanvasStrokeChangeKind.inserted,
        stroke,
      ),
    );
  }

  /// Removes the stroke with [id] and returns it, or returns null when the
  /// document has none.
  CanvasStroke? remove(String id) {
    final stroke = _byId.remove(id);
    if (stroke == null) return null;
    _strokes.removeAt(indexAbove(stroke) - 1);
    _notify(CanvasStrokeChange(CanvasStrokeChangeKind.removed, stroke));
    return stroke;
  }

  /// Calls [observer] after every [insert] and [remove], until
  /// [removeObserver].
  void addObserver(void Function(CanvasStrokeChange change) observer) =>
      _observers.add(observer);

  void removeObserver(void Function(CanvasStrokeChange change) observer) =>
      _observers.remove(observer);

  void _notify(CanvasStrokeChange change) {
    for (final observer in List.of(_observers)) {
      observer(change);
    }
  }

  /// Format identifier stored in saved documents.
  static const String formatIdentifier = 'painter-document';

  /// Current saved-document format version.
  static const int formatVersion = 1;

  /// Serializes to the `painter-document` JSON shape described in the
  /// overview above, bottom stroke first. Ids, seeds, gestures and views are
  /// not part of this format.
  Map<String, Object?> toJson() => {
    'format': formatIdentifier,
    'version': formatVersion,
    'strokes': [
      for (final stroke in _strokes)
        [
          for (final point in stroke.points)
            {
              'x': point.position.dx,
              'y': point.position.dy,
              'weight': point.weight,
            },
        ],
    ],
  };

  /// Parses and validates a document produced by [toJson].
  ///
  /// The stroke at index i gets `seed` = `z` = i + 1, which reproduces the
  /// grain this format rendered it with (DOCF-3), and an id and its own
  /// gesture id from [newId] (a new random actor when omitted).
  ///
  /// Throws [FormatException] for a wrong format identifier or version, a
  /// malformed structure, an empty stroke, or a non-finite coordinate or a
  /// weight outside 0.05-1 (the same range as
  /// `CanvasController._clampWeight`). The caller reports the exception
  /// without replacing the current document.
  factory CanvasDocument.fromJson(Object? value, {String Function()? newId}) {
    if (value is! Map<String, dynamic> ||
        value['format'] != formatIdentifier ||
        value['version'] != formatVersion) {
      throw const FormatException('Unsupported Painter document format.');
    }

    final rawStrokes = value['strokes'];
    if (rawStrokes is! List) {
      throw const FormatException('Painter document strokes must be a list.');
    }

    final strokes = <List<CanvasPoint>>[];
    for (final rawStroke in rawStrokes) {
      if (rawStroke is! List) {
        throw const FormatException('Each Painter stroke must be a list.');
      }
      final points = <CanvasPoint>[];
      for (final rawPoint in rawStroke) {
        if (rawPoint is! Map<String, dynamic>) {
          throw const FormatException('Each Painter point must be an object.');
        }
        final x = rawPoint['x'];
        final y = rawPoint['y'];
        final weight = rawPoint['weight'];
        if (x is! num ||
            y is! num ||
            weight is! num ||
            !x.isFinite ||
            !y.isFinite ||
            !weight.isFinite ||
            weight < 0.05 ||
            weight > 1) {
          throw const FormatException(
            'Painter point coordinates or weight are invalid.',
          );
        }
        points.add(
          CanvasPoint(
            position: Offset(x.toDouble(), y.toDouble()),
            weight: weight.toDouble(),
          ),
        );
      }
      if (points.isEmpty) {
        throw const FormatException('Painter strokes cannot be empty.');
      }
      strokes.add(points);
    }

    final ids = newId ?? ActorIdSource.random().next;
    final document = CanvasDocument.empty();
    for (var i = 0; i < strokes.length; i++) {
      document.insert(
        CanvasStroke(
          strokes[i],
          id: ids(),
          seed: i + 1,
          z: i + 1,
          gesture: ids(),
        ),
      );
    }
    return document;
  }
}

/// Owns the document and shared active chunk; completed chunks from a pointer
/// gesture are inserted on top of the document. Each Canvas pane has a
/// separate `CanvasViewportController`. Notifies after every document or
/// chunk change it makes.
///
/// Coupled to `CanvasView`, which turns pointer events into calls to
/// [beginStroke]/[extendStroke]/[endStroke], and `_CanvasPainter`, which reads
/// [document], [activePoints] and [activeStrokeId]. See the overview at the
/// top of this file.
class CanvasController extends ChangeNotifier {
  /// [newId] produces the `<actorHex>:<counter>` ids of new strokes and
  /// gestures; by default a new random actor's [ActorIdSource].
  /// `ContentDocument.attach` (../document/content_document.dart) replaces it
  /// with the content document's `newId` through [replaceDocument].
  CanvasController({String Function()? newId})
    : _newId = newId ?? ActorIdSource.random().next;

  /// Prototype brush diameter in document units (equal to logical pixels at
  /// the default view in a 1024-pixel pane). `PencilSplats` derives its disc
  /// radius and `PencilSplats.inkMargin` from it, so changing it changes both.
  static const double brushDiameter = 8;

  /// Maximum accumulated document-space path length in a live chunk. Longer
  /// pointer segments are interpolated and committed through `TileCache`.
  static const double activeStrokeChunkLength = 64;

  /// Maximum sampled points in a live chunk, bounding repeated zero-distance
  /// pointer events as well as the geometric chunk length above.
  static const int activeStrokeChunkPoints = 64;

  String Function() _newId;
  CanvasDocument _document = CanvasDocument.empty();
  List<CanvasPoint> _activePoints = [];
  List<CanvasPoint> _activeView = const [];
  double _activeLength = 0;
  String? _activeId;
  String? _gestureId;
  final List<CanvasStroke> _gestureStrokes = [];

  /// Called by [endStroke] with every stroke the finished pointer gesture
  /// added (one per committed chunk, bottom first), before listeners are
  /// notified. `EditHistory` (../document/undo_history.dart) sets it to
  /// record one edit per gesture (docs/decisions/012-undo-per-participant.md
  /// PNT-A0018-01).
  void Function(List<CanvasStroke> strokes)? onGestureCompleted;

  CanvasDocument get document => _document;

  /// The current bounded chunk's points. The read-only view grows until a
  /// chunk is committed to the document, then a new view starts at its
  /// endpoint.
  List<CanvasPoint> get activePoints => _activeView;

  /// The id the current active chunk will be committed under, or null when
  /// no pointer gesture is drawing. `TiledRenderer` draws the live chunk with
  /// `strokeSeedOf` of this id, the seed it keeps on commit.
  String? get activeStrokeId => _activeId;

  /// True from [beginStroke] until [endStroke]: a pointer gesture is drawing.
  /// Undo and redo do nothing meanwhile (UNDO-4).
  bool get strokeInProgress => _gestureId != null;

  void _setActive(List<CanvasPoint> points) {
    _activePoints = points;
    _activeView = UnmodifiableListView(points);
  }

  /// Replaces the shared document and clears any in-progress stroke. Used when
  /// a content document is attached (`ContentDocument.attach` in
  /// ../document/content_document.dart). [newId], when given, becomes the id
  /// source of new strokes and gestures, so their ids embed the new
  /// document's actor. `TileCache.attach` sees the new instance and discards
  /// every tile.
  void replaceDocument(CanvasDocument document, {String Function()? newId}) {
    _document = document;
    if (newId != null) _newId = newId;
    _clearActive();
    notifyListeners();
  }

  /// Starts a new pointer gesture and its first active chunk at
  /// document-space [position]; [weight] is clamped to 0.05-1. Called on
  /// pointer-down by `CanvasView._onPointerDown`.
  void beginStroke(Offset position, double weight) {
    _gestureId = _newId();
    _activeId = _newId();
    _setActive([CanvasPoint(position: position, weight: _clampWeight(weight))]);
    _activeLength = 0;
    notifyListeners();
  }

  /// Appends [position] to the active chunk, committing full chunks as
  /// immutable document strokes so the tile cache can rasterize them during a
  /// long pointer gesture. Long input segments are interpolated at chunk
  /// boundaries. The active list is mutated in place between chunk commits, so
  /// `SplatStream.extend` consumes only newly appended points.
  void extendStroke(Offset position, double weight) {
    if (_activePoints.isEmpty) return;
    final target = CanvasPoint(
      position: position,
      weight: _clampWeight(weight),
    );
    var from = _activePoints.last;
    while (true) {
      if (_activePoints.length >= activeStrokeChunkPoints ||
          _activeLength >= activeStrokeChunkLength) {
        _rollOver(from);
      }

      final delta = target.position - from.position;
      final distance = delta.distance;
      if (distance == 0) {
        _activePoints.add(target);
        break;
      }

      final remaining = activeStrokeChunkLength - _activeLength;
      final step = distance < remaining ? distance : remaining;
      final ratio = step / distance;
      final next = CanvasPoint(
        position: from.position + delta * ratio,
        weight: from.weight + (target.weight - from.weight) * ratio,
      );
      _activePoints.add(next);
      _activeLength += step;
      from = next;
      if (step == distance) break;

      _rollOver(from);
    }
    notifyListeners();
  }

  /// Commits the final active chunk to the document, then clears it and
  /// reports the gesture's strokes to [onGestureCompleted]. Earlier chunks
  /// from the same pointer gesture are already in the document. Called from
  /// `CanvasView._finishPointer`.
  void endStroke() {
    if (_activePoints.isEmpty) return;
    _commitActiveChunk();
    final strokes = List<CanvasStroke>.unmodifiable(_gestureStrokes);
    _clearActive();
    onGestureCompleted?.call(strokes);
    notifyListeners();
  }

  /// Removes the strokes with [ids] from the document and returns them, in
  /// the order of [ids]; ids not in the document are skipped. Notifies once
  /// when anything was removed. For undo, which keeps the returned strokes
  /// to put back with [insertStrokes]
  /// (docs/decisions/012-undo-per-participant.md PNT-A0018-02).
  List<CanvasStroke> removeStrokes(Iterable<String> ids) {
    final removed = <CanvasStroke>[for (final id in ids) ?_document.remove(id)];
    if (removed.isNotEmpty) notifyListeners();
    return removed;
  }

  /// Puts [strokes] back into the document at their (z, id) positions, with
  /// their original ids, seeds and z, then notifies once. For redo; see
  /// [removeStrokes]. Throws [ArgumentError] when an id is already present.
  void insertStrokes(Iterable<CanvasStroke> strokes) {
    var any = false;
    for (final stroke in strokes) {
      _document.insert(stroke);
      any = true;
    }
    if (any) notifyListeners();
  }

  /// Commits the full active chunk and starts the next one at [from], the
  /// shared endpoint, under a new id in the same gesture.
  void _rollOver(CanvasPoint from) {
    _commitActiveChunk();
    _activeId = _newId();
    _setActive([from]);
    _activeLength = 0;
  }

  /// Inserts the active chunk on top of the document under [activeStrokeId],
  /// seeded from that id (docs/decisions/008-document-file-format.md
  /// PNT-A0014-05, PNT-A0014-06).
  void _commitActiveChunk() {
    final id = _activeId!;
    final stroke = CanvasStroke(
      _activePoints,
      id: id,
      seed: strokeSeedOf(id),
      z: _document.nextZ,
      gesture: _gestureId!,
    );
    _document.insert(stroke);
    _gestureStrokes.add(stroke);
  }

  void _clearActive() {
    _setActive([]);
    _activeLength = 0;
    _activeId = null;
    _gestureId = null;
    _gestureStrokes.clear();
  }

  double _clampWeight(double weight) => weight.clamp(0.05, 1).toDouble();
}
