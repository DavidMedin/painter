// What: Widget tests of PainterApp in a Session over real loopback sockets,
//   with an in-test Participant (AppPeer) on the other side.
// Why: the Session layer is tested alone in session_network_test.dart; these
//   tests show that the app wires it up as docs/spec/multiplayer.md and
//   docs/spec/workspace.md ask: Start session lists the addresses (MPLY-1,
//   MPLY-2), strokes cross both ways (MPLY-6), the pane lists Participants
//   with the Host (MPLY-9), a peer joining the app user's workspace and
//   splitting a pane changes the app's panes (WKSP-32, WKSP-33), 'Make
//   host' moves the Host (MPLY-11), joining through the dialog adopts the
//   host's strokes and stored workspace without a file (MPLY-3, MPLY-4,
//   MPLY-14, WKSP-9) or, with 'load stored workspaces' off, keeps a copy of
//   the layout it had (WKSP-10, WKSP-11), an Engine mismatch is refused with both versions and
//   changes nothing (MPLY-8), the app joins another Participant's
//   workspace and on leaving gets its earlier layout back (WKSP-21, WKSP-32,
//   WKSP-36, WKSP-37), a local workspace a peer deletes is recreated from
//   the layout last shown (docs/decisions/009-shared-workspaces.md
//   PNT-A0015-04), and Leave session
//   keeps the strokes and allows a new Start (MPLY-15, MPLY-16). The app's
//   log records each Session Operation it completes (docs/spec/logging.md
//   LOG-10) or the user cancels (LOG-12), and the Session's changes
//   (LOG-15, LOG-18).
// Covers: lib/main.dart (Session flows, membership following),
//   lib/session/session_pane.dart (pane and dialogs),
//   lib/workspace/workspace.dart (openPane, nodesFromJson), with
//   lib/session/session_network.dart and session_document.dart underneath.
//   Helpers are in app_session_support.dart; socket waits go through
//   pumpUntil, which runs real time in tester.runAsync.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:painter/canvas/canvas_view.dart';
import 'package:painter/canvas/pencil_splats.dart' show strokeEngineVersion;
import 'package:painter/logging/log_widgets.dart';
import 'package:painter/logging/painter_log.dart';
import 'package:painter/main.dart';
import 'package:painter/session/session_pane.dart';
import 'package:painter/settings/painter_settings.dart';
import 'package:painter/ui/painter_action_button.dart';
import 'package:painter/session/session_document.dart' show SessionKey;
import 'package:painter/workspace/layout_tree.dart'
    show PaneEdge, projectLayout;
import 'package:painter/workspace/workspace.dart';

import 'app_session_support.dart';

/// The app under test: listens on loopback with an OS-chosen port, offers
/// 'Ann' as the account name, and logs to [logger] when given.
PainterApp _app({PainterLog? logger}) => PainterApp(
  sessionBindAddress: InternetAddress.loopbackIPv4,
  sessionPort: 0,
  accountName: 'Ann',
  logger: logger,
);

/// The message ids [logger] holds at [level], oldest first.
List<String> _logged(PainterLog logger, PainterLogLevel level) => [
  for (final entry in logger.entries)
    if (entry.level == level) entry.messageId,
];

/// Unmounts the app (which leaves its Session) and lets the sockets close.
Future<void> _closeApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  // The closing handshakes run partly on the fake clock's microtasks.
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// A stored workspace (version 2 section as JSON text) of a Canvas pane
/// beside a Log pane.
final String _canvasAndLog = jsonEncode({
  'version': 2,
  'root': {
    'split': 'row',
    'parts': [
      {
        'share': 0.5,
        'node': {
          'pane': {'mode': 'canvas', 'state': <String, Object?>{}},
        },
      },
      {
        'share': 0.5,
        'node': {
          'pane': {'mode': 'log', 'state': <String, Object?>{}},
        },
      },
    ],
  },
});

/// How many panes workspace [workspaceId] shows in [peer]'s replica.
int _paneCount(AppPeer peer, String workspaceId) =>
    projectLayout(peer.session.workspaceNodes(workspaceId)).panes.length;

/// The participant id of the app's local Participant, as [peer] sees it.
String _appIdSeenBy(AppPeer peer) =>
    peer.session.participants.firstWhere((p) => p.id != peer.id).id;

