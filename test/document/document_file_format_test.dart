// What: Unit tests of the `.paint` file format: the format 2 container,
//   reading format 2 and earlier-format files into a content document,
//   encoding, preserved sections, and Flash's section replacement.
// Why: docs/decisions/008-document-file-format.md fixes the container
//   (PNT-A0014-01, PNT-A0014-02) and the earlier-format import
//   (PNT-A0014-08) and deletes unreadable strokes (PNT-A0014-10).
//   docs/spec/document-file.md requires old files to look as
//   before and to be saved as format 2 (DOCF-3, DOCF-4) and unreadable or
//   other-engine files to be refused (DOCF-6, DOCF-7). docs/spec/workspace.md
//   keeps the workspace section apart from the content: a damaged section
//   must not stop the content loading (WKSP-12), Save writes it back as read
//   (WKSP-4), and Flash changes only it (WKSP-2, WKSP-3).
// Covers: lib/document/document_file_format.dart, with
//   lib/document/content_document.dart for the content section.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:painter/canvas/pencil_splats.dart' show strokeEngineVersion;
import 'package:painter/document/content_document.dart';
import 'package:painter/document/document_file_format.dart';

import 'content_test_support.dart';

Map<String, Object?> _earlier({Object? workspace = _absent}) => {
  'format': 'painter-document',
  'version': 1,
  'strokes': [
    [
      {'x': 1.0, 'y': 2.0, 'weight': 0.5},
      {'x': 3.0, 'y': 4.0, 'weight': 0.7},
    ],
    [
      {'x': 9.0, 'y': 9.0, 'weight': 1.0},
    ],
  ],
  if (!identical(workspace, _absent)) 'workspace': workspace,
};

const Object _absent = Object();

Uint8List _earlierBytes({Object? workspace = _absent}) =>
    utf8.encode(jsonEncode(_earlier(workspace: workspace)));

/// Reads [bytes] and disposes the content after the test.
DocumentFileContents _read(Uint8List bytes) {
  final file = DocumentFileContents.read(bytes, testBackend);
  addTearDown(file.content.dispose);
  return file;
}

Uint8List _bytes(List<int> values) => Uint8List.fromList(values);

final _unknown = DocumentSection(7, _bytes([0, 255, 1, 2, 3]));

/// A format 2 file with one drawn stroke, the workspace [section] and an
/// unknown section after it.
Uint8List _format2File(Object section) {
  final replica = Replica.create()..draw(const Offset(4, 4));
  return DocumentFileContents.encode(replica.content, [
    DocumentSection(
      DocumentContainer.workspaceKind,
      utf8.encode(jsonEncode(section)),
    ),
    _unknown,
  ]);
}

