// What: The app shell. `main` starts [PainterApp], which owns the one
// CanvasController (the open document and viewport), builds the MaterialApp
// and AppBar with Open / Save and touch-size controls, wires file operations
// (_openDocument / _saveDocument), displays contextual help, and hosts the
// selectable pane system with canvas and tile-cache diagnostics content.
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
// state that is not part of the painting model itself: the associated document
// path, file-operation state, pane renderers, contextual-help state, and
// touch-target size.
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
// Pane system (docs/decisions/0010-pane-system.md): PaneSystem owns the pane
// layout, Pane Mode selectors, boundary menus, and widths. This shell keeps a
// TiledRenderer for every pane id, even while the pane shows Diagnostics, so
// changing modes preserves diagnostic state. A Diagnostics pane reads the
// first visible Canvas pane's renderer, or its own retained renderer when no
// Canvas pane is visible. F3 toggles Diagnostics beside the focused pane.
// _debugOptions is shared with every CanvasView (which paints the overlays) and
// each CanvasDebugPane (which edits the switches).
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
import 'help/contextual_help.dart';
import 'ui/painter_action_button.dart';
import 'ui/pane_system.dart';
import 'ui/touch_target_settings.dart';

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
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late final DocumentFileService _fileService =
      widget.fileService ?? InAppDocumentFileService();
  String? _documentPath;
  bool _fileOperationInProgress = false;

  final CanvasDebugOptions _debugOptions = CanvasDebugOptions();
  final HelpState _helpState = HelpState();
  final Map<int, TiledRenderer> _renderers = {};
  final GlobalKey<PaneSystemState> _paneSystemKey =
      GlobalKey<PaneSystemState>();
  bool _enlargeTargets = false;

  void _toggleDebugPane() => _paneSystemKey.currentState?.toggleDiagnostics();

  void _onPaneRemoved(int paneId) {
    _renderers.remove(paneId)?.dispose();
  }

  TiledRenderer _rendererFor(int paneId) =>
      _renderers.putIfAbsent(paneId, TiledRenderer.new);

  /// Builds pane content using the renderer retained for its stable pane id.
  Widget _buildPaneContent(BuildContext context, PaneDescriptor pane) {
    final paneRenderer = _rendererFor(pane.id);
    return switch (pane.kind) {
      PaneKind.canvas => CanvasView(
        key: ValueKey('canvas-${pane.id}'),
        controller: _controller,
        debugOptions: _debugOptions,
        renderer: paneRenderer,
      ),
      PaneKind.diagnostics => _diagnosticsContent(pane, paneRenderer),
    };
  }

  /// Builds diagnostics against the visible Canvas, or this pane's retained
  /// renderer when no Canvas pane is visible.
  Widget _diagnosticsContent(PaneDescriptor pane, TiledRenderer paneRenderer) {
    final renderer = pane.canvasPaneId == null
        ? paneRenderer
        : _rendererFor(pane.canvasPaneId!);
    return CanvasDebugPane(
      key: ValueKey('diagnostics-${pane.id}'),
      renderer: renderer,
      controller: _controller,
      options: _debugOptions,
    );
  }

  /// Releases app-owned state and every pane renderer, including hidden ones.
  /// The [DocumentFileService] has no resources and may have been injected.
  @override
  void dispose() {
    for (final renderer in _renderers.values) {
      renderer.dispose();
    }
    _debugOptions.dispose();
    _helpState.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _showContextHelp() async {
    final context = _navigatorKey.currentState?.overlay?.context;
    if (context == null) return;
    await showContextHelp(context, _helpState.activeTopic);
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
            HelpTarget(
              topic: HelpTopics.dialogDetails,
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                minTileHeight: TouchTargetSettings.height(context),
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
            ),
          ],
        ),
        actions: [
          PainterActionButton(
            icon: Icons.close,
            label: 'Close',
            topic: HelpTopics.dialogClose,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  /// Builds the app shell and pane workspace. Help, touch sizing, and shortcuts
  /// wrap Navigator so modal routes inherit them; F1 uses its overlay context.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Painter',
      navigatorKey: _navigatorKey,
      builder: (context, child) => HelpScope(
        helpState: _helpState,
        child: TouchTargetSettings(
          enlarged: _enlargeTargets,
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.f1): _showContextHelp,
              const SingleActivator(LogicalKeyboardKey.f3): _toggleDebugPane,
            },
            child: Focus(autofocus: true, child: child!),
          ),
        ),
      ),
      home: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('Painter'),
            actions: [
              PainterActionButton(
                icon: Icons.folder_open,
                label: 'Open',
                topic: HelpTopics.openDocument,
                onPressed: _fileOperationInProgress
                    ? null
                    : () => _openDocument(context),
              ),
              PainterActionButton(
                icon: Icons.save,
                label: 'Save',
                topic: HelpTopics.saveDocument,
                onPressed: _fileOperationInProgress
                    ? null
                    : () => _saveDocument(context),
              ),
              PainterActionButton(
                icon: Icons.touch_app,
                label: _enlargeTargets ? 'Touch: Large' : 'Touch: Standard',
                topic: HelpTopics.touchTargets,
                onPressed: () =>
                    setState(() => _enlargeTargets = !_enlargeTargets),
              ),
            ],
          ),
          body: PaneSystem(
            key: _paneSystemKey,
            contentBuilder: _buildPaneContent,
            onPaneRemoved: _onPaneRemoved,
          ),
        ),
      ),
    );
  }
}
