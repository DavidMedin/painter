// What: Widget tests run the real PainterApp with docked diagnostics and check
//   that pane readouts, controls, overlay switches and reports track the real
//   tile cache, canvas controller and CanvasDebugOptions; plus two plain unit
//   tests on CanvasDebugOptions and the tile-draw colors.
// Why: The pane (design/diagnostics/debug-pane.md) is the only way to observe
//   the asynchronous tile cache in the app. A readout that lies or a control
//   that does nothing defeats its purpose. Tests also cover pause freezing
//   every readout and that a pane's canvas view survives a mode round trip.
// Covers: lib/debug/canvas_debug_pane.dart, lib/debug/canvas_debug_options.dart,
//   lib/debug/tile_overlay.dart, and lib/main.dart pane-mode wiring.
//
// Overview: the pane is pure presentation over live renderer/controller state.
// The tests pump PainterApp, dock Diagnostics beside the Canvas through the
// pane frame's add button and mode dropdown, draw synthetic strokes, and
// compare visible values with TileCache, CanvasController and options.
// Tile builds require real asynchronous time (see _letTilesLand). Layout uses
// the Ahem test font.
//
// Not verified here: macOS window appearance, Menlo font rendering, counters'
// overhead, and behavior with very large documents or extreme zoom. Overlay
// painting is not pixel-checked; only the switches the canvas reads are.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:painter/canvas/canvas_view.dart';
import 'package:painter/canvas/canvas_viewport.dart';
import 'package:painter/canvas/tile_stats.dart';
import 'package:painter/canvas/tiled_renderer.dart';
import 'package:painter/debug/canvas_debug_options.dart';
import 'package:painter/debug/canvas_debug_pane.dart';
import 'package:painter/debug/imgui.dart';
import 'package:painter/debug/tile_overlay.dart';
import 'package:painter/settings/painter_settings.dart';
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

