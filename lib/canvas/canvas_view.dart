import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'canvas_controller.dart';

class CanvasView extends StatefulWidget {
  const CanvasView({super.key, required this.controller});

  final CanvasController controller;

  @override
  State<CanvasView> createState() => _CanvasViewState();
}

enum _Interaction { draw, pan, rotate }

class _CanvasViewState extends State<CanvasView> {
  final Map<int, _PointerInteraction> _interactions = {};
  final GlobalKey _surfaceKey = GlobalKey();

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
        onPointerSignal: _onPointerSignal,
        child: CustomPaint(
          painter: _CanvasPainter(widget.controller),
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

class _CanvasPainter extends CustomPainter {
  _CanvasPainter(CanvasController controller)
    : controller = controller,
      super(repaint: controller);

  final CanvasController controller;

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

    final linePaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final pointPaint = Paint()..color = Colors.black;
    for (final stroke in controller.document.strokes) {
      _paintPoints(canvas, stroke.points, linePaint, pointPaint);
    }
    _paintPoints(canvas, controller.activePoints, linePaint, pointPaint);
    canvas.restore();
  }

  void _paintPoints(
    Canvas canvas,
    Iterable<CanvasPoint> points,
    Paint linePaint,
    Paint pointPaint,
  ) {
    CanvasPoint? previous;
    for (final point in points) {
      if (previous != null) {
        linePaint.strokeWidth =
            CanvasController.brushDiameter *
            (previous.weight + point.weight) /
            2;
        canvas.drawLine(previous.position, point.position, linePaint);
      }
      canvas.drawCircle(
        point.position,
        CanvasController.brushDiameter * point.weight / 2,
        pointPaint,
      );
      previous = point;
    }
  }

  @override
  bool shouldRepaint(_CanvasPainter oldDelegate) =>
      oldDelegate.controller != controller;
}
