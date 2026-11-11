// What: Helpers for driving PainterApp in a Session from a test: AppPeer, an
//   in-test Participant (ContentDocument drawn by its own CanvasController,
//   SessionDocument, SessionNetwork on 127.0.0.1) that hosts or joins; and
//   widget-test helpers that wait on real sockets, open the Session pane,
//   fill the Session dialogs, draw a stroke, and read the app's state.
// Why: the widget tests (session_app_test.dart) and the macOS integration
//   test (integration_test/session_test.dart) exercise the same flows; one
//   copy keeps them driving the app identically. Socket events arrive on the
//   real event loop while a widget test runs on a fake clock, so every wait
//   alternates tester.runAsync (real time passes, socket callbacks run) with
//   tester.pump (the app's microtasks and frames run).
// Covers: nothing by itself; used with lib/main.dart,
//   lib/session/session_pane.dart, lib/session/session_network.dart,
//   lib/document/content_document.dart and lib/workspace/workspace.dart.

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:painter/canvas/canvas_controller.dart';
import 'package:painter/canvas/canvas_view.dart';
import 'package:painter/canvas/pencil_splats.dart' show strokeEngineVersion;
import 'package:painter/crdt/automerge_crdt_document.dart';
import 'package:painter/document/content_document.dart';
import 'package:painter/session/session_document.dart';
import 'package:painter/session/session_network.dart';
import 'package:painter/ui/painter_action_button.dart';
import 'package:painter/workspace/layout_tree.dart' show createDefaultLayout;

const AutomergeBackend _backend = AutomergeBackend();

/// A Participant inside the test process with the same documents the app
/// has. Call [dispose] (inside tester.runAsync in a widget test) at the end.
final class AppPeer {
  AppPeer._(this.content, this.session, String name, int engine)
    : network = SessionNetwork(
        content: content.crdt,
        session: session,
        name: name,
        engine: engine,
      ) {
    content.attach(controller);
  }

  /// Creates a Session as its creator, with [storedWorkspace] as the
  /// Session's `storedWorkspace`, and listens on 127.0.0.1.
  static Future<AppPeer> host(
    String name, {
    int engine = strokeEngineVersion,
    String? storedWorkspace,
  }) async {
    final document = _backend.create();
    final session = SessionDocument.create(
      document,
      name: name,
      engine: engine,
      nodes: createDefaultLayout(
        newId: document.newId,
        actor: document.actorId,
      ),
      storedWorkspace: storedWorkspace,
    );
    final peer = AppPeer._(
      ContentDocument.create(_backend),
      session,
      name,
      engine,
    );
    await peer.network.start(
      bindAddress: InternetAddress.loopbackIPv4,
      port: 0,
    );
    return peer;
  }

  /// A Participant with empty documents that [join] fills.
  factory AppPeer.joiner(String name, {int engine = strokeEngineVersion}) =>
      AppPeer._(
        ContentDocument.adopt(_backend.create(), requireRoot: false),
        SessionDocument(_backend.create()),
        name,
        engine,
      );

  final ContentDocument content;
  final SessionDocument session;
  final SessionNetwork network;
  final CanvasController controller = CanvasController();

  String get id => session.localId;

  String get address => network.addresses.first;

  /// The strokes this Participant shows.
  List<CanvasStroke> get strokes => controller.document.strokes;

  /// Joins the Session at [address] with a Default workspace.
  Future<void> join(String address) => network.join(
    address,
    nodes: () => createDefaultLayout(
      newId: session.document.newId,
      actor: session.document.actorId,
    ),
    bindAddress: InternetAddress.loopbackIPv4,
    port: 0,
  );

  /// Draws one short stroke at [at] through the controller, as a user would.
  void drawStroke([Offset at = const Offset(10, 10)]) {
    controller
      ..beginStroke(at, 0.5)
      ..extendStroke(at + const Offset(4, 1), 0.5)
      ..endStroke();
  }

