// What: Widget tests for the latest-entry bar, chronological Log pane, its
//   lowest-Severity filter, and app route.
// Why: The shared log history must stay visible at the bottom of the shell
//   (docs/spec/logging.md LOG-7) and in a selectable pane, with the newest
//   record at the scroll bottom (LOG-8). Each Log pane lists records at or
//   above its own lowest Severity, every Severity at first, without hiding
//   anything from other panes, the status bar or the history (LOG-22,
//   LOG-23, docs/decisions/014-logging.md PNT-A0020-07).
// Covers: lib/logging/log_widgets.dart and lib/main.dart Log-pane wiring.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:painter/help/contextual_help.dart';
import 'package:painter/help/manual_catalog.dart';
import 'package:painter/logging/log_widgets.dart';
import 'package:painter/logging/painter_log.dart';
import 'package:painter/main.dart';
import 'package:painter/workspace/pane_kind.dart';

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

  testWidgets('Log records provide help and 48-pixel-tall rows', (
    tester,
  ) async {
    final log = PainterLog.memory();
    final helpState = HelpState();
    final pointer = TestPointer(44, PointerDeviceKind.mouse);
    addTearDown(log.dispose);
    addTearDown(helpState.dispose);
    await log.error(
      'settings.persistence.failed',
      arguments: {'error': 'disk full'},
      stackTrace: 'trace details',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HelpScope(
            helpState: helpState,
            child: LogPane(log: log),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final record = find.byType(ExpansionTile);
    expect(tester.getSize(record).height, greaterThanOrEqualTo(48));
    final tooltip = tester.widget<Tooltip>(
      find.ancestor(of: record, matching: find.byType(Tooltip)).first,
    );
    expect(
      tooltip.message,
      ManualCatalog.article(HelpIds.logEntryDetails).tooltip,
    );
    await tester.sendEventToBinding(pointer.hover(tester.getCenter(record)));
    await tester.pump();
    expect(helpState.activeTopic, HelpIds.logEntryDetails);
    await tester.sendEventToBinding(pointer.hover(Offset.zero));
    await tester.pump();
    Focus.of(tester.element(record)).requestFocus();
    await tester.pump();
    expect(helpState.activeTopic, HelpIds.logEntryDetails);

    await tester.tap(record);
    await tester.pumpAndSettle();
    expect(find.text('Arguments: {"error":"disk full"}'), findsOneWidget);
    expect(find.text('trace details'), findsOneWidget);
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
    // The pane lists the start; the status bar shows the newest record, the
    // mode change itself (LOG-7, LOG-19), which the pane lists too.
    expect(find.text('Painter started.'), findsOneWidget);
    expect(find.text('Changed a pane to Log.'), findsNWidgets(2));
  });

  testWidgets('a lowest Severity hides lower records in that pane only '
      '(LOG-8, LOG-22)', (tester) async {
    final log = PainterLog.memory();
    addTearDown(log.dispose);
    final selected = <PainterLogLevel>[];
    await log.debug('entry.debug');
    await log.info('entry.info');
    await log.warn('entry.warn');
    await log.error('entry.error');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LogPane(
            log: log,
            lowest: PainterLogLevel.warn,
            onLowestChanged: selected.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('[entry.debug]'), findsNothing);
    expect(find.text('[entry.info]'), findsNothing);
    expect(find.text('[entry.warn]'), findsOneWidget);
    expect(find.text('[entry.error]'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('log-lowest-severity')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DEBUG').last);
    await tester.pumpAndSettle();
    expect(selected, [PainterLogLevel.debug]);
  });

  testWidgets('in the app, each Log pane keeps its own lowest Severity, '
      'starting at TRACE (LOG-22, LOG-23)', (tester) async {
    final log = PainterLog.memory();
    addTearDown(log.dispose);
    await log.warn('settings.load.invalid', arguments: {'problem': 'test'});
    await tester.pumpWidget(PainterApp(logger: log));
    await tester.tap(find.byType(DropdownButton<PaneKind>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('frame-right-add-0')));
    await tester.pumpAndSettle();
    expect(find.byType(LogPane), findsNWidgets(2));

    Finder inPane(int index, String text) => find.descendant(
      of: find.byType(LogPane).at(index),
      matching: find.text(text),
    );
    // Both panes start at TRACE and list the debug record of the mode
    // change.
    expect(inPane(0, 'TRACE'), findsOneWidget);
    expect(inPane(0, 'Changed a pane to Log.'), findsOneWidget);
    final recorded = log.entries.length;

    await tester.tap(find.byKey(const ValueKey('log-lowest-severity')).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('WARN').last);
    await tester.pumpAndSettle();

    expect(inPane(0, 'Changed a pane to Log.'), findsNothing);
    expect(
      inPane(0, 'Used a default in place of stored settings: test.'),
      findsOneWidget,
    );
    expect(inPane(1, 'TRACE'), findsOneWidget);
    expect(inPane(1, 'Changed a pane to Log.'), findsOneWidget);
    expect(log.entries, hasLength(recorded), reason: 'the history is whole');
  });
}
