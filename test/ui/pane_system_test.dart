// What: Widget tests for PaneSystem: mode selection, the frame-edge toolbars
//   (add, join, swap), disabled states, rotation, splitter drags and the
//   100 px clamp, handle placement, minimum-size rendering, and help ids.
// Why: PaneSystem turns Workspace state into the chrome that docs/spec/panes.md
//   describes. These tests protect what a user can see and do: where a new
//   pane appears, when a button is disabled, and that dragging never pushes a
//   pane below 100 px.
// Covers: lib/ui/pane_system.dart (with lib/workspace/workspace.dart as its
//   model). Model rules are tested in test/workspace/.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:painter/help/contextual_help.dart';
import 'package:painter/ui/pane_system.dart';
import 'package:painter/workspace/pane_kind.dart';
import 'package:painter/workspace/pane_layout.dart';
import 'package:painter/workspace/workspace.dart';

Widget _content(BuildContext context, PaneDescriptor pane) =>
    Center(child: Text('${pane.kind.name}-${pane.id}'));

Widget _host(Workspace workspace, {HelpState? helpState}) {
  Widget system = SizedBox.expand(
    child: PaneSystem(workspace: workspace, contentBuilder: _content),
  );
  if (helpState != null) {
    system = HelpScope(helpState: helpState, child: system);
  }
  return MaterialApp(home: Scaffold(body: system));
}

Finder _button(PaneEdge edge, String action, int paneId) =>
    find.byKey(ValueKey('frame-${edge.name}-$action-$paneId'));

bool _enabled(WidgetTester tester, Finder button) {
  final ink = find.descendant(of: button, matching: find.byType(InkWell));
  return tester.widget<InkWell>(ink).onTap != null;
}

Future<void> _press(WidgetTester tester, Finder button) async {
  await tester.tap(button);
  await tester.pumpAndSettle();
}

/// Four panes in a 2x2 grid: 0 top left, 1 top right, 2 bottom left, 3 bottom
/// right.
Future<Workspace> _grid(WidgetTester tester) async {
  final workspace = Workspace();
  addTearDown(workspace.dispose);
  await tester.pumpWidget(_host(workspace));
  await _press(tester, _button(PaneEdge.right, 'add', 0));
  await _press(tester, _button(PaneEdge.bottom, 'add', 0));
  await _press(tester, _button(PaneEdge.bottom, 'add', 1));
  return workspace;
}

