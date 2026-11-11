// What: Widget tests drive synthetic pointer input through CanvasView and
//   verify shared document updates, pane-local viewport state, and white paper.
// Why: The canvas controls (docs/decisions/003-vector-canvas.md), bounded
//   chunks (docs/decisions/004-tile-cache.md) and independent per-pane views
//   (docs/spec/canvas.md CNVS-3, CNVS-6) are what a user drives with the
//   mouse and stylus. Events are synthetic; dark-theme paper is checked as
//   pixels.
// Covers: lib/canvas/canvas_view.dart (CanvasView input and painting),
//   lib/canvas/canvas_controller.dart (document, active chunks) and
//   lib/canvas/canvas_viewport.dart (views driven by input).

import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:painter/canvas/canvas_controller.dart';
import 'package:painter/canvas/canvas_view.dart';
import 'package:painter/canvas/canvas_viewport.dart';

void main() {
  // Mouse weight is always 1.0 regardless of pressure. Here the canvas fills
  // the test window from the origin (no AppBar), so a local position equals a
  // global one and the stored points are the event positions mapped through
  // the pane's view.
  testWidgets('mouse stroke records document-space points at fixed weight', (
    tester,
  ) async {
    final controller = await _pumpCanvas(tester);
    final viewport = tester
        .widget<CanvasView>(find.byType(CanvasView))
        .viewport;
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
    expect(stroke.points.first.position, viewport.toDocument(start, size));
    expect(
      stroke.points.last.position,
      viewport.toDocument(start + const Offset(20, 10), size),
    );
    expect(stroke.points.map((point) => point.weight), everyElement(1));
    controller.dispose();
  });

  testWidgets('long mouse gestures commit bounded chunks while drawing', (
    tester,
  ) async {
    final controller = await _pumpCanvas(tester);
    final size = tester.getSize(find.byType(CanvasView));
    final viewport = tester
        .widget<CanvasView>(find.byType(CanvasView))
        .viewport;
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
    final documentEnd = viewport.toDocument(end, size);
    expect(controller.activePoints.last.position, documentEnd);

    await tester.sendEventToBinding(mouse.up());
    expect(controller.activePoints, isEmpty);
    expect(controller.document.strokes.last.points.last.position, documentEnd);
    controller.dispose();
  });

  // Pressure 0.2 / 0.8 map through CanvasView._weightFor,
  // 0.05 + 0.95 * pressure, to the expected 0.24 / 0.81
  // (design/canvas/vector-canvas.md prototype values, not artist-approved). The
  // events are built by hand so pressure, pressureMin and pressureMax can be
  // set explicitly.
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

  // One test for the three mouse viewport controls
  // (docs/decisions/003-vector-canvas.md): secondary-button drag pans,
  // vertical wheel zooms about the pointer, middle-button drag rotates. The
  // pan and zoom checks assert that the document point under the pointer
  // stays under it (toDocument before, toScreen after). Rotation of 50 px of
  // drag giving 0.5 rad is the current dx / 100 rule in CanvasView.
  testWidgets('mouse buttons pan and rotate, and wheel zooms', (tester) async {
    final controller = await _pumpCanvas(tester);
    final viewport = tester
        .widget<CanvasView>(find.byType(CanvasView))
        .viewport;
    final initialSize = tester.getSize(find.byType(CanvasView));
    final start = Offset(initialSize.width / 2, initialSize.height / 2);
    final grabbed = viewport.toDocument(start, initialSize);

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
    final dragged = viewport.toScreen(grabbed, initialSize);
    expect(dragged.dx, closeTo(start.dx + 12, 0.001));
    expect(dragged.dy, closeTo(start.dy + 7, 0.001));

    final zoomAnchor = start + const Offset(60, -40);
    final documentAnchor = viewport.toDocument(zoomAnchor, initialSize);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: zoomAnchor,
        kind: PointerDeviceKind.mouse,
        scrollDelta: const Offset(0, -100),
      ),
    );
    expect(viewport.extent, lessThan(CanvasViewportController.defaultExtent));
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
    final size = tester.getSize(first);
    final dragged = firstViewport.toScreen(
      CanvasViewportController.defaultCenter,
      size,
    );
    expect(dragged.dx, closeTo(size.width / 2 + 18, 0.001));
    expect(dragged.dy, closeTo(size.height / 2 + 9, 0.001));

    final center = Offset(size.width / 2, size.height / 2);
    firstViewport
      ..zoomAt(center, size, 2)
      ..rotateAt(center, size, 0.25);

    expect(firstViewport.extent, CanvasViewportController.defaultExtent / 2);
    expect(firstViewport.rotation, 0.25);
    expect(controller.document.strokeCount, 1);
    expect(secondViewport.center, CanvasViewportController.defaultCenter);
    expect(secondViewport.extent, CanvasViewportController.defaultExtent);
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

  // The painter's canvas is the shared layer canvas, not a per-pane clip:
  // unclipped painting leaks over whatever was drawn earlier in the same
  // layer. docs/design/panes/pane-system.md requires pane content not to
  // overlap, so the paper must appear in the canvas pane's own content
  // area and nowhere else: not on the neighbouring pane, not on either
  // pane's chrome bar.
  testWidgets('canvas paper stays inside its own pane area', (tester) async {
    final controller = CanvasController();
    final viewport = CanvasViewportController();
    addTearDown(controller.dispose);
    addTearDown(viewport.dispose);
    const neighbor = Color(0xFF204080);
    const chrome = Color(0xFF804020);
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            key: boundaryKey,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      SizedBox(
                        height: 40,
                        child: CustomPaint(painter: _SolidPainter(chrome)),
                      ),
                      Expanded(
                        child: CustomPaint(painter: _SolidPainter(neighbor)),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      SizedBox(
                        height: 40,
                        child: CustomPaint(painter: _SolidPainter(chrome)),
                      ),
                      Expanded(
                        child: CanvasView(
                          controller: controller,
                          viewport: viewport,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
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
    // 800x600 test window: two 400-wide panes, each with a 40px chrome bar
    // and a 560px content area below it.
    Color argbAt(int x, int y) {
      final i = (y * image.width + x) * 4;
      return Color.fromARGB(bytes[i + 3], bytes[i], bytes[i + 1], bytes[i + 2]);
    }

    expect(argbAt(600, 320), CanvasView.paperColor,
        reason: 'canvas pane shows its paper');
    expect(argbAt(200, 320), isNot(CanvasView.paperColor),
        reason: 'paper must not leak onto the neighbouring pane');
    expect(argbAt(200, 20), isNot(CanvasView.paperColor),
        reason: 'paper must not leak onto the neighbouring pane chrome');
    expect(argbAt(600, 20), isNot(CanvasView.paperColor),
        reason: 'paper must not leak onto the canvas pane chrome');
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

/// Fills its whole area with one opaque color so a pane region can be
/// identified in a pixel capture (used by the pane occlusion test).
class _SolidPainter extends CustomPainter {
  _SolidPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SolidPainter oldDelegate) =>
      oldDelegate.color != color;
}
