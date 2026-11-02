import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show BuildContext, SelectableText;
import 'package:flutter_test/flutter_test.dart';
import 'package:painter/canvas/canvas_view.dart';
import 'package:painter/document/document_file_service.dart';
import 'package:painter/main.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() {
    temporaryDirectory = Directory.systemTemp.createTempSync(
      'painter-document-test-',
    );
  });

  tearDown(() {
    temporaryDirectory.deleteSync(recursive: true);
  });

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
          .map(
            (stroke) => stroke.points.map((point) => point.weight).toList(),
          )
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
    expect(
      find.textContaining('Could not open the document'),
      findsOneWidget,
    );
    expect(controller.document.strokes, hasLength(1));
    expect(
      controller.document.strokes.single.points.map(
        (point) => point.position,
      ),
      orderedEquals(originalPoints),
    );

    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      contains('FormatException'),
    );

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('File operation failed'), findsOneWidget);
    expect(
      find.textContaining('Could not save the document'),
      findsOneWidget,
    );
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

/// A fake service that returns fixed paths without driving any picker UI,
/// so these tests exercise the save/open/error-handling logic in isolation
/// from the in-app picker dialog (covered separately by
/// `file_picker_dialog_test.dart`).
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
