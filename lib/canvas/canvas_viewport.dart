// What: CanvasViewportController, one Canvas pane's view of the shared canvas:
//   the document point at the pane center, the extent across the pane's
//   shorter side, and the rotation, plus the screen <-> document mapping and
//   the pan, zoom and rotate interactions.
// Why: A view is Per-mode state of its pane (docs/spec/canvas.md CNVS-6) and
//   is stored relative to the pane, not in pixels, so one stored view frames
//   the same region in panes of any size (CNVS-7, CNVS-8,
//   docs/decisions/011-relative-canvas-view.md). It is separate from
//   canvas_controller.dart because the document is shared by every pane while
//   each pane owns its own view.
// Coupled to: canvas_view.dart (input calls the interactions; `_CanvasPainter`
//   applies the same forward transform as [CanvasViewportController.toScreen]),
//   tiled_renderer.dart (level of detail from the pixel zoom),
//   ../workspace/workspace.dart (stores the view in a workspace section) and
//   ../debug/canvas_debug_pane.dart (shows and resets it).

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Owns the view of the shared canvas for exactly one pane.
///
/// The view is [center] (the document point at the pane center), [extent]
/// (document units across the pane's shorter side) and [rotation] (radians,
/// clockwise on screen). None of them depends on the pane's size; the pixel
/// zoom does: [zoomFor] is the shorter side in logical pixels divided by
/// [extent]. Every conversion and interaction therefore takes the pane size,
/// and resizing a pane changes no state here, so the same document point
/// stays at the center and the same extent spans the shorter side (CNVS-8).
///
/// Screen point `s` maps to document point
/// `center + R(-rotation)(s - paneCenter) / zoom`
/// (docs/decisions/011-relative-canvas-view.md PNT-A0017-02).
class CanvasViewportController extends ChangeNotifier {
  /// Smallest and largest [extent] in document units (CNVS-9). On a
  /// 1024-pixel shorter side they are the earlier zoom limits 16 and 0.1,
  /// which `TileGrid`'s levels (`minLevel`..`maxLevel`) were sized to span.
  static const double minimumExtent = 64;
  static const double maximumExtent = 10240;

  /// The default view (PNT-A0017-04): a document drawn under the earlier
  /// default view appears about where it did in a pane near 1024 pixels.
  static const Offset defaultCenter = Offset(512, 512);
  static const double defaultExtent = 1024;

  Offset _center = defaultCenter;
  double _extent = defaultExtent;
  double _rotation = 0;

  /// The document point shown at the pane center.
  Offset get center => _center;

  /// Document units across the pane's shorter side.
  double get extent => _extent;

  /// Rotation in radians, clockwise on screen.
  double get rotation => _rotation;

  /// Pixels per document unit in a pane of [paneSize]: its shorter side
  /// divided by [extent]. Zero for an empty pane (before layout).
  double zoomFor(Size paneSize) => paneSize.shortestSide / _extent;

  /// Returns this pane's center, extent, and rotation to their defaults.
  void resetViewport() {
    _center = defaultCenter;
    _extent = defaultExtent;
    _rotation = 0;
    notifyListeners();
  }

  /// Sets center, extent, and rotation together. [extent] is clamped to
  /// [minimumExtent]..[maximumExtent] like every other extent change.
  void setView({
    required Offset center,
    required double extent,
    required double rotation,
  }) {
    _center = center;
    _extent = _clampExtent(extent);
    _rotation = rotation;
    notifyListeners();
  }

  /// Returns an independent controller holding this view, so a copied pane
  /// starts where this one is without later gestures affecting both.
  CanvasViewportController copy() =>
      CanvasViewportController()
        ..setView(center: _center, extent: _extent, rotation: _rotation);

  /// The view as a Canvas state in a workspace section
  /// (docs/decisions/009-shared-workspaces.md PNT-A0015-07).
  Map<String, Object?> toJson() => {
    'center': {'x': _center.dx, 'y': _center.dy},
    'extent': _extent,
    'rotation': _rotation,
  };

  /// Parses a view written by [toJson]; null when any field is missing or
  /// non-finite, or the extent is outside [minimumExtent]..[maximumExtent].
  static CanvasViewportController? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final center = value['center'];
    final extent = value['extent'];
    final rotation = value['rotation'];
    if (center is! Map<String, dynamic>) return null;
    final x = center['x'];
    final y = center['y'];
    if (x is! num || y is! num || extent is! num || rotation is! num) {
      return null;
    }
    if (!x.isFinite || !y.isFinite || !extent.isFinite || !rotation.isFinite) {
      return null;
    }
    if (extent < minimumExtent || extent > maximumExtent) return null;
    return CanvasViewportController()..setView(
      center: Offset(x.toDouble(), y.toDouble()),
      extent: extent.toDouble(),
      rotation: rotation.toDouble(),
    );
  }

  /// Maps pane-local [screenPosition] in a pane of [paneSize] to document
  /// space. Returns [center] for an empty pane, which has no mapping.
  Offset toDocument(Offset screenPosition, Size paneSize) {
    final zoom = zoomFor(paneSize);
    if (zoom == 0) return _center;
    final fromPaneCenter = screenPosition - paneSize.center(Offset.zero);
    return _center + _rotate(fromPaneCenter, -_rotation) / zoom;
  }

  /// Maps a document position to pane-local screen space in a pane of
  /// [paneSize]; the inverse of [toDocument].
  Offset toScreen(Offset documentPosition, Size paneSize) {
    final fromCenter = (documentPosition - _center) * zoomFor(paneSize);
    return paneSize.center(Offset.zero) + _rotate(fromCenter, _rotation);
  }

  /// Moves the content by [delta] screen pixels in a pane of [paneSize], so
  /// the document point under a dragging pointer follows it.
  void panBy(Offset delta, Size paneSize) {
    final zoom = zoomFor(paneSize);
    if (zoom == 0) return;
    _center -= _rotate(delta, -_rotation) / zoom;
    notifyListeners();
  }

  /// Zooms by [factor] about [screenPosition] (a factor above 1 shows less
  /// document, so [extent] is divided by it), keeping the document point
  /// under it fixed while clamping [extent].
  void zoomAt(Offset screenPosition, Size paneSize, double factor) {
    if (zoomFor(paneSize) == 0) return;
    final anchor = toDocument(screenPosition, paneSize);
    _extent = _clampExtent(_extent / factor);
    _anchor(anchor, screenPosition, paneSize);
    notifyListeners();
  }

  /// Rotates by [delta] radians about [screenPosition], keeping the document
  /// point under it fixed.
  void rotateAt(Offset screenPosition, Size paneSize, double delta) {
    if (zoomFor(paneSize) == 0) return;
    final anchor = toDocument(screenPosition, paneSize);
    _rotation += delta;
    _anchor(anchor, screenPosition, paneSize);
    notifyListeners();
  }

  /// Moves [center] so that [documentPosition] maps to [screenPosition] under
  /// the current extent and rotation; shared by [zoomAt] and [rotateAt].
  void _anchor(Offset documentPosition, Offset screenPosition, Size paneSize) {
    final fromPaneCenter = screenPosition - paneSize.center(Offset.zero);
    _center =
        documentPosition -
        _rotate(fromPaneCenter, -_rotation) / zoomFor(paneSize);
  }

  static double _clampExtent(double extent) =>
      extent.clamp(minimumExtent, maximumExtent).toDouble();

  static Offset _rotate(Offset point, double radians) {
    final cosine = math.cos(radians);
    final sine = math.sin(radians);
    return Offset(
      point.dx * cosine - point.dy * sine,
      point.dx * sine + point.dy * cosine,
    );
  }
}
