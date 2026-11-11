// What: Widget tests drive PainterApp's Open/Save/Flash lifecycle across
//   shared Canvas panes, stored workspaces, and F1 help from a file-error
//   dialog.
// Why: T-005 requires document round-tripping and observable failures; the
//   docked Manual must expose the active error-control article without replacing
//   the current document. docs/spec/workspace.md requires that Open applies a
//   usable stored workspace and otherwise leaves the layout alone, that Save
//   preserves the file's workspace section, and that only Flash writes one.
// Covers: lib/main.dart (PainterApp file operations and Manual routing),
//   lib/document/document_file_service.dart, lib/document/
//   document_file_format.dart, CanvasDocument JSON round-tripping,
//   Workspace.applyJson/toJson through the app, CanvasView input, and
//   ManualPane selection from the Details control.
//
// Overview: how the file workflow is tested
// -----------------------------------------
// The app's open/save logic lives in PainterApp and talks to the file system
// only through DocumentFileService, whose two path-choosing methods need a
// BuildContext because the production service shows the in-app picker dialog
// (InAppFilePicker). These tests replace that service with
// _TestDocumentFileService, which returns fixed paths under a temporary
// directory, so they exercise the app-level flow (AppBar Save/Open buttons ->
// service -> JSON -> controller -> error dialog) without any picker UI. The
// picker dialog itself is tested in file_picker_dialog_test.dart. Files are
// really written and read, in a per-test temp directory deleted in tearDown.
//
// Not verified here (docs/status.md, T-005): the Open/Save UI in the running
// macOS Release build (a live visual confirmation is still outstanding), the
// default picker start directory or InAppDocumentFileService, and a dirty-state
// prompt before open discards changes (a product decision still open in
// docs/design/document/behavior.md). The failure test below checks structured
// file-operation records; the fatal-error behavior in
// docs/design/logging/behavior.md is not covered by this file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Rect, Size;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart'
    show AlertDialog, BuildContext, SelectableText, SizedBox, ValueKey;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:painter/canvas/canvas_controller.dart';
import 'package:painter/canvas/canvas_view.dart';
import 'package:painter/document/document_file_service.dart';
import 'package:painter/help/manual_catalog.dart';
import 'package:painter/help/manual_pane.dart';
import 'package:painter/logging/painter_log.dart';
import 'package:painter/main.dart';
import 'package:painter/settings/painter_settings.dart';
import 'package:painter/ui/painter_action_button.dart';

