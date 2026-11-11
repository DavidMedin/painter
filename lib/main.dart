// What: The app shell restores settings, initializes file-backed logging, and
//   starts PainterApp, which owns document/file state, per-pane renderers and
//   viewports, help, touch sizing, themes, and app-wide error reporting.
// Why: This shell coordinates persistence and state that cross canvas,
//   document, settings, logging, help, and pane systems without coupling those
//   systems to the painting model.
// Coupled to: canvas/, debug/, document/, help/, logging/, settings/, and ui/.
//
//
//
// ---------------------------------------------------------------------------
// App shell overview
//
// What it is: the top-level widget tree and app-owned state beyond the
// painting model: document path, file-operation state, pane renderers, logger,
// contextual help, and touch-target size.
// Why PainterApp owns the document path and the in-flight flag: the path is
// not part of CanvasDocument (the saved format, docs/design/document/
// file-format-and-flow.md, contains strokes only), and the controller
// has no notion of files. "Save writes to the associated path after the first
// successful save" (design/document/file-format-and-flow.md) therefore needs a
// holder outside both the document and the file service; this State is the only
// thing that sees both the open and the save paths. The in-flight flag lives
// here because the Open and Save buttons are built here and are disabled while
// it is set, and because _openDocument and _saveDocument both check it so two
// overlapping operations (for example Open while a Save dialog is up) cannot
// interleave and race on _documentPath or on the controller's document.
//
// Open flow (_openDocument): DocumentFileService.chooseOpenPath ->
// DocumentFileService.readDocument -> DocumentFileContents.parse (jsonDecode,
// then CanvasDocument.fromJson, which validates the format identifier and
// version and throws FormatException) -> CanvasController.replaceDocument ->
// apply the stored workspace if the setting is on and the section is usable ->
// remember the path. The document is replaced only after every earlier step
// succeeded, so a failed open leaves it untouched. An unusable workspace
// section never fails the open. The current pane views are kept
// (docs/spec/workspace.md WKSP-11).
//
// Save flow (_saveDocument): use the remembered path, or ask
// DocumentFileService.chooseSavePath with the suggested name 'Untitled.paint'
// -> CanvasDocument.toJson via jsonEncode -> DocumentFileService.
// writeDocument -> remember the path. The path is stored only after the write
// succeeded, so a failed first save does not make later saves silently
// target a path that was never written.
//
// Error policy (docs/design/document/behavior.md, docs/design/logging/):
// file operation failures are recorded by [PainterLog] with a catalog
// message id, arguments, and stack trace, then shown in an expandable-details
// popup. The app continues running. [installFlutterLogHandlers] routes
// framework and asynchronous errors to that same file-backed history.
// Fatal-error classification is an open question in
// docs/design/logging/behavior.md, so the handlers do not invent one.
//
// Pane system and workspace (docs/spec/panes.md, docs/spec/workspace.md):
// Workspace (workspace/workspace.dart) owns the layout, each pane's mode, and
// per-mode state such as a Canvas pane's viewport; PaneSystem draws it.
// PainterApp retains a renderer per pane. Diagnostics reads the first Canvas
// pane's state or uses its own pane's. Manual panes show contextual help; the
// Log pane and bottom status bar observe the same PainterLog history. Opening
// a file applies its stored workspace when the 'load stored workspaces'
// setting is on; Flash writes the current one into the file; Save leaves the
// file's stored workspace as it was.
//
// ---------------------------------------------------------------------------

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'canvas/canvas_controller.dart';
import 'canvas/canvas_view.dart';
import 'canvas/tiled_renderer.dart';
import 'debug/canvas_debug_options.dart';
import 'debug/canvas_debug_pane.dart';
import 'document/document_file_format.dart';
import 'document/document_file_service.dart';
import 'help/contextual_help.dart';
import 'help/manual_pane.dart';
import 'logging/flutter_log_handlers.dart';
import 'logging/log_widgets.dart';
import 'logging/painter_log.dart';
import 'settings/painter_settings.dart';
import 'settings/settings_store.dart';
import 'settings/theme_settings_pane.dart';
import 'ui/painter_action_button.dart';
import 'ui/pane_system.dart';
import 'ui/touch_target.dart';
import 'workspace/pane_kind.dart';
import 'workspace/workspace.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final logger = await PainterLog.open(
    pipeToStdout: args.contains('--log-to-stdout'),
  );
  installFlutterLogHandlers(logger);
  await logger.info('app.started');
  final store = SharedPreferencesPainterSettingsStore();
  PainterSettings settings;
  try {
    settings = await store.load();
  } catch (error, stackTrace) {
    await logger.warn(
      'settings.load.failed',
      arguments: {'error': error.toString()},
      stackTrace: stackTrace.toString(),
    );
    settings = PainterSettings.defaults;
  }
  runApp(
    PainterApp(
      initialSettings: settings,
      persistSettings: store.save,
      logger: logger,
    ),
  );
}

