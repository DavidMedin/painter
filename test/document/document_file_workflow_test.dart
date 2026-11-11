// What: Widget tests drive PainterApp's Open/Save/Flash lifecycle across
//   shared Canvas panes, stored workspaces, earlier-format and format 2
//   files, Undo/Redo from the AppBar and the keyboard, and F1 help from a
//   file-error dialog.
// Why: docs/spec/document-file.md requires that old files open and are saved
//   in the current format (DOCF-3, DOCF-4) and that a file that cannot be
//   read, or has another engine version, is refused with the reason while
//   the current document stays (DOCF-6, DOCF-7); the docked Manual must
//   expose the active error-control article without replacing the current
//   document. docs/spec/workspace.md requires that Open applies a usable
//   stored workspace and otherwise leaves the layout alone, that Save
//   preserves the file's workspace section, and that only Flash writes one.
//   docs/spec/undo-redo.md and docs/spec/keybinds.md (KEY-3) require Undo
//   and Redo from buttons and Command+Z / Command+Shift+Z.
// Covers: lib/main.dart (PainterApp file operations, Undo/Redo and Manual
//   routing), lib/document/document_file_service.dart, lib/document/
//   document_file_format.dart, lib/document/content_document.dart,
//   lib/document/undo_history.dart, Workspace.applyJson/toJson through the
//   app, CanvasView input, and ManualPane selection from the Details
//   control.
//
// Overview: how the file workflow is tested
// -----------------------------------------
// The app's open/save logic lives in PainterApp and talks to the file system
// only through DocumentFileService, whose two path-choosing methods need a
// BuildContext because the production service shows the in-app picker dialog
// (InAppFilePicker). These tests replace that service with
// _TestDocumentFileService, which returns fixed paths under a temporary
// directory, so they exercise the app-level flow (AppBar Save/Open buttons ->
// service -> file format -> controller -> error dialog) without any picker
// UI. The picker dialog itself is tested in file_picker_dialog_test.dart.
// Files are really written and read, in a per-test temp directory deleted in
// tearDown. Fixtures are written in the earlier JSON format; Save turns them
// into format 2, which _readFile reads back with DocumentFileContents.
//
// Not verified here: the Open/Save UI in the running macOS Release build,
// the default picker start directory or InAppDocumentFileService, a
// dirty-state prompt before open discards changes, and fatal-error
// behavior.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect, Size;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart'
    show AlertDialog, BuildContext, SelectableText, SizedBox, Text, ValueKey;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:painter/canvas/canvas_controller.dart';
