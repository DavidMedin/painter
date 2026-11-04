// What: Widget tests drive Open/Save through the real PainterApp, draw through
//   both Canvas panes into one document, reopen it to replace content and
//   reset both viewports, and verify that file failures preserve the document.
// Why: T-005 requires document round-tripping and observable file-operation
//   failures (docs/project-brief.md). ADR 0002 specifies associated-path saves;
//   opening resets every Canvas viewport and failed operations leave the app
//   running without replacing the current document.
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
// default picker start directory or InAppDocumentFileService, a dirty-state
// prompt before open discards changes (a product decision still open in
// ADR 0002), and logging of the failures to the terminal (debugPrint in
// _showFileOperationError is not asserted). The brief's fatal-error scenario
// is not covered by this file.

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart'
    show AlertDialog, BuildContext, SelectableText, ValueKey;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:painter/canvas/canvas_view.dart';
import 'package:painter/document/document_file_service.dart';
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
  // Confirms the associated save path is reused, and opening the saved file
  // discards a later stroke and resets both Canvas viewport transforms.
  testWidgets(
    'both Canvas panes share saved content and reset their views on open',
    (tester) async {
      final path = '${temporaryDirectory.path}/round-trip.paint';
      final fileService = _TestDocumentFileService(
        openPath: path,
        savePath: path,
      );
      await tester.pumpWidget(PainterApp(fileService: fileService));
      await tester.tap(find.byKey(const ValueKey('split-menu-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Side by side'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pane-mode-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Canvas').last);
      await tester.pumpAndSettle();

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
      for (final viewport in viewports) {
        viewport
          ..panBy(const Offset(40, 25))
          ..zoomAt(const Offset(50, 50), canvasSize, 2)
          ..rotateAt(const Offset(50, 50), canvasSize, 0.25);
      }

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(controller.document.strokes, hasLength(3));
      expect(fileService.savePathRequests, 1);
      for (final viewport in viewports) {
        expect(viewport.pan, Offset.zero);
        expect(viewport.zoom, 1);
        expect(viewport.rotation, 0);
      }
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
    await tester.pumpWidget(PainterApp(fileService: fileService));

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
