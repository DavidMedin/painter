// What: Widget tests cover pane mode selection, visible borders, boundary
//   menus, resizing, deletion to zero panes, and reopening the workspace.
// Why: PaneSystem owns pane identity, ordering, and relative widths, so each
//   boundary action must preserve the adjacent-pane and empty-state contracts.
// Covers: lib/ui/pane_system.dart (PaneSystem and PaneSystemState).

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:painter/ui/pane_system.dart';

Widget _content(BuildContext context, PaneDescriptor pane) =>
    Center(child: Text('${pane.kind.name}-${pane.id}'));

Widget _host() {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox.expand(
        child: PaneSystem(contentBuilder: _content, onPaneRemoved: (_) {}),
      ),
    ),
  );
}

Future<void> _rightClickAt(WidgetTester tester, Offset position) async {
  final gesture = await tester.startGesture(
    position,
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Pane Mode selector has visible contrast and rounded borders', (
    tester,
  ) async {
    await tester.pumpWidget(_host());

    expect(find.text('Pane Mode'), findsOneWidget);
    expect(find.byKey(const ValueKey('pane-mode-0')), findsOneWidget);
    expect(find.text('Split'), findsNothing);
    expect(find.text('Close'), findsNothing);

    final theme = Theme.of(tester.element(find.byType(Scaffold)));
    final frame = tester.widget<Container>(
      find.byKey(const ValueKey('pane-frame-0')),
    );
    final frameDecoration = frame.decoration! as BoxDecoration;
    expect(frameDecoration.borderRadius, BorderRadius.circular(8));
    expect(frameDecoration.border!.top.width, 1.5);

    final header = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('pane-header-0')),
    );
    final headerColor = (header.decoration as BoxDecoration).color;
    expect(headerColor, theme.colorScheme.surfaceContainerHigh);
    expect(headerColor, isNot(theme.colorScheme.surface));

    await tester.tap(find.byKey(const ValueKey('pane-mode-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Diagnostics').last);
    await tester.pumpAndSettle();

    expect(find.text('diagnostics-0'), findsOneWidget);
    expect(find.byKey(const ValueKey('pane-mode-0')), findsOneWidget);
  });

  testWidgets(
    'inner boundary adds between panes, resizes, and deletes beside',
    (tester) async {
      await tester.pumpWidget(_host());
      await _rightClickAt(
        tester,
        tester.getCenter(find.byKey(const ValueKey('pane-boundary-1'))),
      );
      expect(find.text('Add pane to the right'), findsOneWidget);
      expect(find.text('Delete left pane'), findsOneWidget);
      expect(find.text('Delete right pane'), findsNothing);
      await tester.tap(find.text('Add pane to the right'));
      await tester.pumpAndSettle();

      expect(find.text('canvas-0'), findsOneWidget);
      expect(find.text('canvas-1'), findsOneWidget);
      final firstPane = find.byKey(const ValueKey('pane-0'));
      final widthBefore = tester.getSize(firstPane).width;
      await tester.drag(
        find.byKey(const ValueKey('pane-boundary-1')),
        const Offset(80, 0),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(firstPane).width, greaterThan(widthBefore + 40));

      await _rightClickAt(
        tester,
        tester.getCenter(find.byKey(const ValueKey('pane-boundary-1'))),
      );
      expect(find.text('Add pane between panes'), findsOneWidget);
      expect(find.text('Delete left pane'), findsOneWidget);
      expect(find.text('Delete right pane'), findsOneWidget);
      await tester.tap(find.text('Add pane between panes'));
      await tester.pumpAndSettle();
      expect(find.text('canvas-0'), findsOneWidget);
      expect(find.text('canvas-2'), findsOneWidget);
      expect(find.text('canvas-1'), findsOneWidget);

      await _rightClickAt(
        tester,
        tester.getCenter(find.byKey(const ValueKey('pane-boundary-3'))),
      );
      expect(find.text('Add pane to the right'), findsOneWidget);
      expect(find.text('Delete left pane'), findsOneWidget);
      expect(find.text('Delete right pane'), findsNothing);
      await tester.tap(find.text('Delete left pane'));
      await tester.pumpAndSettle();
      expect(find.text('canvas-1'), findsNothing);
      expect(find.text('canvas-0'), findsOneWidget);
      expect(find.text('canvas-2'), findsOneWidget);
    },
  );

  testWidgets(
    'outer-left actions add beside, delete to zero, and reopen Canvas',
    (tester) async {
      await tester.pumpWidget(_host());
      await _rightClickAt(
        tester,
        tester.getCenter(find.byKey(const ValueKey('pane-boundary-0'))),
      );
      expect(find.text('Add pane to the left'), findsOneWidget);
      expect(find.text('Delete right pane'), findsOneWidget);
      expect(find.text('Delete left pane'), findsNothing);
      await tester.tap(find.text('Add pane to the left'));
      await tester.pumpAndSettle();
      expect(find.text('canvas-1'), findsOneWidget);
      expect(find.text('canvas-0'), findsOneWidget);

      await _rightClickAt(
        tester,
        tester.getCenter(find.byKey(const ValueKey('pane-boundary-0'))),
      );
      await tester.tap(find.text('Delete right pane'));
      await tester.pumpAndSettle();
      expect(find.text('canvas-1'), findsNothing);
      expect(find.text('canvas-0'), findsOneWidget);

      await _rightClickAt(
        tester,
        tester.getCenter(find.byKey(const ValueKey('pane-boundary-0'))),
      );
      await tester.tap(find.text('Delete right pane'));
      await tester.pumpAndSettle();
      expect(find.text('Pane Mode'), findsNothing);
      expect(find.text('canvas-0'), findsNothing);

      final openButton = find.widgetWithText(FilledButton, 'Open Canvas Pane');
      expect(openButton, findsOneWidget);
      final button = tester.widget<FilledButton>(openButton);
      final style = button.style!;
      final colors = Theme.of(tester.element(openButton)).colorScheme;
      expect(style.backgroundColor!.resolve({}), colors.primary);
      expect(style.foregroundColor!.resolve({}), colors.onPrimary);
      expect(colors.primary, isNot(colors.surface));

      await tester.tap(openButton);
      await tester.pumpAndSettle();
      expect(find.text('canvas-2'), findsOneWidget);
      expect(find.text('Pane Mode'), findsOneWidget);
    },
  );
}