import 'package:painter/canvas/canvas_view.dart';
import 'package:painter/canvas/pencil_splats.dart' show strokeEngineVersion;
import 'package:painter/crdt/automerge_crdt_document.dart';
import 'package:painter/document/content_document.dart';
import 'package:painter/document/document_file_format.dart';
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
        ..panBy(const Offset(40, 25), canvasSize)
        ..zoomAt(const Offset(50, 50), canvasSize, 2)
        ..rotateAt(const Offset(50, 50), canvasSize, 0.25);
      viewports[1].panBy(const Offset(-7, 3), canvasSize);
      final expectedViews = [
        for (final viewport in viewports)
          (viewport.center, viewport.extent, viewport.rotation),
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
          (view.viewport.center, view.viewport.extent, view.viewport.rotation),
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
    expect(
      tester.widget<CanvasView>(find.byType(CanvasView)).viewport.extent,
      512,
    );
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
        expect(saved.format2, isTrue, reason: 'Save writes format 2');
        expect(saved.strokeCount, 3, reason: 'the save really wrote');
        expect(saved.workspace, entry.value);
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
    expect(saved.strokeCount, 2);
    expect(saved.hasWorkspace, isFalse);
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
    final fileBefore = _readJson(path);
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
        .widget<CanvasView>(find.byType(CanvasView).at(0))
        .viewport;
    left
      ..panBy(const Offset(30, 5), const Size(100, 100))
      ..zoomAt(Offset.zero, const Size(100, 100), 2);
    final center = left.center;

    await _tapAction(tester, 'Flash layout');

    final flashed = _readJson(path);
    expect(flashed['strokes'], fileBefore['strokes']);
    expect(flashed['format'], fileBefore['format']);
    expect(flashed['version'], fileBefore['version']);
    final section = flashed['workspace'] as Map<String, dynamic>;
    expect(section['version'], 2);
    final root = section['root'] as Map<String, dynamic>;
    expect(root['split'], 'row');
    final parts = (root['parts'] as List).cast<Map<String, dynamic>>();
    expect([for (final part in parts) part['share']], [0.5, 0.5]);
    final first = parts[0]['node']['pane'] as Map<String, dynamic>;
    final second = parts[1]['node']['pane'] as Map<String, dynamic>;
    expect(first['mode'], 'canvas');
    expect(first['state']['canvas']['extent'], 512);
    // The new pane's view was never changed, so it stores none and opens
    // with the default view, as checked after reopening below.
    expect(second['mode'], 'canvas');

    // Dropping the second pane and reopening brings the flashed layout back
    // together with each pane's own view.
    await tester.tap(find.byKey(const ValueKey('frame-right-join-0')));
    await tester.pumpAndSettle();
    expect(find.byType(CanvasView), findsOneWidget);
    await _tapAction(tester, 'Open');

    expect(controller.document.strokeCount, 2);
    expect(find.byType(CanvasView), findsNWidgets(2));
    final restoredLeft = tester
        .widget<CanvasView>(find.byType(CanvasView).at(0))
        .viewport;
    final restoredRight = tester
        .widget<CanvasView>(find.byType(CanvasView).at(1))
        .viewport;
    expect(restoredLeft.extent, 512);
    expect(restoredLeft.center, center);
    expect(restoredRight.extent, 1024);
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
    final flashed = _readJson(path)['workspace'];
    expect((flashed as Map<String, dynamic>)['root']['parts'], hasLength(2));

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
    expect(saved.strokeCount, 3, reason: 'the save really wrote');
    expect(saved.workspace, flashed);
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

  // Failure modes: opening a file that is not a Painter document fails while
  // reading it as the earlier format (FormatException shown in Details);
  // saving to a path inside a directory that does not exist fails in
  // writeDocument. In both cases the one stroke drawn beforehand must
  // survive, the dialog is closed with its Close button, and the app must
  // still be present.
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
    final pendingRead = Completer<Uint8List>();
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

  // DOCF-3, DOCF-4: an earlier-format file opens with its old grain, is saved
  // as format 2, and reopens with the same strokes.
  testWidgets('Save writes an earlier-format file as format 2', (
    tester,
  ) async {
    final path = '${temporaryDirectory.path}/old.paint';
    _writeFixture(path);
    await _pumpApp(
      tester,
      _TestDocumentFileService(openPath: path, savePath: path),
    );
    final controller = tester
        .widget<CanvasView>(find.byType(CanvasView))
        .controller;
    await _tapAction(tester, 'Open');
    final opened = [
      for (final s in controller.document.strokes) (s.id, s.seed, s.z),
    ];
    expect([for (final s in opened) s.$2], [1, 2]);

    await _tapAction(tester, 'Save');
    expect(_readFile(path).format2, isTrue);
    await _tapAction(tester, 'Open');

    expect([
      for (final s in controller.document.strokes) (s.id, s.seed, s.z),
    ], opened);
  });

  // DOCF-6, DOCF-7: a file that cannot be read in full or that has another
  // engine version is refused with the reason, and the drawn stroke stays.
  final unreadable = <String, (Uint8List Function(), Matcher)>{
    'truncated format 2': (
      () {
        final content = ContentDocument.create(const AutomergeBackend());
        final bytes = DocumentFileContents.encode(content, const []);
        content.dispose();
        return Uint8List.sublistView(bytes, 0, bytes.length - 5);
      },
      contains('FormatException'),
    ),
    'other engine version': (
      () {
        final crdt = const AutomergeBackend().create()
          ..put(['format'], ContentDocument.formatIdentifier)
          ..put(['version'], ContentDocument.formatVersion)
          ..put(['engine'], strokeEngineVersion + 1)
          ..putMap(['strokes'])
          ..commit();
        final bytes = DocumentContainer([
          DocumentSection(DocumentContainer.contentKind, crdt.save()),
        ]).encode();
        crdt.dispose();
        return bytes;
      },
      allOf(
        contains('version ${strokeEngineVersion + 1}'),
        contains('version $strokeEngineVersion'),
      ),
    ),
  };
  for (final entry in unreadable.entries) {
    testWidgets('Open refuses a file (${entry.key}) and keeps the document', (
      tester,
    ) async {
      final path = '${temporaryDirectory.path}/refused.paint';
      File(path).writeAsBytesSync(entry.value.$1());
      await _pumpApp(tester, _TestDocumentFileService(openPath: path));
      final canvasFinder = find.byType(CanvasView);
      final controller = tester.widget<CanvasView>(canvasFinder).controller;
      await _drawStroke(tester, canvasFinder, 1, const Offset(10, 10));
      final before = controller.document.strokes.single;

      await _tapAction(tester, 'Open');

      expect(find.text('File operation failed'), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.textContaining('Could not open the document'))
            .data,
        entry.value.$2,
      );
      expect(controller.document.strokes.single, same(before));
      expect(_actionEnabled(tester, 'Undo'), isTrue);
    });
  }

  // Flash leaves a format 2 file's content section exactly as on disk, so
  // the unsaved stroke stays out of the file (WKSP-2, WKSP-3).
  testWidgets('Flash changes only the workspace section of a format 2 file', (
    tester,
  ) async {
    final path = '${temporaryDirectory.path}/flash2.paint';
    _writeFixture(path, workspace: 'previous section');
    await _pumpApp(tester, _TestDocumentFileService(openPath: path));
    await _tapAction(tester, 'Open');
    await _tapAction(tester, 'Save');
    final before = _readFile(path).sections;
    await _drawStroke(
      tester,
      find.byType(CanvasView),
      1,
      const Offset(-24, 12),
    );
    await _splitCanvas(tester);

    await _tapAction(tester, 'Flash layout');

    final after = _readFile(path);
    expect(after.strokeCount, 2);
    expect([for (final s in after.sections) s.kind], [1, 2]);
    expect(after.sections.first.bytes, before.first.bytes);
    expect(after.workspace, isNotNull);
    expect(after.workspace, isNot('previous section'));
  });

  // docs/spec/undo-redo.md: Draw A, draw B, undo -> only A; redo -> both.
  testWidgets('Undo and Redo buttons revert and reapply a stroke', (
    tester,
  ) async {
    await _pumpApp(tester, _TestDocumentFileService());
    final canvasFinder = find.byType(CanvasView);
    final controller = tester.widget<CanvasView>(canvasFinder).controller;
    expect(_actionEnabled(tester, 'Undo'), isFalse);
    expect(_actionEnabled(tester, 'Redo'), isFalse);
    await _drawStroke(tester, canvasFinder, 1, const Offset(-20, 0));
    await _drawStroke(tester, canvasFinder, 2, const Offset(20, 0));
    final ids = [for (final s in controller.document.strokes) s.id];

    await _tapAction(tester, 'Undo');
    expect([for (final s in controller.document.strokes) s.id], [ids.first]);
    expect(_actionEnabled(tester, 'Redo'), isTrue);

    await _tapAction(tester, 'Redo');
    expect([for (final s in controller.document.strokes) s.id], ids);
    expect(_actionEnabled(tester, 'Redo'), isFalse);
  });

  testWidgets('Command+Z undoes and Command+Shift+Z redoes (KEY-3)', (
    tester,
  ) async {
    await _pumpApp(tester, _TestDocumentFileService());
    final canvasFinder = find.byType(CanvasView);
    final controller = tester.widget<CanvasView>(canvasFinder).controller;
    await _drawStroke(tester, canvasFinder, 1, Offset.zero);

    await _commandKey(tester, LogicalKeyboardKey.keyZ);
    expect(controller.document.strokeCount, 0);

    await _commandKey(tester, LogicalKeyboardKey.keyZ, shift: true);
    expect(controller.document.strokeCount, 1);
  });

  testWidgets('Undo is disabled mid-stroke and ignores Command+Z (UNDO-4)', (
    tester,
  ) async {
    await _pumpApp(tester, _TestDocumentFileService());
    final canvasFinder = find.byType(CanvasView);
    final controller = tester.widget<CanvasView>(canvasFinder).controller;
    await _drawStroke(tester, canvasFinder, 1, Offset.zero);
    final start = tester.getCenter(canvasFinder) + const Offset(30, 30);
    final pointer = TestPointer(2, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      pointer.down(start, buttons: kPrimaryMouseButton),
    );
    await tester.sendEventToBinding(
      pointer.move(start + const Offset(9, 9), buttons: kPrimaryMouseButton),
    );
    await tester.pump();

    expect(_actionEnabled(tester, 'Undo'), isFalse);
    await _commandKey(tester, LogicalKeyboardKey.keyZ);
    expect(controller.strokeInProgress, isTrue);
    expect(controller.document.strokeCount, 1);

    await tester.sendEventToBinding(pointer.up());
    await tester.pump();
    expect(controller.document.strokeCount, 2);
    expect(_actionEnabled(tester, 'Undo'), isTrue);
  });

  // PNT-A0018-05: opening a document starts a new history.
  testWidgets('Open clears the undo history', (tester) async {
    final path = '${temporaryDirectory.path}/fresh.paint';
    _writeFixture(path);
    await _pumpApp(tester, _TestDocumentFileService(openPath: path));
    final canvasFinder = find.byType(CanvasView);
    await _drawStroke(tester, canvasFinder, 1, Offset.zero);
    await _tapAction(tester, 'Undo');
    expect(_actionEnabled(tester, 'Redo'), isTrue);
    await _drawStroke(tester, canvasFinder, 2, Offset.zero);
    expect(_actionEnabled(tester, 'Undo'), isTrue);

    await _tapAction(tester, 'Open');

    expect(_actionEnabled(tester, 'Undo'), isFalse);
    expect(_actionEnabled(tester, 'Redo'), isFalse);
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
  Future<Uint8List> readDocument(String path) async =>
      File(path).readAsBytesSync();

  @override
  Future<void> writeDocument(String path, Uint8List bytes) async {
    File(path).writeAsBytesSync(bytes);
  }
}

class _PendingReadDocumentFileService extends _TestDocumentFileService {
  _PendingReadDocumentFileService({
    required super.openPath,
    required this.readCompleter,
  });

  final Completer<Uint8List> readCompleter;

  @override
  Future<Uint8List> readDocument(String path) => readCompleter.future;
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
/// left one zoomed in 3 times.
class _Arrangement {
  _Arrangement(this.controller, this.rects, this.extent);

  final CanvasController controller;
  final List<Rect> rects;
  final double extent;
}

Future<_Arrangement> _arrangeCurrentLayout(WidgetTester tester) async {
  await _splitCanvas(tester);
  final left = tester
      .widget<CanvasView>(find.byType(CanvasView).at(0))
      .viewport;
  left.zoomAt(Offset.zero, const Size(100, 100), 3);
  await tester.pump();
  return _Arrangement(
    tester.widget<CanvasView>(find.byType(CanvasView).first).controller,
    [for (final rect in _canvasRects(tester)) rect],
    left.extent,
  );
}

/// The Canvas panes' rectangles in tree order.
List<Rect> _canvasRects(WidgetTester tester) => [
  tester.getRect(find.byType(CanvasView).at(0)),
  tester.getRect(find.byType(CanvasView).at(1)),
];

/// Expects the layout built by [_arrangeCurrentLayout] to be exactly as left.
void _expectLayoutUntouched(WidgetTester tester, _Arrangement layout) {
  expect(find.byType(ManualPane), findsNothing);
  expect(find.byType(CanvasView), findsNWidgets(2));
  expect(_canvasRects(tester), layout.rects);
  expect(
    tester
        .widget<CanvasView>(find.byType(CanvasView).at(0))
        .viewport
        .extent,
    layout.extent,
  );
}

/// A pane node of a version 2 workspace section
/// (docs/decisions/009-shared-workspaces.md PNT-A0015-07).
Map<String, Object?> _paneNode(String mode, Map<String, Object?> state) => {
  'pane': {'mode': mode, 'state': state},
};

/// A version 2 section whose root is a row split into [parts], each a share
/// and a node.
Map<String, Object?> _rowSection(
  List<(double, Map<String, Object?>)> parts, {
  int version = 2,
}) => {
  'version': version,
  'root': {
    'split': 'row',
    'parts': [
      for (final (share, node) in parts) {'share': share, 'node': node},
    ],
  },
};

Map<String, Object?> _canvasState(double extent) => {
  'canvas': {
    'center': {'x': 512.0, 'y': 512.0},
    'extent': extent,
    'rotation': 0.0,
  },
};

/// A usable stored workspace: a zoomed Canvas on the left, the Manual on the
/// right showing the Open document article.
final Map<String, Object?> _canvasAndManualSection = _rowSection([
  (0.5, _paneNode('canvas', _canvasState(512))),
  (
    0.5,
    _paneNode('manual', {
      'manual': {'help': 'openDocument'},
    }),
  ),
]);

/// Workspace values a file may hold that this version must not apply.
final Map<String, Object?> _unusableSections = {
  'version 1 rectangles': {
    'version': 1,
    'panes': [
      {
        'id': 0,
        'left': 0.0,
        'top': 0.0,
        'right': 1.0,
        'bottom': 1.0,
        'mode': 'canvas',
        'state': _canvasState(512),
      },
    ],
  },
  'zero share': _rowSection([
    (0.0, _paneNode('canvas', _canvasState(512))),
  ]),
  'unknown mode': _rowSection([
    (1.0, _paneNode('hologram', _canvasState(512))),
  ]),
  'newer version': _rowSection([
    (1.0, _paneNode('canvas', _canvasState(512))),
  ], version: 99),
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

/// An earlier-format file, as JSON.
Map<String, dynamic> _readJson(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

/// What a saved file holds, read the way Open reads it.
class _SavedFile {
  _SavedFile(this.bytes, DocumentFileContents contents)
    : strokeCount = contents.content.canvas.strokeCount,
      hasWorkspace = contents.sections.any(
        (s) => s.kind == DocumentContainer.workspaceKind,
      ),
      workspace = contents.workspaceSection;

  final Uint8List bytes;
  final int strokeCount;
  final bool hasWorkspace;
  final Object? workspace;

  bool get format2 => DocumentContainer.hasMagic(bytes);

  /// The file's sections, content included, in file order.
  List<DocumentSection> get sections =>
      DocumentContainer.parse(bytes).sections;
}

_SavedFile _readFile(String path) {
  final bytes = File(path).readAsBytesSync();
  final contents = DocumentFileContents.read(bytes, const AutomergeBackend());
  try {
    return _SavedFile(bytes, contents);
  } finally {
    contents.content.dispose();
  }
}

/// Whether the AppBar action labelled [label] is enabled.
bool _actionEnabled(WidgetTester tester, String label) =>
    tester
        .widget<PainterActionButton>(
          find.widgetWithText(PainterActionButton, label),
        )
        .onPressed !=
    null;

/// Presses [key] with Command held, and Shift too when [shift].
Future<void> _commandKey(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool shift = false,
}) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await tester.pump();
}
