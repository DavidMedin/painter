// What: Widget tests for the latest-entry bar, chronological Log pane, and app route.
// Why: The shared log history must stay visible at the bottom of the shell and
//   selectable pane, with the newest record at the scroll bottom.
// Covers: lib/logging/log_widgets.dart and lib/main.dart Log-pane wiring.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:painter/logging/log_widgets.dart';
import 'package:painter/logging/painter_log.dart';
import 'package:painter/main.dart';
import 'package:painter/ui/pane_system.dart';

void main() {
  testWidgets('status bar updates when a later record arrives', (tester) async {
    final log = PainterLog.memory();
    addTearDown(log.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: LogStatusBar(log: log),
        ),
      ),
    );

    expect(find.text('No log entries'), findsOneWidget);
    await log.info('app.started');
    await tester.pump();
    expect(find.text('Painter started.'), findsOneWidget);

    await log.error(
      'document.operation.failed',
      arguments: {'operation': 'save', 'error': 'disk full'},
    );
    await tester.pump();
    expect(
      find.text('Failed to save Painter document: disk full'),
      findsOneWidget,
    );
    expect(find.text('Painter started.'), findsNothing);
  });

  testWidgets('Log pane shows chronological rows and scrolls to the newest', (
    tester,
  ) async {
    final log = PainterLog.memory();
    addTearDown(log.dispose);
    for (var index = 0; index < 40; index++) {
      await log.info('entry.$index');
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 180, child: LogPane(log: log)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final list = tester.widget<ListView>(find.byType(ListView));
    final scrollController = list.controller!;
    expect(scrollController.offset, greaterThan(0));
    expect(find.text('[entry.39]'), findsOneWidget);

    scrollController.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.text('[entry.0]'), findsOneWidget);
    expect(find.text('[entry.1]'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('[entry.1]')).dy,
      greaterThan(tester.getTopLeft(find.text('[entry.0]')).dy),
    );

    scrollController.jumpTo(scrollController.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.text('[entry.39]'), findsOneWidget);
    expect(find.text('[entry.0]'), findsNothing);
  });

  testWidgets('PainterApp exposes Log as a pane mode', (tester) async {
    final log = PainterLog.memory();
    addTearDown(log.dispose);
    await log.info('app.started');
    await tester.pumpWidget(PainterApp(logger: log));

    await tester.tap(find.byType(DropdownButton<PaneKind>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log'));
    await tester.pumpAndSettle();

    expect(find.byType(LogPane), findsOneWidget);
    expect(find.text('Painter started.'), findsNWidgets(2));
  });
}
