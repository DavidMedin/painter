// What: The shared canvas document and active-stroke model, plus
//   CanvasViewportController for one pane's transient pan/zoom/rotation.
// Why: Document content is shared by every Canvas pane, while view transforms
//   belong to one pane. This model stays independent from input and rendering.
// Coupled to: canvas_view.dart (input and painting), tiled_renderer.dart and
//   tile_cache.dart (rendered document), main.dart (document lifecycle), and
//   pencil_splats.dart / splat_worker.dart (derived marks).

import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Canvas state model (overview)
//
// What: Two kinds of state, kept deliberately apart.
//   1. Document (`CanvasDocument`): an ordered, append-only list of immutable
//      `CanvasStroke`s, each a list of `CanvasPoint`s (document-space
//      position + brush weight). This is the only thing that is saved.
//   2. Active chunk (`CanvasController.activePoints`): the bounded tail of the
//      pointer gesture being drawn right now. Completed chunks are appended to
//      the shared document as immutable strokes, allowing TileCache to
//      rasterize the trail while the latest chunk remains live.
//
// Each Canvas pane owns a `CanvasViewportController` for its view. It maps
// between widget-local and document coordinates without changing shared
// strokes, so panning or zooming one pane cannot move another. Viewport state
// is transient and is not part of the saved document.
//
// Why this split: document coordinates must not depend on the viewport
// (ADR 0001), so panning, zooming and rotating never touch the document and
// the tile cache (tile_cache.dart) stays valid across them. Bounded chunks let
// TileCache advance its per-tile `CachedTile.appliedStrokes` count while a
// pointer gesture continues, instead of keeping its entire splat batch live.
//
// Why strokes are immutable: tiles, splat buffers (`SplatWorker`) and
// bounds are derived from a stroke once and reused for the session. A stroke
// that could change would silently invalidate all of them.
// `CanvasStroke` copies its points into an unmodifiable list and caches
// `bounds` at construction.
//
// Seeds: a stroke's `seed` is its 1-based index in the document. Splat
// randomness is a hash of the seed (see the overview in pencil_splats.dart),
// so strokes tracing the same path still get different specks. The seed is
// not saved: `fromJson` re-derives it from stroke order, which equals the
// order they were drawn, so a saved-and-reopened document looks the same
// (ADR 0005). Active chunks borrow `CanvasDocument.nextSeed`, so each chunk's
// grain stays stable when committed. Long pointer gestures therefore consist
// of several independently seeded document strokes.
//
// Why `ChangeNotifier` and no state-management package: the whole state is
// one object with a handful of mutators; widgets and painters just listen
// (`_CanvasPainter` repaints via `Listenable.merge([controller, ...])`).
// ADR 0001 chose this to avoid a dependency while keeping mutation out of
// widget painting code.
//
// Saved format (ADR 0002): UTF-8 JSON, format identifier `painter-document`,
// integer version 1:
//   {"format": "painter-document", "version": 1,
//    "strokes": [[{"x": 1.0, "y": 2.0, "weight": 0.5}, ...], ...]}
// Only document-space points and weights are stored; splats are derived at
// paint time (ADR 0004), so no pencil-specific data is in the file. The
// identifier and version let incompatible files be rejected instead of
// misread. The file I/O itself lives in ../main.dart (`jsonEncode(toJson())`
// / `CanvasDocument.fromJson(jsonDecode(...))`) and lib/document/.
//
// Prototype values: `brushDiameter`, the weight range 0.05-1 and the zoom
// limits are prototype choices, not settled product values (ADR 0001,
// docs/architecture.md "Prototype parameters").
// ---------------------------------------------------------------------------

/// One sampled input point of a stroke: a document-space [position] and a
/// brush [weight] in 0.05-1 that scales the brush diameter.
///
/// The range is enforced in `CanvasController._clampWeight` for live input and
/// in `CanvasDocument.fromJson` for loaded files; keep the two in sync.
@immutable
class CanvasPoint {
  const CanvasPoint({required this.position, required this.weight});

  final Offset position;
  final double weight;
}

/// An immutable stroke.
///
/// [seed] differentiates the deterministic speck pattern of strokes that trace
/// the same path. It is the stroke's 1-based position in its document, so it is
/// stable for the lifetime of the document, not persisted, and re-derived when
/// a file is opened. [bounds] is the document-space rectangle that contains
/// every point; it does not include brush radius.
///
/// The constructor copies the points into an unmodifiable list and computes
/// [bounds] once. `TileCache` inflates [bounds] by `PencilSplats.inkMargin` to
/// decide which tiles a stroke touches, and `SplatWorker.generate` consumes
/// [points] and [seed] to build the stroke's splats.
@immutable
class CanvasStroke {
  CanvasStroke(Iterable<CanvasPoint> points, {this.seed = 0})
    : points = List<CanvasPoint>.unmodifiable(points) {
    bounds = _boundsOf(this.points);
  }