void main() {
  late Directory temporaryDirectory;

  // Each test gets its own directory so saved files never leak between tests
  // or into the repository.
  setUp(() {
    temporaryDirectory = Directory.systemTemp.createTempSync(
      'painter-document-test-',
    );
  });

  tearDown(() {
    temporaryDirectory.deleteSync(recursive: true);
  });

  // Confirms the associated save path is reused, both panes show the saved
  // content, and opening the saved file discards a later stroke but leaves
  // each Canvas pane's view as it was (WKSP-11: a file without a stored
  // workspace does not reset the active one).
  testWidgets(
    'both Canvas panes share saved content and Open leaves their views alone',
    (tester) async {
      final path = '${temporaryDirectory.path}/round-trip.paint';
      final fileService = _TestDocumentFileService(
        openPath: path,
        savePath: path,
      );
      await tester.pumpWidget(PainterApp(fileService: fileService));
      await _splitCanvas(tester);

      final views = tester
          .widgetList<CanvasView>(find.byType(CanvasView))
          .toList();
      expect(views, hasLength(2));
      final canvasFinder = find.byType(CanvasView).first;
      final controller = views.first.controller;
      final viewports = views.map((view) => view.viewport).toList();
      await _drawStroke(tester, canvasFinder, 1, const Offset(-24, 12));
      await _drawStroke(
        tester,
        find.byType(CanvasView).last,
        2,
        const Offset(36, -18),
      );
      expect(controller.document.strokes, hasLength(2));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(File(path).existsSync(), isTrue);
      expect(controller.document.strokes, hasLength(2));

      await _drawStroke(tester, canvasFinder, 3, const Offset(90, 30));
      expect(controller.document.strokes, hasLength(3));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final expectedPoints = controller.document.strokes
          .map(
            (stroke) => stroke.points.map((point) => point.position).toList(),
          )
          .toList();
      final expectedWeights = controller.document.strokes
          .map((stroke) => stroke.points.map((point) => point.weight).toList())
          .toList();
      await _drawStroke(tester, canvasFinder, 4, const Offset(120, 42));
      final canvasSize = tester.getSize(canvasFinder);
      // Give the panes different views so a reset or a swap shows up.
      viewports[0]
        ..panBy(const Offset(40, 25))
        ..zoomAt(const Offset(50, 50), canvasSize, 2)
        ..rotateAt(const Offset(50, 50), canvasSize, 0.25);
      viewports[1].panBy(const Offset(-7, 3));
      final expectedViews = [
        for (final viewport in viewports)
          (viewport.pan, viewport.zoom, viewport.rotation),
      ];

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(controller.document.strokes, hasLength(3));
      expect(fileService.savePathRequests, 1);
      final reopenedViews = tester
          .widgetList<CanvasView>(find.byType(CanvasView))
          .toList();
      expect(reopenedViews, hasLength(2));
      expect([
        for (final view in reopenedViews)
          (view.viewport.pan, view.viewport.zoom, view.viewport.rotation),
      ], expectedViews);
      final reopenedStrokes = controller.document.strokes.toList();
      for (var index = 0; index < reopenedStrokes.length; index++) {
        expect(
          reopenedStrokes[index].points.map((point) => point.position),
          orderedEquals(expectedPoints[index]),
        );
        expect(
          reopenedStrokes[index].points.map((point) => point.weight),
          orderedEquals(expectedWeights[index]),
        );
      }
    },
  );

  // Open applies a stored workspace (WKSP-9) unless the setting is off
  // (WKSP-10) or the section is unusable (WKSP-12); in those cases the
  // layout and every view stay as they were (WKSP-11), the strokes still
  // load, and no error is shown.
  testWidgets('Open applies the workspace stored in the file', (tester) async {
    final path = '${temporaryDirectory.path}/stored.paint';
    _writeFixture(path, workspace: _canvasAndManualSection);
    await _pumpApp(tester, _TestDocumentFileService(openPath: path));
    final controller = tester
        .widget<CanvasView>(find.byType(CanvasView))
        .controller;

    await _tapAction(tester, 'Open');

    expect(controller.document.strokeCount, 2);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(CanvasView), findsOneWidget);
    expect(find.byType(ManualPane), findsOneWidget);
    expect(
      tester.widget<ManualPane>(find.byType(ManualPane)).helpId,
      HelpId.openDocument,
    );
    expect(tester.widget<CanvasView>(find.byType(CanvasView)).viewport.zoom, 2);
    expect(
      tester.getRect(find.byType(CanvasView)).right,
      lessThanOrEqualTo(tester.getRect(find.byType(ManualPane)).left),
    );
  });

  testWidgets('Open ignores the stored workspace when loading is off', (
    tester,
  ) async {
    final path = '${temporaryDirectory.path}/stored.paint';
    _writeFixture(path, workspace: _canvasAndManualSection);
    await _pumpApp(
      tester,
      _TestDocumentFileService(openPath: path),
      loadStoredWorkspaces: false,
    );
    final layout = await _arrangeCurrentLayout(tester);

    await _tapAction(tester, 'Open');

    expect(find.byType(AlertDialog), findsNothing);
    expect(layout.controller.document.strokeCount, 2);
    _expectLayoutUntouched(tester, layout);
  });

  for (final entry in _unusableSections.entries) {
    testWidgets(
      'Open keeps the layout for an unusable section (${entry.key})',
      (tester) async {
        final path = '${temporaryDirectory.path}/damaged.paint';
        _writeFixture(path, workspace: entry.value);
        await _pumpApp(tester, _TestDocumentFileService(openPath: path));
        final layout = await _arrangeCurrentLayout(tester);

        await _tapAction(tester, 'Open');

        expect(find.byType(AlertDialog), findsNothing);
        expect(layout.controller.document.strokeCount, 2);
        _expectLayoutUntouched(tester, layout);
      },
    );
  }

  // Save must preserve the section exactly as it was read (WKSP-4), even one
  // this version cannot use, and must not invent one for a file without it.
  for (final entry in {
    'usable section': _canvasAndManualSection,
    ..._unusableSections,
  }.entries) {
    testWidgets(
      'Save writes the ${entry.key} workspace section back unchanged',
      (tester) async {
        final path = '${temporaryDirectory.path}/preserved.paint';
        _writeFixture(path, workspace: entry.value);
        await _pumpApp(tester, _TestDocumentFileService(openPath: path));
        await _tapAction(tester, 'Open');
        await _drawStroke(
          tester,
          find.byType(CanvasView).first,
          1,
          const Offset(-24, 12),
        );

        await _tapAction(tester, 'Save');

        final saved = _readFile(path);
        expect(saved['strokes'], hasLength(3), reason: 'the save really wrote');
        expect(saved['workspace'], entry.value);
      },
    );
  }

  testWidgets('Save adds no workspace section to a file that had none', (
    tester,
  ) async {
    final path = '${temporaryDirectory.path}/plain.paint';
    _writeFixture(path);
    await _pumpApp(tester, _TestDocumentFileService(openPath: path));
    await _tapAction(tester, 'Open');
    await _splitCanvas(tester);

    await _tapAction(tester, 'Save');

    final saved = _readFile(path);
    expect(saved['strokes'], hasLength(2));
    expect(saved.containsKey('workspace'), isFalse);
  });

  // Flash writes only the layout: the file's strokes are not replaced by the
  // in-memory document, so an unsaved stroke never reaches the file.
  testWidgets('Flash stores the layout and views without saving strokes', (
    tester,
  ) async {
    final path = '${temporaryDirectory.path}/flash.paint';
    _writeFixture(path, workspace: 'previous section');
    await _pumpApp(tester, _TestDocumentFileService(openPath: path));
    await _tapAction(tester, 'Open');
    final fileBefore = _readFile(path);
    final controller = tester
        .widget<CanvasView>(find.byType(CanvasView))
        .controller;
    await _drawStroke(
      tester,
      find.byType(CanvasView),
      1,
      const Offset(-24, 12),
    );
    expect(controller.document.strokeCount, 3);
    await _splitCanvas(tester);
    final left = tester
        .widget<CanvasView>(find.byKey(const ValueKey('canvas-0')))
        .viewport;
    left
      ..panBy(const Offset(30, 5))
      ..zoomAt(Offset.zero, const Size(100, 100), 2);
    final pan = left.pan;

    await _tapAction(tester, 'Flash layout');

    final flashed = _readFile(path);
    expect(flashed['strokes'], fileBefore['strokes']);
    expect(flashed['format'], fileBefore['format']);
    expect(flashed['version'], fileBefore['version']);
    final section = flashed['workspace'] as Map<String, dynamic>;
    expect(section['version'], 1);
    final panes = <Object?, Map<String, dynamic>>{
      for (final pane in section['panes'] as List)
        (pane as Map<String, dynamic>)['id']: pane,
    };
    expect(panes.keys, unorderedEquals([0, 1]));
    final first = panes[0]!;
    final second = panes[1]!;
    expect([first['left'], first['right']], [0, 0.5]);
    expect([second['left'], second['right']], [0.5, 1]);
    expect(first['mode'], 'canvas');
    expect(first['state']['canvas']['zoom'], 2);
    expect(second['state']['canvas']['zoom'], 1);

    // Dropping the second pane and reopening brings the flashed layout back
    // together with each pane's own view.
    await tester.tap(find.byKey(const ValueKey('frame-right-join-0')));
    await tester.pumpAndSettle();
    expect(find.byType(CanvasView), findsOneWidget);
    await _tapAction(tester, 'Open');

    expect(controller.document.strokeCount, 2);
    expect(find.byType(CanvasView), findsNWidgets(2));
    final restoredLeft = tester
        .widget<CanvasView>(find.byKey(const ValueKey('canvas-0')))
        .viewport;
    final restoredRight = tester
        .widget<CanvasView>(find.byKey(const ValueKey('canvas-1')))
        .viewport;
    expect(restoredLeft.zoom, 2);
    expect(restoredLeft.pan, pan);
    expect(restoredRight.zoom, 1);
  });

  testWidgets('Flash layout is disabled until the document has a file', (
    tester,
  ) async {
    final path = '${temporaryDirectory.path}/first-save.paint';
    await _pumpApp(tester, _TestDocumentFileService(savePath: path));
    bool flashEnabled() =>
        tester
            .widget<PainterActionButton>(
              find.widgetWithText(PainterActionButton, 'Flash layout'),
            )
            .onPressed !=
        null;

    expect(flashEnabled(), isFalse);
    await _tapAction(tester, 'Flash layout');
    expect(File(path).existsSync(), isFalse);

    await _tapAction(tester, 'Save');
    expect(flashEnabled(), isTrue);
  });

  // WKSP-4: only Flash (or a save to a new file) writes a section, so a layout
  // change after a Flash must not leak into the file through Save.
  testWidgets('Save keeps a flashed section after the layout changed', (
    tester,
  ) async {
    final path = '${temporaryDirectory.path}/flash-then-save.paint';
    _writeFixture(path);
    await _pumpApp(tester, _TestDocumentFileService(openPath: path));
    await _tapAction(tester, 'Open');
    await _splitCanvas(tester);
    await _tapAction(tester, 'Flash layout');
    final flashed = _readFile(path)['workspace'];
    expect((flashed as Map<String, dynamic>)['panes'], hasLength(2));

    await tester.tap(find.byKey(const ValueKey('frame-right-join-0')));
    await tester.pumpAndSettle();
    expect(find.byType(CanvasView), findsOneWidget);
    await _drawStroke(
      tester,
      find.byType(CanvasView),
      1,
      const Offset(-24, 12),
    );
    await _tapAction(tester, 'Save');

    final saved = _readFile(path);
    expect(saved['strokes'], hasLength(3), reason: 'the save really wrote');
    expect(saved['workspace'], flashed);
  });

  testWidgets('Flash reports a file it cannot update', (tester) async {
    final path = '${temporaryDirectory.path}/vanished.paint';
    _writeFixture(path);
    await _pumpApp(tester, _TestDocumentFileService(openPath: path));
    await _tapAction(tester, 'Open');
    File(path).deleteSync();

    await _tapAction(tester, 'Flash layout');

    expect(find.text('File operation failed'), findsOneWidget);
    expect(find.textContaining('Could not flash the document'), findsOneWidget);
    expect(File(path).existsSync(), isFalse);
  });

  // Failure modes: opening a file that is not a Painter document fails inside
  // CanvasDocument.fromJson (FormatException shown in Details); saving to a
  // path inside a directory that does not exist fails in writeDocument. In
  // both cases the one stroke drawn beforehand must survive, the dialog is
  // closed with its Close button, and the app must still be present.
  testWidgets('file failures show details and preserve document content', (
    tester,
  ) async {
    final path = '${temporaryDirectory.path}/invalid.paint';
    File(path).writeAsStringSync('not a Painter document');
    final fileService = _TestDocumentFileService(
      openPath: path,
      savePath: '${temporaryDirectory.path}/missing/save.paint',
    );
    final logger = PainterLog.memory();
    addTearDown(logger.dispose);
    await tester.pumpWidget(
      PainterApp(fileService: fileService, logger: logger),
    );

    final canvasFinder = find.byType(CanvasView);
    final controller = tester.widget<CanvasView>(canvasFinder).controller;
    await _drawStroke(tester, canvasFinder, 4, const Offset(10, 10));
    final originalPoints = controller.document.strokes.single.points
        .map((point) => point.position)
        .toList();

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('File operation failed'), findsOneWidget);
    expect(find.textContaining('Could not open the document'), findsOneWidget);
    expect(logger.entries, hasLength(1));
    expect(logger.entries.single.messageId, 'document.operation.failed');
    expect(logger.entries.single.arguments['operation'], 'open');
    expect(
      logger.entries.single.arguments['error'],
      contains('FormatException'),
    );
    expect(logger.entries.single.stackTrace, contains('_openDocument'));
    expect(controller.document.strokes, hasLength(1));
    expect(
      controller.document.strokes.single.points.map((point) => point.position),
      orderedEquals(originalPoints),
    );

    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      contains('FormatException'),
    );
    final pointer = TestPointer(42, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      pointer.hover(tester.getCenter(find.text('Details'))),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    await tester.pumpAndSettle();
    expect(find.byType(ManualPane), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.textContaining('Expand the error details to inspect the operation'),
      findsOneWidget,
    );

    final errorDialogClose = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Close'),
    );
    await tester.tap(errorDialogClose);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('File operation failed'), findsOneWidget);
    expect(find.textContaining('Could not save the document'), findsOneWidget);
    expect(logger.entries, hasLength(2));
    expect(logger.entries.last.messageId, 'document.operation.failed');
    expect(logger.entries.last.arguments['operation'], 'save');
    expect(logger.entries.last.stackTrace, isNotEmpty);
    expect(controller.document.strokes, hasLength(1));
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      contains('Exception'),
    );
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Close'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PainterApp), findsOneWidget);
    expect(controller.document.strokes, hasLength(1));
  });
  testWidgets('document failures log after PainterApp unmounts', (
    tester,
  ) async {
    final pendingRead = Completer<String>();
    final fileService = _PendingReadDocumentFileService(
      openPath: '${temporaryDirectory.path}/pending.paint',
      readCompleter: pendingRead,
    );
    final logger = PainterLog.memory();
    addTearDown(logger.dispose);
    await tester.pumpWidget(
      PainterApp(fileService: fileService, logger: logger),
    );

    await tester.tap(find.text('Open'));
    await tester.pump();
    expect(logger.entries, isEmpty);
    await tester.pumpWidget(const SizedBox());
    pendingRead.completeError(StateError('read failed'), StackTrace.current);
    await tester.pump();

    expect(logger.entries, hasLength(1));
    expect(logger.entries.single.messageId, 'document.operation.failed');
    expect(logger.entries.single.arguments['operation'], 'open');
    expect(logger.entries.single.arguments['error'], contains('read failed'));
    expect(logger.entries.single.stackTrace, isNotEmpty);
    expect(find.byType(PainterApp), findsNothing);
  });
}

