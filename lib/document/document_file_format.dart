// What: The `.paint` file format: DocumentContainer (format 2: magic,
//   version and typed sections), DocumentSection, and DocumentFileContents,
//   a read file (content document plus the sections Save writes back), with
//   reading of the earlier JSON format and Flash's section replacement.
// Why: docs/decisions/008-document-file-format.md stores the content's
//   Automerge document with its change history (DOCF-1) and keeps the
//   workspace section separate from the content (WKSP-1), preserved by every
//   Save (WKSP-4) and written only by Flash (WKSP-3). Files from before
//   format 2 still open (DOCF-3) and are saved as format 2 (DOCF-4).
// Coupled to: content_document.dart (section kind 1 and earlier-format
//   import), ../crdt/crdt_document.dart (CrdtBackend),
//   ../workspace/workspace.dart (judges the workspace section's contents),
//   and ../main.dart (Open, Save and Flash).
//
// Format 2 (PNT-A0014-01, PNT-A0014-02): the 8 bytes [documentFileMagic], a
// little-endian u32 container version 2, then sections to the end of the
// file, each a little-endian u32 kind, a little-endian u32 length and that
// many bytes. Kind 1 is the content document's save; kind 2 is the workspace
// section as UTF-8 JSON; other kinds are kept byte for byte. A file without
// the magic is the earlier format: one JSON object holding the strokes and
// an optional `workspace` value (PNT-A0014-08).
//
// The workspace section is handed to the workspace as decoded JSON and never
// judged here, so a section this version cannot use still reaches the file
// unchanged on Save; it is kept as its bytes for that.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show immutable;

import '../crdt/crdt_document.dart';
import 'content_document.dart';

/// The first 8 bytes of a format 2 file: `\x89PNTR\r\n\x1a`.
const List<int> documentFileMagic = [
  0x89,
  0x50,
  0x4E,
  0x54,
  0x52,
  0x0D,
  0x0A,
  0x1A,
];

/// One section of a format 2 file, its [bytes] as stored.
@immutable
class DocumentSection {
  const DocumentSection(this.kind, this.bytes);

  final int kind;
  final Uint8List bytes;
}

/// The container layout of a format 2 file; see the header of this file.
class DocumentContainer {
  const DocumentContainer(this.sections);

  /// The container version this build reads and writes.
  static const int version = 2;

  /// Section kind holding the content document's save.
  static const int contentKind = 1;

  /// Section kind holding the workspace section as UTF-8 JSON.
  static const int workspaceKind = 2;

  static const int _headerBytes = 12;

  /// Every section, in file order.
  final List<DocumentSection> sections;

  /// Whether [bytes] start with [documentFileMagic].
  static bool hasMagic(Uint8List bytes) {
    if (bytes.length < documentFileMagic.length) return false;
    for (var i = 0; i < documentFileMagic.length; i++) {
      if (bytes[i] != documentFileMagic[i]) return false;
    }
    return true;
  }

  /// Reads a format 2 file. Throws [FormatException] when [bytes] lack the
  /// magic, have another container version, or end inside a section.
  static DocumentContainer parse(Uint8List bytes) {
    if (!hasMagic(bytes)) {
      throw const FormatException('Not a Painter document file.');
    }
    if (bytes.length < _headerBytes) {
      throw const FormatException('The document file ends before its version.');
    }
    final data = ByteData.sublistView(bytes);
    final fileVersion = data.getUint32(8, Endian.little);
    if (fileVersion != version) {
      throw FormatException(
        'Unsupported document file version $fileVersion; '
        'this Painter reads version $version.',
      );
    }
    final sections = <DocumentSection>[];
    var offset = _headerBytes;
    while (offset < bytes.length) {
      if (bytes.length - offset < 8) {
        throw FormatException(
          'The document file ends inside the header of section '
          '${sections.length + 1}.',
        );
      }
      final kind = data.getUint32(offset, Endian.little);
      final length = data.getUint32(offset + 4, Endian.little);
      offset += 8;
      if (bytes.length - offset < length) {
        throw FormatException(
          'Section ${sections.length + 1} (kind $kind) needs $length bytes, '
          'but the file has ${bytes.length - offset} left.',
        );
      }
      sections.add(
        DocumentSection(
          kind,
          Uint8List.fromList(bytes.sublist(offset, offset + length)),
        ),
      );
      offset += length;
    }
    return DocumentContainer(sections);
  }

  /// The file bytes: magic, version, then [sections] in order.
  Uint8List encode() {
    final builder = BytesBuilder(copy: false)
      ..add(documentFileMagic)
      ..add(_u32(version));
    for (final section in sections) {
      builder
        ..add(_u32(section.kind))
        ..add(_u32(section.bytes.length))
        ..add(section.bytes);
    }
    return builder.takeBytes();
  }

  static Uint8List _u32(int value) =>
      (ByteData(4)..setUint32(0, value, Endian.little)).buffer.asUint8List();
}

