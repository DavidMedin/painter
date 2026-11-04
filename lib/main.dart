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
// FormatException) -> CanvasController.replaceDocument -> reset each existing
// Canvas pane's viewport -> remember the path. The document is replaced only
// after every earlier step succeeded, so a failed open leaves it untouched
// (ADR 0002).
//
// Save flow (_saveDocument): use the remembered path, or ask
// DocumentFileService.chooseSavePath with the suggested name 'Untitled.paint'
// -> CanvasDocument.toJson via jsonEncode -> DocumentFileService.
// writeDocument -> remember the path. The path is stored only after the write
// succeeded, so a failed first save does not make later saves silently
// target a path that was never written.
//
// Error policy (docs/project-brief.md "Errors", ADR 0002 and ADR 0014): file
// operation failures are recorded by [PainterLog] with a catalog message id,
// arguments, and stack trace, then shown in an expandable-details popup. The
// app continues running. [installFlutterLogHandlers] routes framework and
// asynchronous errors to that same file-backed history. Fatal-error
// classification remains undefined by the brief, so the handlers do not
// invent one.
//
// Pane system (docs/decisions/0010-pane-system.md, ADRs 0012–0013): PaneSystem
// owns the split tree, content modes, focus, and resize weights. PainterApp
// retains a renderer per pane and an independent viewport per Canvas pane.
// Diagnostics reads a visible Canvas pane's state or uses its own retained
// renderer and viewport. Manual panes show contextual help; the Log pane and
// bottom status bar observe the same PainterLog history.
//
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
import 'help/manual_pane.dart';
import 'logging/flutter_log_handlers.dart';
import 'logging/log_widgets.dart';
import 'logging/painter_log.dart';
import 'settings/painter_settings.dart';
import 'settings/settings_store.dart';
import 'settings/theme_settings_pane.dart';
import 'ui/painter_action_button.dart';
import 'ui/pane_system.dart';
import 'ui/touch_target_settings.dart';

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
  bool _fileOperationInProgress = false;

  final CanvasDebugOptions _debugOptions = CanvasDebugOptions();
  final HelpState _helpState = HelpState();
  final Map<int, CanvasViewportController> _viewports = {};
  final Map<int, TiledRenderer> _renderers = {};
  final GlobalKey<PaneSystemState> _paneSystemKey =
      GlobalKey<PaneSystemState>();
  bool _enlargeTargets = false;

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

  void _toggleDebugPane() => _paneSystemKey.currentState?.toggleDiagnostics();

  void _onPaneRemoved(int paneId) {
    _renderers.remove(paneId)?.dispose();
    _viewports.remove(paneId)?.dispose();
  }

  void _onPaneTypeChanged(int paneId, PaneKind kind) {
    if (kind != PaneKind.canvas) {
      _viewports.remove(paneId)?.dispose();
    }
  }

  TiledRenderer _rendererFor(int paneId) =>
      _renderers.putIfAbsent(paneId, TiledRenderer.new);

  CanvasViewportController _viewportFor(int paneId) =>
      _viewports.putIfAbsent(paneId, CanvasViewportController.new);

  /// Builds pane content from its selected mode and app-owned state.
  Widget _buildPaneContent(BuildContext context, PaneDescriptor pane) {
    final paneRenderer = _rendererFor(pane.id);
    return switch (pane.kind) {
      PaneKind.canvas => CanvasView(
        key: ValueKey('canvas-${pane.id}'),
        controller: _controller,
        viewport: _viewportFor(pane.id),
        debugOptions: _debugOptions,
        renderer: paneRenderer,
      ),
      PaneKind.diagnostics => _diagnosticsContent(pane, paneRenderer),
      PaneKind.settings => ThemeSettingsPane(controller: _settings),
      PaneKind.manual => ManualPane(
        helpId: pane.manualHelpId,
        onHelpIdSelected: pane.onManualHelpSelected,
      ),
      PaneKind.log => LogPane(log: _logger),
    };
  }

  /// Builds diagnostics from the first Canvas, or this pane when none is visible.
  Widget _diagnosticsContent(PaneDescriptor pane, TiledRenderer paneRenderer) {
    final canvasPaneId = pane.canvasPaneId ?? pane.id;
    final renderer = pane.canvasPaneId == null
        ? paneRenderer
        : _rendererFor(canvasPaneId);
    return CanvasDebugPane(
      key: ValueKey('diagnostics-${pane.id}'),
      renderer: renderer,
      controller: _controller,
      viewport: _viewportFor(canvasPaneId),
      options: _debugOptions,
    );
  }

  /// Opens the hovered or focused control's article in the docked manual.
  void _showContextHelp() {
    _paneSystemKey.currentState?.openManual(_helpState.activeTopic);
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
    for (final viewport in _viewports.values) {
      viewport.dispose();
    }
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
      final document = CanvasDocument.fromJson(jsonDecode(contents));
      if (!mounted) return;
      _controller.replaceDocument(document);
      for (final viewport in _viewports.values) {
        viewport.resetViewport();
      }
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

  /// Logs a failed open/save and shows the popup with expandable details
  /// required by docs/project-brief.md "Errors".
  ///
  /// [operation] is the verb ('open' or 'save') spliced into the message.
  /// Called only from the catch blocks of [_openDocument] and [_saveDocument].
  /// The log happens before the `mounted` check so the failure is recorded
  /// even if the widget is gone.
  Future<void> _showFileOperationError(
    BuildContext context,
    String operation,
    Object error,
    StackTrace stackTrace,
  ) async {
    await _logger.error(
      'document.operation.failed',
      arguments: {'operation': operation, 'error': error.toString()},
      stackTrace: stackTrace.toString(),
    );
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
              topic: HelpIds.dialogDetails,
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
            child: TouchTargetSettings(
              enlarged: _enlargeTargets,
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.f1):
                      _showContextHelp,
                  const SingleActivator(LogicalKeyboardKey.f3):
                      _toggleDebugPane,
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
                    icon: Icons.touch_app,
                    label: _enlargeTargets ? 'Touch: Large' : 'Touch: Standard',
                    topic: HelpIds.touchTargets,
                    onPressed: () =>
                        setState(() => _enlargeTargets = !_enlargeTargets),
                  ),
                ],
              ),
              body: Column(
                children: [
                  Expanded(
                    child: PaneSystem(
                      key: _paneSystemKey,
                      contentBuilder: _buildPaneContent,
                      onPaneRemoved: _onPaneRemoved,
                      onPaneTypeChanged: _onPaneTypeChanged,
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
