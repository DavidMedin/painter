// What: The application shell. `main` starts [PainterApp], which owns the one
// CanvasController (the open document and viewport), builds the MaterialApp
// and AppBar with Open / Save / debug-pane buttons, wires the file-operation
// flow (_openDocument / _saveDocument), shows file-operation errors
// (_showFileOperationError), and toggles the tile-cache debug pane.
//
// Why: Something has to own the state that crosses subsystems: the canvas
// (canvas/), the file I/O abstraction (document/), and the debug pane
// (debug/). The canvas code has no file or dialog logic and the document/
// code has no canvas types, so this is where the two are connected
// (JSON text from the file service <-> CanvasDocument). Keeping that glue
// here keeps canvas_controller.dart free of dart:io and dialogs, and
// document_file_service.dart free of canvas types.
//
// Coupled to: canvas/canvas_controller.dart (CanvasController,
// CanvasDocument), canvas/canvas_view.dart (CanvasView), canvas/
// tiled_renderer.dart (TiledRenderer), debug/canvas_debug_options.dart,
// debug/canvas_debug_pane.dart, document/document_file_service.dart.
//
// ---------------------------------------------------------------------------
// App shell overview
//
// What it is: the top-level widget tree and the small amount of mutable
// state that is not part of the painting model itself: the path of the
// associated document file, the "file operation in progress" flag, and
// whether the debug pane is visible.
//
// Why PainterApp owns the document path and the in-flight flag: the path is
// not part of CanvasDocument (the saved format, docs/decisions/0002-saved-
// document-format-and-flow.md, contains strokes only), and the controller
// has no notion of files. "Save writes to the associated path after the first
// successful save" (ADR 0002) therefore needs a holder outside both the
// document and the file service; this State is the only thing that sees both
// the open and the save paths. The in-flight flag lives here because the
// Open and Save buttons are built here and are disabled while it is set, and
// because _openDocument and _saveDocument both check it so two overlapping
// operations (for example Open while a Save dialog is up) cannot interleave
// and race on _documentPath or on the controller's document.
//
// Open flow (_openDocument): DocumentFileService.chooseOpenPath ->
// DocumentFileService.readDocument -> jsonDecode ->
// CanvasDocument.fromJson (validates format identifier/version, throws
// FormatException) -> CanvasController.replaceDocument (also resets the
// viewport) -> remember the path. The document is replaced only after every
// earlier step succeeded, so a failed open leaves the current document
// untouched (ADR 0002).
//
// Save flow (_saveDocument): use the remembered path, or ask
// DocumentFileService.chooseSavePath with the suggested name 'Untitled.paint'
// -> CanvasDocument.toJson via jsonEncode -> DocumentFileService.
// writeDocument -> remember the path. The path is stored only after the write
// succeeded, so a failed first save does not make later saves silently
// target a path that was never written.
//
// Error policy (docs/project-brief.md "Errors", ADR 0002): a failed file
// operation is logged to the terminal with its stack trace, shown in a popup
// with an expandable "Details" section, and the app keeps running. In this
// file that is implemented by the catch blocks in _openDocument and
// _saveDocument, which call _showFileOperationError (its only callers);
// _showFileOperationError does the debugPrint logging and the dialog. The
// brief also asks for logging of non-file internal errors and for fatal-error
// handling; nothing in lib/ installs a global handler for those (no
// FlutterError.onError or runZonedGuarded), so that part of the brief is not
// implemented here.
//
// Debug pane (docs/decisions/0006-debug-pane.md): hidden by default. The
// AppBar bug button and the F3 key both call _toggleDebugPane. The pane needs
// the TiledRenderer that CanvasView creates internally; CanvasView reports it
// through its onRenderer callback (from its initState), which stores it in
// _renderer, and the pane is only built once _renderer is non-null.
// _debugOptions is created here and shared with CanvasView (which paints the
// overlays) and with CanvasDebugPane (which edits the switches).
// ---------------------------------------------------------------------------

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'canvas/canvas_controller.dart';
import 'canvas/canvas_view.dart';
import 'canvas/tiled_renderer.dart';
import 'debug/canvas_debug_options.dart';
import 'debug/canvas_debug_pane.dart';
import 'document/document_file_service.dart';

void main() {
  runApp(const PainterApp());
}

/// The root widget of the Painter app.
///
/// It is a StatefulWidget only so that [_PainterAppState] can own the
/// controller, document path, and debug-pane state; see the app shell
/// overview at the top of this file.
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

  final CanvasDebugOptions _debugOptions = CanvasDebugOptions();
  TiledRenderer? _renderer;
  bool _showDebugPane = false;

  void _toggleDebugPane() => setState(() => _showDebugPane = !_showDebugPane);

  /// Releases the objects this State created itself. The [DocumentFileService]
  /// is not disposed: it holds no resources and may have been injected.
  @override
  void dispose() {
    _debugOptions.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Runs the Open flow described in the overview at the top of this file.
  ///
  /// [context] is the AppBar's [Builder] context (see [build]); it must be
  /// below the [MaterialApp] so the picker and error dialogs can find a
  /// Navigator. A cancelled picker (null path) is not an error and changes
  /// nothing. Any other failure, including the FormatException from
  /// [CanvasDocument.fromJson] and I/O errors from
  /// [DocumentFileService.readDocument], is reported through
  /// [_showFileOperationError]. The `mounted` checks guard the awaits: the
  /// widget can be disposed while a dialog or file read is pending.
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

  /// Runs the Save flow described in the overview at the top of this file.
  ///
  /// Mirrors [_openDocument] (same in-flight guard, same error path through
  /// [_showFileOperationError]). If a path is already associated the picker
  /// is skipped; otherwise a cancelled picker (null path) aborts silently.
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

  /// Logs a failed open/save to the terminal and shows the popup with
  /// expandable details required by docs/project-brief.md "Errors".
  ///
  /// [operation] is the verb ('open' or 'save') spliced into the message, so
  /// it must read correctly in "Failed to $operation" and "Could not
  /// $operation the document". Called only from the catch blocks of
  /// [_openDocument] and [_saveDocument]. The log happens before the
  /// `mounted` check so the failure is recorded even if the widget is gone.
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

  /// Builds the app: AppBar (Open, Save, debug toggle) over a [Stack] of the
  /// [CanvasView] and, when enabled, the [CanvasDebugPane] floating on top.
  ///
  /// The [Builder] gives the buttons a context that is below the
  /// [MaterialApp]; passing this State's own context to [_openDocument] or
  /// [_saveDocument] would have no Navigator ancestor for showDialog. The
  /// [CallbackShortcuts] plus autofocused [Focus] route F3 to
  /// [_toggleDebugPane]; the Focus node is what lets key events reach the
  /// shortcut when nothing else is focused.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Painter',
      home: Builder(
        builder: (context) => CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.f3): _toggleDebugPane,
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
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
                  IconButton(
                    tooltip: 'Debug pane (F3)',
                    isSelected: _showDebugPane,
                    onPressed: _toggleDebugPane,
                    icon: const Icon(Icons.bug_report_outlined),
                    selectedIcon: const Icon(Icons.bug_report),
                  ),
                ],
              ),
              body: Stack(
                children: [
                  CanvasView(
                    controller: _controller,
                    debugOptions: _debugOptions,
                    onRenderer: (renderer) => _renderer = renderer,
                  ),
                  if (_showDebugPane && _renderer != null)
                    CanvasDebugPane(
                      renderer: _renderer!,
                      controller: _controller,
                      options: _debugOptions,
                      onClose: _toggleDebugPane,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