/// A read document file: its content and the other sections, which Save
/// writes back unchanged (WKSP-4, PNT-A0014-02).
class DocumentFileContents {
  const DocumentFileContents(this.content, this.sections);

  /// The content; the caller owns it and must dispose it.
  final ContentDocument content;

  /// Every section except the content, in file order: the workspace section
  /// (kind 2) if the file had one, and sections of unknown kinds.
  final List<DocumentSection> sections;

  /// The workspace section as decoded JSON, or null when there is none or
  /// its bytes are not UTF-8 JSON. It may be unusable; only the workspace
  /// model judges that.
  Object? get workspaceSection => workspaceJson(sections);

  /// Whether the file has a workspace section at all, readable or not; an
  /// unreadable one makes [workspaceSection] null as no section does.
  bool get hasWorkspaceSection => sections.any(
    (section) => section.kind == DocumentContainer.workspaceKind,
  );

  /// Reads [bytes]: a format 2 file, or else an earlier-format JSON file,
  /// imported into a new content document from [backend] (PNT-A0014-08)
  /// whose workspace value becomes a kind 2 section.
  ///
  /// Throws [FormatException] for a file that cannot be read in full and
  /// [StrokeEngineMismatch] for another engine version (DOCF-6, DOCF-7). The
  /// workspace section is never validated here, so a damaged one cannot stop
  /// the content loading (WKSP-12).
  static DocumentFileContents read(Uint8List bytes, CrdtBackend backend) {
    if (!DocumentContainer.hasMagic(bytes)) {
      return _readEarlier(bytes, backend);
    }
    final container = DocumentContainer.parse(bytes);
    final contentSections = [
      for (final section in container.sections)
        if (section.kind == DocumentContainer.contentKind) section,
    ];
    if (contentSections.length != 1) {
      throw FormatException(
        'A document file needs one content section, this one has '
        '${contentSections.length}.',
      );
    }
    final content = ContentDocument.load(backend, contentSections.single.bytes);
    return DocumentFileContents(content, [
      for (final section in container.sections)
        if (section.kind != DocumentContainer.contentKind) section,
    ]);
  }

  static DocumentFileContents _readEarlier(
    Uint8List bytes,
    CrdtBackend backend,
  ) {
    final json = jsonDecode(utf8.decode(bytes));
    final content = ContentDocument.importEarlier(backend, json);
    final workspace = (json as Map<String, dynamic>)['workspace'];
    return DocumentFileContents(content, [?_workspaceSection(workspace)]);
  }

  /// The format 2 bytes for [content] followed by [sections] (DOCF-4).
  static Uint8List encode(
    ContentDocument content,
    List<DocumentSection> sections,
  ) => DocumentContainer([
    DocumentSection(DocumentContainer.contentKind, content.save()),
    ...sections,
  ]).encode();

  /// The kind 2 section of [sections] decoded as JSON; see
  /// [workspaceSection].
  static Object? workspaceJson(List<DocumentSection> sections) {
    for (final section in sections) {
      if (section.kind != DocumentContainer.workspaceKind) continue;
      try {
        return jsonDecode(utf8.decode(section.bytes));
      } on FormatException {
        // Not a failure here: an undecodable section is Unusable, like one
        // that decodes to something unreadable. Callers that apply a present
        // section report it as unusable (docs/spec/logging.md LOG-13).
        return null;
      }
    }
    return null;
  }

  /// [sections] with the workspace section set to [workspace]: replaced in
  /// place, or appended when there was none. A null [workspace] removes it.
  static List<DocumentSection> withWorkspace(
    List<DocumentSection> sections,
    Object? workspace,
  ) {
    final replacement = _workspaceSection(workspace);
    final result = <DocumentSection>[];
    var replaced = false;
    for (final section in sections) {
      if (section.kind == DocumentContainer.workspaceKind) {
        if (!replaced && replacement != null) result.add(replacement);
        replaced = true;
      } else {
        result.add(section);
      }
    }
    if (!replaced && replacement != null) result.add(replacement);
    return result;
  }

  /// Returns [bytes], an existing file, with its workspace section set to
  /// [workspace] and everything else as on disk; this is what Flash writes,
  /// so strokes the user has not saved never reach the file. A format 2 file
  /// keeps its content and other sections byte for byte; an earlier-format
  /// file stays in that format with its `workspace` value replaced. Throws
  /// [FormatException] when [bytes] are neither.
  static Uint8List withWorkspaceSection(Uint8List bytes, Object? workspace) {
    if (DocumentContainer.hasMagic(bytes)) {
      final container = DocumentContainer.parse(bytes);
      return DocumentContainer(withWorkspace(container.sections, workspace))
          .encode();
    }
    final json = jsonDecode(utf8.decode(bytes));
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Painter document must be a JSON object.');
    }
    json['workspace'] = workspace;
    return utf8.encode(jsonEncode(json));
  }

  static DocumentSection? _workspaceSection(Object? workspace) =>
      workspace == null
      ? null
      : DocumentSection(
          DocumentContainer.workspaceKind,
          utf8.encode(jsonEncode(workspace)),
        );
}
