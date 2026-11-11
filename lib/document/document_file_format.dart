// What: DocumentFileContents, the parsed form of a `.paint` file: the canvas
//   document plus the raw workspace section, with encode and an in-place
//   section replacement used by Flash.
// Why: docs/spec/workspace.md keeps a stored workspace in a section of the
//   file that is separate from the document's content (WKSP-1), preserved by
//   every Save (WKSP-4) and written only by Flash (WKSP-3). The document model
//   (../canvas/canvas_controller.dart, CanvasDocument) knows only strokes, so
//   this file owns the top-level JSON object that holds both.
// Coupled to: ../canvas/canvas_controller.dart (CanvasDocument.toJson and
//   fromJson, which ignore the `workspace` key), ../workspace/workspace.dart
//   (reads and writes the section's contents), and ../main.dart (open, save,
//   and Flash flows). Decision: docs/decisions/006-workspace-in-file.md.
//
// The file is one JSON object: the `painter-document` fields (`format`,
// `version`, `strokes`) plus an optional `workspace` key. The section is kept
// as decoded JSON, not parsed, so a section this version cannot read (a newer
// version's, or a damaged one) is written back unchanged by Save instead of
// being lost.

import 'dart:convert';

import '../canvas/canvas_controller.dart';

/// A parsed document file: strokes plus the workspace section as stored.
class DocumentFileContents {
  const DocumentFileContents(this.document, this.workspaceSection);

  final CanvasDocument document;

  /// The file's `workspace` value as decoded JSON, or null when the file has
  /// none. It may be unusable; only the workspace model judges that.
  final Object? workspaceSection;

  /// Parses [text]. Throws [FormatException] for anything
  /// [CanvasDocument.fromJson] rejects; the workspace section is never
  /// validated here, so a damaged section cannot stop the content loading
  /// (WKSP-12).
  static DocumentFileContents parse(String text) {
    final json = jsonDecode(text);
    final document = CanvasDocument.fromJson(json);
    final section = (json as Map<String, dynamic>)['workspace'];
    return DocumentFileContents(document, section);
  }

  /// The file text for [document] with its [workspaceSection] preserved
  /// (WKSP-4).
  String encode() {
    final json = document.toJson();
    if (workspaceSection != null) json['workspace'] = workspaceSection;
    return jsonEncode(json);
  }

  /// Returns [text], an existing file's contents, with its `workspace` value
  /// set to [section] and everything else unchanged; this is what Flash
  /// writes, so it never saves strokes the user has not saved. Throws
  /// [FormatException] if [text] is not a JSON object.
  static String withWorkspaceSection(String text, Object? section) {
    final json = jsonDecode(text);
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Painter document must be a JSON object.');
    }
    json['workspace'] = section;
    return jsonEncode(json);
  }
}
