import 'dart:io';

import 'package:flutter/widgets.dart';

import 'file_picker_dialog.dart';

/// Reads, writes, and locates Painter document files.
///
/// Picking is a separate concern from the actual file I/O so tests can
/// inject fixed paths without driving any picker UI.
abstract class DocumentFileService {
  Future<String?> chooseOpenPath(BuildContext context);

  Future<String?> chooseSavePath(BuildContext context, String suggestedName);

  Future<String> readDocument(String path) => File(path).readAsString();

  Future<void> writeDocument(String path, String contents) =>
      File(path).writeAsString(contents);
}

/// The production [DocumentFileService]: picks files through
/// [InAppFilePicker], an in-app dialog, rather than a native file picker.
class InAppDocumentFileService extends DocumentFileService {
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
