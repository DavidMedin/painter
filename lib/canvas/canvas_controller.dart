// What: The canvas state model. `CanvasPoint`/`CanvasStroke`/`CanvasDocument`
// hold the saved content (including its JSON format), and `CanvasController`
// holds everything transient: viewport pan/zoom/rotation, the in-progress
// stroke, and the screen <-> document coordinate transforms.
//
// Why: One place owns every mutation of canvas state, so input code
// (canvas_view.dart), rendering (tiled_renderer.dart, tile_cache.dart) and
// file I/O (../main.dart) all share one source of truth and none of them
// mutates the model directly. It imports only Flutter geometry types, so it
// has no dependency on rendering or input code; the splat generator
// (pencil_splats.dart) and worker (splat_worker.dart) depend on it, not the
// reverse.

import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Canvas state model (overview)
//
// What: Three kinds of state, kept deliberately apart.
//   1. Document (`CanvasDocument`): an ordered, append-only list of immutable
//      `CanvasStroke`s, each a list of `CanvasPoint`s (document-space
//      position + brush weight). This is the only thing that is saved.
//   2. Viewport (`CanvasController.pan/zoom/rotation`): how the document is
//      looked at. Never saved, never part of the document; opening a file
//      resets it (`replaceDocument`), and `resetViewport` resets it alone.
//   3. Active stroke (`CanvasController.activePoints`): the stroke being drawn
//      right now. It is not in the document until `endStroke` commits it.
//
// Why this split: document coordinates must not depend on the viewport
// (ADR 0001), so panning, zooming and rotating never touch the document and
// the tile cache (tile_cache.dart) stays valid across them. Keeping the
// active stroke out of the document means the document only ever grows by
// whole strokes, which is what lets `TileCache` track "strokes [0, n) are
// already drawn into this tile" (`CachedTile.appliedStrokes`).
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
// (ADR 0005). The active stroke borrows `CanvasDocument.nextSeed`, so its
// grain does not change when `endStroke` commits it. Deleting or reordering
// strokes, if ever added, would change seeds and would need a persisted id.
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
  /// is 1). `CanvasController.endStroke` uses it for the committed stroke and
  /// `TiledRenderer._paintActive` uses it for the in-progress stroke; they must
  /// agree so the grain is identical before and after pointer-up.
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

/// Owns the document, the viewport and the active stroke, and is the only
/// code that mutates them. Notifies listeners after every change.
///
/// Coupled to `CanvasView`, which turns pointer events into calls to
/// [beginStroke]/[extendStroke]/[endStroke], [panBy], [zoomAt] and [rotateAt],
/// and to `_CanvasPainter`, which applies the same viewport transform that
/// [toScreen]/[toDocument] describe. See the overview at the top of this
/// file.
class CanvasController extends ChangeNotifier {
  /// Prototype brush diameter in document units (equal to logical pixels at
  /// the default viewport). `PencilSplats` derives its disc radius and
  /// `PencilSplats.inkMargin` from it, so changing it changes both.
  static const double brushDiameter = 8;

  /// Prototype zoom limits (ADR 0001). The tile levels in `TileGrid`
  /// (`minLevel`..`maxLevel`) are sized to span this range.
  static const double minimumZoom = 0.1;
  static const double maximumZoom = 16;

  CanvasDocument _document = CanvasDocument.empty();
  List<CanvasPoint> _activePoints = [];
  List<CanvasPoint> _activeView = const [];
  Offset _pan = Offset.zero;
  double _zoom = 1;
  double _rotation = 0;

  CanvasDocument get document => _document;

  /// The in-progress stroke's points. The same read-only view instance is
  /// returned (and grows) for the whole stroke; a new stroke yields a new one.
  List<CanvasPoint> get activePoints => _activeView;

  Offset get pan => _pan;
  double get zoom => _zoom;
  double get rotation => _rotation;

  void _setActive(List<CanvasPoint> points) {
    _activePoints = points;
    _activeView = UnmodifiableListView(points);
  }

  /// Replaces the current document, clearing any in-progress stroke and
  /// resetting the viewport. Used when opening a file (`_PainterAppState` in
  /// main.dart). `TileCache.attach` sees the new instance and discards every
  /// tile.
  void replaceDocument(CanvasDocument document) {
    _document = document;
    _setActive([]);
    _pan = Offset.zero;
    _zoom = 1;
    _rotation = 0;
    notifyListeners();
  }

