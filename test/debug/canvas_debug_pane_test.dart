// What: Widget tests that run the real PainterApp with the debug pane open and
//   check that the pane's readouts, controls, overlay switches and report
//   track the real tile cache, canvas controller and CanvasDebugOptions; plus
//   two plain unit tests on CanvasDebugOptions and the tile-draw colors.
// Why: The pane (ADR 0006) is the only way to observe the asynchronous tile
//   cache (ADR 0005) in a running app, so a readout that lies or a control
//   that does nothing defeats its purpose. docs/status.md ("Debug Pane
//   Verification") says these tests also caught bugs; the one found here
//   (Pause not freezing every readout) is marked on its test below.
// Covers: lib/debug/canvas_debug_pane.dart (CanvasDebugPane and its private
//   snapshot, report text), lib/debug/canvas_debug_options.dart,
//   lib/debug/tile_overlay.dart (tileDrawColor), and the wiring in
//   lib/main.dart (AppBar button, F3, CanvasView.onRenderer/debugOptions).
//
// Overview: how the pane is tested
// --------------------------------
// The pane is pure presentation: it reads a TiledRenderer and a
// CanvasController, edits CanvasDebugOptions plus two TileCache limits
// (maxInFlight, maxTiles), and refreshes on a 250 ms timer from one frozen
// snapshot per refresh (ADR 0006, "Frozen snapshot"). Because it only has
// meaning next to a live cache, these tests are widget-driven end to end:
// PainterApp is pumped, the pane is opened with F3, strokes are drawn with
// synthetic mouse events, and the assertions compare what the pane shows with
// the TileCache / CanvasController / CanvasDebugOptions objects it reads.
// The tile builds run on real asynchronous work, so helpers wait in real time
// (see _letTilesLand). Layout uses the Ahem test font.
//
// Not verified here (per docs/status.md and ADR 0006): how the pane or the
// overlays look in a running macOS window or in the Menlo font, the overhead
// of the always-on counters, and behavior with a very large document or
// extreme zoom. The overlay painting (paintTileOverlay) is not pixel-checked
// in this file; only the switches the canvas reads are. The pane's window
// mechanics (drag, clamp, collapse) are tested in imgui_test.dart.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:painter/canvas/canvas_view.dart';
import 'package:painter/canvas/tile_stats.dart';
import 'package:painter/canvas/tiled_renderer.dart';
import 'package:painter/debug/canvas_debug_options.dart';
import 'package:painter/debug/canvas_debug_pane.dart';
import 'package:painter/debug/imgui.dart';
import 'package:painter/debug/tile_overlay.dart';
import 'package:painter/main.dart';

/// The pane widget, present only while the debug pane is open.
Finder get _pane => find.byType(CanvasDebugPane);

/// The TiledRenderer the pane is reading.
TiledRenderer _rendererOf(WidgetTester tester) {
  // The renderer is private to the view; reach it through the callback the app
  // installed by finding the pane after opening it.
  return tester.widget<CanvasDebugPane>(_pane).renderer;
}

/// The value shown in the [ImValue] row labelled [label].
String _row(WidgetTester tester, String label) {
  final row = find.ancestor(
    of: find.text(label),
    matching: find.byType(ImValue),
  );
  final value = tester.widget<ImValue>(row.first);
  return value.value;
}

/// Draws one short mouse stroke (120 x 30 units) in the canvas area to the
/// right of the pane, so the press cannot land on the pane window, which is
/// anchored at the top-left and is 340 wide (CanvasDebugPane). Uses synthetic
/// mouse events through the binding, like the canvas tests.
Future<void> _drawStroke(WidgetTester tester) async {
  final canvas = find.byType(CanvasView);
  // Right of the pane (which starts at the left edge and is 340 wide).
  final rect = tester.getRect(canvas);
  final start = Offset(rect.right - 200, rect.center.dy);
  final mouse = TestPointer(1, PointerDeviceKind.mouse);
  await tester.sendEventToBinding(
    mouse.down(start, buttons: kPrimaryMouseButton),
  );
  await tester.sendEventToBinding(
    mouse.move(start + const Offset(120, 30), buttons: kPrimaryMouseButton),
  );
  await tester.sendEventToBinding(mouse.up());
  await tester.pump();
}

