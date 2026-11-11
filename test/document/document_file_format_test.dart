// What: Unit tests for DocumentFileContents: parsing with and without a
//   workspace section, encoding, and Flash's section replacement.
// Why: The file holds strokes and a workspace section that must stay separate
//   (WKSP-1): a damaged section must not stop strokes loading (WKSP-12), Save
//   must write the section back as read (WKSP-4), and Flash must change only
//   the section (WKSP-2, WKSP-3).
// Covers: lib/document/document_file_format.dart.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:painter/canvas/canvas_controller.dart';
import 'package:painter/document/document_file_format.dart';

Map<String, Object?> _file({Object? workspace = _absent}) => {
  'format': 'painter-document',
  'version': 1,
  'strokes': [
    [
      {'x': 1.0, 'y': 2.0, 'weight': 0.5},
      {'x': 3.0, 'y': 4.0, 'weight': 0.7},
    ],
  ],
  if (!identical(workspace, _absent)) 'workspace': workspace,
};

const Object _absent = Object();

void main() {
  test('parse reads strokes and returns the section untouched', () {
    final section = {
      'version': 99,
      'anything': [1, 2, 3],
    };
    final contents = DocumentFileContents.parse(
      jsonEncode(_file(workspace: section)),
    );

    expect(contents.document.strokeCount, 1);
    expect(contents.workspaceSection, section);
  });

  test('a file without a section has none', () {
    final contents = DocumentFileContents.parse(jsonEncode(_file()));
    expect(contents.workspaceSection, isNull);
    expect(jsonDecode(contents.encode()), isNot(contains('workspace')));
  });

  test('a section of any shape never stops the strokes loading', () {
    for (final section in <Object?>[
      'text',
      7,
      [],
      {'panes': 'x'},
    ]) {
      final contents = DocumentFileContents.parse(
        jsonEncode(_file(workspace: section)),
      );
      expect(contents.document.strokeCount, 1);
      // Save writes the damaged section back as it was read.
      expect(jsonDecode(contents.encode())['workspace'], section);
    }
  });

  test('invalid strokes still fail the whole parse', () {
    final broken = _file()..['strokes'] = 'not a list';
    expect(
      () => DocumentFileContents.parse(jsonEncode(broken)),
      throwsFormatException,
    );
  });

  test('encode keeps the strokes of the document it was given', () {
    final document = CanvasDocument.fromJson(_file());
    final encoded = jsonDecode(
      DocumentFileContents(document, {'version': 1}).encode(),
    );
    expect(encoded['strokes'], _file()['strokes']);
    expect(encoded['workspace'], {'version': 1});
  });

  group('withWorkspaceSection', () {
    test('replaces only the section', () {
      final original = jsonEncode(_file(workspace: {'old': true}));
      final changed = jsonDecode(
        DocumentFileContents.withWorkspaceSection(original, {'new': true}),
      );
      expect(changed['workspace'], {'new': true});
      expect(changed['strokes'], _file()['strokes']);
      expect(changed['format'], 'painter-document');
      expect(changed['version'], 1);
    });

    test('adds a section to a file that had none', () {
      final changed = jsonDecode(
        DocumentFileContents.withWorkspaceSection(jsonEncode(_file()), {
          'new': true,
        }),
      );
      expect(changed['workspace'], {'new': true});
    });

    test('refuses text that is not a JSON object', () {
      expect(
        () => DocumentFileContents.withWorkspaceSection('[1]', {}),
        throwsFormatException,
      );
    });
  });

  test('the section is independent of CanvasDocument content', () {
    final contents = DocumentFileContents.parse(
      jsonEncode(_file(workspace: {'version': 1})),
    );
    expect(contents.document.toJson(), isNot(contains('workspace')));
    expect(
      contents.document.strokeAt(0).points.first.position,
      const Offset(1, 2),
    );
  });
}
