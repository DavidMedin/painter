import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'canvas_controller.dart';
import 'tile_grid.dart';
import 'tiled_renderer.dart';

class CanvasView extends StatefulWidget {
  const CanvasView({super.key, required this.controller});

  final CanvasController controller;

  @override
  State<CanvasView> createState() => _CanvasViewState();
}

enum _Interaction { draw, pan, rotate }

class _CanvasViewState extends State<CanvasView> {
  final Map<int, _PointerInteraction> _interactions = {};
  _TrackpadGesture? _trackpadGesture;
  final GlobalKey _surfaceKey = GlobalKey();
  final TiledRenderer _renderer = TiledRenderer();

  Size get _viewportSize {
    final renderObject = _surfaceKey.currentContext?.findRenderObject();
    return renderObject is RenderBox ? renderObject.size : Size.zero;
  }

  void _onPointerDown(PointerDownEvent event) {
    final interaction = switch (event.kind) {
      PointerDeviceKind.mouse => _mouseInteraction(event.buttons),
      PointerDeviceKind.stylus => _Interaction.draw,
      _ => null,
    };
    if (interaction == null) return;

    _interactions[event.pointer] = _PointerInteraction(
      interaction,
      event.localPosition,
    );
    if (interaction == _Interaction.draw) {
      widget.controller.beginStroke(
        widget.controller.toDocument(event.localPosition, _viewportSize),
        _weightFor(event),
      );
    }
  }

  _Interaction? _mouseInteraction(int buttons) {
    if ((buttons & kSecondaryMouseButton) != 0) return _Interaction.pan;
    if ((buttons & kMiddleMouseButton) != 0) return _Interaction.rotate;
    if ((buttons & kPrimaryMouseButton) != 0) return _Interaction.draw;
    return null;
  }

  void _onPointerMove(PointerMoveEvent event) {
    final interaction = _interactions[event.pointer];
    if (interaction == null) return;

    final delta = event.localPosition - interaction.lastPosition;
    interaction.lastPosition = event.localPosition;
    switch (interaction.mode) {
      case _Interaction.draw:
        widget.controller.extendStroke(
          widget.controller.toDocument(event.localPosition, _viewportSize),
          _weightFor(event),
        );
      case _Interaction.pan:
        widget.controller.panBy(delta);
      case _Interaction.rotate:
        widget.controller.rotateAt(
          event.localPosition,
          _viewportSize,
          delta.dx / 100,
        );
    }
  }

  double _weightFor(PointerEvent event) {
    if (event.kind == PointerDeviceKind.mouse) return 1;
    final pressureRange = event.pressureMax - event.pressureMin;
    final pressure = pressureRange > 0
        ? (event.pressure - event.pressureMin) / pressureRange
        : 1.0;
    return 0.05 + 0.95 * pressure.clamp(0, 1);
  }

  void _finishPointer(PointerEvent event) {
    final interaction = _interactions.remove(event.pointer);
    if (interaction?.mode == _Interaction.draw) {
      widget.controller.endStroke();
    }
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || event.kind != PointerDeviceKind.mouse) {
      return;
    }
    widget.controller.zoomAt(
      event.localPosition,
      _viewportSize,
      math.exp(-event.scrollDelta.dy / 500),
    );
  }

  void _onPanZoomStart(PointerPanZoomStartEvent event) {
    _trackpadGesture = _TrackpadGesture(event.localPosition);
  }

  void _onPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    final gesture = _trackpadGesture;
    if (gesture == null) return;

    if (event.panDelta != Offset.zero) {
      widget.controller.panBy(event.panDelta);
    }

    final viewportSize = _viewportSize;
    if (event.scale != gesture.lastScale) {
      widget.controller.zoomAt(
        gesture.focalPoint,
        viewportSize,
        event.scale / gesture.lastScale,
      );
      gesture.lastScale = event.scale;
    }

    if (event.rotation != gesture.lastRotation) {
      widget.controller.rotateAt(
        gesture.focalPoint,
        viewportSize,
        event.rotation - gesture.lastRotation,
      );
      gesture.lastRotation = event.rotation;
    }
  }

  void _onPanZoomEnd(PointerPanZoomEndEvent event) {
    _trackpadGesture = null;
  }

  @override
  void dispose() {
    _renderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Canvas',
      child: Listener(
        key: _surfaceKey,
        behavior: HitTestBehavior.opaque,
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _finishPointer,
        onPointerCancel: _finishPointer,
        onPointerPanZoomStart: _onPanZoomStart,
        onPointerPanZoomUpdate: _onPanZoomUpdate,
        onPointerPanZoomEnd: _onPanZoomEnd,
        onPointerSignal: _onPointerSignal,
        child: CustomPaint(
          painter: _CanvasPainter(
            widget.controller,
            _renderer,
            MediaQuery.devicePixelRatioOf(context),
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _PointerInteraction {
  _PointerInteraction(this.mode, this.lastPosition);

  final _Interaction mode;
  Offset lastPosition;
}

class _TrackpadGesture {
  _TrackpadGesture(this.focalPoint);

  final Offset focalPoint;
  double lastScale = 1;
  double lastRotation = 0;
}

class _CanvasPainter extends CustomPainter {
  _CanvasPainter(this.controller, this.renderer, this.devicePixelRatio)
    : super(repaint: Listenable.merge([controller, renderer.cache]));

  final CanvasController controller;
  final TiledRenderer renderer;
  final double devicePixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(Colors.white, BlendMode.src);
    canvas.save();
    final center = Offset(size.width / 2, size.height / 2);
    canvas.translate(controller.pan.dx, controller.pan.dy);
    canvas.translate(center.dx, center.dy);
    canvas.rotate(controller.rotation);
    canvas.scale(controller.zoom);
    canvas.translate(-center.dx, -center.dy);
    renderer.paint(
      canvas,
      document: controller.document,
      active: controller.activePoints,
      visible: TileGrid.visibleDocumentRect(
        size,
        (screen) => controller.toDocument(screen, size),
      ),
      pixelsPerUnit: controller.zoom * devicePixelRatio,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CanvasPainter oldDelegate) =>
      oldDelegate.controller != controller ||
      oldDelegate.renderer != renderer ||
      oldDelegate.devicePixelRatio != devicePixelRatio;
}