/// Draws one short mouse stroke (14 x 8 units) starting at [offset] from the
/// canvas center. Callers pass a distinct [pointerId] per stroke so each one
/// is a fresh TestPointer. Pumps one frame after releasing.
Future<void> _drawStroke(
  WidgetTester tester,
  Finder canvasFinder,
  int pointerId,
  Offset offset,
) async {
  final center = tester.getRect(canvasFinder).center;
  final start = center + offset;
  final pointer = TestPointer(pointerId, PointerDeviceKind.mouse);
  await tester.sendEventToBinding(
    pointer.down(start, buttons: kPrimaryMouseButton),
  );
  await tester.sendEventToBinding(
    pointer.move(start + const Offset(14, 8), buttons: kPrimaryMouseButton),
  );
  await tester.sendEventToBinding(pointer.up());
  await tester.pump();
}

/// A fake DocumentFileService that returns fixed paths without driving any
/// picker UI, so these tests exercise the save/open/error-handling logic in
/// isolation from the in-app picker dialog (covered separately by
/// `file_picker_dialog_test.dart`).
///
/// [openPath] / [savePath] are what the "user" picks (null models a cancelled
/// picker). [savePathRequests] counts how often the app asked where to save,
/// which is how the tests observe that later saves reuse the associated path.
/// readDocument / writeDocument use synchronous File calls, so nothing awaits
/// real file I/O under the widget test's pumpAndSettle.
class _TestDocumentFileService extends DocumentFileService {
  _TestDocumentFileService({this.openPath, this.savePath});