/// Selects [label] in the mode dropdown of pane [paneId].
Future<void> _chooseMode(WidgetTester tester, int paneId, String label) async {
  await tester.tap(find.byKey(ValueKey('pane-mode-$paneId')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

/// Docks a Diagnostics pane (id 1) right of the Canvas pane (id 0): adds a
/// pane on pane 0's right edge, then switches the new pane to Diagnostics.
Future<void> _openDiagnostics(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('frame-right-add-0')));
  await tester.pumpAndSettle();
  await _chooseMode(tester, 1, 'Diagnostics');
}

/// Draws one short mouse stroke well inside a Canvas pane ([canvas], default
/// the only CanvasView) with synthetic mouse events through the binding, like
/// the canvas tests.
Future<void> _drawStroke(WidgetTester tester, [Finder? canvas]) async {
  final rect = tester.getRect(canvas ?? find.byType(CanvasView));
  final start = Offset(rect.left + rect.width * 0.65, rect.center.dy);
  final mouse = TestPointer(1, PointerDeviceKind.mouse);
  await tester.sendEventToBinding(
    mouse.down(start, buttons: kPrimaryMouseButton),
  );
  // Short enough to stay one stroke (under the 64-unit chunk length) even in
  // a 100 px pane, where the default 1024-unit extent maps 1 px to ~10 units.
  await tester.sendEventToBinding(
    mouse.move(start + const Offset(4, 1), buttons: kPrimaryMouseButton),
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

  testWidgets('a pane keeps its canvas view across a Diagnostics round trip', (
    tester,
  ) async {
    await tester.pumpWidget(const PainterApp());
    final viewport = tester
        .widget<CanvasView>(find.byType(CanvasView))
        .viewport;
    viewport
      ..panBy(const Offset(40, 10), const Size(100, 100))
      ..zoomAt(Offset.zero, const Size(100, 100), 2)
      ..rotateAt(Offset.zero, const Size(100, 100), 0.5);
    final center = viewport.center;
    final extent = viewport.extent;

    await _chooseMode(tester, 0, 'Diagnostics');
    expect(_pane, findsOneWidget);
    expect(find.byType(CanvasView), findsNothing);

    await _chooseMode(tester, 0, 'Canvas');
    expect(_pane, findsNothing);
    expect(find.byType(CanvasView), findsOneWidget);
    final restored = tester
        .widget<CanvasView>(find.byType(CanvasView))
        .viewport;
    expect(restored.center, center);
    expect(restored.extent, extent);
    expect(restored.rotation, closeTo(0.5, 1e-9));
  });

  testWidgets('diagnostics controls are at least 48 px tall', (tester) async {
    await tester.pumpWidget(const PainterApp());
    await _openDiagnostics(tester);

    for (final control in [
      find.byType(ImCheckbox).first,
      find.byType(ImSliderInt).first,
    ]) {
      await tester.ensureVisible(control);
      await tester.pump();
      expect(tester.getSize(control).height, greaterThanOrEqualTo(48));
    }
  });

  testWidgets(
    'drawing still works with docked diagnostics and a split canvas',
    (tester) async {
      await tester.pumpWidget(const PainterApp());
      await _openDiagnostics(tester);
      final controller = tester
          .widget<CanvasView>(find.byType(CanvasView))
          .controller;

      await _drawStroke(tester);
      expect(controller.document.strokeCount, 1);

      // Splitting the Canvas pane adds a second Canvas pane (second in tree
      // order, so second in the Stack) that shares the document; both it and
      // the first pane keep accepting strokes.
      await tester.tap(find.byKey(const ValueKey('frame-right-add-0')));
      await tester.pumpAndSettle();
      expect(_pane, findsOneWidget);
      expect(find.byType(CanvasView), findsNWidgets(2));
      await _drawStroke(tester, find.byType(CanvasView).at(1));
      expect(controller.document.strokeCount, 2);
      await _drawStroke(tester, find.byType(CanvasView).at(0));
      expect(controller.document.strokeCount, 3);
    },
  );

  // The 'Document and splats' section starts closed (initiallyOpen: false), so
  // the test opens it first. The 300 ms pump lets the pane's 250 ms refresh
  // timer take a new snapshot after the tiles land.
  testWidgets('readouts follow real cache state as strokes land', (
    tester,
  ) async {
    await tester.pumpWidget(const PainterApp());
    await _openDiagnostics(tester);

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

  // Regression (docs/design/diagnostics/debug-pane.md, Regression Notes): the pane used to mix frozen and live reads,
  // so Pause did not actually freeze every readout and the report could
  // disagree with the screen. The test compares every Text widget while
  // paused after a stroke, new tiles, a pan and more frames. It also checks
  // options.paused after each tap so a missed tap cannot pass vacuously.
  testWidgets('pause freezes the readouts until resumed', (tester) async {
    await tester.pumpWidget(const PainterApp());
    await _openDiagnostics(tester);
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
    // At extent 1024 a 1024-pixel pane is 1:1, so the center moves by -delta.
    view.viewport.panBy(const Offset(7, 3), const Size(1024, 1024));
    await tester.pump(const Duration(milliseconds: 600));
    expect(texts(), before, reason: 'frozen while paused');

    await setPaused(false);
    await tester.pump(const Duration(milliseconds: 600));
    final after = texts();
    expect(after, isNot(before), reason: 'live again after resuming');
    final center = after[after.indexOf('center') + 1];
    expect(center, '505.0, 509.0');
  });

  // The expected defaults (maxInFlight 2, maxTiles 256) and slider ranges
  // (1..8, 16..1024) mirror the pane and TileCache; if those constants change
  // this test must change with them.
  testWidgets('sliders change the real cache limits', (tester) async {
    await tester.pumpWidget(const PainterApp());
    await _openDiagnostics(tester);
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
      await _openDiagnostics(tester);
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

  testWidgets('reset view returns center, extent and rotation to defaults', (
    tester,
  ) async {
    await tester.pumpWidget(const PainterApp());
    await _openDiagnostics(tester);
    final viewport = tester
        .widget<CanvasView>(find.byType(CanvasView))
        .viewport;
    viewport
      ..panBy(const Offset(40, 10), const Size(100, 100))
      ..zoomAt(Offset.zero, const Size(100, 100), 2)
      ..rotateAt(Offset.zero, const Size(100, 100), 0.5);
    expect(viewport.extent, CanvasViewportController.defaultExtent / 2);

    final button = find.text('Reset view');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    expect(viewport.center, CanvasViewportController.defaultCenter);
    expect(viewport.extent, CanvasViewportController.defaultExtent);
    expect(viewport.rotation, 0);
  });

  testWidgets('overlay checkboxes flip the options the canvas reads', (
    tester,
  ) async {
    await tester.pumpWidget(const PainterApp());
    await _openDiagnostics(tester);
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
    await _openDiagnostics(tester);
    await _drawStroke(tester);
    await _letTilesLand(tester);

    final button = find.text('Copy report');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();

    expect(copied, isNotNull);
    expect(copied, contains('painter tile cache report'));
    expect(copied, contains('document: strokes=1 points=2'));
    expect(
      copied,
      contains('viewport: center=512.0,512.0 extent=1024.0 rotation=0.000rad'),
    );
    expect(copied, matches(RegExp(r'builds=\d+ \(full=\d+')));
    expect(find.text('Report copied to clipboard'), findsOneWidget);
  });

  // The pane's refresh timer is a Timer.periodic cancelled in dispose; the
  // test harness fails a test that ends with a pending timer.
  testWidgets('the pane stops its refresh timer when closed', (tester) async {
    await tester.pumpWidget(const PainterApp());
    await _openDiagnostics(tester);
    // Joining pane 0 over its right neighbor removes the Diagnostics pane.
    await tester.tap(find.byKey(const ValueKey('frame-right-join-0')));
    await tester.pumpAndSettle();
    // A leaked periodic timer would fail the end-of-test pending-timer check.
    expect(_pane, findsNothing);
    expect(find.byType(CanvasView), findsOneWidget);
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
  test(
    'every tile draw class has a distinct color in both built-in themes',
    () {
      for (final palette in [
        PainterSettings.gruvboxLight,
        PainterSettings.gruvboxDark,
      ]) {
        final theme = palette.themeData;
        final colors = theme.extension<PainterThemeColors>()!;
        final draws = {
          for (final draw in TileDraw.values)
            draw: tileDrawColor(draw, theme.colorScheme, colors),
        };
        expect(
          draws.values.toSet().length,
          TileDraw.values.length,
          reason: palette.name,
        );
      }
    },
  );
}
