// What: Smoke tests for the initial canvas, hidden diagnostics, the F1
//   manual, and the AppBar's Session button.
// Why: The app launch and contextual help routes are observable shell behavior;
//   F1 must open and navigate the docked manual rather than a transient dialog,
//   and the Session button must dock the Session pane the same way.
// Covers: lib/main.dart (PainterApp shortcuts and toolbar),
//   lib/help/manual_pane.dart (manual content), lib/session/session_pane.dart
//   (its not-in-session state), lib/workspace/workspace.dart (openPane), and
//   CanvasView. Sessions over sockets are tested in
//   test/session/session_app_test.dart.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:painter/canvas/canvas_view.dart';
import 'package:painter/debug/canvas_debug_pane.dart';
import 'package:painter/help/manual_pane.dart';
import 'package:painter/main.dart';
import 'package:painter/session/session_pane.dart';
import 'package:painter/ui/painter_action_button.dart';

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
  testWidgets('F1 opens and reuses the manual for the hovered control', (
    tester,
  ) async {
    await tester.pumpWidget(const PainterApp());

    final pointer = TestPointer(42, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      pointer.hover(tester.getCenter(find.text('Open'))),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    await tester.pumpAndSettle();

    expect(find.byType(ManualPane), findsOneWidget);
    expect(
      find.textContaining('Choose a .paint file in the in-app picker.'),
      findsOneWidget,
    );

    await tester.sendEventToBinding(
      pointer.hover(tester.getCenter(find.text('Save').first)),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    await tester.pumpAndSettle();

    expect(find.byType(ManualPane), findsOneWidget);
    expect(
      find.textContaining('Choose a destination the first time you save.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Choose a .paint file in the in-app picker.'),
      findsNothing,
    );

    final paintingSection = find.text('Painting');
    await tester.ensureVisible(paintingSection);
    await tester.tap(paintingSection);
    await tester.pumpAndSettle();
    final canvasArticle = find.byKey(const ValueKey('manual-item-canvas'));
    await tester.ensureVisible(canvasArticle);
    await tester.tap(canvasArticle);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Drag with the primary mouse button'),
      findsOneWidget,
    );
  });

  testWidgets('the Session button docks one Session pane outside a Session', (
    tester,
  ) async {
    await tester.pumpWidget(const PainterApp());
    final button = find.widgetWithText(PainterActionButton, 'Session');

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byType(SessionPane), findsOneWidget);
    expect(find.byType(CanvasView), findsOneWidget);
    expect(find.text('You are not in a session.'), findsOneWidget);
    expect(find.byKey(const ValueKey('session-start')), findsOneWidget);
    expect(find.byKey(const ValueKey('session-join')), findsOneWidget);

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byType(SessionPane), findsOneWidget);
  });
}