  final String? openPath;
  final String? savePath;
  int savePathRequests = 0;

  @override
  Future<String?> chooseOpenPath(BuildContext context) async => openPath;

  @override
  Future<String?> chooseSavePath(
    BuildContext context,
    String suggestedName,
  ) async {
    savePathRequests++;
    return savePath;
  }

  @override
  Future<String> readDocument(String path) async =>
      File(path).readAsStringSync();

  @override
  Future<void> writeDocument(String path, String contents) async {
    File(path).writeAsStringSync(contents);
  }
}

class _PendingReadDocumentFileService extends _TestDocumentFileService {
  _PendingReadDocumentFileService({
    required super.openPath,
    required this.readCompleter,
  });

  final Completer<String> readCompleter;

  @override
  Future<String> readDocument(String path) => readCompleter.future;
}

/// Splits the Canvas pane 0 along its right edge; pane 1 is a Canvas pane with
/// a copy of pane 0's view.
Future<void> _splitCanvas(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('frame-right-add-0')));
  await tester.pumpAndSettle();
}

/// Taps the AppBar action labelled [label] (matched on the button, because
/// the Manual's navigation tree also contains some of these words).
Future<void> _tapAction(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(PainterActionButton, label));
  await tester.pumpAndSettle();
}

Future<void> _pumpApp(
  WidgetTester tester,
  DocumentFileService fileService, {
  bool loadStoredWorkspaces = true,
}) => tester.pumpWidget(
  PainterApp(
    fileService: fileService,
    initialSettings: PainterSettings.defaults.copyWith(
      loadStoredWorkspaces: loadStoredWorkspaces,
    ),
  ),
);

