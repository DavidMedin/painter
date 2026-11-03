// What: Smoke tests for the initial canvas and F1 contextual help.
// Why: The initial paint-ready canvas and keyboard-discoverable help are
//   observable app-shell behavior; tests ensure both remain available.
// Covers: lib/main.dart (PainterApp shortcuts and toolbar) and
//   lib/canvas/canvas_view.dart (CanvasView, its 'Canvas' Semantics label).

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:painter/canvas/canvas_view.dart';
import 'package:painter/main.dart';

void main() {
  // Semantics are off by default in widget tests; ensureSemantics turns them
  // on so find.bySemanticsLabel can see the canvas's 'Canvas' label.
  testWidgets('launches directly to the blank canvas', (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(const PainterApp());

    expect(
      find.descendant(
        of: find.byType(CanvasView),
        matching: find.bySemanticsLabel('Canvas'),
      ),
      findsOneWidget,
    );
    expect(find.byType(CanvasView), findsOneWidget);
    semantics.dispose();
  });
  testWidgets('F1 opens help for the hovered control', (tester) async {
    await tester.pumpWidget(const PainterApp());

    final pointer = TestPointer(42, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      pointer.hover(tester.getCenter(find.text('Open'))),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    await tester.pumpAndSettle();

    expect(find.text('Open document'), findsOneWidget);
    expect(
      find.textContaining('Browse to a .paint file and select it'),
      findsOneWidget,
    );
  });
}
