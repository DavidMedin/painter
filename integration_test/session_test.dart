// What: An end-to-end test of a Session in the real macOS app: PainterApp
//   starts a Session from its UI on 127.0.0.1, an in-process Participant
//   (AppPeer) joins over loopback, a stroke crosses each way, and a pane
//   split crosses each way through the shared workspace.
// Why: docs/plan.md section 8 asks for strokes and workspace edits to appear
//   on both sides of a Session; the widget tests run on a fake clock with a
//   mocked HttpClient, so this run on the real platform, with the app
//   sandbox's network entitlements (macos/Runner/*.entitlements), is the
//   one that shows the app can listen and connect for real. Run with
//   `flutter test integration_test -d macos`.
// Covers: lib/main.dart (Start session, membership following),
//   lib/session/session_pane.dart, lib/session/session_network.dart,
//   lib/document/content_document.dart, lib/workspace/workspace.dart.
//   Helpers come from test/session/app_session_support.dart.

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:painter/canvas/canvas_view.dart';
import 'package:painter/main.dart';
import 'package:painter/workspace/layout_tree.dart' show PaneEdge;
import 'package:painter/workspace/workspace.dart';

import '../test/session/app_session_support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a Session started from the app exchanges strokes and a '
      'workspace split with a peer over loopback', (tester) async {
    useRealHttpClient();
    await tester.pumpWidget(
      PainterApp(
        sessionBindAddress: InternetAddress.loopbackIPv4,
        sessionPort: 0,
        accountName: 'Ann',
      ),
    );
    await tester.pumpAndSettle();
    await drawInApp(tester);
    expect(appStrokes(tester), hasLength(1));

    final address = await startSessionFromUi(tester, 'Ann');
    final peer = AppPeer.joiner('Bo');
    await settle(tester, () => peer.join(address), reason: 'the peer joining');
    expect(peer.strokes, hasLength(1));
    await pumpUntil(
      tester,
      () => showsKey('session-participant-${peer.id}'),
      reason: 'the pane listing the peer',
    );

    // A stroke each way.
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

    // The peer joins the app user's workspace; a split each way.
    final appId = peer.session.participants
        .firstWhere((participant) => participant.id != peer.id)
        .id;
    late final Workspace shared;
    await tester.runAsync(() async {
      peer.session.joinWorkspace(appId);
      shared = Workspace(
        session: peer.session,
        workspaceId: peer.session.localParticipant!.workspace,
      );
      shared.add(shared.firstCanvasPaneId!, PaneEdge.right);
    });
    await pumpUntil(
      tester,
      () => find.byType(CanvasView).evaluate().length == 2,
      reason: "the peer's split in the app",
    );
    final panesBefore = shared.paneCount;
    await tapKey(tester, 'frame-right-add-0');
    await pumpUntil(
      tester,
      () => shared.paneCount == panesBefore + 1,
      reason: "the app's split at the peer",
    );

    await tapKey(tester, 'session-leave');
    await pumpUntil(
      tester,
      () => showsKey('session-start'),
      reason: 'leaving the Session',
    );
    expect(appStrokes(tester), hasLength(3));

    await tester.runAsync(() async => shared.dispose());
    await settle(tester, peer.dispose, reason: 'the peer leaving');
    await tester.pumpWidget(const SizedBox());
  });
}
