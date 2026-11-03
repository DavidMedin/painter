// What: Smoke test that PainterApp starts on the canvas screen.
// Why: docs/project-brief.md says that launching without a file opens
//   directly to a blank, paint-ready canvas with no splash screen;
//   docs/status.md (T-003) lists this test as the launch check. It asserts
//   only that a CanvasView and a semantics node labelled 'Canvas' are present
//   right after the first frame; it does not assert that the canvas is empty
//   (no strokes) or that no other route is shown.
// Covers: lib/main.dart (PainterApp) and lib/canvas/canvas_view.dart
//   (CanvasView, its 'Canvas' Semantics label).

import 'package:flutter_test/flutter_test.dart';
import 'package:painter/canvas/canvas_view.dart';
import 'package:painter/main.dart';

void main() {
  // Semantics are off by default in widget tests; ensureSemantics turns them
  // on so find.bySemanticsLabel can see the canvas's 'Canvas' label.
  testWidgets('launches directly to the blank canvas', (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(const PainterApp());

    expect(find.bySemanticsLabel('Canvas'), findsOneWidget);
    expect(find.byType(CanvasView), findsOneWidget);
    semantics.dispose();
  });
}
