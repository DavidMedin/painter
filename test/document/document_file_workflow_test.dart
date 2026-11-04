// What: Widget tests of the Open/Save lifecycle through the real PainterApp:
//   first save, repeated save to the same path, open replacing the current
//   document and resetting the viewport (stroke points and weights compared),
//   and open/save failures showing the expandable-details error dialog while
//   the current document is kept.
// Why: Verifies the T-005 requirements in docs/project-brief.md ("Document and
//   File Lifecycle", "Errors") and the decisions of ADR 0002: save then reopen
//   preserves content, Save writes to the associated path after the first
//   successful save, opening resets the viewport, and a failed file operation
//   neither replaces the document nor terminates the app.
// Covers: lib/main.dart (PainterApp, _openDocument, _saveDocument,
//   _showFileOperationError), lib/document/document_file_service.dart
//   (DocumentFileService, subclassed here), CanvasController /
//   CanvasDocument (lib/canvas/canvas_controller.dart) round-tripping through
//   toJson / fromJson, and CanvasView as the drawing surface.
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
// Not verified here (docs/status.md T-005): the Open/Save UI in the running
// macOS Release build (a live visual confirmation is still outstanding), the
// default picker start directory or InAppDocumentFileService, and a dirty-state
// prompt before open discards changes (a product decision still open in
// ADR 0002). The failure test below checks structured file-operation records;
// the brief's fatal-error scenario is not covered by this file.

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart'
    show AlertDialog, BuildContext, SelectableText;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:painter/canvas/canvas_view.dart';
import 'package:painter/document/document_file_service.dart';
import 'package:painter/logging/painter_log.dart';
import 'package:painter/main.dart';

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

  // Pins ADR 0002's "after the first successful save, Save writes to that
  // associated path": two Save taps must ask for a path once
  // (savePathRequests == 1 at the end). The later stroke, pan and zoom before
  // Open are discarded by Open: the document returns to the two saved strokes
  // and the viewport returns to pan zero / zoom 1 (replaceDocument resets it).
  testWidgets(
    'save and reopen preserves strokes and replaces current content',
    (tester) async {
      final path = '${temporaryDirectory.path}/round-trip.paint';
      final fileService = _TestDocumentFileService(
        openPath: path,
        savePath: path,
      );
      await tester.pumpWidget(PainterApp(fileService: fileService));

      final canvasFinder = find.byType(CanvasView);
      final controller = tester.widget<CanvasView>(canvasFinder).controller;
      await _drawStroke(tester, canvasFinder, 1, const Offset(-24, 12));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(File(path).existsSync(), isTrue);
      expect(controller.document.strokes, hasLength(1));

      await _drawStroke(tester, canvasFinder, 2, const Offset(36, -18));
      expect(controller.document.strokes, hasLength(2));
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
      await _drawStroke(tester, canvasFinder, 3, const Offset(90, 30));
      controller.panBy(const Offset(40, 25));
      controller.zoomAt(const Offset(50, 50), tester.getSize(canvasFinder), 2);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(controller.document.strokes, hasLength(2));
      expect(fileService.savePathRequests, 1);
      expect(controller.pan, Offset.zero);
      expect(controller.zoom, 1);
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
    expect(find.text('Error details'), findsOneWidget);
    expect(
      find.textContaining('Expand the error details to inspect the operation'),
      findsOneWidget,
    );
    final helpDialog = find.ancestor(
      of: find.text('Error details'),
      matching: find.byType(AlertDialog),
    );
    await tester.tap(
      find.descendant(of: helpDialog, matching: find.text('Close')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Close'));
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
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(PainterApp), findsOneWidget);
    expect(controller.document.strokes, hasLength(1));
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
