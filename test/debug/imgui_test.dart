// What: Widget tests for the ImGui-style widget kit: ImWindow (drag, clamping,
//   collapse, close), ImSection, ImCheckbox, ImSliderInt (pointer and
//   accessibility input), ImButton, ImPlot and ImStackedBar.
// Why: The kit is the building block of the debug pane (ADR 0006) and is
//   written with ordinary retained Flutter widgets, so its window drag,
//   clamping and gesture behavior is pinned here. Two tests below are
//   regressions for bugs that docs/status.md ("Debug Pane Verification")
//   lists as found and fixed by tests (bugs 1 and 2); each is marked where
//   it appears. Bug 3 (Pause) is covered in canvas_debug_pane_test.dart.
// Covers: lib/debug/imgui.dart (ImWindow, ImSection, ImCheckbox, ImButton,
//   ImSliderInt, ImPlot, ImStackedBar, ImSegment, ImText).
//
// Overview: the kit under test
// ----------------------------
// lib/debug/imgui.dart is a small widget kit that imitates Dear ImGui's dense,
// flat look. It is not an immediate-mode engine and knows nothing about the
// painter (ADR 0006), so these tests need no canvas, document or tile cache:
// each test pumps a few kit widgets into a bare MaterialApp + Stack and drives
// them with synthetic taps/drags (WidgetTester) or the semantics tree.
//
// Strategy: widget-driven and headless (docs/testing.md); positions and
// callbacks are asserted, not pixels. Layout uses the test font (Ahem), so
// nothing here checks glyph shapes or the Menlo typeface, theme colors, or how
// the kit looks in a running macOS window (not verified per docs/status.md).
// ImPlot and ImStackedBar are only checked for readout text and for not
// throwing on degenerate data, not for what they paint. ImValue, ImSeparator
// and ImLegend are not tested here directly (ImValue is exercised through the
// pane tests in canvas_debug_pane_test.dart).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:painter/debug/imgui.dart';

/// Finds the window's visible box (the DecoratedBox around the title 'win')
/// so tests can read the window's on-screen rectangle. ImWindow itself fills
/// its parent so it can measure it; only this inner box has the window's size.
Finder _box() => find
    .ancestor(of: find.text('win'), matching: find.byType(DecoratedBox))
    .first;

/// Hosts [children] in a Stack of a known [size] (default 800x600). ImWindow
/// is a Positioned.fill that measures its container with a LayoutBuilder, so
/// the tests need a Stack with a definite size to make clamping predictable.
Widget _host(List<Widget> children, {Size size = const Size(800, 600)}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: Scaffold(body: Stack(children: children)),
    ),
  );
}