  final List<CanvasPoint> points;
  final int seed;

  /// Document-space rectangle containing every point (no brush radius).
  late final Rect bounds;

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

/// The saved content: an append-only list of immutable [CanvasStroke]s.
///
/// Only `CanvasController` appends (via the library-private `_addStroke`), and
/// strokes are never removed or reordered. `TileCache` relies on this: it
/// records per tile how many leading strokes are already drawn
/// (`CachedTile.appliedStrokes`) and treats a different document *instance*
/// (`TileCache.attach`) as the only way earlier strokes can change.
class CanvasDocument {
  CanvasDocument.empty() : _strokes = [];

  CanvasDocument._(this._strokes);

  final List<CanvasStroke> _strokes;

  Iterable<CanvasStroke> get strokes => _strokes;

  int get strokeCount => _strokes.length;

  CanvasStroke strokeAt(int index) => _strokes[index];

  void _addStroke(CanvasStroke stroke) => _strokes.add(stroke);

  /// Seed the next appended stroke will receive (1-based, so the first stroke
  /// is 1). `CanvasController._commitActiveChunk` uses it for the committed
  /// chunk and `TiledRenderer._paintActive` uses it for the live chunk; they
  /// agree so grain stays stable when that chunk is committed.
  int get nextSeed => _strokes.length + 1;

  /// Format identifier stored in saved documents.
  static const String formatIdentifier = 'painter-document';

  /// Current saved-document format version.
  static const int formatVersion = 1;

  /// Serializes to the `painter-document` JSON shape described in the
  /// overview above (ADR 0002). Seeds and viewport are intentionally omitted.
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
  /// Throws [FormatException] for a wrong format identifier or version, a
  /// malformed structure, an empty stroke, or a non-finite coordinate or a
  /// weight outside 0.05-1 (the same range as
  /// `CanvasController._clampWeight`). Seeds are re-derived here as
  /// `index + 1` rather than read from the file. `main.dart` reports the
  /// exception in the error dialog without replacing the current document.
  factory CanvasDocument.fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['format'] != formatIdentifier ||
        value['version'] != formatVersion) {
      throw const FormatException('Unsupported Painter document format.');
    }

    final rawStrokes = value['strokes'];
    if (rawStrokes is! List) {
      throw const FormatException('Painter document strokes must be a list.');
    }

    final strokes = <CanvasStroke>[];
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
      strokes.add(CanvasStroke(points, seed: strokes.length + 1));
    }
    return CanvasDocument._(strokes);
  }
}

/// Owns the document and shared active chunk; completed chunks from a pointer
/// gesture are appended to the document. Each Canvas pane has a separate
/// [CanvasViewportController]. Notifies after every document or chunk change.
///
/// Coupled to `CanvasView`, which turns pointer events into calls to
/// [beginStroke]/[extendStroke]/[endStroke], and `_CanvasPainter`, which reads
/// [document] and [activePoints]. See the overview at the top of this file.
class CanvasController extends ChangeNotifier {
  /// Prototype brush diameter in document units (equal to logical pixels at
  /// the default viewport). `PencilSplats` derives its disc radius and
  /// `PencilSplats.inkMargin` from it, so changing it changes both.
  static const double brushDiameter = 8;

  /// Maximum accumulated document-space path length in a live chunk. Longer
  /// pointer segments are interpolated and committed through `TileCache`.
  static const double activeStrokeChunkLength = 64;

  /// Maximum sampled points in a live chunk, bounding repeated zero-distance
  /// pointer events as well as the geometric chunk length above.
  static const int activeStrokeChunkPoints = 64;

  CanvasDocument _document = CanvasDocument.empty();
  List<CanvasPoint> _activePoints = [];
  List<CanvasPoint> _activeView = const [];
  double _activeLength = 0;

  CanvasDocument get document => _document;

  /// The current bounded chunk's points. The read-only view grows until a
  /// chunk is appended to the document, then a new view starts at its endpoint.
  List<CanvasPoint> get activePoints => _activeView;

  void _setActive(List<CanvasPoint> points) {
    _activePoints = points;
    _activeView = UnmodifiableListView(points);
  }

