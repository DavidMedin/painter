// What: Widget tests for pane content selection, splitting, resizing, and close.
// Why: PaneSystem owns pane identity and relative widths, so user actions must
//   change the visible content and layout without dropping the final pane.
// Covers: lib/ui/pane_system.dart (PaneSystem and PaneSystemState).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:painter/ui/pane_system.dart';

Widget _content(BuildContext context, PaneDescriptor pane) =>
    Center(child: Text('${pane.kind.name}-${pane.id}'));

Widget _host() {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox.expand(
        child: PaneSystem(
          contentBuilder: _content,
          onPaneRemoved: (_) {},
          onPaneTypeChanged: (_, _) {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('content selector replaces the selected pane content', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    expect(find.text('canvas-0'), findsOneWidget);

    await tester.tap(find.text('Canvas').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Diagnostics').last);
    await tester.pumpAndSettle();

    expect(find.text('canvas-0'), findsNothing);
    expect(find.text('diagnostics-0'), findsOneWidget);
  });

  testWidgets(
    'split adds a pane, divider resizes it, and close preserves one',
    (tester) async {
      await tester.pumpWidget(_host());
      expect(find.text('canvas-0'), findsOneWidget);
      expect(find.text('Close'), findsNothing);

      await tester.tap(find.text('Split').first);
      await tester.pumpAndSettle();
      expect(find.text('canvas-0'), findsOneWidget);
      expect(find.text('diagnostics-1'), findsOneWidget);

      final pane = find.byKey(const ValueKey('pane-0'));
      final widthBefore = tester.getSize(pane).width;
      await tester.drag(
        find.bySemanticsLabel('Resize pane boundary'),
        const Offset(80, 0),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(pane).width, greaterThan(widthBefore + 40));

      await tester.tap(find.text('Close').last);
      await tester.pumpAndSettle();
      expect(find.text('canvas-0'), findsOneWidget);
      expect(find.text('diagnostics-1'), findsNothing);
      expect(find.text('Close'), findsNothing);
    },
  );
}
