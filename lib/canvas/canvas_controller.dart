import 'dart:math' as math;

import 'package:flutter/material.dart';

@immutable
class CanvasPoint {
  const CanvasPoint({required this.position, required this.weight});

  final Offset position;
  final double weight;
}

@immutable
class CanvasStroke {
  CanvasStroke(Iterable<CanvasPoint> points)
    : points = List<CanvasPoint>.unmodifiable(points);

  final List<CanvasPoint> points;
}

class CanvasDocument {
  CanvasDocument.empty();

  final List<CanvasStroke> _strokes = [];

  Iterable<CanvasStroke> get strokes => _strokes;

  void _addStroke(CanvasStroke stroke) => _strokes.add(stroke);
}

class CanvasController extends ChangeNotifier {
  static const double brushDiameter = 8;
  static const double minimumZoom = 0.1;
  static const double maximumZoom = 16;

  final CanvasDocument _document = CanvasDocument.empty();
  List<CanvasPoint> _activePoints = [];
  Offset _pan = Offset.zero;
  double _zoom = 1;
  double _rotation = 0;

  CanvasDocument get document => _document;
  Iterable<CanvasPoint> get activePoints => _activePoints;
  Offset get pan => _pan;
  double get zoom => _zoom;
  double get rotation => _rotation;

  void beginStroke(Offset position, double weight) {
    _activePoints = [
      CanvasPoint(position: position, weight: _clampWeight(weight)),
    ];
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
    _document._addStroke(CanvasStroke(_activePoints));
    _activePoints = [];
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
