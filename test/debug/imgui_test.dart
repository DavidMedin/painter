// What: Widget tests for the ImGui-style widget kit: ImSection, ImCheckbox,
//   ImSliderInt (pointer and accessibility input), ImButton, ImPlot and
//   ImStackedBar.
// Why: The kit is the building block of the diagnostics pane
// (design/diagnostics/debug-pane.md) and
//   uses ordinary retained Flutter widgets. These tests validate control
//   transitions and numerical readouts without opening a GUI window.
// Covers: lib/debug/imgui.dart (ImSection, ImCheckbox, ImButton, ImSliderInt,
//   ImPlot, ImStackedBar, ImSegment, and ImText).
//
// Layout uses the test font (Ahem), so these tests do not check glyph shapes,
// Menlo rendering, theme colors, or the appearance of a running macOS window.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:painter/debug/imgui.dart';

Widget _host(List<Widget> children, {Size size = const Size(800, 600)}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: Scaffold(
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('sections toggle and keep open state across rebuilds', (
    tester,
  ) async {
    final label = ValueNotifier('a');
    await tester.pumpWidget(
      _host([
        ValueListenableBuilder<String>(
          valueListenable: label,
          builder: (_, value, _) =>
              ImSection(title: 'sec', children: [ImText('content $value')]),
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
      _host([ImCheckbox(label: 'flag', value: false, onChanged: seen.add)]),
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
        ImSliderInt(label: 'n', value: 5, min: 0, max: 10, onChanged: seen.add),
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
        ImSliderInt(label: 'n', value: 3, min: 0, max: 4, onChanged: seen.add),
      ]),
    );
    final node = tester.getSemantics(find.bySemanticsLabel('n'));
    expect(node.value, '3');
    tester.semantics.increase(find.semantics.byLabel('n'));
    tester.semantics.decrease(find.semantics.byLabel('n'));
    expect(seen, [4, 2]);
    handle.dispose();
  });
  testWidgets('focused slider responds to arrow keys', (tester) async {
    final seen = <int>[];
    await tester.pumpWidget(
      _host([
        ImSliderInt(label: 'n', value: 5, min: 0, max: 10, onChanged: seen.add),
      ]),
    );
    await tester.tapAt(tester.getCenter(find.byType(ImSliderInt)));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(seen.last, 6);
  });

  testWidgets('disabled button ignores taps', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(
      _host([
        ImButton(label: 'on', onPressed: () => pressed++),
        const ImButton(label: 'off', onPressed: null),
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
        const ImPlot(label: 'empty', samples: []),
        ImPlot(label: 'flat', samples: [0, 0, 0], unit: 'ms'),
        ImPlot(label: 'ramp', samples: [1, 2, 3], unit: 'ms'),
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
        const ImStackedBar(segments: []),
        const ImStackedBar(segments: [ImSegment(0, Colors.red, 'a')]),
        const ImStackedBar(
          segments: [
            ImSegment(3, Colors.red, 'a'),
            ImSegment(0, Colors.blue, 'b'),
          ],
        ),
      ]),
    );
    expect(tester.takeException(), isNull);
  });
}