/// A layout that is easy to tell from the stored ones: two Canvas panes, the
/// left one zoomed to 3.
class _Arrangement {
  _Arrangement(this.controller, this.rects, this.zoom);

  final CanvasController controller;
  final List<Rect> rects;
  final double zoom;
}

Future<_Arrangement> _arrangeCurrentLayout(WidgetTester tester) async {
  await _splitCanvas(tester);
  final left = tester
      .widget<CanvasView>(find.byKey(const ValueKey('canvas-0')))
      .viewport;
  left.zoomAt(Offset.zero, const Size(100, 100), 3);
  await tester.pump();
  return _Arrangement(
    tester.widget<CanvasView>(find.byType(CanvasView).first).controller,
    [for (final rect in _canvasRects(tester)) rect],
    left.zoom,
  );
}

List<Rect> _canvasRects(WidgetTester tester) => [
  tester.getRect(find.byKey(const ValueKey('canvas-0'))),
  tester.getRect(find.byKey(const ValueKey('canvas-1'))),
];

/// Expects the layout built by [_arrangeCurrentLayout] to be exactly as left.
void _expectLayoutUntouched(WidgetTester tester, _Arrangement layout) {
  expect(find.byType(ManualPane), findsNothing);
  expect(find.byType(CanvasView), findsNWidgets(2));
  expect(_canvasRects(tester), layout.rects);
  expect(
    tester
        .widget<CanvasView>(find.byKey(const ValueKey('canvas-0')))
        .viewport
        .zoom,
    layout.zoom,
  );
}