  /// Replaces the shared document and clears any in-progress stroke. Used when
  /// opening a file (`_PainterAppState` in main.dart); that owner resets each
  /// pane's [CanvasViewportController]. `TileCache.attach` sees the new
  /// instance and discards every tile.
  void replaceDocument(CanvasDocument document) {
    _document = document;
    _setActive([]);
    _activeLength = 0;
    notifyListeners();
  }

  /// Starts a new active chunk at document-space [position]; [weight] is
  /// clamped to 0.05-1. Called on pointer-down by `CanvasView._onPointerDown`.
  void beginStroke(Offset position, double weight) {
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
        _commitActiveChunk();
        _setActive([from]);
        _activeLength = 0;
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

      _commitActiveChunk();
      _setActive([from]);
      _activeLength = 0;
    }
    notifyListeners();
  }

  /// Commits the final active chunk to the document, then clears it. Earlier
  /// chunks from the same pointer gesture are already in the document. Called
  /// from `CanvasView._finishPointer`.
  void endStroke() {
    if (_activePoints.isEmpty) return;
    _commitActiveChunk();
    _setActive([]);
    _activeLength = 0;
    notifyListeners();
  }

  /// Appends the immutable active chunk with the next document seed.
  void _commitActiveChunk() {
    _document._addStroke(CanvasStroke(_activePoints, seed: _document.nextSeed));
  }

  double _clampWeight(double weight) => weight.clamp(0.05, 1).toDouble();
}

/// Owns the transient view of the shared canvas for exactly one pane.
///
/// Panning, zooming, rotating, and coordinate conversion use this object's
/// state only. `CanvasController` owns the shared document and active stroke;
/// every Canvas pane listens to both objects so document changes appear in all
/// views without coupling their individual view transforms.
class CanvasViewportController extends ChangeNotifier {
  /// Prototype zoom limits (ADR 0001). The tile levels in `TileGrid`
  /// (`minLevel`..`maxLevel`) are sized to span this range.
  static const double minimumZoom = 0.1;
  static const double maximumZoom = 16;

  Offset _pan = Offset.zero;
  double _zoom = 1;
  double _rotation = 0;

  Offset get pan => _pan;
  double get zoom => _zoom;
  double get rotation => _rotation;

  /// Returns this pane's pan, zoom, and rotation to their defaults.
  void resetViewport() {
    _pan = Offset.zero;
    _zoom = 1;
    _rotation = 0;
    notifyListeners();
  }

  /// Maps widget-local [screenPosition] to document space by undoing this
  /// viewport's transform about [viewportSize]'s centre.
  Offset toDocument(Offset screenPosition, Size viewportSize) {
    final center = Offset(viewportSize.width / 2, viewportSize.height / 2);
    final centered = screenPosition - center - _pan;
    return _rotate(centered, -_rotation) / _zoom + center;
  }

  /// Pans by [delta] screen pixels. Pan is applied after rotation and zoom.
  void panBy(Offset delta) {
    _pan += delta;
    notifyListeners();
  }

  /// Zooms by [factor] about [screenPosition], keeping its document point
  /// anchored while clamping to [minimumZoom]..[maximumZoom].
  void zoomAt(Offset screenPosition, Size viewportSize, double factor) {
    final documentPosition = toDocument(screenPosition, viewportSize);
    _zoom = (_zoom * factor).clamp(minimumZoom, maximumZoom).toDouble();
    _pan += screenPosition - toScreen(documentPosition, viewportSize);
    notifyListeners();
  }

  /// Rotates by [delta] radians about [screenPosition], keeping its document
  /// point anchored.
  void rotateAt(Offset screenPosition, Size viewportSize, double delta) {
    final documentPosition = toDocument(screenPosition, viewportSize);
    _rotation += delta;
    _pan += screenPosition - toScreen(documentPosition, viewportSize);
    notifyListeners();
  }

  /// Maps a document position to widget-local screen space, inverse of
  /// [toDocument].
  Offset toScreen(Offset documentPosition, Size viewportSize) {
    final center = Offset(viewportSize.width / 2, viewportSize.height / 2);
    final centered = (documentPosition - center) * _zoom;
    return _rotate(centered, _rotation) + center + _pan;
  }

  Offset _rotate(Offset point, double radians) {
    final cosine = math.cos(radians);
    final sine = math.sin(radians);
    return Offset(
      point.dx * cosine - point.dy * sine,
      point.dx * sine + point.dy * cosine,
    );
  }
}
