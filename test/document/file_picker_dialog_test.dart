import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:painter/document/file_picker_dialog.dart';

void main() {
  late Directory root;

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
