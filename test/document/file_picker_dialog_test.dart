// What: Widget tests of InAppFilePicker on its own: listing only directories
//   and `.paint` files, open mode (tap a file, navigate into a directory),
//   save mode (typed name gets `.paint` appended), and cancel returning null.
// Why: docs/design/document/file-format-and-flow.md replaced the native file
//   dialogs with this in-house picker so the Open/Save flow can be driven
//   headlessly. This file tests the part that replaces the native file
//   dialog, which could not be driven headlessly before. These tests are what
//   make that claim true for the picker's own UI.
// Covers: lib/document/file_picker_dialog.dart (InAppFilePicker,
//   FilePickerMode, InAppFilePicker.show). The app-level flow that uses the
//   picker through InAppDocumentFileService is not covered here; see
//   document_file_workflow_test.dart (which bypasses the picker).
//
// Each test runs against a throwaway directory tree (see setUp) so the
// picker's real dart:io directory listing is exercised, not a mock. Not
// verified: the picker's default start directory in the real service, going
// up a directory, or behavior on unreadable directories.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:painter/document/file_picker_dialog.dart';

void main() {
  late Directory root;

  // Tree: root/{sub/nested.paint, existing.paint, ignored.txt}. The .txt file
  // is there to exercise the extension filter; the subdirectory to exercise
  // navigation.
  setUp(() {
    root = Directory.systemTemp.createTempSync('painter-picker-test-');
    Directory('${root.path}/sub').createSync();
    File('${root.path}/sub/nested.paint').writeAsStringSync('{}');
    File('${root.path}/existing.paint').writeAsStringSync('{}');
    File('${root.path}/ignored.txt').writeAsStringSync('not a document');
  });

  tearDown(() {
    root.deleteSync(recursive: true);
  });

  /// Opens the picker and returns its (not-yet-awaited) result future, so
  /// the test can interact with the dialog before awaiting the outcome.
  /// InAppFilePicker.show returns when the dialog closes, so awaiting it
  /// before tapping would deadlock the test.
  Future<Future<String?>> openPicker(
    WidgetTester tester, {
    required FilePickerMode mode,
    String suggestedName = '',
  }) async {
    late Future<String?> pending;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () {
                pending = InAppFilePicker.show(
                  context,
                  mode: mode,
                  startDirectory: root,
                  suggestedName: suggestedName,
                );
              },
              child: const Text('open picker'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open picker'));
    await tester.pumpAndSettle();
    return pending;
  }

  testWidgets('lists directories and .paint files, hiding other extensions', (
    tester,
  ) async {
    await openPicker(tester, mode: FilePickerMode.open);

    expect(find.text('sub'), findsOneWidget);
    expect(find.text('existing.paint'), findsOneWidget);
    expect(find.text('ignored.txt'), findsNothing);
  });

  testWidgets('open mode: tapping a file confirms and returns its path', (
    tester,
  ) async {
    final pending = await openPicker(tester, mode: FilePickerMode.open);

    await tester.tap(find.text('existing.paint'));
    await tester.pumpAndSettle();

    expect(await pending, '${root.path}/existing.paint');
  });

  testWidgets('open mode: navigating into a directory lists its contents', (
    tester,
  ) async {
    final pending = await openPicker(tester, mode: FilePickerMode.open);

    await tester.tap(find.text('sub'));
    await tester.pumpAndSettle();
    expect(find.text('nested.paint'), findsOneWidget);
    expect(find.text('existing.paint'), findsNothing);

    await tester.tap(find.text('nested.paint'));
    await tester.pumpAndSettle();

    expect(await pending, '${root.path}/sub/nested.paint');
  });

  testWidgets('save mode: typing a name and confirming appends .paint', (
    tester,
  ) async {
    final pending = await openPicker(
      tester,
      mode: FilePickerMode.save,
      suggestedName: 'Untitled.paint',
    );

    expect(find.widgetWithText(TextField, 'Untitled.paint'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'my painting');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(await pending, '${root.path}/my painting.paint');
  });

  testWidgets('cancel returns null without a result', (tester) async {
    final pending = await openPicker(tester, mode: FilePickerMode.open);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(await pending, isNull);
  });
}
