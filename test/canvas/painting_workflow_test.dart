// What: One end-to-end widget test through the real PainterApp: launch to the
//   canvas, draw a mouse stroke (weight 1.0) and a stylus stroke (pressure
//   weights), then pan, zoom about the pointer, and rotate with the mouse.
// Why: T-004 acceptance (docs/project-brief.md "First Painting Workflow" and
//   its acceptance scenarios; docs/status.md "T-004 Verification"). It
//   combines the interactions that canvas_view_test.dart checks one by one,
//   but through the full app shell so the AppBar and layout in lib/main.dart
//   are present. Pointer input is synthetic (mouse and stylus events), so
//   physical stylus hardware and raster output are not verified, as noted in
//   docs/status.md.
// Covers: lib/main.dart (PainterApp), lib/canvas/canvas_view.dart (CanvasView
//   input handling), lib/canvas/canvas_controller.dart (CanvasController).

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:painter/canvas/canvas_view.dart';
import 'package:painter/main.dart';

void main() {
  // All positions are computed relative to the canvas's actual on-screen
  // offset (topLeft), not the window origin: docs/status.md (T-005) records
  // that an earlier version assumed the canvas started at the window origin
  // and broke once the Open/Save AppBar was added above it. The stylus
  // events are hand-built so pressure can be set; 0.2 / 0.8 map to weights
  // 0.24 / 0.81 (see CanvasView._weightFor).
  testWidgets('paint and navigate the macOS canvas', (tester) async {
    await tester.pumpWidget(const PainterApp());

    expect(
      find.descendant(
        of: find.byType(CanvasView),
        matching: find.bySemanticsLabel('Canvas'),
      ),
      findsOneWidget,
    );
    final canvasFinder = find.byType(CanvasView);
    final controller = tester.widget<CanvasView>(canvasFinder).controller;
    final size = tester.getSize(canvasFinder);
    final topLeft = tester.getTopLeft(canvasFinder);
    final center = topLeft + Offset(size.width / 2, size.height / 2);

    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    final start = center - const Offset(30, 20);
    await tester.sendEventToBinding(
      mouse.down(start, buttons: kPrimaryMouseButton),
    );
    await tester.sendEventToBinding(
      mouse.move(start + const Offset(20, 10), buttons: kPrimaryMouseButton),
    );
    await tester.sendEventToBinding(mouse.up());
    await tester.pump();

    final mouseStroke = controller.document.strokes.single;
    expect(mouseStroke.points, hasLength(2));
    expect(mouseStroke.points.map((point) => point.weight), everyElement(1));

    await tester.sendEventToBinding(
      PointerDownEvent(
        pointer: 2,
        kind: PointerDeviceKind.stylus,
        position: topLeft + const Offset(200, 200),
        buttons: kPrimaryButton,
        pressure: 0.2,
        pressureMin: 0,
        pressureMax: 1,
      ),
    );
    await tester.sendEventToBinding(
      PointerMoveEvent(
        pointer: 2,
        kind: PointerDeviceKind.stylus,
        position: topLeft + const Offset(220, 210),
        delta: const Offset(20, 10),
        buttons: kPrimaryButton,
        pressure: 0.8,
        pressureMin: 0,
        pressureMax: 1,
      ),
    );
    await tester.sendEventToBinding(
      PointerUpEvent(
        pointer: 2,
        kind: PointerDeviceKind.stylus,
        position: topLeft + const Offset(220, 210),
      ),
    );
    await tester.pump();

    final stylusStroke = controller.document.strokes.last;
    expect(stylusStroke.points.first.weight, closeTo(0.24, 0.001));
    expect(stylusStroke.points.last.weight, closeTo(0.81, 0.001));

    final panMouse = TestPointer(3, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      panMouse.down(center, buttons: kSecondaryMouseButton),
    );
    await tester.sendEventToBinding(
      panMouse.move(
        center + const Offset(12, 7),
        buttons: kSecondaryMouseButton,
      ),
    );
    await tester.sendEventToBinding(panMouse.up());
    expect(controller.pan, const Offset(12, 7));

    final zoomAnchor = center + const Offset(60, -40);
    final localZoomAnchor = zoomAnchor - topLeft;
    final documentAnchor = controller.toDocument(localZoomAnchor, size);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: zoomAnchor,
        kind: PointerDeviceKind.mouse,
        scrollDelta: const Offset(0, -100),
      ),
    );
    expect(controller.zoom, greaterThan(1));
    final zoomedAnchor = controller.toScreen(documentAnchor, size);
    expect(zoomedAnchor.dx, closeTo(localZoomAnchor.dx, 0.001));
    expect(zoomedAnchor.dy, closeTo(localZoomAnchor.dy, 0.001));

    final rotateMouse = TestPointer(5, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      rotateMouse.down(center, buttons: kMiddleMouseButton),
    );
    await tester.sendEventToBinding(
      rotateMouse.move(
        center + const Offset(50, 0),
        buttons: kMiddleMouseButton,
      ),
    );
    await tester.sendEventToBinding(rotateMouse.up());
    expect(controller.rotation, closeTo(0.5, 0.001));
  });
}
