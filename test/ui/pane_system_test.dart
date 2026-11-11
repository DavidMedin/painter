// What: Widget tests for PaneSystem: mode selection, the frame-edge toolbars
//   (add, join, swap), disabled states, rotation, splitter drags and the 10%
//   clamp, handle placement, minimum-size rendering, help ids, and redraws
//   after remote edits.
// Why: PaneSystem turns the Workspace's projection into the chrome that
//   docs/spec/panes.md describes. These tests protect what a user can see
//   and do: where a new pane appears, when a button is disabled (PANE-14,
//   PANE-25, PANE-27), and that dragging never pushes a pane below 10% of the
//   workspace (PANE-26).
// Covers: lib/ui/pane_system.dart (with lib/workspace/workspace.dart as its
//   model over a real Automerge document). Model rules are tested in
//   test/workspace/.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:painter/help/contextual_help.dart';
import 'package:painter/ui/pane_system.dart';
import 'package:painter/workspace/layout_tree.dart';
import 'package:painter/workspace/pane_kind.dart';
import 'package:painter/workspace/workspace.dart';

import '../workspace/workspace_test_support.dart';

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

/// A frame button of the pane at [index] in tree order.
Finder _button(PaneEdge edge, String action, int index) =>
    find.byKey(ValueKey('frame-${edge.name}-$action-$index'));

/// The mode dropdown of the pane at [index] in tree order.
Finder _mode(int index) => find.byKey(ValueKey('pane-mode-$index'));

/// The frame of pane [id].
Finder _frame(String id) => find.byKey(ValueKey('pane-$id'));

/// The splitter [splitter] of the shown layout.
Finder _splitter(LayoutSplitter splitter) =>
    find.byKey(ValueKey('splitter-${splitter.key}'));

bool _enabled(WidgetTester tester, Finder button) {
  final ink = find.descendant(of: button, matching: find.byType(InkWell));
  return tester.widget<InkWell>(ink).onTap != null;
}

Future<void> _press(WidgetTester tester, Finder button) async {
  await tester.tap(button);
  await tester.pumpAndSettle();
}

/// A workspace shown in an 800x600 PaneSystem.
Future<Workspace> _shown(WidgetTester tester) async {
  final workspace = openWorkspace();
  await tester.pumpWidget(_host(workspace));
  return workspace;
}

/// Four panes in a 2x2 grid built by splitting the left and right halves
/// separately: tree order top left, bottom left, top right, bottom right.
/// One vertical splitter runs the full height.
Future<Workspace> _columnsGrid(WidgetTester tester) async {
  final workspace = await _shown(tester);
  await _press(tester, _button(PaneEdge.right, 'add', 0));
  await _press(tester, _button(PaneEdge.bottom, 'add', 0));
  await _press(tester, _button(PaneEdge.bottom, 'add', 2));
  return workspace;
}

/// Four panes in a 2x2 grid built by splitting the top and bottom halves
/// separately: tree order top left, top right, bottom left, bottom right.
/// Each half has its own vertical splitter.
Future<Workspace> _rowsGrid(WidgetTester tester) async {
  final workspace = await _shown(tester);
  await _press(tester, _button(PaneEdge.bottom, 'add', 0));
  await _press(tester, _button(PaneEdge.right, 'add', 0));
  await _press(tester, _button(PaneEdge.right, 'add', 2));
  return workspace;
}