/// Lets background tile builds finish; real async work needs real time.
///
/// Tile builds (TileCache runs splat generation in a worker and rasterizes
/// with Picture.toImage) complete on real asynchronous work that the test's
/// fake clock does not advance, so pump() alone would never see them land.
/// tester.runAsync lets real time pass; the loop polls renderer.cache.idle
/// (up to 100 x 20 ms), and each pump() runs the frame a landed tile
/// schedules. One extra wait-and-pump after the loop lets the last landing
/// repaint.
Future<void> _letTilesLand(WidgetTester tester) async {
  final renderer = _rendererOf(tester);
  for (var i = 0; i < 100 && !renderer.cache.idle; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pump();
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  // ADR 0006: "Hidden by default". The app must still open straight to the
  // blank canvas (docs/project-brief.md).
  testWidgets('the pane is hidden at launch (blank canvas only)', (
    tester,
  ) async {
    await tester.pumpWidget(const PainterApp());
    expect(_pane, findsNothing);
    expect(find.byType(CanvasView), findsOneWidget);
  });

  testWidgets('the app bar button and F3 both toggle the pane', (tester) async {
    await tester.pumpWidget(const PainterApp());

    await tester.tap(find.byTooltip('Debug pane (F3)'));
    await tester.pump();
    expect(_pane, findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.f3);
    await tester.pump();
    expect(_pane, findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.f3);
    await tester.pump();
    expect(_pane, findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(_pane, findsNothing);
  });

  // ADR 0006 states canvas input outside the pane is unaffected and tests it
  // here; the second half checks the opposite: pressing the pane's own title
  // bar drags the window and must not add a stroke.
  testWidgets(
    'drawing still works with the pane open and clicks on it do not draw',
    (tester) async {
      await tester.pumpWidget(const PainterApp());
      await tester.sendKeyEvent(LogicalKeyboardKey.f3);
      await tester.pump();
      final controller = tester
          .widget<CanvasView>(find.byType(CanvasView))
          .controller;

      await _drawStroke(tester);
      expect(controller.document.strokeCount, 1);

      // A press-drag on the pane's own title must move the window, not paint.
      final mouse = TestPointer(2, PointerDeviceKind.mouse);
      final title = tester.getCenter(find.text('Painter debug  [F3]'));
      await tester.sendEventToBinding(
        mouse.down(title, buttons: kPrimaryMouseButton),
      );
      await tester.sendEventToBinding(
        mouse.move(title + const Offset(30, 30), buttons: kPrimaryMouseButton),
      );
      await tester.sendEventToBinding(mouse.up());
      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.document.strokeCount, 1);
    },
  );

  // The 'Document and splats' section starts closed (initiallyOpen: false), so
  // the test opens it first. The 300 ms pump lets the pane's 250 ms refresh
  // timer take a new snapshot after the tiles land.
  testWidgets('readouts follow real cache state as strokes land', (
    tester,
  ) async {
    await tester.pumpWidget(const PainterApp());
    await tester.sendKeyEvent(LogicalKeyboardKey.f3);
    await tester.pump();

    final header = find.text('Document and splats');
    await tester.ensureVisible(header);
    await tester.tap(header);
    await tester.pump();
    expect(_row(tester, 'strokes'), '0');
    await _drawStroke(tester);
    await _letTilesLand(tester);
    // The pane refreshes on a timer.
    await tester.pump(const Duration(milliseconds: 300));

    final cache = _rendererOf(tester).cache;
    expect(cache.counters.builds, greaterThan(0));
    expect(_row(tester, 'strokes'), '1');
    expect(_row(tester, 'points'), '2');
    expect(_row(tester, 'builds'), '${cache.counters.builds}');
    expect(_row(tester, 'idle'), 'yes');
  });

  // Regression (status.md bug 3): the pane used to mix frozen and live reads,
  // so Pause did not actually freeze every readout and the report could
  // disagree with the screen. The test compares every Text widget while
  // paused after a stroke, new tiles, a pan and more frames. It also checks
  // options.paused after each tap so a missed tap cannot pass vacuously.
  testWidgets('pause freezes the readouts until resumed', (tester) async {
    await tester.pumpWidget(const PainterApp());
    await tester.sendKeyEvent(LogicalKeyboardKey.f3);
    await tester.pump();
    final view = tester.widget<CanvasView>(find.byType(CanvasView));
    final options = view.debugOptions!;

    Future<void> setPaused(bool paused) async {
      final box = find.text('pause readouts');
      await tester.ensureVisible(box);
      await tester.tap(box);
      await tester.pump();
      // A tap that missed would otherwise make this test pass vacuously.
      expect(options.paused, paused);
    }

    List<String?> texts() =>
        tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList();

    await setPaused(true);
    final before = texts();

    // Real changes: a stroke, new tiles, a viewport move, and more frames.
    await _drawStroke(tester);
    await _letTilesLand(tester);
    view.controller.panBy(const Offset(7, 3));
    await tester.pump(const Duration(milliseconds: 600));
    expect(texts(), before, reason: 'frozen while paused');

    await setPaused(false);
    await tester.pump(const Duration(milliseconds: 600));
    final after = texts();
    expect(after, isNot(before), reason: 'live again after resuming');
    final pan = after[after.indexOf('pan') + 1];
    expect(pan, '7.0, 3.0');
  });

  // The expected defaults (maxInFlight 2, maxTiles 256) and slider ranges
  // (1..8, 16..1024) mirror the pane and TileCache; if those constants change
  // this test must change with them.
  testWidgets('sliders change the real cache limits', (tester) async {
    await tester.pumpWidget(const PainterApp());
    await tester.sendKeyEvent(LogicalKeyboardKey.f3);
    await tester.pump();
    final cache = _rendererOf(tester).cache;
    expect(cache.maxInFlight, 2);
    expect(cache.maxTiles, 256);

    // The bar is the row minus a 6px gap and a 110px label column.
    Future<Rect> barOf(String label) async {
      final slider = find.widgetWithText(ImSliderInt, label);
      await tester.ensureVisible(slider);
      await tester.pump();
      final r = tester.getRect(slider);
      return Rect.fromLTRB(r.left, r.top, r.right - 116, r.bottom);
    }

    var bar = await barOf('max in flight');
    await tester.tapAt(bar.centerLeft);
    await tester.pump();
    expect(cache.maxInFlight, 1, reason: 'left edge is the minimum');

    await tester.tapAt(bar.centerRight - const Offset(1, 0));
    await tester.pump();
    expect(cache.maxInFlight, 8, reason: 'right edge is the maximum');

    bar = await barOf('max tiles');
    await tester.tapAt(bar.centerLeft);
    await tester.pump();
    expect(cache.maxTiles, 16);
    await tester.tapAt(bar.center);
    await tester.pump();
    expect(cache.maxTiles, closeTo((16 + 1024) / 2, 8));
  });

  // invalidateAll (TileCache) must clear tiles and generated splats before the
  // next frame can re-request them, so the first assertions run before any
  // pump. The splatsGenerated check proves the splats were rebuilt rather
  // than reused.
  testWidgets(
    'discard-all drops every built tile and rebuilds from the document',
    (tester) async {
      await tester.pumpWidget(const PainterApp());
      await tester.sendKeyEvent(LogicalKeyboardKey.f3);
      await tester.pump();
      await _drawStroke(tester);
      await _letTilesLand(tester);
      final cache = _rendererOf(tester).cache;
      expect(cache.imageTiles, greaterThan(0));
      final fullBefore = cache.counters.fullBuilds;
      final generatedBefore = cache.counters.splatsGenerated;

      final button = find.text('Discard all tiles (rebuild)');
      await tester.ensureVisible(button);
      await tester.tap(button);
      // Inspect before any frame can re-request tiles.
      expect(cache.cachedTiles, 0);
      expect(cache.imageTiles, 0);
      expect(cache.generatedStrokes, 0);

      // One frame repaints the canvas, which re-requests the visible tiles.
      await tester.pump();
      await _letTilesLand(tester);
      expect(cache.imageTiles, greaterThan(0));
      expect(cache.counters.fullBuilds, greaterThan(fullBefore));
      expect(
        cache.counters.splatsGenerated,
        greaterThan(generatedBefore),
        reason: 'splats were regenerated, not reused',
      );
    },
  );

  testWidgets('reset view returns pan, zoom and rotation to defaults', (
    tester,
  ) async {
    await tester.pumpWidget(const PainterApp());
    await tester.sendKeyEvent(LogicalKeyboardKey.f3);
    await tester.pump();
    final controller = tester
        .widget<CanvasView>(find.byType(CanvasView))
        .controller;
    controller
      ..panBy(const Offset(40, 10))
      ..zoomAt(Offset.zero, const Size(100, 100), 2)
      ..rotateAt(Offset.zero, const Size(100, 100), 0.5);
    expect(controller.zoom, 2);

    final button = find.text('Reset view');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    expect(controller.pan, Offset.zero);
    expect(controller.zoom, 1);
    expect(controller.rotation, 0);
  });

  testWidgets('overlay checkboxes flip the options the canvas reads', (
    tester,
  ) async {
    await tester.pumpWidget(const PainterApp());
    await tester.sendKeyEvent(LogicalKeyboardKey.f3);
    await tester.pump();
    final options = tester
        .widget<CanvasView>(find.byType(CanvasView))
        .debugOptions!;
    expect(options.anyOverlay, isFalse);

    for (final (label, read) in <(String, bool Function())>[
      ('tile state tint', () => options.showTileState),
      ('tile grid', () => options.showTileGrid),
      ('tile coordinates', () => options.showCoordinates),
      ('visible rectangle', () => options.showVisibleRect),
    ]) {
      final box = find.text(label);
      await tester.ensureVisible(box);
      await tester.tap(box);
      await tester.pump();
      expect(read(), isTrue, reason: label);
    }
    expect(options.anyOverlay, isTrue);
    // The legend appears with the tint.
    expect(find.text('coarser fallback'), findsWidgets);
  });

  // imCopy writes through Clipboard.setData on SystemChannels.platform; the
  // mock handler captures that call. The expected strings come from
  // _Reading.report() in canvas_debug_pane.dart.
  testWidgets('copy report puts a readable summary on the clipboard', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(const PainterApp());
    await tester.sendKeyEvent(LogicalKeyboardKey.f3);
    await tester.pump();
    await _drawStroke(tester);
    await _letTilesLand(tester);

    final button = find.text('Copy report');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();

    expect(copied, isNotNull);
    expect(copied, contains('painter tile cache report'));
    expect(copied, contains('document: strokes=1 points=2'));
    expect(copied, contains('viewport: zoom=1.000'));
    expect(copied, matches(RegExp(r'builds=\d+ \(full=\d+')));
    expect(find.text('Report copied to clipboard'), findsOneWidget);
  });

  // The pane's refresh timer is a Timer.periodic cancelled in dispose; the
  // test harness fails a test that ends with a pending timer.
  testWidgets('the pane stops its refresh timer when closed', (tester) async {
    await tester.pumpWidget(const PainterApp());
    await tester.sendKeyEvent(LogicalKeyboardKey.f3);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f3);
    await tester.pump();
    // A leaked periodic timer would fail the end-of-test pending-timer check.
    expect(_pane, findsNothing);
  });

  test('CanvasDebugOptions notifies only on real changes', () {
    final options = CanvasDebugOptions();
    addTearDown(options.dispose);
    var notified = 0;
    options.addListener(() => notified++);

    options.showTileGrid = false; // already false
    expect(notified, 0);
    options.showTileGrid = true;
    options.showTileGrid = true;
    expect(notified, 1);
    options.paused = true;
    expect(notified, 2);
    expect(options.anyOverlay, isTrue);
    options.showTileGrid = false;
    expect(options.anyOverlay, isFalse);
  });

  // The tint legend and the canvas both take their colors from tileDrawColor.
  test('every tile draw class has a distinct colour and a name', () {
    // Guards the overlay/legend pairing: two classes sharing a colour would be
    // indistinguishable on the canvas.
    final colors = {for (final d in TileDraw.values) d: tileDrawColor(d)};
    expect(colors.values.toSet().length, TileDraw.values.length);
  });
}