/// The root widget of the Painter app.
class PainterApp extends StatefulWidget {
  const PainterApp({
    super.key,
    this.fileService,
    this.initialSettings = PainterSettings.defaults,
    this.persistSettings,
    this.logger,
  });

  /// Overridable for tests; defaults to [InAppDocumentFileService].
  final DocumentFileService? fileService;
  final PainterSettings initialSettings;
  final Future<void> Function(PainterSettings settings)? persistSettings;

  /// Overridable for tests; defaults to an in-memory log store.
  final PainterLog? logger;
  @override
  State<PainterApp> createState() => _PainterAppState();
}

class _PainterAppState extends State<PainterApp> {
  late final PainterLog _logger;
  late final bool _ownsLogger;
  final CanvasController _controller = CanvasController();
  late final DocumentFileService _fileService =
      widget.fileService ?? InAppDocumentFileService();
  late final PainterSettingsController _settings;
  String? _documentPath;

  /// The `workspace` value of the opened file as read or last flashed, kept so
  /// Save writes it back unchanged (WKSP-4).
  Object? _workspaceSection;
  bool _fileOperationInProgress = false;

  final CanvasDebugOptions _debugOptions = CanvasDebugOptions();
  final HelpState _helpState = HelpState();
  final Map<int, TiledRenderer> _renderers = {};
  late final Workspace _workspace = Workspace(onPaneRemoved: _onPaneRemoved);

  @override
  void initState() {
    super.initState();
    _ownsLogger = widget.logger == null;
    _logger = widget.logger ?? PainterLog.memory();
    _settings = PainterSettingsController(
      initial: widget.initialSettings,
      persist: widget.persistSettings,
    );
  }

  /// Releases the renderer of a pane that left the workspace.
  void _onPaneRemoved(int paneId) => _renderers.remove(paneId)?.dispose();

  TiledRenderer _rendererFor(int paneId) => _renderers.putIfAbsent(
    paneId,
    () => TiledRenderer(
      onSplatWorkerError: (error, stackTrace) {
        unawaited(
          _logger.error(
            'splat.worker.failed',
            arguments: {'error': error.toString()},
            stackTrace: stackTrace.toString(),
          ),
        );
      },
    ),
  );

  /// Builds pane content from its selected mode and app-owned state.
  Widget _buildPaneContent(BuildContext context, PaneDescriptor pane) {
    final paneRenderer = _rendererFor(pane.id);
    return switch (pane.kind) {
      PaneKind.canvas => CanvasView(
        key: ValueKey('canvas-${pane.id}'),
        controller: _controller,
        viewport: _workspace.canvasViewport(pane.id),
        debugOptions: _debugOptions,
        renderer: paneRenderer,
      ),
      PaneKind.diagnostics => _diagnosticsContent(pane, paneRenderer),
      PaneKind.settings => ThemeSettingsPane(
        controller: _settings,
        logger: _logger,
      ),
      PaneKind.manual => ManualPane(
        helpId: _workspace.manualHelpId(pane.id),
        onHelpIdSelected: (helpId) =>
            _workspace.setManualHelpId(pane.id, helpId),
      ),
      PaneKind.log => LogPane(log: _logger),
    };
  }

  /// Builds diagnostics from the first Canvas, or this pane when none exists.
  Widget _diagnosticsContent(PaneDescriptor pane, TiledRenderer paneRenderer) {
    final canvasPaneId = _workspace.firstCanvasPaneId ?? pane.id;
    final renderer = canvasPaneId == pane.id
        ? paneRenderer
        : _rendererFor(canvasPaneId);
    return CanvasDebugPane(
      key: ValueKey('diagnostics-${pane.id}'),
      renderer: renderer,
      controller: _controller,
      viewport: _workspace.canvasViewport(canvasPaneId),
      options: _debugOptions,
    );
  }

  /// Opens the hovered or focused control's article in the docked manual.
  void _showContextHelp() {
    _workspace.openManual(_helpState.activeTopic);
  }