void main() {
  setUpAll(useRealHttpClient);

  testWidgets('the app hosts: a peer joins, strokes cross both ways, the peer '
      'splits the shared workspace, Make host moves the Host, and Leave '
      'session keeps the strokes', (tester) async {
    final logger = PainterLog.memory();
    addTearDown(logger.dispose);
    await tester.pumpWidget(_app(logger: logger));
    await drawInApp(tester);
    expect(appStrokes(tester), hasLength(1));

    final address = await startSessionFromUi(tester, 'Ann');
    expect(address, startsWith('127.0.0.1:'));

    final peer = AppPeer.joiner('Bo');
    await settle(tester, () => peer.join(address), reason: 'the peer joining');
    expect(peer.strokes, hasLength(1), reason: 'first sync precedes join');
    final appId = _appIdSeenBy(peer);
    expect(peer.session.participant(appId)!.name, 'Ann');

    // The pane lists both Participants, the app's user as Host.
    await pumpUntil(
      tester,
      () => showsKey('session-participant-${peer.id}'),
      reason: 'the pane listing the peer',
    );
    expect(
      tester
          .widget<Text>(find.byKey(ValueKey('session-participant-${peer.id}')))
          .data,
      'Bo',
    );
    expect(
      tester
          .widget<Text>(find.byKey(ValueKey('session-participant-$appId')))
          .data,
      'Ann (you) · Host',
    );

    // A stroke drawn by the peer appears in the app, and one drawn in the
    // app reaches the peer.
    await tester.runAsync(() async => peer.drawStroke());
    await pumpUntil(
      tester,
      () => appStrokes(tester).length == 2,
      reason: "the peer's stroke in the app",
    );
    await drawInApp(tester);
    await pumpUntil(
      tester,
      () => peer.strokes.length == 3,
      reason: "the app's stroke at the peer",
    );
    expect(
      peer.strokes.map((s) => s.id).toSet(),
      appStrokes(tester).map((s) => s.id).toSet(),
    );

    // The peer joins the app user's workspace and splits its Canvas pane.
    expect(find.byType(CanvasView), findsOneWidget);
    await tester.runAsync(() async {
      peer.session.joinWorkspace(appId);
      final shared = Workspace(
        session: peer.session,
        workspaceId: peer.session.localParticipant!.workspace,
      );
      expect(shared.paneCount, 2, reason: 'Canvas and Session panes');
      shared.add(shared.firstCanvasPaneId!, PaneEdge.right);
      shared.dispose();
    });
    await pumpUntil(
      tester,
      () => find.byType(CanvasView).evaluate().length == 2,
      reason: "the peer's split in the app",
    );

    // Make host moves the Host to the peer everywhere.
    await tapKey(tester, 'session-make-host-${peer.id}');
    await pumpUntil(
      tester,
      () => peer.network.roster.value.hostId == peer.id,
      reason: 'the peer as Host',
    );
    await pumpUntil(
      tester,
      () =>
          tester
              .widget<Text>(
                find.byKey(ValueKey('session-participant-${peer.id}')),
              )
              .data ==
          'Bo · Host',
      reason: 'the pane marking the peer as Host',
    );
    expect(showsKey('session-make-host-${peer.id}'), isFalse);

    // Leave session keeps the strokes and the layout; the peer sees the app
    // leave.
    await tapKey(tester, 'session-leave');
    await pumpUntil(
      tester,
      () => showsKey('session-start'),
      reason: 'the not-in-session pane',
    );
    expect(appStrokes(tester), hasLength(3));
    expect(find.byType(CanvasView), findsNWidgets(2));
    await pumpUntil(
      tester,
      () => peer.session.participant(appId)?.left ?? false,
      reason: 'the peer seeing the app leave',
    );

    // A later Start session works again, from a one-Participant document.
    await tapKey(tester, 'session-start');
    await tester.pumpAndSettle();
    await tapKey(tester, 'session-dialog-confirm');
    await pumpUntil(
      tester,
      () => showsKey('session-address-0'),
      reason: 'the second Session',
    );
    expect(
      find.byKey(ValueKey('session-participant-${peer.id}')),
      findsNothing,
    );
    expect(appStrokes(tester), hasLength(3));

    // LOG-10, LOG-15 and LOG-18: each step above is in the app's log.
    expect(
      _logged(logger, PainterLogLevel.info),
      containsAllInOrder([
        'session.start.succeeded',
        'session.participant.joined',
        'session.promote.succeeded',
        'session.leave.succeeded',
        'session.start.succeeded',
      ]),
    );
    expect(
      _logged(logger, PainterLogLevel.info),
      contains('session.host.changed'),
    );
    final joined = logger.entries.firstWhere(
      (entry) => entry.messageId == 'session.participant.joined',
    );
    expect(joined.arguments['participant'], 'Bo');

    await settle(tester, peer.dispose, reason: 'the peer leaving');
    await _closeApp(tester);
  });

  testWidgets('cancelling the Start and Join dialogs logs a debug record '
      '(LOG-12)', (tester) async {
    final logger = PainterLog.memory();
    addTearDown(logger.dispose);
    await tester.pumpWidget(_app(logger: logger));
    await tapAction(tester, 'Session');
    await tester.pumpAndSettle();
    for (final key in ['session-start', 'session-join']) {
      await tapKey(tester, key);
      await tester.pumpAndSettle();
      await tapKey(tester, 'session-dialog-cancel');
      await tester.pumpAndSettle();
    }

    expect(
      _logged(logger, PainterLogLevel.debug),
      containsAllInOrder(['session.start.cancelled', 'session.join.cancelled']),
    );
    expect(_logged(logger, PainterLogLevel.info), isEmpty);
    await _closeApp(tester);
  });

  testWidgets('the app joins and leaves a peer\'s workspace', (tester) async {
    await tester.pumpWidget(_app());
    final address = await startSessionFromUi(tester, 'Ann');
    final peer = AppPeer.joiner('Bo');
    await settle(tester, () => peer.join(address), reason: 'the peer joining');
    await pumpUntil(
      tester,
      () => showsKey('session-join-workspace-${peer.id}'),
      reason: "the peer's Join workspace button",
    );
    final appId = _appIdSeenBy(peer);
    expect(find.byType(SessionPane), findsOneWidget);
    // Make the app's own layout recognizable: two Canvas panes.
    await tapKey(tester, 'frame-right-add-0');
    await tester.pumpAndSettle();
    expect(find.byType(CanvasView), findsNWidgets(2));
    await pumpUntil(
      tester,
      () => _paneCount(peer, peer.session.participant(appId)!.workspace) == 3,
      reason: "the app's split at the peer",
    );
    final ownWorkspace = peer.session.participant(appId)!.workspace;

    await tapKey(tester, 'session-join-workspace-${peer.id}');
    await pumpUntil(
      tester,
      () => find.byType(SessionPane).evaluate().isEmpty,
      reason: "the app showing the peer's one-pane workspace",
    );
    expect(find.byType(CanvasView), findsOneWidget);

    // Showing the Session pane now adds it to the shared workspace.
    await tapAction(tester, 'Session');
    await pumpUntil(
      tester,
      () => _paneCount(peer, peer.session.localParticipant!.workspace) == 2,
      reason: 'the Session pane in the shared workspace at the peer',
    );
    expect(
      peer.session.participant(appId)!.workspace,
      peer.session.localParticipant!.workspace,
    );
    // WKSP-21: the app's earlier workspace survives while the app would
    // return to it.
    expect(peer.session.hasWorkspace(ownWorkspace), isTrue);

    await tapKey(tester, 'session-leave-workspace');
    await pumpUntil(
      tester,
      () => !showsKey('session-leave-workspace'),
      reason: 'the app back in a workspace of its own',
    );
    await pumpUntil(
      tester,
      () => peer.session.participant(appId)!.workspace == ownWorkspace,
      reason: 'the peer seeing the app return to its earlier workspace',
    );
    // WKSP-37: the earlier layout returns; the shared one keeps the
    // Session pane the app added.
    expect(find.byType(CanvasView), findsNWidgets(2));
    expect(find.byType(SessionPane), findsOneWidget);
    expect(_paneCount(peer, peer.session.localParticipant!.workspace), 2);

    await settle(tester, peer.dispose, reason: 'the peer leaving');
    await _closeApp(tester);
  });

  testWidgets('a local workspace a peer deletes comes back with the layout '
      'last shown', (tester) async {
    await tester.pumpWidget(_app());
    final address = await startSessionFromUi(tester, 'Ann');
    final peer = AppPeer.joiner('Bo');
    await settle(tester, () => peer.join(address), reason: 'the peer joining');
    final appId = _appIdSeenBy(peer);
    final deleted = peer.session.participant(appId)!.workspace;
    await pumpUntil(
      tester,
      () => _paneCount(peer, deleted) == 2,
      reason: "the app's workspace at the peer",
    );

    await tester.runAsync(() async {
      peer.session.document.delete([SessionKey.workspaces, deleted]);
      peer.session.document.commit();
    });
    await pumpUntil(tester, () {
      final now = peer.session.participant(appId)!.workspace;
      return now != deleted && _paneCount(peer, now) == 2;
    }, reason: 'the app recreating its workspace');
    // PNT-A0015-04: never a blank workspace area.
    expect(find.byType(CanvasView), findsOneWidget);
    expect(find.byType(SessionPane), findsOneWidget);

    await settle(tester, peer.dispose, reason: 'the peer leaving');
    await _closeApp(tester);
  });

  testWidgets('the app joins a host through the dialog and gets its strokes '
      'and stored workspace, with no file', (tester) async {
    final host = (await tester.runAsync(
      () => AppPeer.host('Cy', storedWorkspace: _canvasAndLog),
    ))!;
    await tester.runAsync(() async => host.drawStroke());

    final logger = PainterLog.memory();
    addTearDown(logger.dispose);
    await tester.pumpWidget(_app(logger: logger));
    await drawInApp(tester);
    await tapAction(tester, 'Session');
    await tester.pumpAndSettle();
    await submitJoinFromUi(tester, host.address, 'Ann');
    await pumpUntil(
      tester,
      () => find.byType(LogPane).evaluate().isNotEmpty,
      reason: "the joined Session's stored workspace",
    );
    await tester.pumpAndSettle();

    // The host's content replaced the app's, and the stored workspace is the
    // app's layout.
    expect(appStrokes(tester).map((s) => s.id), host.strokes.map((s) => s.id));
    expect(find.byType(CanvasView), findsOneWidget);
    expect(find.byType(LogPane), findsOneWidget);
    // MPLY-14: no file, so Flash is disabled.
    expect(
      tester
          .widget<PainterActionButton>(
            find.widgetWithText(PainterActionButton, 'Flash layout'),
          )
          .onPressed,
      isNull,
    );

    await pumpUntil(
      tester,
      () => host.network.roster.value.members.length == 2,
      reason: 'the host seeing the app',
    );
    final appId = host.session.participants
        .firstWhere((p) => p.id != host.id)
        .id;
    expect(host.session.participant(appId)!.name, 'Ann');

    await drawInApp(tester);
    await pumpUntil(
      tester,
      () => host.strokes.length == 2,
      reason: "the app's stroke at the host",
    );

    // LOG-10: the join is logged with its address; the stored workspace
    // was usable, so nothing was a warning.
    final join = logger.entries.singleWhere(
      (entry) => entry.messageId == 'session.join.succeeded',
    );
    expect(join.level, PainterLogLevel.info);
    expect(join.arguments['address'], host.address);
    expect(_logged(logger, PainterLogLevel.warn), isEmpty);

    await settle(tester, host.dispose, reason: 'the host leaving');
    await _closeApp(tester);
  });

  testWidgets('with load stored workspaces off, a joiner keeps a copy of '
      'its layout', (tester) async {
    final host = (await tester.runAsync(
      () => AppPeer.host('Cy', storedWorkspace: _canvasAndLog),
    ))!;
    await tester.pumpWidget(
      PainterApp(
        sessionBindAddress: InternetAddress.loopbackIPv4,
        sessionPort: 0,
        accountName: 'Ann',
        initialSettings: PainterSettings.defaults.copyWith(
          loadStoredWorkspaces: false,
        ),
      ),
    );
    await tapKey(tester, 'frame-right-add-0');
    await tester.pumpAndSettle();
    await tapAction(tester, 'Session');
    await tester.pumpAndSettle();
    expect(find.byType(CanvasView), findsNWidgets(2));

    await submitJoinFromUi(tester, host.address, 'Ann');
    await pumpUntil(
      tester,
      () => showsKey('session-participant-${host.id}'),
      reason: 'the joined Session in the copied Session pane',
    );
    expect(find.byType(CanvasView), findsNWidgets(2));
    expect(find.byType(LogPane), findsNothing);
    expect(appStrokes(tester), isEmpty);

    await settle(tester, host.dispose, reason: 'the host leaving');
    await _closeApp(tester);
  });

  testWidgets('an Engine mismatch shows both versions and changes nothing', (
    tester,
  ) async {
    final host = (await tester.runAsync(
      () => AppPeer.host('Dee', engine: strokeEngineVersion + 1),
    ))!;

    await tester.pumpWidget(_app());
    await drawInApp(tester);
    final before = appStrokes(tester).map((s) => s.id).toList();
    await tapAction(tester, 'Session');
    await tester.pumpAndSettle();
    await submitJoinFromUi(tester, host.address, 'Ann');
    await pumpUntil(
      tester,
      () => showsKey('session-refused-dialog'),
      reason: 'the refusal',
    );
    expect(
      find.text('Your Engine version: $strokeEngineVersion'),
      findsOneWidget,
    );
    expect(
      find.text('Session Engine version: ${strokeEngineVersion + 1}'),
      findsOneWidget,
    );
    await tapKey(tester, 'session-dialog-close');
    await tester.pumpAndSettle();

    expect(appStrokes(tester).map((s) => s.id), before);
    expect(showsKey('session-start'), isTrue);
    expect(host.session.participants, hasLength(1));

    await settle(tester, host.dispose, reason: 'the host leaving');
    await _closeApp(tester);
  });
}
