import 'dart:convert';

import 'package:flutter/material.dart';

import 'canvas/canvas_controller.dart';
import 'canvas/canvas_view.dart';
import 'document/document_file_service.dart';

void main() {
  runApp(const PainterApp());
}

class PainterApp extends StatefulWidget {
  const PainterApp({super.key, this.fileService});

  /// Overridable for tests; defaults to [InAppDocumentFileService].
  final DocumentFileService? fileService;

  @override
  State<PainterApp> createState() => _PainterAppState();
}

class _PainterAppState extends State<PainterApp> {
  final CanvasController _controller = CanvasController();
  late final DocumentFileService _fileService =
      widget.fileService ?? InAppDocumentFileService();
  String? _documentPath;
  bool _fileOperationInProgress = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openDocument(BuildContext context) async {
    if (_fileOperationInProgress) return;
    setState(() => _fileOperationInProgress = true);
    try {
      final path = await _fileService.chooseOpenPath(context);
      if (path == null || !mounted) return;
      final contents = await _fileService.readDocument(path);
      final document = CanvasDocument.fromJson(jsonDecode(contents));
      if (!mounted) return;
      _controller.replaceDocument(document);
      _documentPath = path;
    } catch (error, stackTrace) {
      if (!context.mounted) return;
      await _showFileOperationError(context, 'open', error, stackTrace);
    } finally {
      if (mounted) setState(() => _fileOperationInProgress = false);
    }
  }

  Future<void> _saveDocument(BuildContext context) async {
    if (_fileOperationInProgress) return;
    setState(() => _fileOperationInProgress = true);
    try {
      var path = _documentPath;
      path ??= await _fileService.chooseSavePath(context, 'Untitled.paint');
      if (path == null || !mounted) return;
      final contents = jsonEncode(_controller.document.toJson());
      await _fileService.writeDocument(path, contents);
      if (mounted) _documentPath = path;
    } catch (error, stackTrace) {
      if (!context.mounted) return;
      await _showFileOperationError(context, 'save', error, stackTrace);
    } finally {
      if (mounted) setState(() => _fileOperationInProgress = false);
    }
  }

  Future<void> _showFileOperationError(
    BuildContext context,
    String operation,
    Object error,
    StackTrace stackTrace,
  ) async {
    debugPrint('Failed to $operation Painter document: $error\n$stackTrace');
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('File operation failed'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Could not $operation the document: $error'),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Details'),
              children: [
                SizedBox(
                  height: 180,
                  width: 400,
                  child: SingleChildScrollView(
                    child: SelectableText('$error\n\n$stackTrace'),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Painter',
      home: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('Painter'),
            actions: [
              TextButton.icon(
                onPressed: _fileOperationInProgress
                    ? null
                    : () => _openDocument(context),
                icon: const Icon(Icons.folder_open),
                label: const Text('Open'),
              ),
              TextButton.icon(
                onPressed: _fileOperationInProgress
                    ? null
                    : () => _saveDocument(context),
                icon: const Icon(Icons.save),
                label: const Text('Save'),
              ),
            ],
          ),
          body: CanvasView(controller: _controller),
        ),
      ),
    );
  }
}