void main() {
  testWidgets('title bar drag moves the window', (tester) async {
    await tester.pumpWidget(
      _host([
        const ImWindow(
          title: 'win',
          initialOffset: Offset(50, 60),
          children: [ImText('body')],
        ),
      ]),
    );
    expect(tester.getTopLeft(_box()), const Offset(50, 60));

    // Many small moves so the drag slop is a fixed, small loss.
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('win')),
    );
    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(const Offset(4, 2));
    }
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 100));

    final moved = tester.getTopLeft(_box()) - const Offset(50, 60);
    expect(moved.dx, inInclusiveRange(40, 80));
    expect(moved.dy, inInclusiveRange(20, 40));
    expect(
      moved.dx / moved.dy,
      closeTo(2, 0.35),
      reason: 'follows the pointer',
    );
  });

  // Regression (status.md bug 1): with a window dragged far off screen its
  // stored offset used to keep drifting, so it could not be dragged back and
  // its close button could become unreachable. Pins ImWindow._clamped, which
  // clamps the stored offset in the drag handler, not just the painted one.
  testWidgets('a dragged window cannot be lost off screen', (tester) async {
    await tester.pumpWidget(
      _host([
        const ImWindow(
          title: 'win',
          initialOffset: Offset(50, 60),
          width: 320,
          children: [],
        ),
      ]),
    );
    await tester.drag(find.text('win'), const Offset(5000, 5000));
    await tester.pump(const Duration(milliseconds: 100));
    final rect = tester.getRect(_box());
    expect(
      rect.right,
      lessThanOrEqualTo(800),
      reason: 'close button stays on screen',
    );
    expect(rect.top, lessThan(600));
    expect(find.text('win').hitTestable(), findsOneWidget);

    // Stored offset is clamped too, so dragging back works immediately rather
    // than after undoing the 5000px overshoot.
    await tester.drag(find.text('win'), const Offset(-100, -100));
    await tester.pump(const Duration(milliseconds: 100));
    final back = tester.getRect(_box());
    expect(back.left, lessThan(rect.left));
    expect(back.top, lessThan(rect.top));
  });

  // Pins the "window wider than its container" branch of ImWindow._clamped.
  testWidgets('a window wider than the screen pins to the left edge', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host([
        const ImWindow(
          title: 'win',
          initialOffset: Offset(300, 10),
          width: 900,
          children: [],
        ),
      ]),
    );
    await tester.drag(find.text('win'), const Offset(10, 0));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getTopLeft(_box()).dx, 0);
  });

  // The double-tap recognizer sits on the title text only; the arrow expands a
  // collapsed window with a single tap.
  testWidgets('double-tapping the title collapses, the arrow expands', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host([
        const ImWindow(title: 'win', children: [ImText('body text')]),
      ]),
    );
    expect(find.text('body text'), findsOneWidget);

    await tester.tap(find.text('win'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('win'));
    await tester.pumpAndSettle();
    expect(find.text('body text'), findsNothing);

    await tester.tap(find.byIcon(Icons.arrow_right));
    await tester.pump();
    expect(find.text('body text'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget);
  });

  // Regression (status.md bug 2): a double-tap recognizer on the whole title
  // bar delayed single taps on the collapse arrow and close button by about
  // 300 ms while it waited for a possible second tap (ADR 0006).
  testWidgets(
    'arrow and close respond to a single tap with no double-tap delay',
    (tester) async {
      var closed = 0;
      await tester.pumpWidget(
        _host([
          ImWindow(
            title: 'win',
            onClose: () => closed++,
            children: const [ImText('body text')],
          ),
        ]),
      );

      // No pump(duration) between the tap and the check: a recognizer waiting for
      // a second tap would still be holding the first.
      await tester.tap(find.byIcon(Icons.arrow_drop_down));
      await tester.pump();
      expect(find.text('body text'), findsNothing);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(closed, 1);
    },
  );

  testWidgets('sections toggle and keep open state across rebuilds', (
    tester,
  ) async {
    final label = ValueNotifier('a');
    await tester.pumpWidget(
      _host([
        ImWindow(
          title: 'win',
          children: [
            ValueListenableBuilder<String>(
              valueListenable: label,
              builder: (_, value, _) =>
                  ImSection(title: 'sec', children: [ImText('content $value')]),
            ),
          ],
        ),
      ]),
    );
    expect(find.text('content a'), findsOneWidget);
    await tester.tap(find.text('sec'));
    await tester.pump();
    expect(find.textContaining('content'), findsNothing);

    label.value = 'b';
    await tester.pump();
    expect(
      find.textContaining('content'),
      findsNothing,
      reason: 'stays closed',
    );
    await tester.tap(find.text('sec'));
    await tester.pump();
    expect(find.text('content b'), findsOneWidget);
  });

  testWidgets('checkbox reports the toggled value', (tester) async {
    final seen = <bool>[];
    await tester.pumpWidget(
      _host([
        ImWindow(
          title: 'win',
          children: [
            ImCheckbox(label: 'flag', value: false, onChanged: seen.add),
          ],
        ),
      ]),
    );
    await tester.tap(find.text('flag'));
    expect(seen, [true]);
  });

  // The bar is pointer-position driven (ImSliderInt._at): clamped at both ends,
  // even when the drag goes far past the track.
  testWidgets('slider maps drag position to a clamped integer', (tester) async {
    final seen = <int>[];
    await tester.pumpWidget(
      _host([
        ImWindow(
          title: 'win',
          width: 400,
          children: [
            ImSliderInt(
              label: 'n',
              value: 5,
              min: 0,
              max: 10,
              onChanged: seen.add,
            ),
          ],
        ),
      ]),
    );
    final bar = find.byType(ImSliderInt);
    final rect = tester.getRect(bar);
    // Track spans the row minus the 6px gap and 110px label column.
    await tester.tapAt(Offset(rect.left + 1, rect.center.dy));
    expect(seen.last, 0);
    await tester.tapAt(Offset(rect.left + 200, rect.center.dy));
    expect(seen.last, inInclusiveRange(1, 9));
    await tester.dragFrom(
      Offset(rect.left + 10, rect.center.dy),
      const Offset(5000, 0),
    );
    expect(seen.last, 10);
    expect(seen, everyElement(inInclusiveRange(0, 10)));
  });

  // The slider's Semantics (excludeSemantics: true) must stay operable for
  // assistive tech via increase/decrease actions, not only pointer input.
  testWidgets('slider exposes increase/decrease to accessibility', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final seen = <int>[];
    await tester.pumpWidget(
      _host([
        ImWindow(
          title: 'win',
          children: [
            ImSliderInt(
              label: 'n',
              value: 3,
              min: 0,
              max: 4,
              onChanged: seen.add,
            ),
          ],
        ),
      ]),
    );
    final node = tester.getSemantics(find.bySemanticsLabel('n'));
    expect(node.value, '3');
    tester.semantics.increase(find.semantics.byLabel('n'));
    tester.semantics.decrease(find.semantics.byLabel('n'));
    expect(seen, [4, 2]);
    handle.dispose();
  });

  testWidgets('disabled button ignores taps', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(
      _host([
        ImWindow(
          title: 'win',
          children: [
            ImButton(label: 'on', onPressed: () => pressed++),
            const ImButton(label: 'off', onPressed: null),
          ],
        ),
      ]),
    );
    await tester.tap(find.text('on'));
    await tester.tap(find.text('off'));
    expect(pressed, 1);
  });

  // The assertions are on the readout text; takeException guards the paint
  // path for an empty series, a one-sample-or-fewer series and an all-zero
  // series (ImPlot scales by max(max, 1e-6) so a flat zero plot never divides
  // by zero).
  testWidgets('plot reports min/avg/max and tolerates empty or flat data', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host([
        const ImWindow(
          title: 'win',
          children: [
            ImPlot(label: 'empty', samples: []),
            ImPlot(label: 'flat', samples: [0, 0, 0], unit: 'ms'),
            ImPlot(label: 'ramp', samples: [1, 2, 3], unit: 'ms'),
          ],
        ),
      ]),
    );
    expect(find.textContaining('empty  (no samples)'), findsOneWidget);
    expect(find.textContaining('min 0.00ms'), findsOneWidget);
    expect(
      find.textContaining('min 1.00ms  avg 2.00ms  max 3.00ms'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('stacked bar ignores empty and all-zero segments', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host([
        const ImWindow(
          title: 'win',
          children: [
            ImStackedBar(segments: []),
            ImStackedBar(segments: [ImSegment(0, Colors.red, 'a')]),
            ImStackedBar(
              segments: [
                ImSegment(3, Colors.red, 'a'),
                ImSegment(0, Colors.blue, 'b'),
              ],
            ),
          ],
        ),
      ]),
    );
    expect(tester.takeException(), isNull);
  });
}