  /// Returns pan, zoom, and rotation to their defaults, keeping the document.
  void resetViewport() {
    _pan = Offset.zero;
    _zoom = 1;
    _rotation = 0;
    notifyListeners();
  }

  /// Starts a new active stroke at document-space [position]; [weight] is
  /// clamped to 0.05-1. Called on pointer-down by `CanvasView._onPointerDown`.
  void beginStroke(Offset position, double weight) {
    _setActive([CanvasPoint(position: position, weight: _clampWeight(weight))]);
    notifyListeners();
  }

  /// Appends a point to the active stroke; a no-op when no stroke is active.
  /// The active list is mutated in place and [activePoints] is a live view of
  /// it, so `SplatStream.extend` can consume only the new tail.
  void extendStroke(Offset position, double weight) {
    if (_activePoints.isEmpty) return;
    _activePoints.add(
      CanvasPoint(position: position, weight: _clampWeight(weight)),
    );
    notifyListeners();
  }

  /// Commits the active stroke to the document with seed
  /// `CanvasDocument.nextSeed`, then clears the active stroke. Called from
  /// `CanvasView._finishPointer`.
  void endStroke() {
    if (_activePoints.isEmpty) return;
    _document._addStroke(CanvasStroke(_activePoints, seed: _document.nextSeed));
    _setActive([]);
    notifyListeners();
  }

  /// Maps a screen (widget-local) position to document space by undoing the
  /// viewport transform: remove pan, rotate by `-rotation` and divide by zoom,
  /// both about the viewport centre. The inverse of [toScreen], and the same
  /// transform `_CanvasPainter.paint` applies to the canvas.
  Offset toDocument(Offset screenPosition, Size viewportSize) {
    final center = Offset(viewportSize.width / 2, viewportSize.height / 2);
    final centered = screenPosition - center - _pan;
    return _rotate(centered, -_rotation) / _zoom + center;
  }

  /// Pans by [delta] screen pixels. Pan is applied after rotation and zoom, so
  /// it is always in screen space.
  void panBy(Offset delta) {
    _pan += delta;
    notifyListeners();
  }

  /// Multiplies zoom by [factor] (clamped to [minimumZoom]..[maximumZoom]) and
  /// adjusts pan so the document point under [screenPosition] stays under it.
  /// Used for wheel zoom (`CanvasView._onPointerSignal`) and trackpad pinch
  /// (`CanvasView._onPanZoomUpdate`).
  void zoomAt(Offset screenPosition, Size viewportSize, double factor) {
    final documentPosition = toDocument(screenPosition, viewportSize);
    _zoom = (_zoom * factor).clamp(minimumZoom, maximumZoom).toDouble();
    _pan += screenPosition - toScreen(documentPosition, viewportSize);
    notifyListeners();
  }

  /// Rotates by [delta] radians about the document point under
  /// [screenPosition], compensating pan so that point stays put. Used for
  /// middle-drag rotate (`CanvasView._onPointerMove`) and trackpad twist
  /// (`CanvasView._onPanZoomUpdate`).
  void rotateAt(Offset screenPosition, Size viewportSize, double delta) {
    final documentPosition = toDocument(screenPosition, viewportSize);
    _rotation += delta;
    _pan += screenPosition - toScreen(documentPosition, viewportSize);
    notifyListeners();
  }

  /// Maps a document-space position to screen space; the inverse of
  /// [toDocument].
  Offset toScreen(Offset documentPosition, Size viewportSize) {
    final center = Offset(viewportSize.width / 2, viewportSize.height / 2);
    final centered = (documentPosition - center) * _zoom;
    return _rotate(centered, _rotation) + center + _pan;
  }

  double _clampWeight(double weight) => weight.clamp(0.05, 1).toDouble();

  Offset _rotate(Offset point, double radians) {
    final cosine = math.cos(radians);
    final sine = math.sin(radians);
    return Offset(
      point.dx * cosine - point.dy * sine,
      point.dx * sine + point.dy * cosine,
    );
  }
}
