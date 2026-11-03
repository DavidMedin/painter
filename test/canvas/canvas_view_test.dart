// What: Widget tests that feed synthetic pointer events straight into
//   CanvasView and assert on the CanvasController: a mouse stroke's
//   document-space points and fixed weight 1.0; a stylus stroke's
//   pressure-to-weight mapping; and mouse pan (secondary button), wheel zoom
//   anchored at the pointer, and middle-button rotation.
// Why: T-003 acceptance (docs/status.md "T-003 Verification"; ADR 0001 for
//   the controls and the prototype pressure mapping). Per ADR 0001 these
//   tests assert document and viewport state, not raster output, and
//   physical stylus hardware is not covered: the stylus is a synthetic
//   PointerDeviceKind.stylus event.
// Covers: lib/canvas/canvas_view.dart (CanvasView input handling, _weightFor)
//   and lib/canvas/canvas_controller.dart (CanvasController, toDocument /
//   toScreen, CanvasDocument strokes). Trackpad gestures (ADR 0003) are not
//   tested in this file.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:painter/canvas/canvas_controller.dart';
import 'package:painter/canvas/canvas_view.dart';

void main() {
  // Mouse weight is always 1.0 regardless of pressure (docs/project-brief.md).
  // Here the canvas fills the test window from the origin (no AppBar), so a
  // local position equals a global one and the stored document-space points
  // can be compared directly with the event positions at the unchanged
  // default viewport.
  testWidgets('mouse stroke records document-space points at fixed weight', (
    tester,
  ) async {
    final controller = await _pumpCanvas(tester);
    final size = tester.getSize(find.byType(CanvasView));
    final start = Offset(size.width / 2 - 30, size.height / 2 - 20);
    final mouse = TestPointer(1, PointerDeviceKind.mouse);

    await tester.sendEventToBinding(
      mouse.down(start, buttons: kPrimaryMouseButton),
    );
    await tester.sendEventToBinding(
      mouse.move(start + const Offset(20, 10), buttons: kPrimaryMouseButton),
    );
    await tester.sendEventToBinding(mouse.up());
    await tester.pump();

    final stroke = controller.document.strokes.single;
    expect(stroke.points, hasLength(2));
    expect(stroke.points.first.position, start);
    expect(stroke.points.last.position, start + const Offset(20, 10));
    expect(stroke.points.map((point) => point.weight), everyElement(1));
    controller.dispose();
  });

  // Pressure 0.2 / 0.8 map through CanvasView._weightFor,
  // 0.05 + 0.95 * pressure, to the expected 0.24 / 0.81 (ADR 0001 prototype
  // values, not artist-approved). The events are built by hand so pressure,
  // pressureMin and pressureMax can be set explicitly.
  testWidgets('stylus pressure changes stroke weight', (tester) async {
    final controller = await _pumpCanvas(tester);
    await tester.sendEventToBinding(
      const PointerDownEvent(
        pointer: 2,
        kind: PointerDeviceKind.stylus,
        position: Offset(200, 200),
        buttons: kPrimaryButton,
        pressure: 0.2,
        pressureMin: 0,
        pressureMax: 1,
      ),
    );
    await tester.sendEventToBinding(
      const PointerMoveEvent(
        pointer: 2,
        kind: PointerDeviceKind.stylus,
        position: Offset(220, 210),
        delta: Offset(20, 10),
        buttons: kPrimaryButton,
        pressure: 0.8,
        pressureMin: 0,
        pressureMax: 1,
      ),
    );
    await tester.sendEventToBinding(
      const PointerUpEvent(
        pointer: 2,
        kind: PointerDeviceKind.stylus,
        position: Offset(220, 210),
      ),
    );
    await tester.pump();

    final points = controller.document.strokes.single.points;
    expect(points.first.weight, closeTo(0.24, 0.001));
    expect(points.last.weight, closeTo(0.81, 0.001));
    controller.dispose();
  });

  // One test for the three mouse viewport controls (ADR 0001): secondary-
  // button drag pans, vertical wheel zooms about the pointer, middle-button
  // drag rotates. The zoom check asserts the document point under the pointer
  // stays at the same screen position (toDocument before, toScreen after).
  // Rotation of 50 px of drag giving 0.5 rad is the current dx / 100 rule in
  // CanvasView.
  testWidgets('mouse buttons pan and rotate, and wheel zooms', (tester) async {
    final controller = await _pumpCanvas(tester);
    final initialSize = tester.getSize(find.byType(CanvasView));
    final start = Offset(initialSize.width / 2, initialSize.height / 2);

    final panMouse = TestPointer(3, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      panMouse.down(start, buttons: kSecondaryMouseButton),
    );
    await tester.sendEventToBinding(
      panMouse.move(
        start + const Offset(12, 7),
        buttons: kSecondaryMouseButton,
      ),
    );
    await tester.sendEventToBinding(panMouse.up());
    expect(controller.pan, const Offset(12, 7));

    final zoomAnchor = start + const Offset(60, -40);
    final documentAnchor = controller.toDocument(zoomAnchor, initialSize);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: zoomAnchor,
        kind: PointerDeviceKind.mouse,
        scrollDelta: const Offset(0, -100),
      ),
    );
    expect(controller.zoom, greaterThan(1));
    final zoomedAnchor = controller.toScreen(documentAnchor, initialSize);
    expect(zoomedAnchor.dx, closeTo(zoomAnchor.dx, 0.001));
    expect(zoomedAnchor.dy, closeTo(zoomAnchor.dy, 0.001));

    final rotateMouse = TestPointer(5, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      rotateMouse.down(start, buttons: kMiddleMouseButton),
    );
    await tester.sendEventToBinding(
      rotateMouse.move(
        start + const Offset(50, 0),
        buttons: kMiddleMouseButton,
      ),
    );
    await tester.sendEventToBinding(rotateMouse.up());
    expect(controller.rotation, closeTo(0.5, 0.001));
    controller.dispose();
  });
}

/// Pumps a bare CanvasView inside Scaffold(body:) with a fresh controller and
/// returns it; tests dispose it. No AppBar, so the canvas starts at the
/// window origin and local coordinates equal global ones.
Future<CanvasController> _pumpCanvas(WidgetTester tester) async {
  final controller = CanvasController();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: CanvasView(controller: controller)),
    ),
  );
  return controller;
}

