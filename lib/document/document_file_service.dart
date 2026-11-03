// What: The seam between the app and the file system for opening and saving
// documents: the abstract [DocumentFileService] (choose a path, read text,
// write text) and its production implementation [InAppDocumentFileService],
// which picks paths with the in-app [InAppFilePicker]. Also holds the
// overview of the whole open/save system (this file plus
// file_picker_dialog.dart).
//
// Why: PainterApp (../main.dart) needs "ask the user for a path" and "read /
// write a file" without hard-wiring either to a dialog. Putting them behind
// one small interface lets tests substitute fixed paths and skip the picker
// UI (see _TestDocumentFileService in
// test/document/document_file_workflow_test.dart), and keeps all dart:io
// file access for documents in one place. This file knows nothing about
// strokes or JSON: it moves strings; ../main.dart does the encoding.
//
// ---------------------------------------------------------------------------
// Open/save flow overview
//
// What it is: the pieces that let the user open a `.paint` document and
// save the current one: PainterApp._openDocument / PainterApp._saveDocument
// in ../main.dart (orchestration, error handling), DocumentFileService
// (this file: path choice + string I/O), and InAppFilePicker in
// file_picker_dialog.dart (the dialog that actually shows the files).
//
// Why an in-house picker instead of a native dialog or plugin: decided in
// docs/decisions/0002-saved-document-format-and-flow.md. The picker is built
// from ordinary Flutter widgets so `flutter test` can drive the entire
// open/save flow headlessly (navigate, type a name, confirm, cancel) with no
// native dialog and no file-picker plugin dependency (docs/status.md T-005
// notes no `file_selector` or other plugin was added). An earlier attempt with
// native dialogs (`file_selector`) could not be verified in a local macOS VM
// guest; the ADR records that story and keeps it on the
// `vm-native-dialog-approach` branch. The cost, also from the ADR, is that the
// picker does not inherit native behavior (recents, search, iCloud locations,
// keyboard shortcuts).
//
// Why picking is separate from I/O: the two methods that need a
// BuildContext (chooseOpenPath, chooseSavePath) are the only ones that touch
// UI, so a test double can override them to return fixed paths and the
// picker dialog is not needed to test the open/save logic (the picker is
// tested separately in test/document/file_picker_dialog_test.dart).
// readDocument / writeDocument have default dart:io implementations; the
// existing test double also overrides those with synchronous file calls.
//
// How it works:
//   1. PainterApp calls chooseOpenPath or chooseSavePath. The production
//      service calls InAppFilePicker.show, which shows a dialog and resolves
//      to an absolute path, or null if the user cancels.
//   2. PainterApp calls readDocument (open) or writeDocument (save), then
//      converts between the text and CanvasDocument itself
//      (CanvasDocument.fromJson / toJson in ../canvas/canvas_controller.dart).
//   3. Errors are not caught here. File-system failures from
//      readDocument / writeDocument propagate as exceptions to PainterApp,
//      whose catch blocks show the error dialog (ADR 0002, brief "Errors").
//      Malformed documents are rejected later, by CanvasDocument.fromJson.
// The save picker returns a path that always ends in `.paint`; the open
// picker lists only directories and `.paint` files.
// ---------------------------------------------------------------------------

import 'dart:io';

import 'package:flutter/widgets.dart';

import 'file_picker_dialog.dart';

/// Locates, reads, and writes Painter document files on behalf of
/// PainterApp (../main.dart). See the open/save flow overview at the top of
/// this file.
///
/// Picking is a separate concern from the actual file I/O so tests can
/// inject fixed paths without driving any picker UI. [InAppDocumentFileService]
/// is the production subclass.
abstract class DocumentFileService {
  /// Asks the user which existing document to open. Returns the absolute
  /// path, or `null` if the user cancelled. Called by
  /// PainterApp._openDocument.
  Future<String?> chooseOpenPath(BuildContext context);

  /// Asks the user where to save. [suggestedName] pre-fills the file name
  /// (PainterApp._saveDocument passes 'Untitled.paint'). Returns the absolute
  /// path, or `null` if the user cancelled. Called by
  /// PainterApp._saveDocument only when no path is associated with the
  /// document yet.
  Future<String?> chooseSavePath(BuildContext context, String suggestedName);

  /// Returns the raw text of the file at [path]. Throws [FileSystemException]
  /// if it cannot be read; interpreting the text is the caller's job.
  Future<String> readDocument(String path) => File(path).readAsString();

  /// Writes [contents] to [path], replacing any existing file. Throws
  /// [FileSystemException] on failure.
  Future<void> writeDocument(String path, String contents) =>
      File(path).writeAsString(contents);
}

/// The production [DocumentFileService]: picks files through
/// [InAppFilePicker], an in-app dialog, rather than a native file picker.
class InAppDocumentFileService extends DocumentFileService {
  /// Where the picker opens: the user's home directory (`$HOME`), or the
  /// process's current directory if `$HOME` is unset. ADR 0002 specifies
  /// starting from the home directory.
  Directory _startDirectory() {
    final home = Platform.environment['HOME'];
    return home != null ? Directory(home) : Directory.current;
  }

  @override
  Future<String?> chooseOpenPath(BuildContext context) {
    return InAppFilePicker.show(
      context,
      mode: FilePickerMode.open,
      startDirectory: _startDirectory(),
    );
  }

  @override
  Future<String?> chooseSavePath(BuildContext context, String suggestedName) {
    return InAppFilePicker.show(
      context,
      mode: FilePickerMode.save,
      startDirectory: _startDirectory(),
      suggestedName: suggestedName,
    );
  }
}
