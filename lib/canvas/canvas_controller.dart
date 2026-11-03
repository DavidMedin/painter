import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';

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

class CanvasDocument {
  CanvasDocument.empty() : _strokes = [];

  CanvasDocument._(this._strokes);

  final List<CanvasStroke> _strokes;

  Iterable<CanvasStroke> get strokes => _strokes;

  int get strokeCount => _strokes.length;

  CanvasStroke strokeAt(int index) => _strokes[index];

  void _addStroke(CanvasStroke stroke) => _strokes.add(stroke);

  /// Seed the next appended stroke will receive.
  int get nextSeed => _strokes.length + 1;

  /// Format identifier stored in saved documents.
  static const String formatIdentifier = 'painter-document';

  /// Current saved-document format version.
  static const int formatVersion = 1;

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

class CanvasController extends ChangeNotifier {
  static const double brushDiameter = 8;
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
  /// resetting the viewport. Used when opening a file.
  void replaceDocument(CanvasDocument document) {
    _document = document;
    _setActive([]);
    _pan = Offset.zero;
    _zoom = 1;
    _rotation = 0;
    notifyListeners();
  }

  void beginStroke(Offset position, double weight) {
    _setActive([CanvasPoint(position: position, weight: _clampWeight(weight))]);
    notifyListeners();
  }

  void extendStroke(Offset position, double weight) {
    if (_activePoints.isEmpty) return;
    _activePoints.add(
      CanvasPoint(position: position, weight: _clampWeight(weight)),
    );
    notifyListeners();
  }

  void endStroke() {
    if (_activePoints.isEmpty) return;
    _document._addStroke(CanvasStroke(_activePoints, seed: _document.nextSeed));
    _setActive([]);
    notifyListeners();
  }

  Offset toDocument(Offset screenPosition, Size viewportSize) {
    final center = Offset(viewportSize.width / 2, viewportSize.height / 2);
    final centered = screenPosition - center - _pan;
    return _rotate(centered, -_rotation) / _zoom + center;
  }

  void panBy(Offset delta) {
    _pan += delta;
    notifyListeners();
  }

  void zoomAt(Offset screenPosition, Size viewportSize, double factor) {
    final documentPosition = toDocument(screenPosition, viewportSize);
    _zoom = (_zoom * factor).clamp(minimumZoom, maximumZoom).toDouble();
    _pan += screenPosition - toScreen(documentPosition, viewportSize);
    notifyListeners();
  }

  void rotateAt(Offset screenPosition, Size viewportSize, double delta) {
    final documentPosition = toDocument(screenPosition, viewportSize);
    _rotation += delta;
    _pan += screenPosition - toScreen(documentPosition, viewportSize);
    notifyListeners();
  }

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