  /// Whether this Participant sees [participantId] as present.
  bool sees(String participantId) =>
      network.roster.value.member(participantId)?.present ?? false;

  Future<void> dispose() async {
    await network.leave();
    content.dispose();
    controller.dispose();
    session.document.dispose();
  }
}

/// Restores the real HttpClient. TestWidgetsFlutterBinding installs a global
/// mock that answers every request with status 400, and WebSocket.connect
/// goes through HttpClient, so Session widget tests call this in setUpAll.
void useRealHttpClient() => HttpOverrides.global = null;

/// Waits until [condition] holds, letting real time pass (socket events)
/// and pumping (the app's microtasks, timers and frames) in turn; fails
/// with [reason] after [timeout] of real time.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  String reason = 'condition',
  Duration timeout = const Duration(seconds: 10),
}) async {
  final watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > timeout) fail('Timed out waiting for $reason.');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Runs [action], which talks to the app over sockets, to completion: it
/// starts in real time (tester.runAsync) but is awaited through [pumpUntil],
/// because the app's side of every exchange needs pumps to run. Returns its
/// result or rethrows its error.
Future<T> settle<T>(
  WidgetTester tester,
  Future<T> Function() action, {
  String reason = 'a peer action',
  Duration timeout = const Duration(seconds: 15),
}) async {
  late final Future<T> future;
  var done = false;
  await tester.runAsync(() async {
    future = action();
    future.whenComplete(() => done = true).ignore();
  });
  await pumpUntil(tester, () => done, reason: reason, timeout: timeout);
  return future;
}

/// Taps the AppBar button labelled [label].
Future<void> tapAction(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(PainterActionButton, label));
  await tester.pump();
}

/// Taps the widget with key [key] and pumps a frame.
Future<void> tapKey(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key));
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pump();
}

/// Whether a widget with key [key] is shown.
bool showsKey(String key) => find.byKey(ValueKey(key)).evaluate().isNotEmpty;

/// Shows the Session pane and starts a Session named [name] through its
/// dialog; returns the first Session address the pane lists.
Future<String> startSessionFromUi(WidgetTester tester, String name) async {
  await tapAction(tester, 'Session');
  await tester.pumpAndSettle();
  await tapKey(tester, 'session-start');
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('session-name-field')),
    name,
  );
  await tapKey(tester, 'session-dialog-confirm');
  await pumpUntil(
    tester,
    () => showsKey('session-address-0'),
    reason: 'the Session addresses',
  );
  return tester
      .widget<SelectableText>(find.byKey(const ValueKey('session-address-0')))
      .data!;
}

/// Opens Join session from the shown Session pane and submits [address]
/// and [name]; the caller waits for the outcome.
Future<void> submitJoinFromUi(
  WidgetTester tester,
  String address,
  String name,
) async {
  await tapKey(tester, 'session-join');
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('session-address-field')),
    address,
  );
  await tester.enterText(
    find.byKey(const ValueKey('session-name-field')),
    name,
  );
  await tapKey(tester, 'session-dialog-confirm');
}

/// The strokes the app's canvas shows (every Canvas pane shares one
/// controller).
List<CanvasStroke> appStrokes(WidgetTester tester) => tester
    .widget<CanvasView>(find.byType(CanvasView).first)
    .controller
    .document
    .strokes;

/// Draws one short mouse stroke in the first Canvas pane of the app.
Future<void> drawInApp(WidgetTester tester) async {
  final rect = tester.getRect(find.byType(CanvasView).first);
  final start = Offset(rect.left + rect.width * 0.4, rect.center.dy);
  final mouse = TestPointer(7, PointerDeviceKind.mouse);
  await tester.sendEventToBinding(
    mouse.down(start, buttons: kPrimaryMouseButton),
  );
  await tester.sendEventToBinding(
    mouse.move(start + const Offset(4, 1), buttons: kPrimaryMouseButton),
  );
  await tester.sendEventToBinding(mouse.up());
  await tester.pump();
}