void main() {
  testWidgets('pane controls expose their contextual help', (tester) async {
    final helpState = HelpState();
    final pointer = TestPointer(42, PointerDeviceKind.mouse);
    final workspace = openWorkspace();
    addTearDown(helpState.dispose);
    await tester.pumpWidget(_host(workspace, helpState: helpState));

    Future<void> hover(Finder target, HelpId expected) async {
      await tester.sendEventToBinding(pointer.hover(tester.getCenter(target)));
      await tester.pump();
      expect(helpState.activeTopic, expected);
    }

    await hover(_mode(0), HelpIds.paneType);
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
    final workspace = await _shown(tester);
    await _press(tester, _button(PaneEdge.right, 'add', 0));
    final [left, right] = workspace.paneIds;

    await _press(tester, _mode(1));
    await _press(tester, find.text('Diagnostics').last);

    expect(find.text('canvas-$left'), findsOneWidget);
    expect(find.text('diagnostics-$right'), findsOneWidget);
    expect(find.text('canvas-$right'), findsNothing);
    expect(workspace.kindOf(right), PaneKind.diagnostics);
  });

  for (final edge in PaneEdge.values) {
    testWidgets('add on the ${edge.name} edge puts the new pane there', (
      tester,
    ) async {
      final workspace = await _shown(tester);
      final id = workspace.paneIds.single;
      final before = tester.getRect(_frame(id));

      await _press(tester, _button(edge, 'add', 0));

      final addedId = workspace.paneIds.firstWhere((other) => other != id);
      final original = tester.getRect(_frame(id));
      final added = tester.getRect(_frame(addedId));
      expect(find.text('canvas-$addedId'), findsOneWidget);
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
    await _shown(tester);
    // A single pane borders only the workspace boundary.
    for (final edge in PaneEdge.values) {
      expect(_enabled(tester, _button(edge, 'join', 0)), isFalse);
      expect(_enabled(tester, _button(edge, 'swap', 0)), isFalse);
      expect(_enabled(tester, _button(edge, 'add', 0)), isTrue);
    }

    // Pane 0 on the left, panes 1 and 2 stacked on the right: pane 0's right
    // edge is bordered by two panes (PANE-14).
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
    final workspace = await _shown(tester);
    await _press(tester, _button(PaneEdge.right, 'add', 0));
    final [left, right] = workspace.paneIds;
    await _press(tester, _mode(1));
    await _press(tester, find.text('Log').last);

    await _press(tester, _button(PaneEdge.right, 'join', 0));

    expect(find.text('canvas-$left'), findsOneWidget);
    expect(find.text('log-$right'), findsNothing);
    expect(_frame(right), findsNothing);
    expect(
      tester.getSize(_frame(left)),
      tester.getSize(find.byType(PaneSystem)),
    );
    expect(find.bySemanticsLabel('Resize pane boundary'), findsNothing);
  });

  testWidgets('joining aligned panes of different splits reshapes the tree '
      '(PANE-25)', (tester) async {
    final workspace = await _rowsGrid(tester);
    final [topLeft, topRight, bottomLeft, bottomRight] = workspace.paneIds;
    expect(_enabled(tester, _button(PaneEdge.bottom, 'join', 0)), isTrue);

    await _press(tester, _button(PaneEdge.bottom, 'join', 0));

    expect(workspace.paneIds, unorderedEquals([topLeft, topRight, bottomRight]));
    expect(_frame(bottomLeft), findsNothing);
    final left = tester.getRect(_frame(topLeft));
    expect(left.top, tester.getRect(_frame(topRight)).top);
    expect(left.bottom, tester.getRect(_frame(bottomRight)).bottom);
  });

  testWidgets('a moved splitter breaks the alignment of the other half', (
    tester,
  ) async {
    final workspace = await _rowsGrid(tester);
    final bottomSplitter = workspace.splitters.lastWhere(
      (splitter) => splitter.vertical,
    );
    expect(_enabled(tester, _button(PaneEdge.bottom, 'swap', 0)), isTrue);

    await tester.dragFrom(
      tester.getCenter(_splitter(bottomSplitter)),
      const Offset(100, 0),
    );
    await tester.pumpAndSettle();

    // The top-left pane's bottom edge now borders two panes.
    expect(_enabled(tester, _button(PaneEdge.bottom, 'join', 0)), isFalse);
    expect(_enabled(tester, _button(PaneEdge.bottom, 'swap', 0)), isFalse);
  });

  testWidgets('swap exchanges the content of two panes in place', (
    tester,
  ) async {
    final workspace = await _shown(tester);
    await _press(tester, _button(PaneEdge.right, 'add', 0));
    final [left, right] = workspace.paneIds;
    await _press(tester, _mode(1));
    await _press(tester, find.text('Settings').last);
    final leftBefore = tester.getRect(_frame(left));

    await _press(tester, _button(PaneEdge.right, 'swap', 0));

    expect(find.text('settings-$left'), findsOneWidget);
    expect(find.text('canvas-$right'), findsOneWidget);
    expect(tester.getRect(_frame(left)), leftBefore);
  });

  testWidgets('add is disabled below 20% of the workspace (PANE-27)', (
    tester,
  ) async {
    final workspace = await _shown(tester);
    final id = workspace.paneIds.single;

    // Widths 100%, 50% and 25% may be halved; 12.5% may not.
    for (var i = 0; i < 3; i++) {
      expect(_enabled(tester, _button(PaneEdge.right, 'add', 0)), isTrue);
      await _press(tester, _button(PaneEdge.right, 'add', 0));
    }
    expect(_enabled(tester, _button(PaneEdge.right, 'add', 0)), isFalse);
    expect(_enabled(tester, _button(PaneEdge.left, 'add', 0)), isFalse);
    // The pane is still tall enough to split the other way.
    expect(_enabled(tester, _button(PaneEdge.top, 'add', 0)), isTrue);
    expect(tester.takeException(), isNull);
    expect(workspace.rectOf(id).width, closeTo(0.125, 1e-9));
  });

  testWidgets('left and right toolbars are rotated, top and bottom are not', (
    tester,
  ) async {
    await _shown(tester);

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
    final workspace = await _shown(tester);
    final pane = tester.getRect(_frame(workspace.paneIds.single));

    Offset at(PaneEdge edge) => tester.getCenter(_button(edge, 'join', 0));
    expect(at(PaneEdge.top).dy, lessThan(pane.top + 30));
    expect(at(PaneEdge.bottom).dy, greaterThan(pane.bottom - 30));
    expect(at(PaneEdge.left).dx, lessThan(pane.left + 30));
    expect(at(PaneEdge.right).dx, greaterThan(pane.right - 30));
    // Every strip is centered along its edge.
    expect(at(PaneEdge.top).dx, closeTo(pane.center.dx, 1));
    expect(at(PaneEdge.left).dy, closeTo(pane.center.dy, 40));
  });

  testWidgets('dragging a splitter resizes both panes and stops at 10% '
      '(PANE-26)', (tester) async {
    final workspace = await _shown(tester);
    await _press(tester, _button(PaneEdge.right, 'add', 0));
    final [left, right] = workspace.paneIds;
    final splitter = find.bySemanticsLabel('Resize pane boundary');
    final leftBefore = tester.getSize(_frame(left));
    final rightBefore = tester.getSize(_frame(right));

    await tester.drag(splitter, const Offset(80, 0));
    await tester.pumpAndSettle();
    // Drag recognition swallows the first ~20 px, so compare the two panes
    // with each other rather than with the finger travel.
    final grown = tester.getSize(_frame(left)).width - leftBefore.width;
    final shrunk = rightBefore.width - tester.getSize(_frame(right)).width;
    expect(grown, greaterThan(40));
    expect(grown, closeTo(shrunk, 1));

    // A drag far past the limit leaves the right pane 10% of the workspace.
    await tester.drag(splitter, const Offset(2000, 0));
    await tester.pumpAndSettle();
    expect(workspace.rectOf(right).width, closeTo(0.1, 1e-9));
    expect(tester.takeException(), isNull);

    await tester.drag(splitter, const Offset(-2000, 0));
    await tester.pumpAndSettle();
    expect(workspace.rectOf(left).width, closeTo(0.1, 1e-9));
  });

  testWidgets('several drag updates between frames all take effect', (
    tester,
  ) async {
    final workspace = await _shown(tester);
    await _press(tester, _button(PaneEdge.right, 'add', 0));
    final left = workspace.paneIds.first;
    final before = workspace.rectOf(left).width * 800;

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
    final grown = workspace.rectOf(left).width * 800 - before;
    expect(grown, greaterThan(25));
    expect(grown, lessThanOrEqualTo(50 + 1e-6));
  });

  testWidgets('one drag moves the whole boundary of a split', (tester) async {
    final workspace = await _columnsGrid(tester);
    final [topLeft, bottomLeft, topRight, bottomRight] = workspace.paneIds;
    final vertical = workspace.splitters.singleWhere(
      (splitter) => splitter.vertical,
    );
    expect(_splitter(vertical), findsOneWidget);

    // Start away from the middle, where the horizontal splitters meet it.
    await tester.dragFrom(
      tester.getTopLeft(_splitter(vertical)) + const Offset(4, 100),
      const Offset(100, 0),
    );
    await tester.pumpAndSettle();

    final upper = tester.getRect(_frame(topLeft));
    final lower = tester.getRect(_frame(bottomLeft));
    expect(upper.right, lower.right);
    expect(upper.width, greaterThan(400 - 4 + 50));
    // The panes stay joinable: their borders are still exactly aligned.
    expect(_enabled(tester, _button(PaneEdge.right, 'join', 0)), isTrue);
    expect(_enabled(tester, _button(PaneEdge.right, 'join', 1)), isTrue);
    expect(workspace.rectOf(topRight).left, workspace.rectOf(bottomRight).left);
  });

  testWidgets('a splitter handle sits at the center of its splitter', (
    tester,
  ) async {
    final workspace = await _columnsGrid(tester);
    expect(workspace.splitters, hasLength(3));
    for (final splitter in workspace.splitters) {
      final finder = _splitter(splitter);
      final handle = find.descendant(
        of: finder,
        matching: find.byType(Container),
      );
      expect(handle, findsOneWidget);
      final center = tester.getCenter(finder);
      final grip = tester.getCenter(handle);
      expect(grip.dx, closeTo(center.dx, 0.5));
      expect(grip.dy, closeTo(center.dy, 0.5));
    }
  });

  testWidgets('pane frames do not overlap and leave no gap but splitters', (
    tester,
  ) async {
    final workspace = await _columnsGrid(tester);
    final rects = [
      for (final id in workspace.paneIds) tester.getRect(_frame(id)),
    ];
    for (var i = 0; i < rects.length; i++) {
      for (var j = i + 1; j < rects.length; j++) {
        final overlap = rects[i].intersect(rects[j]);
        expect(overlap.width <= 0 || overlap.height <= 0, isTrue);
      }
    }
    // Between the two columns and the two rows lies exactly one 8 px
    // splitter.
    final [topLeft, bottomLeft, topRight, _] = rects;
    expect(topRight.left - topLeft.right, closeTo(8, 1e-6));
    expect(bottomLeft.top - topLeft.bottom, closeTo(8, 1e-6));
  });

  testWidgets('panes at the minimum size and smaller build without errors', (
    tester,
  ) async {
    final originalSize = tester.view.physicalSize;
    addTearDown(() => tester.view.physicalSize = originalSize);
    await _shown(tester);
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
    final workspace = await _shown(tester);
    await _press(tester, _button(PaneEdge.right, 'add', 0));
    final [left, right] = workspace.paneIds;
    final primary = Theme.of(
      tester.element(find.byType(PaneSystem)),
    ).colorScheme.primary;

    Color frame(String id) {
      final listener = tester.widget<Listener>(_frame(id));
      final box = listener.child! as DecoratedBox;
      return ((box.decoration as BoxDecoration).border! as Border).top.color;
    }

    await tester.tap(find.text('canvas-$left'));
    await tester.pump();
    expect(frame(left), primary);
    expect(frame(right), isNot(primary));
  });

  testWidgets('edits of another Member are drawn when they arrive '
      '(WKSP-33)', (tester) async {
    final local = sessionWithDefaultWorkspace();
    final remote = replicaOf(local);
    final shown = openWorkspace(session: local);
    final other = openWorkspace(session: remote);
    await tester.pumpWidget(_host(shown));
    final id = shown.paneIds.single;

    final added = other.add(id, PaneEdge.bottom)!;
    other.setKind(added, PaneKind.log);
    syncAll([local, remote]);
    await tester.pumpAndSettle();

    expect(find.text('canvas-$id'), findsOneWidget);
    expect(find.text('log-$added'), findsOneWidget);
    expect(find.bySemanticsLabel('Resize pane boundary'), findsOneWidget);
  });
}
