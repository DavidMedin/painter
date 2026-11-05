// What: [InAppFilePicker], a dialog built from ordinary Flutter widgets that
// browses the file system (directories and `.paint` files only) and returns
// the chosen absolute path. It has two modes ([FilePickerMode]): open (tap a
// file to choose it) and save (type or pick a file name, then confirm).
//
// Why: Open/Save use an in-house picker instead of the platform's native file
// dialogs so the whole flow can be driven by `flutter test` with no native UI
// and no file-picker plugin (docs/design/document/file-format-and-flow.md).
// This file is only the UI half; it never reads or writes document
// contents.
//
// Coupled to: document_file_service.dart (InAppDocumentFileService is the
// only production caller of [InAppFilePicker.show]; the overview of the whole
// open/save system is there), and test/document/file_picker_dialog_test.dart.
// See the overview in document_file_service.dart.

import 'dart:io';

import 'package:flutter/material.dart';

import '../help/contextual_help.dart';
import '../ui/painter_action_button.dart';
import '../ui/touch_target_settings.dart';

/// Whether an [InAppFilePicker] is choosing a file to open or a path to
/// save to.
enum FilePickerMode { open, save }

/// An in-app file browser dialog that lists directories and `.paint`
/// documents without using the platform's native file picker.
///
/// Returns the chosen absolute path, or `null` if the user cancels. Used
/// through `InAppDocumentFileService.chooseOpenPath` and `chooseSavePath`
/// (document_file_service.dart); call [show] rather than constructing the
/// widget directly.
class InAppFilePicker extends StatefulWidget {
  const InAppFilePicker({
    super.key,
    required this.mode,
    required this.startDirectory,
    this.suggestedName = '',
  });

  final FilePickerMode mode;
  final Directory startDirectory;
  final String suggestedName;

  /// The only file extension the picker lists and appends on save. Must match
  /// the `.paint` format extension of design/document/file-format-and-flow.md.
  static const String extension = '.paint';

  /// Shows the picker in a dialog and returns the chosen path, or `null`
  /// if the user cancels.
  static Future<String?> show(
    BuildContext context, {
    required FilePickerMode mode,
    required Directory startDirectory,
    String suggestedName = '',
  }) {
    return showDialog<String>(
      context: context,
      builder: (context) => InAppFilePicker(
        mode: mode,
        startDirectory: startDirectory,
        suggestedName: suggestedName,
      ),
    );
  }

  @override
  State<InAppFilePicker> createState() => _InAppFilePickerState();
}

/// One row of the directory listing: a name (not a full path) and whether it
/// is a directory. Built by [_InAppFilePickerState._listEntries].
class _FileEntry {
  const _FileEntry({required this.name, required this.isDirectory});

  final String name;
  final bool isDirectory;
}

/// State for [InAppFilePicker]: tracks the directory being browsed and the
/// file-name text field (save mode).
///
/// Paths are built by joining with `/`, which is correct for the current
/// macOS target but would need revisiting for Windows.
class _InAppFilePickerState extends State<InAppFilePicker> {
  late Directory _currentDirectory;
  late final TextEditingController _nameController;
  List<_FileEntry> _entries = [];
  String? _listError;

