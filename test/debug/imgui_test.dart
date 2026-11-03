import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:painter/debug/imgui.dart';

/// The visible window box (the host fills its container so it can measure it).
Finder _box() => find
    .ancestor(of: find.text('win'), matching: find.byType(DecoratedBox))
    .first;

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
