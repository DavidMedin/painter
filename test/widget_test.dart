// What: Smoke tests for the initial canvas, hidden diagnostics, and F1 help.
// Why: The app's launch layout and keyboard-discoverable help are observable
//   shell behavior; tests ensure the blank Canvas remains the only initial pane.
// Covers: lib/main.dart (PainterApp shortcuts and toolbar) and
//   lib/canvas/canvas_view.dart (CanvasView, its 'Canvas' Semantics label).

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:painter/canvas/canvas_view.dart';
import 'package:painter/debug/canvas_debug_pane.dart';
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
    expect(find.byType(CanvasDebugPane), findsNothing);
    expect(
      find.text('Add a Canvas pane to inspect diagnostics.'),
      findsNothing,
    );
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