Map<String, Object?> _paneJson(
  int id,
  double left,
  double right,
  String mode,
  Map<String, Object?> state,
) => {
  'id': id,
  'left': left,
  'top': 0.0,
  'right': right,
  'bottom': 1.0,
  'mode': mode,
  'state': state,
};

Map<String, Object?> _canvasState(double zoom) => {
  'canvas': {
    'pan': {'dx': 0.0, 'dy': 0.0},
    'zoom': zoom,
    'rotation': 0.0,
  },
};

/// A usable stored workspace: a zoomed Canvas on the left, the Manual on the
/// right showing the Open document article.
final Map<String, Object?> _canvasAndManualSection = {
  'version': 1,
  'panes': [
    _paneJson(0, 0, 0.5, 'canvas', _canvasState(2)),
    _paneJson(1, 0.5, 1, 'manual', {
      'manual': {'help': 'openDocument'},
    }),
  ],
};

/// Workspace values a file may hold that this version must not apply.
final Map<String, Object?> _unusableSections = {
  'overlapping panes': {
    'version': 1,
    'panes': [
      _paneJson(0, 0, 0.6, 'canvas', _canvasState(2)),
      _paneJson(1, 0.4, 1, 'canvas', _canvasState(2)),
    ],
  },
  'unknown mode': {
    'version': 1,
    'panes': [_paneJson(0, 0, 1, 'hologram', _canvasState(2))],
  },
  'newer version': {
    'version': 99,
    'panes': [_paneJson(0, 0, 1, 'canvas', _canvasState(2))],
  },
  'not an object': 'garbage',
};

/// Writes a two-stroke document file, with [workspace] as its `workspace`
/// value when given.
void _writeFixture(String path, {Object? workspace}) {
  List<Object?> stroke(double x) => [
    {'x': x, 'y': 10.0, 'weight': 0.5},
    {'x': x + 5, 'y': 12.0, 'weight': 0.6},
  ];
  File(path).writeAsStringSync(
    jsonEncode({
      'format': CanvasDocument.formatIdentifier,
      'version': CanvasDocument.formatVersion,
      'strokes': [stroke(10), stroke(40)],
      'workspace': ?workspace,
    }),
  );
}

Map<String, dynamic> _readFile(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
