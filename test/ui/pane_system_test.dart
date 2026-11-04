// What: Widget tests cover pane mode, contextual help, split direction,
//   resizing, focus, close, and docked Manual placement.
// Why: PaneSystem owns pane identity and split weights; Manual must fit the
//   nested tree without disturbing existing pane content or geometry.
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
    expect(_paneBorderColor(tester, 1), primary);
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

    final saveDocumentItem =
        find.byKey(const ValueKey('manual-item-saveDocument'));
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