void main() {
  testWidgets('pane controls expose their contextual help', (tester) async {
    final helpState = HelpState();
    final pointer = TestPointer(42, PointerDeviceKind.mouse);
    final workspace = Workspace();
    addTearDown(helpState.dispose);
    addTearDown(workspace.dispose);
    await tester.pumpWidget(_host(workspace, helpState: helpState));

    Future<void> hover(Finder target, HelpId expected) async {
      await tester.sendEventToBinding(pointer.hover(tester.getCenter(target)));
      await tester.pump();
      expect(helpState.activeTopic, expected);
    }

    await hover(find.byKey(const ValueKey('pane-mode-0')), HelpIds.paneType);
    await hover(_button(PaneEdge.right, 'add', 0), HelpIds.paneBoundary);
    await _press(tester, _button(PaneEdge.right, 'add', 0));
    await hover(
      find.bySemanticsLabel('Resize pane boundary'),
      HelpIds.paneBoundary,
    );
  });

  testWidgets('the mode dropdown replaces the content of its pane only', (
    tester,
  ) async {
    final workspace = Workspace();
    addTearDown(workspace.dispose);
    await tester.pumpWidget(_host(workspace));
    await _press(tester, _button(PaneEdge.right, 'add', 0));

    await _press(tester, find.byKey(const ValueKey('pane-mode-1')));
    await _press(tester, find.text('Diagnostics').last);

    expect(find.text('canvas-0'), findsOneWidget);
    expect(find.text('diagnostics-1'), findsOneWidget);
    expect(find.text('canvas-1'), findsNothing);
    expect(workspace.kindOf(1), PaneKind.diagnostics);
  });

  for (final edge in PaneEdge.values) {
    testWidgets('add on the ${edge.name} edge puts the new pane there', (
      tester,
    ) async {
      final workspace = Workspace();
      addTearDown(workspace.dispose);
      await tester.pumpWidget(_host(workspace));
      final before = tester.getRect(find.byKey(const ValueKey('pane-0')));

      await _press(tester, _button(edge, 'add', 0));

      final original = tester.getRect(find.byKey(const ValueKey('pane-0')));
      final added = tester.getRect(find.byKey(const ValueKey('pane-1')));
      expect(find.text('canvas-1'), findsOneWidget);
      switch (edge) {
        case PaneEdge.top:
          expect(added.bottom, lessThanOrEqualTo(original.top));
          expect(added.top, before.top);
        case PaneEdge.bottom:
          expect(added.top, greaterThanOrEqualTo(original.bottom));
          expect(added.bottom, before.bottom);
        case PaneEdge.left:
          expect(added.right, lessThanOrEqualTo(original.left));
          expect(added.left, before.left);
        case PaneEdge.right:
          expect(added.left, greaterThanOrEqualTo(original.right));
          expect(added.right, before.right);
      }
      // The two panes split the former pane between them.
      if (edge.isVertical) {
        expect(added.width + original.width, closeTo(before.width - 8, 1));
      } else {
        expect(added.height + original.height, closeTo(before.height - 8, 1));
      }
    });
  }

  testWidgets('join and swap are disabled on edges without one neighbor', (
    tester,
  ) async {
    final workspace = Workspace();
    addTearDown(workspace.dispose);
    await tester.pumpWidget(_host(workspace));
    // A single pane borders only the workspace boundary.
    for (final edge in PaneEdge.values) {
      expect(_enabled(tester, _button(edge, 'join', 0)), isFalse);
      expect(_enabled(tester, _button(edge, 'swap', 0)), isFalse);
      expect(_enabled(tester, _button(edge, 'add', 0)), isTrue);
    }

    // Pane 0 on the left, panes 1 and 2 stacked on the right: pane 0's right
    // edge is bordered by two panes.
    await _press(tester, _button(PaneEdge.right, 'add', 0));
    await _press(tester, _button(PaneEdge.bottom, 'add', 1));
    expect(_enabled(tester, _button(PaneEdge.right, 'join', 0)), isFalse);
    expect(_enabled(tester, _button(PaneEdge.right, 'swap', 0)), isFalse);
    expect(_enabled(tester, _button(PaneEdge.left, 'join', 1)), isFalse);
    // Panes 1 and 2 share a whole edge.
    expect(_enabled(tester, _button(PaneEdge.bottom, 'join', 1)), isTrue);
    expect(_enabled(tester, _button(PaneEdge.top, 'swap', 2)), isTrue);
  });

  testWidgets('join absorbs the neighbor and keeps the pane mode', (
    tester,
  ) async {
    final workspace = Workspace();
    addTearDown(workspace.dispose);
    await tester.pumpWidget(_host(workspace));
    await _press(tester, _button(PaneEdge.right, 'add', 0));
    await _press(tester, find.byKey(const ValueKey('pane-mode-1')));
    await _press(tester, find.text('Log').last);

    await _press(tester, _button(PaneEdge.right, 'join', 0));

    expect(find.text('canvas-0'), findsOneWidget);
    expect(find.text('log-1'), findsNothing);
    expect(find.byKey(const ValueKey('pane-1')), findsNothing);
    expect(
      tester.getSize(find.byKey(const ValueKey('pane-0'))),
      tester.getSize(find.byType(PaneSystem)),
    );
    expect(find.bySemanticsLabel('Resize pane boundary'), findsNothing);
  });

  testWidgets('swap exchanges the content of two panes in place', (
    tester,
  ) async {
    final workspace = Workspace();
    addTearDown(workspace.dispose);
    await tester.pumpWidget(_host(workspace));
    await _press(tester, _button(PaneEdge.right, 'add', 0));
    await _press(tester, find.byKey(const ValueKey('pane-mode-1')));
    await _press(tester, find.text('Settings').last);
    final leftBefore = tester.getRect(find.byKey(const ValueKey('pane-0')));

    await _press(tester, _button(PaneEdge.right, 'swap', 0));

    expect(find.text('settings-0'), findsOneWidget);
    expect(find.text('canvas-1'), findsOneWidget);
    expect(tester.getRect(find.byKey(const ValueKey('pane-0'))), leftBefore);
  });

  testWidgets('add is disabled once a pane is too small to halve', (
    tester,
  ) async {
    final workspace = Workspace();
    addTearDown(workspace.dispose);
    await tester.pumpWidget(_host(workspace));

    // 800 -> 400 -> 200 -> 100 px: the third split still leaves two 100 px
    // halves, the fourth would not.
    for (var i = 0; i < 3; i++) {
      expect(_enabled(tester, _button(PaneEdge.right, 'add', 0)), isTrue);
      await _press(tester, _button(PaneEdge.right, 'add', 0));
    }
    expect(_enabled(tester, _button(PaneEdge.right, 'add', 0)), isFalse);
    expect(_enabled(tester, _button(PaneEdge.left, 'add', 0)), isFalse);
    // The pane is still tall enough to split the other way.
    expect(_enabled(tester, _button(PaneEdge.top, 'add', 0)), isTrue);
    expect(tester.takeException(), isNull);
    expect(workspace.layout.rect(0).width * 800, closeTo(100, 1e-6));
  });

  testWidgets('left and right toolbars are rotated, top and bottom are not', (
    tester,
  ) async {
    final workspace = Workspace();
    addTearDown(workspace.dispose);
    await tester.pumpWidget(_host(workspace));

    int? turns(PaneEdge edge) {
      final rotated = find.ancestor(
        of: _button(edge, 'add', 0),
        matching: find.byType(RotatedBox),
      );
      return rotated.evaluate().isEmpty
          ? null
          : tester.widget<RotatedBox>(rotated).quarterTurns;
    }

    expect(turns(PaneEdge.top), isNull);
    expect(turns(PaneEdge.bottom), isNull);
    // Counter-clockwise on the left, clockwise on the right.
    expect(turns(PaneEdge.left), 3);
    expect(turns(PaneEdge.right), 1);
  });

  testWidgets('toolbars lie along their own edge of the pane', (tester) async {
    final workspace = Workspace();
    addTearDown(workspace.dispose);
    await tester.pumpWidget(_host(workspace));
    final pane = tester.getRect(find.byKey(const ValueKey('pane-0')));

    Offset at(PaneEdge edge) => tester.getCenter(_button(edge, 'join', 0));
    expect(at(PaneEdge.top).dy, lessThan(pane.top + 30));
    expect(at(PaneEdge.bottom).dy, greaterThan(pane.bottom - 30));
    expect(at(PaneEdge.left).dx, lessThan(pane.left + 30));
    expect(at(PaneEdge.right).dx, greaterThan(pane.right - 30));
    // Every strip is centered along its edge.
    expect(at(PaneEdge.top).dx, closeTo(pane.center.dx, 1));
    expect(at(PaneEdge.left).dy, closeTo(pane.center.dy, 40));
  });

  testWidgets('dragging a splitter resizes both panes and stops at 100 px', (
    tester,
  ) async {
    final workspace = Workspace();
    addTearDown(workspace.dispose);
    await tester.pumpWidget(_host(workspace));
    await _press(tester, _button(PaneEdge.right, 'add', 0));
    final splitter = find.bySemanticsLabel('Resize pane boundary');
    final leftBefore = tester.getSize(find.byKey(const ValueKey('pane-0')));
    final rightBefore = tester.getSize(find.byKey(const ValueKey('pane-1')));

    await tester.drag(splitter, const Offset(80, 0));
    await tester.pumpAndSettle();
    // Drag recognition swallows the first ~20 px, so compare the two panes
    // with each other rather than with the finger travel.
    final grown =
        tester.getSize(find.byKey(const ValueKey('pane-0'))).width -
        leftBefore.width;
    final shrunk =
        rightBefore.width -
        tester.getSize(find.byKey(const ValueKey('pane-1'))).width;
    expect(grown, greaterThan(40));
    expect(grown, closeTo(shrunk, 1));

    // A drag far past the limit leaves the right pane its 100 px share.
    await tester.drag(splitter, const Offset(2000, 0));
    await tester.pumpAndSettle();
    expect(workspace.layout.rect(1).width * 800, closeTo(100, 1e-6));
    expect(tester.takeException(), isNull);

    await tester.drag(splitter, const Offset(-2000, 0));
    await tester.pumpAndSettle();
    expect(workspace.layout.rect(0).width * 800, closeTo(100, 1e-6));
  });

  testWidgets('several drag updates between frames all take effect', (
    tester,
  ) async {
    final workspace = Workspace();
    addTearDown(workspace.dispose);
    await tester.pumpWidget(_host(workspace));
    await _press(tester, _button(PaneEdge.right, 'add', 0));
    final before = workspace.layout.rect(0).width * 800;

    final gesture = await tester.startGesture(
      tester.getCenter(find.bySemanticsLabel('Resize pane boundary')),
    );
    for (var i = 0; i < 5; i++) {
      await gesture.moveBy(const Offset(10, 0));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    // Drag recognition swallows the first ~20 px; losing every update but the
    // last would leave at most 10 px.
    final grown = workspace.layout.rect(0).width * 800 - before;
    expect(grown, greaterThan(25));
    expect(grown, lessThanOrEqualTo(50 + 1e-6));
  });

  testWidgets('one drag moves every aligned border of a shared splitter', (
    tester,
  ) async {
    final workspace = await _grid(tester);
    final vertical = find.byKey(const ValueKey('splitter-v:0,2|1,3'));
    expect(vertical, findsOneWidget);

    // Start away from the middle, where the horizontal splitter crosses.
    await tester.dragFrom(
      tester.getTopLeft(vertical) + const Offset(4, 100),
      const Offset(100, 0),
    );
    await tester.pumpAndSettle();

    final topLeft = tester.getRect(find.byKey(const ValueKey('pane-0')));
    final bottomLeft = tester.getRect(find.byKey(const ValueKey('pane-2')));
    expect(topLeft.right, bottomLeft.right);
    expect(topLeft.width, greaterThan(400 - 4 + 50));
    // The panes stay joinable: their borders are still exactly aligned.
    expect(_enabled(tester, _button(PaneEdge.right, 'join', 0)), isTrue);
    expect(_enabled(tester, _button(PaneEdge.right, 'join', 2)), isTrue);
    expect(workspace.layout.rect(1).left, workspace.layout.rect(3).left);
  });

  testWidgets('a splitter handle sits at the center of its splitter', (
    tester,
  ) async {
    await _grid(tester);
    for (final key in ['splitter-v:0,2|1,3', 'splitter-h:0,1|2,3']) {
      final splitter = find.byKey(ValueKey(key));
      final handle = find.descendant(
        of: splitter,
        matching: find.byType(Container),
      );
      expect(handle, findsOneWidget);
      final center = tester.getCenter(splitter);
      final grip = tester.getCenter(handle);
      expect(grip.dx, closeTo(center.dx, 0.5));
      expect(grip.dy, closeTo(center.dy, 0.5));
    }
  });

  testWidgets('pane frames do not overlap and leave no gap but splitters', (
    tester,
  ) async {
    await _grid(tester);
    final rects = [
      for (var id = 0; id < 4; id++)
        tester.getRect(find.byKey(ValueKey('pane-$id'))),
    ];
    for (var i = 0; i < rects.length; i++) {
      for (var j = i + 1; j < rects.length; j++) {
        final overlap = rects[i].intersect(rects[j]);
        expect(overlap.width <= 0 || overlap.height <= 0, isTrue);
      }
    }
    // Between the two columns lies exactly one 8 px splitter.
    expect(rects[1].left - rects[0].right, closeTo(8, 1e-6));
    expect(rects[3].top - rects[1].bottom, closeTo(8, 1e-6));
  });

  testWidgets('panes at the minimum size and smaller build without errors', (
    tester,
  ) async {
    final originalSize = tester.view.physicalSize;
    addTearDown(() => tester.view.physicalSize = originalSize);
    final workspace = Workspace();
    addTearDown(workspace.dispose);
    await tester.pumpWidget(_host(workspace));
    for (var i = 0; i < 3; i++) {
      await _press(tester, _button(PaneEdge.right, 'add', 0));
    }
    expect(tester.takeException(), isNull);

    // The window shrinks below what the layout needs (deferred in
    // docs/spec/panes.md): panes degrade to frames instead of overflowing.
    final ratio = tester.view.devicePixelRatio;
    tester.view.physicalSize = Size(60 * ratio, 90 * ratio);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the frame of the pane last pressed is highlighted', (
    tester,
  ) async {
    final workspace = Workspace();
    addTearDown(workspace.dispose);
    await tester.pumpWidget(_host(workspace));
    await _press(tester, _button(PaneEdge.right, 'add', 0));
    final primary = Theme.of(tester.element(find.byType(PaneSystem)))
        .colorScheme
        .primary;

    Color frame(int id) {
      final listener = tester.widget<Listener>(
        find.byKey(ValueKey('pane-$id')),
      );
      final box = listener.child! as DecoratedBox;
      return ((box.decoration as BoxDecoration).border! as Border).top.color;
    }

    await tester.tap(find.text('canvas-0'));
    await tester.pump();
    expect(frame(0), primary);
    expect(frame(1), isNot(primary));
  });
}