  @override
  void initState() {
    super.initState();
    _currentDirectory = widget.startDirectory;
    _nameController = TextEditingController(text: widget.suggestedName);
    _listEntries();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// Re-reads [_currentDirectory] and rebuilds [_entries]: every
  /// subdirectory plus every file ending in `.paint` (case-insensitive),
  /// directories first, then alphabetical ignoring case. Symlinks are not
  /// followed. On failure (for example no permission) the list is cleared and
  /// [_listError] is shown instead, so navigating into an unreadable folder
  /// does not throw out of the dialog. Must be called after every change to
  /// [_currentDirectory] ([_openDirectory], [_goUp], [initState]).
  ///
  /// Directory URIs end in `/`, so empty path segments are dropped before
  /// taking the last one as the display name.
  void _listEntries() {
    try {
      final entries =
          _currentDirectory
              .listSync(followLinks: false)
              .whereType<FileSystemEntity>()
              .where((entity) {
                if (entity is Directory) return true;
                return entity.path.toLowerCase().endsWith(
                  InAppFilePicker.extension,
                );
              })
              .map(
                (entity) => _FileEntry(
                  name: entity.uri.pathSegments.where((s) => s.isNotEmpty).last,
                  isDirectory: entity is Directory,
                ),
              )
              .toList()
            ..sort((a, b) {
              if (a.isDirectory != b.isDirectory) {
                return a.isDirectory ? -1 : 1;
              }
              return a.name.toLowerCase().compareTo(b.name.toLowerCase());
            });
      setState(() {
        _entries = entries;
        _listError = null;
      });
    } catch (error) {
      setState(() {
        _entries = [];
        _listError = 'Could not list $_currentDirectoryPath: $error';
      });
    }
  }

  String get _currentDirectoryPath => _currentDirectory.path;

  /// Descends into the subdirectory [name] of the current directory.
  void _openDirectory(String name) {
    setState(() {
      _currentDirectory = Directory('${_currentDirectory.path}/$name');
    });
    _listEntries();
  }

  /// Moves to the parent directory; does nothing at the file-system root
  /// (where the parent path equals the current path).
  void _goUp() {
    final parent = _currentDirectory.parent;
    if (parent.path == _currentDirectory.path) return;
    setState(() => _currentDirectory = parent);
    _listEntries();
  }

  /// Open mode: completes the dialog with the full path of the file [name].
  void _chooseOpenFile(String name) {
    Navigator.of(context).pop('${_currentDirectory.path}/$name');
  }

  /// Save mode: completes the dialog with the typed name appended to the
  /// current directory. Ignores an empty name, and adds `.paint` if the name
  /// does not already end with it, so a saved document always has the format
  /// extension. Does not ask before overwriting an existing file.
  void _confirmSave() {
    var name = _nameController.text.trim();
    if (name.isEmpty) return;
    if (!name.toLowerCase().endsWith(InAppFilePicker.extension)) {
      name = '$name${InAppFilePicker.extension}';
    }
    Navigator.of(context).pop('${_currentDirectory.path}/$name');
  }

  /// Builds the dialog. In save mode a tapped file only fills the name field
  /// (the user then confirms with the Save button or by submitting the
  /// field); in open mode a tapped file completes the dialog immediately.
  /// Tapping a directory navigates in both modes. Cancel pops with `null`.
  @override
  Widget build(BuildContext context) {
    final isSave = widget.mode == FilePickerMode.save;
    return AlertDialog(
      title: Text(isSave ? 'Save document' : 'Open document'),
      content: SizedBox(
        width: 480,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                PainterActionButton(
                  icon: Icons.arrow_upward,
                  label: 'Up',
                  topic: HelpIds.pickerUp,
                  onPressed: _goUp,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _currentDirectoryPath,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const Divider(height: 1),
            Expanded(
              child: _listError != null
                  ? Center(child: Text(_listError!))
                  : ListView.builder(
                      itemCount: _entries.length,
                      itemBuilder: (context, index) {
                        final entry = _entries[index];
                        final topic = entry.isDirectory
                            ? HelpIds.pickerDirectory
                            : isSave
                            ? HelpIds.pickerSaveFile
                            : HelpIds.pickerFile;
                        return ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: TouchTargetSettings.height(context),
                          ),
                          child: HelpTarget(
                            topic: topic,
                            child: ListTile(
                              leading: Icon(
                                entry.isDirectory
                                    ? Icons.folder
                                    : Icons.insert_drive_file,
                              ),
                              title: Text(entry.name),
                              onTap: entry.isDirectory
                                  ? () => _openDirectory(entry.name)
                                  : isSave
                                  ? () => _nameController.text = entry.name
                                  : () => _chooseOpenFile(entry.name),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            if (isSave) ...[
              const Divider(height: 1),
              HelpTarget(
                topic: HelpIds.pickerFileName,
                child: TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'File name'),
                  onSubmitted: (_) => _confirmSave(),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        PainterActionButton(
          icon: Icons.cancel_outlined,
          label: 'Cancel',
          topic: HelpIds.pickerCancel,
          onPressed: () => Navigator.of(context).pop(),
        ),
        if (isSave)
          PainterActionButton(
            icon: Icons.save,
            label: 'Save',
            topic: HelpIds.pickerSave,
            onPressed: _confirmSave,
          ),
      ],
    );
  }
}