  /// Releases app-owned settings, logger, renderers, viewports, and help state.
  /// [DocumentFileService] is not disposed; it may be injected and holds no
  /// resources.
  @override
  void dispose() {
    _settings.dispose();
    for (final renderer in _renderers.values) {
      renderer.dispose();
    }
    _debugOptions.dispose();
    _helpState.dispose();
    _controller.dispose();
    _workspace.dispose();
    if (_ownsLogger) _logger.dispose();
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
      final file = DocumentFileContents.parse(contents);
      if (!mounted) return;
      _controller.replaceDocument(file.document);
      _workspaceSection = file.workspaceSection;
      if (_settings.settings.loadStoredWorkspaces) {
        _workspace.applyJson(file.workspaceSection);
      }
      _documentPath = path;
    } catch (error, stackTrace) {
      await _logFileOperationError('open', error, stackTrace);
      if (context.mounted) {
        await _showFileOperationError(context, 'open', error, stackTrace);
      }
    } finally {
      if (mounted) setState(() => _fileOperationInProgress = false);
    }
  }

  /// Runs the Save flow described in the overview at the top of this file.
  ///
  /// Mirrors [_openDocument] (same in-flight guard, then record the failure
  /// before showing details if the action context remains mounted). The
  /// behavior is specified in `docs/design/document/behavior.md`. If a path is
  /// already associated the picker is skipped; cancelling it aborts silently.
  Future<void> _saveDocument(BuildContext context) async {
    if (_fileOperationInProgress) return;
    setState(() => _fileOperationInProgress = true);
    try {
      var path = _documentPath;
      path ??= await _fileService.chooseSavePath(context, 'Untitled.paint');
      if (path == null || !mounted) return;
      final contents = DocumentFileContents(
        _controller.document,
        _workspaceSection,
      ).encode();
      await _fileService.writeDocument(path, contents);
      if (mounted) _documentPath = path;
    } catch (error, stackTrace) {
      await _logFileOperationError('save', error, stackTrace);
      if (context.mounted) {
        await _showFileOperationError(context, 'save', error, stackTrace);
      }
    } finally {
      if (mounted) setState(() => _fileOperationInProgress = false);
    }
  }

  /// Writes the current workspace into the opened document's file (WKSP-2).
  ///
  /// Only the file's `workspace` section changes: the file is read, its
  /// section replaced, and the text written back, so strokes the user has not
  /// saved stay out of the file. Needs [_documentPath]; the Flash button is
  /// disabled until the document has a file. Failures are reported like Open
  /// and Save failures.
  Future<void> _flashWorkspace(BuildContext context) async {
    if (_fileOperationInProgress) return;
    final path = _documentPath;
    if (path == null) return;
    setState(() => _fileOperationInProgress = true);
    try {
      final section = _workspace.toJson();
      final text = await _fileService.readDocument(path);
      await _fileService.writeDocument(
        path,
        DocumentFileContents.withWorkspaceSection(text, section),
      );
      _workspaceSection = section;
    } catch (error, stackTrace) {
      await _logFileOperationError('flash', error, stackTrace);
      if (context.mounted) {
        await _showFileOperationError(context, 'flash', error, stackTrace);
      }
    } finally {
      if (mounted) setState(() => _fileOperationInProgress = false);
    }
  }

  /// Records a failed open/save before any mounted-context check.
  ///
  /// This keeps failures in the shared history if the pane was removed while
  /// I/O was pending; the document behavior is specified in
  /// `docs/design/document/behavior.md`.
  Future<void> _logFileOperationError(
    String operation,
    Object error,
    StackTrace stackTrace,
  ) => _logger.error(
    'document.operation.failed',
    arguments: {'operation': operation, 'error': error.toString()},
    stackTrace: stackTrace.toString(),
  );

  /// Shows the popup with expandable details required by
  /// `docs/design/document/behavior.md`.
  Future<void> _showFileOperationError(
    BuildContext context,
    String operation,
    Object error,
    StackTrace stackTrace,
  ) async {
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
              topic: HelpIds.dialogDetails,
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                minTileHeight: touchTargetHeight,
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
            topic: HelpIds.dialogClose,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  /// Builds the app shell using the currently selected light/dark palettes.
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _settings,
      builder: (context, _) {
        final settings = _settings.settings;
        return MaterialApp(
          title: 'Painter',
          theme: settings.themeFor(Brightness.light).themeData,
          darkTheme: settings.themeFor(Brightness.dark).themeData,
          themeMode: settings.mode,
          builder: (context, child) => HelpScope(
            helpState: _helpState,
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.f1): _showContextHelp,
              },
              child: Focus(autofocus: true, child: child!),
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
                    topic: HelpIds.openDocument,
                    onPressed: _fileOperationInProgress
                        ? null
                        : () => _openDocument(context),
                  ),
                  PainterActionButton(
                    icon: Icons.save,
                    label: 'Save',
                    topic: HelpIds.saveDocument,
                    onPressed: _fileOperationInProgress
                        ? null
                        : () => _saveDocument(context),
                  ),
                  PainterActionButton(
                    icon: Icons.flash_on,
                    label: 'Flash layout',
                    topic: HelpIds.flashWorkspace,
                    onPressed: _fileOperationInProgress || _documentPath == null
                        ? null
                        : () => _flashWorkspace(context),
                  ),
                ],
              ),
              body: Column(
                children: [
                  Expanded(
                    child: PaneSystem(
                      workspace: _workspace,
                      contentBuilder: _buildPaneContent,
                    ),
                  ),
                  LogStatusBar(log: _logger),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