void main() {
  group('container', () {
    test('round-trips sections in order, byte for byte', () {
      final container = DocumentContainer([
        DocumentSection(1, _bytes([1, 2, 3])),
        DocumentSection(2, _bytes([])),
        DocumentSection(0xfffffffe, _bytes(List.filled(300, 9))),
      ]);
      final bytes = container.encode();

      expect(bytes.sublist(0, 8), documentFileMagic);
      expect(bytes.sublist(8, 12), [2, 0, 0, 0]);
      expect(bytes.sublist(12, 20), [1, 0, 0, 0, 3, 0, 0, 0]);
      final parsed = DocumentContainer.parse(bytes);
      expect([for (final s in parsed.sections) s.kind], [1, 2, 0xfffffffe]);
      for (var i = 0; i < 3; i++) {
        expect(parsed.sections[i].bytes, container.sections[i].bytes);
      }
      expect(parsed.encode(), bytes);
    });

    test('refuses a truncated file or another version', () {
      final bytes = DocumentContainer([
        DocumentSection(1, _bytes([1, 2, 3, 4])),
      ]).encode();
      for (final length in [10, 14, bytes.length - 1]) {
        expect(
          () => DocumentContainer.parse(bytes.sublist(0, length)),
          throwsFormatException,
          reason: 'cut at $length',
        );
      }
      final newer = Uint8List.fromList(bytes)..[8] = 3;
      expect(
        () => DocumentContainer.parse(newer),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('version 3'),
          ),
        ),
      );
    });
  });

  group('format 2', () {
    test('read gives the content and keeps the other sections', () {
      final file = _read(_format2File({'version': 99}));
      expect(file.content.canvas.strokeCount, 1);
      expect(file.workspaceSection, {'version': 99});
      expect([for (final s in file.sections) s.kind], [2, 7]);
    });

    test('unknown sections survive read and encode byte-identically', () {
      final file = _read(_format2File({'a': 1}));
      final saved = DocumentContainer.parse(
        DocumentFileContents.encode(file.content, file.sections),
      );
      expect([for (final s in saved.sections) s.kind], [1, 2, 7]);
      expect(saved.sections[2].bytes, _unknown.bytes);
      expect(jsonDecode(utf8.decode(saved.sections[1].bytes)), {'a': 1});
    });

    test('a workspace section that is not JSON is kept but not applied', () {
      final replica = Replica.create();
      final damaged = DocumentSection(
        DocumentContainer.workspaceKind,
        _bytes([0xff, 0xfe, 0x00]),
      );
      final file = _read(
        DocumentFileContents.encode(replica.content, [damaged]),
      );
      expect(file.workspaceSection, isNull);
      expect(file.sections.single.bytes, damaged.bytes);
    });

    test('refuses a file without a content section or with garbage in it',
        () {
      expect(
        () => _read(const DocumentContainer([]).encode()),
        throwsFormatException,
      );
      expect(
        () => _read(
          DocumentContainer([
            DocumentSection(1, _bytes([1, 2, 3])),
          ]).encode(),
        ),
        throwsFormatException,
      );
    });

    test('an unreadable stroke never makes a file unopenable', () {
      final replica = Replica.create()..draw(const Offset(4, 4));
      replica.content.crdt
        ..putMap(['strokes', 'x:1'])
        ..put(['strokes', 'x:1', 'z'], ContentDocument.maxZ + 1)
        ..commit();
      final file = _read(
        DocumentFileContents.encode(replica.content, const []),
      );
      expect(file.content.canvas.strokeCount, 1);
      final saved = _read(DocumentFileContents.encode(file.content, const []));
      expect(saved.content.crdt.keys(['strokes']), hasLength(1));
    });

    test('refuses content from another engine version', () {
      final crdt = testBackend.create()
        ..put(['format'], ContentDocument.formatIdentifier)
        ..put(['version'], ContentDocument.formatVersion)
        ..put(['engine'], strokeEngineVersion + 1)
        ..putMap(['strokes'])
        ..commit();
      addTearDown(crdt.dispose);
      final bytes = DocumentContainer([
        DocumentSection(1, crdt.save()),
      ]).encode();
      expect(() => _read(bytes), throwsA(isA<StrokeEngineMismatch>()));
    });
  });

  group('earlier format', () {
    test('imports strokes with seed = z = i + 1 and its workspace value', () {
      final file = _read(_earlierBytes(workspace: {'version': 1}));
      final strokes = file.content.canvas.strokes;
      expect([for (final s in strokes) (s.seed, s.z)], [(1, 1), (2, 2)]);
      expect(strokes.first.points.first.position, const Offset(1, 2));
      expect(file.workspaceSection, {'version': 1});
      expect(file.sections.single.kind, DocumentContainer.workspaceKind);
    });

    test('is saved as format 2 that reads back the same strokes', () {
      final file = _read(_earlierBytes());
      expect(file.sections, isEmpty);
      final saved = DocumentFileContents.encode(file.content, file.sections);
      expect(DocumentContainer.hasMagic(saved), isTrue);

      final reread = _read(saved);
      final before = file.content.canvas.strokes;
      final after = reread.content.canvas.strokes;
      expect(after, hasLength(2));
      for (var i = 0; i < 2; i++) {
        expect(
          [after[i].id, after[i].seed, after[i].z],
          [before[i].id, before[i].seed, before[i].z],
        );
      }
    });

    test('a workspace value of any shape never stops the strokes loading', () {
      for (final section in <Object?>[
        'text',
        7,
        [],
        {'panes': 'x'},
      ]) {
        final file = _read(_earlierBytes(workspace: section));
        expect(file.content.canvas.strokeCount, 2);
        expect(file.workspaceSection, section);
      }
    });

    test('invalid strokes or text fail the whole read', () {
      final broken = _earlier()..['strokes'] = 'not a list';
      expect(
        () => _read(utf8.encode(jsonEncode(broken))),
        throwsFormatException,
      );
      expect(() => _read(utf8.encode('not a document')), throwsFormatException);
      expect(() => _read(_bytes([0xff, 0xfe])), throwsFormatException);
    });
  });

  group('withWorkspaceSection (Flash)', () {
    test('replaces only the workspace section of a format 2 file', () {
      final original = _format2File({'old': true});
      final before = DocumentContainer.parse(original).sections;

      final flashed = DocumentContainer.parse(
        DocumentFileContents.withWorkspaceSection(original, {'new': true}),
      ).sections;

      expect([for (final s in flashed) s.kind], [1, 2, 7]);
      expect(flashed[0].bytes, before[0].bytes);
      expect(flashed[2].bytes, before[2].bytes);
      expect(jsonDecode(utf8.decode(flashed[1].bytes)), {'new': true});
    });

    test('adds a section to a format 2 file that had none', () {
      final replica = Replica.create();
      final original = DocumentFileContents.encode(replica.content, const []);
      final flashed = DocumentContainer.parse(
        DocumentFileContents.withWorkspaceSection(original, {'new': true}),
      ).sections;
      expect([for (final s in flashed) s.kind], [1, 2]);
    });

    test('keeps an earlier-format file in that format', () {
      final changed = jsonDecode(
        utf8.decode(
          DocumentFileContents.withWorkspaceSection(
            _earlierBytes(workspace: {'old': true}),
            {'new': true},
          ),
        ),
      );
      expect(changed['workspace'], {'new': true});
      expect(changed['strokes'], _earlier()['strokes']);
      expect(changed['version'], 1);
    });

    test('refuses bytes that are neither format', () {
      expect(
        () => DocumentFileContents.withWorkspaceSection(
          utf8.encode('[1]'),
          {},
        ),
        throwsFormatException,
      );
    });

    test('withWorkspace replaces in place or appends', () {
      final workspace = DocumentSection(2, utf8.encode('{}'));
      final replaced = DocumentFileContents.withWorkspace([
        workspace,
        _unknown,
      ], 'x');
      expect([for (final s in replaced) s.kind], [2, 7]);
      expect(utf8.decode(replaced.first.bytes), '"x"');
      final appended = DocumentFileContents.withWorkspace([_unknown], 'y');
      expect([for (final s in appended) s.kind], [7, 2]);
    });
  });
}
