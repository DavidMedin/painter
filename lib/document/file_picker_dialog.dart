import 'dart:io';

import 'package:flutter/material.dart';

/// Whether an [InAppFilePicker] is choosing a file to open or a path to
/// save to.
enum FilePickerMode { open, save }

/// An in-app file browser dialog that lists directories and `.paint`
/// documents without using the platform's native file picker.
///
/// Returns the chosen absolute path, or `null` if the user cancels.
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

class _FileEntry {
  const _FileEntry({required this.name, required this.isDirectory});

  final String name;
  final bool isDirectory;
}

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

  void _openDirectory(String name) {
    setState(() {
      _currentDirectory = Directory('${_currentDirectory.path}/$name');
    });
    _listEntries();
  }

  void _goUp() {
    final parent = _currentDirectory.parent;
    if (parent.path == _currentDirectory.path) return;
    setState(() => _currentDirectory = parent);
    _listEntries();
  }

  void _chooseOpenFile(String name) {
    Navigator.of(context).pop('${_currentDirectory.path}/$name');
  }

  void _confirmSave() {
    var name = _nameController.text.trim();
    if (name.isEmpty) return;
    if (!name.toLowerCase().endsWith(InAppFilePicker.extension)) {
      name = '$name${InAppFilePicker.extension}';
    }
    Navigator.of(context).pop('${_currentDirectory.path}/$name');
  }

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
                IconButton(
                  tooltip: 'Up a directory',
                  icon: const Icon(Icons.arrow_upward),
                  onPressed: _goUp,
                ),
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
                        return ListTile(
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
                        );
                      },
                    ),
            ),
            if (isSave) ...[
              const Divider(height: 1),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'File name'),
                onSubmitted: (_) => _confirmSave(),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (isSave)
          TextButton(onPressed: _confirmSave, child: const Text('Save')),
      ],
    );
  }
}
