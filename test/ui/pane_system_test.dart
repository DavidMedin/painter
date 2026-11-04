// What: Widget tests cover pane modes, Manual placement, visible surfaces and
//   borders, split direction, resizing, divider actions, focus, and close.
// Why: PaneSystem owns pane identity and split weights; tests protect its nested
//   layout, mode changes, and behavior when space is too narrow for full actions.
// Covers: lib/ui/pane_system.dart (PaneSystem and PaneSystemState).

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:painter/help/contextual_help.dart';
import 'package:painter/help/manual_catalog.dart';
import 'package:painter/help/manual_pane.dart';
import 'package:painter/ui/pane_system.dart';

Widget _content(BuildContext context, PaneDescriptor pane) =>
    Center(child: Text('${pane.kind.name}-${pane.id}'));

Widget _manualContent(BuildContext context, PaneDescriptor pane) =>
    pane.kind == PaneKind.manual
    ? ManualPane(
        helpId: pane.manualHelpId,
        onHelpIdSelected: pane.onManualHelpSelected,
      )
    : _content(context, pane);

Widget _host({
  GlobalKey<PaneSystemState>? paneSystemKey,
  PaneContentBuilder contentBuilder = _content,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox.expand(
        child: PaneSystem(
          key: paneSystemKey,
          contentBuilder: contentBuilder,
          onPaneRemoved: (_) {},
          onPaneTypeChanged: (_, _) {},
        ),
      ),
    ),
  );
}

Color _paneBorderColor(WidgetTester tester, int paneId) {
  final listener = tester.widget<Listener>(
    find.byKey(ValueKey('pane-$paneId')),
  );
  final decoration = listener.child! as DecoratedBox;
  final border = (decoration.decoration as BoxDecoration).border! as Border;
  return border.top.color;
}

