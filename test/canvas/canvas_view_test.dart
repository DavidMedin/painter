// What: Widget tests drive synthetic pointer input through CanvasView and
//   verify shared document updates, pane-local viewport state, and white paper.
// Why: T-003 acceptance covers canvas controls (ADR 0001); ADR 0009 adds the
//   bounded-chunk requirement, and pane behavior needs independent transforms.
//   Mouse/stylus events are synthetic; dark-theme paper is checked as pixels.
// Covers: lib/canvas/canvas_view.dart (CanvasView input and painting) and
//   lib/canvas/canvas_controller.dart (document, active chunks, viewports).

import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  testWidgets('long mouse gestures commit bounded chunks while drawing', (
    tester,
  ) async {
    final controller = await _pumpCanvas(tester);
    final size = tester.getSize(find.byType(CanvasView));
    final start = Offset(size.width / 2 - 300, size.height / 2);
    final end = start + const Offset(600, 0);
    final mouse = TestPointer(7, PointerDeviceKind.mouse);

    await tester.sendEventToBinding(
      mouse.down(start, buttons: kPrimaryMouseButton),
    );
    await tester.sendEventToBinding(
      mouse.move(end, buttons: kPrimaryMouseButton),
    );

    expect(controller.document.strokeCount, greaterThan(1));
    expect(
      controller.activePoints.length,
      lessThanOrEqualTo(CanvasController.activeStrokeChunkPoints),
    );
    expect(controller.activePoints.last.position, end);

    await tester.sendEventToBinding(mouse.up());
    expect(controller.activePoints, isEmpty);
    expect(controller.document.strokes.last.points.last.position, end);
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
    final viewport = tester
        .widget<CanvasView>(find.byType(CanvasView))
        .viewport;
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
    expect(viewport.pan, const Offset(12, 7));

    final zoomAnchor = start + const Offset(60, -40);
    final documentAnchor = viewport.toDocument(zoomAnchor, initialSize);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: zoomAnchor,
        kind: PointerDeviceKind.mouse,
        scrollDelta: const Offset(0, -100),
      ),
    );
    expect(viewport.zoom, greaterThan(1));
    final zoomedAnchor = viewport.toScreen(documentAnchor, initialSize);
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
    expect(viewport.rotation, closeTo(0.5, 0.001));
    controller.dispose();
  });
  testWidgets('Canvas panes share content but keep independent viewports', (
    tester,
  ) async {
    final controller = CanvasController();
    final firstViewport = CanvasViewportController();
    final secondViewport = CanvasViewportController();
    addTearDown(controller.dispose);
    addTearDown(firstViewport.dispose);
    addTearDown(secondViewport.dispose);
    controller
      ..beginStroke(const Offset(10, 20), 1)
      ..endStroke();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              Expanded(
                child: CanvasView(
                  controller: controller,
                  viewport: firstViewport,
                ),
              ),
              Expanded(
                child: CanvasView(
                  controller: controller,
                  viewport: secondViewport,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final first = find.byType(CanvasView).first;
    final start = tester.getRect(first).center;
    final mouse = TestPointer(10, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      mouse.down(start, buttons: kSecondaryMouseButton),
    );
    await tester.sendEventToBinding(
      mouse.move(start + const Offset(18, 9), buttons: kSecondaryMouseButton),
    );
    await tester.sendEventToBinding(mouse.up());
    expect(firstViewport.pan, const Offset(18, 9));

    final size = tester.getSize(first);
    final center = Offset(size.width / 2, size.height / 2);
    firstViewport
      ..zoomAt(center, size, 2)
      ..rotateAt(center, size, 0.25);

    expect(firstViewport.zoom, 2);
    expect(firstViewport.rotation, 0.25);
    expect(controller.document.strokeCount, 1);
    expect(firstViewport.pan, isNot(secondViewport.pan));
    expect(secondViewport.pan, Offset.zero);
    expect(secondViewport.zoom, 1);
    expect(secondViewport.rotation, 0);
  });

  testWidgets('canvas paper stays white in a dark app theme', (tester) async {
    final controller = CanvasController();
    final viewport = CanvasViewportController();
    addTearDown(controller.dispose);
    addTearDown(viewport.dispose);
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: RepaintBoundary(
            key: boundaryKey,
            child: CanvasView(controller: controller, viewport: viewport),
          ),
        ),
      ),
    );
    await tester.pump();

    final boundary =
        boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = (await tester.runAsync(() => boundary.toImage()))!;
    final data = (await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    ))!;
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final pixel = ((image.height ~/ 2) * image.width + image.width ~/ 2) * 4;

    expect(bytes.sublist(pixel, pixel + 4), [255, 255, 255, 255]);
    image.dispose();
  });
}

/// Pumps a bare CanvasView inside Scaffold(body:) with a fresh controller and
/// returns it; tests dispose it. No AppBar, so the canvas starts at the
/// window origin and local coordinates equal global ones.
Future<CanvasController> _pumpCanvas(WidgetTester tester) async {
  final controller = CanvasController();
  final viewport = CanvasViewportController();
  addTearDown(viewport.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CanvasView(controller: controller, viewport: viewport),
      ),
    ),
  );
  return controller;
}