void main() {
  testWidgets('pane controls expose their contextual help', (tester) async {
    final helpState = HelpState();
    final pointer = TestPointer(42, PointerDeviceKind.mouse);
    addTearDown(helpState.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HelpScope(
            helpState: helpState,
            child: SizedBox.expand(
              child: PaneSystem(
                contentBuilder: _content,
                onPaneRemoved: (_) {},
                onPaneTypeChanged: (_, _) {},
              ),
            ),
          ),
        ),
      ),
    );

    Future<void> hover(Finder target, HelpId expected) async {
      await tester.sendEventToBinding(pointer.hover(tester.getCenter(target)));
      await tester.pump();
      expect(helpState.activeTopic, expected);
    }

    await hover(find.byKey(const ValueKey('pane-mode-0')), HelpIds.paneType);
    final splitButton = find.byKey(const ValueKey('split-menu-0'));
    await hover(splitButton, HelpIds.paneBoundary);
    await tester.tap(splitButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Side by side'));
    await tester.pumpAndSettle();
    await hover(
      find.bySemanticsLabel('Resize pane boundary'),
      HelpIds.paneBoundary,
    );
    await hover(find.text('Close').last, HelpIds.paneBoundary);
  });
  testWidgets('selected pane mode is visible and replaces its content', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    final selector = find.byKey(const ValueKey('pane-mode-0'));
    var dropdown = tester.widget<DropdownButton<PaneKind>>(selector);
    expect(dropdown.value, PaneKind.canvas);
    expect(dropdown.style!.fontWeight, FontWeight.w600);
    expect(find.text('canvas-0'), findsOneWidget);

    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Diagnostics').last);
    await tester.pumpAndSettle();

    dropdown = tester.widget<DropdownButton<PaneKind>>(selector);
    expect(dropdown.value, PaneKind.diagnostics);
    expect(find.text('canvas-0'), findsNothing);
    expect(find.text('diagnostics-0'), findsOneWidget);
  });

  testWidgets('non-canvas pane content rests on the themed surface', (
    tester,
  ) async {
    final theme = ThemeData.dark();
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: SizedBox.expand(
            child: PaneSystem(
              contentBuilder: _content,
              onPaneRemoved: (_) {},
              onPaneTypeChanged: (_, _) {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('split-menu-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Side by side'));
    await tester.pumpAndSettle();

    final pane = find.byKey(const ValueKey('pane-1'));
    final surface = find.descendant(
      of: pane,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Material && widget.color == theme.colorScheme.surface,
      ),
    );
    expect(surface, findsOneWidget);
    expect(find.text('diagnostics-1'), findsOneWidget);
  });

  testWidgets('right-clicking a divider splits and closes adjacent panes', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.tap(find.byKey(const ValueKey('split-menu-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Side by side'));
    await tester.pumpAndSettle();

    var divider = find.bySemanticsLabel('Resize pane boundary').first;
    await tester.tapAt(
      tester.getCenter(divider),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Split left pane top-and-bottom'));
    await tester.pumpAndSettle();
    expect(find.text('canvas-0'), findsOneWidget);
    expect(find.text('diagnostics-2'), findsOneWidget);

    divider = find.bySemanticsLabel('Resize pane boundary').first;
    await tester.tapAt(
      tester.getCenter(divider),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close top pane'));
    await tester.pumpAndSettle();
    expect(find.text('canvas-0'), findsNothing);
    expect(find.text('diagnostics-2'), findsOneWidget);
    expect(find.text('diagnostics-1'), findsOneWidget);
  });

  testWidgets('narrow panes keep controls usable without layout overflow', (
    tester,
  ) async {
    final originalSize = tester.view.physicalSize;
    addTearDown(() => tester.view.physicalSize = originalSize);
    await tester.pumpWidget(_host());

    Future<void> splitFirstPane() async {
      await tester.tap(find.byKey(const ValueKey('split-menu-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Side by side'));
      await tester.pumpAndSettle();
    }

    await splitFirstPane();
    await splitFirstPane();
    await splitFirstPane();
    final compactMenu = find.byKey(const ValueKey('pane-actions-0'));
    expect(compactMenu, findsOneWidget);
    await tester.tap(compactMenu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    expect(find.text('settings-0'), findsOneWidget);
    await tester.tap(compactMenu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manual').last);
    await tester.pumpAndSettle();
    expect(find.text('manual-0'), findsOneWidget);
    await tester.tap(compactMenu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log').last);
    await tester.pumpAndSettle();
    expect(find.text('log-0'), findsOneWidget);

    final devicePixelRatio = tester.view.devicePixelRatio;
    tester.view.physicalSize = Size(
      40 * devicePixelRatio,
      200 * devicePixelRatio,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byKey(const ValueKey('pane-1'))).width,
      closeTo(14, 1),
    );
    expect(find.byKey(const ValueKey('pane-mode-1')), findsNothing);
  });
  testWidgets('side-by-side and top-bottom splits resize and close', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    final pane = find.byKey(const ValueKey('pane-0'));
    final initial = tester.getSize(pane);

    await tester.tap(find.byKey(const ValueKey('split-menu-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Side by side'));
    await tester.pumpAndSettle();
    expect(find.text('canvas-0'), findsOneWidget);
    expect(find.text('diagnostics-1'), findsOneWidget);
    final primary = Theme.of(tester.element(find.byType(PaneSystem)))
        .colorScheme
        .primary;
    final inactiveListener = tester.widget<Listener>(
      find.byKey(const ValueKey('pane-0')),
    );
    final inactiveDecoration = inactiveListener.child! as DecoratedBox;
    final inactiveBorder =
        (inactiveDecoration.decoration as BoxDecoration).border! as Border;
    expect(
      inactiveBorder.top.color,
      Theme.of(tester.element(pane)).colorScheme.outlineVariant,
    );
    expect(inactiveBorder.top.width, 2);
    final divider = find.bySemanticsLabel('Resize pane boundary');
    expect(tester.getSize(divider).width, 12);
    final handleBackground = tester.widget<ColoredBox>(
      find.descendant(of: divider, matching: find.byType(ColoredBox)),
    );
    expect(
      handleBackground.color,
      Theme.of(tester.element(pane)).colorScheme.surfaceContainerHighest,
    );
    final grip = find.descendant(of: divider, matching: find.byType(Container));
    expect(tester.getSize(grip).width, 4);
    await tester.tap(find.text('canvas-0'));
    await tester.pump();
    expect(_paneBorderColor(tester, 0), primary);
    final widthBefore = tester.getSize(pane).width;
    await tester.drag(
      find.bySemanticsLabel('Resize pane boundary'),
      const Offset(80, 0),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(pane).width, greaterThan(widthBefore + 40));
    expect(tester.getSize(pane).height, closeTo(initial.height, 1));

    await tester.tap(find.text('Close').last);
    await tester.pumpAndSettle();
    expect(find.text('canvas-0'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('split-menu-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Top and bottom'));
    await tester.pumpAndSettle();
    expect(find.text('canvas-0'), findsOneWidget);
    expect(find.text('diagnostics-2'), findsOneWidget);
    final heightBefore = tester.getSize(pane).height;
    await tester.drag(
      find.bySemanticsLabel('Resize pane boundary'),
      const Offset(0, 80),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(pane).height, greaterThan(heightBefore + 40));
    expect(tester.getSize(pane).width, closeTo(initial.width, 1));

    await tester.tap(find.text('Close').last);
    await tester.pumpAndSettle();
    expect(find.text('canvas-0'), findsOneWidget);
    expect(find.text('Close'), findsNothing);
  });
  testWidgets('Manual opens beside the widest pane and reuses its page', (
    tester,
  ) async {
    final paneSystemKey = GlobalKey<PaneSystemState>();
    await tester.pumpWidget(
      _host(paneSystemKey: paneSystemKey, contentBuilder: _manualContent),
    );

    Future<void> splitHorizontally(int paneId) async {
      await tester.tap(find.byKey(ValueKey('split-menu-$paneId')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Side by side'));
      await tester.pumpAndSettle();
    }

    Future<void> selectCanvas(int paneId) async {
      await tester.tap(find.byKey(ValueKey('pane-mode-$paneId')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Canvas').last);
      await tester.pumpAndSettle();
    }

    await splitHorizontally(0);
    await selectCanvas(1);
    await splitHorizontally(1);
    await selectCanvas(2);
    await tester.tap(find.text('canvas-2'));
    await tester.pumpAndSettle();

    final widestBefore = tester.getSize(find.byKey(const ValueKey('pane-0')));
    expect(
      widestBefore.width,
      greaterThan(tester.getSize(find.byKey(const ValueKey('pane-1'))).width),
    );
    paneSystemKey.currentState!.openManual(HelpId.openDocument);
    await tester.pumpAndSettle();

    expect(find.byType(ManualPane), findsOneWidget);
    final paneZero = find.byKey(const ValueKey('pane-0'));
    final manualPane = find.byKey(const ValueKey('pane-3'));
    final paneOne = find.byKey(const ValueKey('pane-1'));
    final paneTwo = find.byKey(const ValueKey('pane-2'));
    expect(tester.getSize(paneZero).width, lessThan(widestBefore.width));
    expect(
      tester.getTopLeft(paneZero).dx,
      lessThan(tester.getTopLeft(manualPane).dx),
    );
    expect(
      tester.getTopLeft(manualPane).dx,
      lessThan(tester.getTopLeft(paneOne).dx),
    );
    expect(
      tester.getTopLeft(paneOne).dx,
      lessThan(tester.getTopLeft(paneTwo).dx),
    );

    final saveDocumentItem = find.byKey(
      const ValueKey('manual-item-saveDocument'),
    );
    await tester.ensureVisible(saveDocumentItem);
    await tester.tap(saveDocumentItem);
    await tester.pumpAndSettle();
    final article = find.byKey(const ValueKey('manual-article'));
    expect(
      find.descendant(
        of: article,
        matching: find.text(ManualCatalog.article(HelpId.saveDocument).title),
      ),
      findsOneWidget,
    );

    paneSystemKey.currentState!.openManual(HelpId.canvas);
    await tester.pumpAndSettle();
    expect(find.byType(ManualPane), findsOneWidget);
    expect(
      find.descendant(
        of: article,
        matching: find.text(ManualCatalog.article(HelpId.canvas).title),
      ),
      findsOneWidget,
    );
  });
}
