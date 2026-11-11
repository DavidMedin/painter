// What: The app shell restores settings, initializes file-backed logging, and
//   starts PainterApp, which owns document/file state, undo history,
//   per-pane renderers and viewports, help, touch sizing, themes, the
//   Session (start, join, leave, workspace membership), and app-wide error
//   reporting.
// Why: This shell coordinates persistence and state that cross canvas,
//   document, settings, logging, help, session, and pane systems without
//   coupling those systems to the painting model.
// Coupled to: canvas/, crdt/, debug/, document/, help/, logging/, session/
//   (SessionNetwork, SessionDocument, session_pane.dart), settings/, ui/,
//   and workspace/.
//
// ---------------------------------------------------------------------------
// App shell overview
//
// What it is: the top-level widget tree and app-owned state beyond the
// painting model: the content document and its undo history, document path,
// the file's preserved sections, file-operation state, pane renderers,
// logger, contextual help, and touch-target size.
// Why PainterApp owns the document path and the in-flight flag: the path is
// not part of the content (docs/spec/document-file.md DOCF-8), and the
// controller has no notion of files. Save writes to the associated path
// after the first successful save, so the path needs a holder outside both
// the document and the file service; this State is the only thing that sees
// both the open and the save paths. The in-flight flag lives here because the
// Open and Save buttons are built here and are disabled while it is set, and
// because _openDocument and _saveDocument both check it so two overlapping
// operations (for example Open while a Save dialog is up) cannot interleave
// and race on _documentPath or on the controller's document.
//
// Document (document/content_document.dart, docs/decisions/
// 008-document-file-format.md): the app starts with a new empty
// ContentDocument. _attachContent attaches a content document to the shared
// CanvasController and gives it a new EditHistory (document/undo_history.dart,
// docs/decisions/012-undo-per-participant.md PNT-A0018-05); _replaceContent
// also disposes the previous pair. Undo and Redo are AppBar buttons and
// Command+Z / Command+Shift+Z (docs/spec/keybinds.md KEY-3), disabled while
// nothing can be undone or redone or a stroke is in progress (UNDO-4).
//
// Open flow (_openDocument): DocumentFileService.chooseOpenPath ->
// DocumentFileService.readDocument -> DocumentFileContents.read (format 2,
// or an earlier-format file imported into a new content document; throws
// FormatException or StrokeEngineMismatch) -> _replaceContent -> keep the
// file's other sections for Save -> apply the stored workspace if the setting
// is on and the section is usable -> remember the path. The document is
// replaced only after every earlier step succeeded, so a failed open leaves
// it untouched (DOCF-6, DOCF-7). An unusable workspace section never fails
// the open. The current pane views are kept (docs/spec/workspace.md
// WKSP-11).
//
// Save flow (_saveDocument): use the remembered path, or ask
// DocumentFileService.chooseSavePath with the suggested name 'Untitled.paint'
// -> DocumentFileContents.encode (always format 2, DOCF-4, with the
// preserved sections, WKSP-4 and WKSP-20) -> DocumentFileService.
// writeDocument -> remember the path. The path is stored only after the write
// succeeded, so a failed first save does not make later saves silently
// target a path that was never written.
//
// Error policy: file operation failures are recorded by [PainterLog] with a
// catalog message id, arguments, and stack trace, then shown in an
// expandable-details popup (DOCF-7 asks for the reason to be shown). The app
// continues running. [installFlutterLogHandlers] routes framework and
// asynchronous errors to that same file-backed history. No fatal-error
// classification is recorded, so the handlers do not invent one.
//
// Logging (docs/spec/logging.md, docs/decisions/014-logging.md): every
// Operation this State runs records its success (info), cancellation
// (debug) or failure (error); fallbacks such as an unusable stored
// workspace or deleted unreadable strokes are warnings. Edits are recorded
// by the models that make them (EditHistory, Workspace), and Session
// membership by SessionNetwork, each given [_logger]. Quitting records an
// info record and waits for it to reach the file ([_onExitRequested]).
//
// Pane system and workspace (docs/spec/panes.md, docs/spec/workspace.md):
// PainterApp creates the session document (session/session_document.dart,
// docs/decisions/009-shared-workspaces.md) with the local Participant as the
// only Member of a Default workspace. Workspace (workspace/workspace.dart)
// shows and edits that workspace's Layout tree, each pane's mode, and
// per-mode state such as a Canvas pane's view; PaneSystem draws it.
// PainterApp retains a renderer per pane id. Diagnostics reads the first
// Canvas pane's state or uses its own pane's. Manual panes show contextual
// help; the Log pane and bottom status bar observe the same PainterLog
// history. Opening a file applies its stored workspace when the 'load stored
// workspaces' setting is on; Flash writes the current one into the file;
// Save leaves the file's stored workspace as it was.
//
// Session (docs/spec/multiplayer.md, docs/decisions/013-session-
// networking.md; network overview in session/session_network.dart): outside
// a Session [_network] is null. Start session asks for a name, stores it and
// the file's workspace section (`storedWorkspace`) in the session document,
// and starts a SessionNetwork on the app's own content and session
// documents. Join session builds a SessionNetwork on new empty documents;
// only when the join succeeded does the app adopt them: the content with a
// new EditHistory and no file (MPLY-14), the session document, and a
// Workspace for the new workspace, whose first table comes from
// [_joinedWorkspaceNodes] (WKSP-9, WKSP-11, WKSP-31). A refusal or a failed
// connection changes nothing. Leave session keeps the content and replaces
// the session document with a new one-Participant document holding a copy of
// the current workspace's node table (same pane ids, so panes keep their
// renderers), which is the outside-a-Session state (PNT-A0015-01) and lets a
// later Start session begin clean. Open is disabled while in a Session,
// because the network syncs the content document it started or joined with.
// Workspace membership: [_onSessionChanged] checks after every session
// document change whether the local Participant's `workspace` moved (Join
// workspace, Leave workspace, or a copy made on leaving); if so a Workspace
// for the new id replaces the old one. If a peer deleted the local
// workspace (SessionDocument.localWorkspaceMissing), the check first
// recreates it from the layout the app last showed
// (Workspace.lastShownNodes, PNT-A0015-04), so the workspace area never
// stays blank. That check runs in a microtask, never inside the document
// listener, because the old Workspace is a listener of the same
// notification; microtasks run before the next frame, so the empty layout
// is never drawn. Workspaces dispose the live views of vanished panes after
// the next frame ([_afterDetach]), once their widgets have detached. Flash
// writes [_workspace], the workspace the user is a Member of (WKSP-2).
// Session failures are logged like file failures and shown in a dialog.
//
// ---------------------------------------------------------------------------

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'canvas/canvas_controller.dart';
import 'canvas/canvas_view.dart';
import 'canvas/pencil_splats.dart' show strokeEngineVersion;
import 'canvas/tiled_renderer.dart';
import 'crdt/automerge_crdt_document.dart';
import 'crdt/crdt_document.dart';
import 'debug/canvas_debug_options.dart';
import 'debug/canvas_debug_pane.dart';
import 'document/content_document.dart';
import 'document/document_file_format.dart';
import 'document/document_file_service.dart';
import 'document/undo_history.dart';
import 'help/contextual_help.dart';
import 'help/manual_pane.dart';
import 'logging/flutter_log_handlers.dart';
import 'logging/log_widgets.dart';
import 'logging/painter_log.dart';
import 'session/session_document.dart';
import 'session/session_network.dart';
import 'session/session_pane.dart';
import 'settings/painter_settings.dart';
import 'settings/settings_store.dart';
import 'settings/theme_settings_pane.dart';
import 'ui/painter_action_button.dart';
import 'ui/pane_system.dart';
import 'ui/touch_target.dart';
import 'workspace/layout_tree.dart' show LayoutNodes, createDefaultLayout;
import 'workspace/pane_kind.dart';
import 'workspace/workspace.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final logger = await startLogging(args);
  final store = SharedPreferencesPainterSettingsStore();
  final invalidSettings = <String>[];
  PainterSettings settings;
  try {
    settings = await store.load(onInvalid: invalidSettings.add);
  } catch (error, stackTrace) {
    await logger.warn(
      'settings.load.failed',
      arguments: {'error': error.toString()},
      stackTrace: stackTrace.toString(),
    );
    settings = PainterSettings.defaults;
  }
  for (final problem in invalidSettings) {
    await logger.warn('settings.load.invalid', arguments: {'problem': problem});
  }
  runApp(
    PainterApp(
      initialSettings: settings,
      persistSettings: store.save,
      logger: logger,
    ),
  );
}

/// Opens the file-backed log in [directory] (the user's log directory by
/// default), mirroring it to stdout when [args] hold `--log-to-stdout`
/// (LOG-6), routes uncaught errors to it (LOG-14), and records the start
/// (LOG-9). Runs before anything else can fail.
Future<PainterLog> startLogging(
  List<String> args, {
  Directory? directory,
}) async {
  final logger = await PainterLog.open(
    directory: directory,
    pipeToStdout: args.contains('--log-to-stdout'),
  );
  installFlutterLogHandlers(logger);
  await logger.info('app.started');
  return logger;
}

/// The root widget of the Painter app.
class PainterApp extends StatefulWidget {
  const PainterApp({
    super.key,
    this.fileService,
    this.initialSettings = PainterSettings.defaults,
    this.persistSettings,
    this.logger,
    this.sessionBindAddress,
    this.sessionPort,
    this.accountName,
  });

  /// Overridable for tests; defaults to [InAppDocumentFileService].
  final DocumentFileService? fileService;
  final PainterSettings initialSettings;
  final Future<void> Function(PainterSettings settings)? persistSettings;

  /// Overridable for tests; defaults to an in-memory log store.
  final PainterLog? logger;

  /// Where a Session listens; null for SessionNetwork.start's defaults (all
  /// IPv4 interfaces, port 47800 or an OS-chosen one, PNT-A0019-01). Tests
  /// pass the loopback address and port 0.
  final InternetAddress? sessionBindAddress;
  final int? sessionPort;

  /// The name the Session dialogs offer (MPLY-10); null for the account
  /// name in the `USER` environment variable.
  final String? accountName;

  @override
  State<PainterApp> createState() => _PainterAppState();
}

class _PainterAppState extends State<PainterApp> {
  late final PainterLog _logger;
  late final bool _ownsLogger;
  final CanvasController _controller = CanvasController();
  late final DocumentFileService _fileService =
      widget.fileService ??
      InAppDocumentFileService(onListError: _onPickerListError);
  late final PainterSettingsController _settings;
  String? _documentPath;

  /// Creates and loads content documents
  /// (docs/decisions/007-crdt-automerge.md).
  static const CrdtBackend _backend = AutomergeBackend();

  /// The document the controller draws, and the local undo history for it;
  /// replaced together by [_replaceContent].
  late ContentDocument _content;
  late EditHistory _history;

  /// Notifies when Undo or Redo may have become enabled or disabled: the
  /// history changed, or a stroke started or ended.
  late Listenable _undoState;

  /// The opened file's sections other than the content (its workspace
  /// section as read or last flashed, and unknown kinds), kept so Save
  /// writes them back unchanged (WKSP-4, WKSP-20).
  List<DocumentSection> _preservedSections = const [];
  bool _fileOperationInProgress = false;

  final CanvasDebugOptions _debugOptions = CanvasDebugOptions();
  final HelpState _helpState = HelpState();
  final Map<String, TiledRenderer> _renderers = {};

  /// The session document (docs/decisions/009-shared-workspaces.md
  /// PNT-A0015-01). Outside a Session it holds only the local Participant,
  /// the only Member of one workspace (WKSP-31). Replaced by
  /// [_replaceSession] when a join succeeds or the Session is left.
  late SessionDocument _session;

  /// The workspace the local Participant is a Member of; replaced by
  /// [_bindWorkspace] when that membership changes.
  late Workspace _workspace;

  /// The local Participant's network while in a Session; null outside one.
  SessionNetwork? _network;

  /// Set while Start, Join or Leave session runs; their buttons are
  /// disabled meanwhile so two flows cannot interleave.
  bool _sessionOperationInProgress = false;

  /// Whether [_followMembership] is already scheduled.
  bool _membershipCheckDue = false;

  /// Records Painter quitting before it exits (LOG-24).
  late final AppLifecycleListener _lifecycle;

  /// A new session document created by this app as the only Participant,
  /// named [name], in a workspace holding [nodes], or the Layout tree's
  /// default table when null (the Default workspace).
  static SessionDocument _createSession({
    String name = '',
    LayoutNodes? nodes,
  }) {
    final document = _backend.create();
    return SessionDocument.create(
      document,
      name: name,
      engine: strokeEngineVersion,
      nodes:
          nodes ??
          createDefaultLayout(newId: document.newId, actor: document.actorId),
    );
  }

  /// The name the Session dialogs offer (MPLY-10).
  String get _accountName =>
      widget.accountName ?? Platform.environment['USER'] ?? '';

  @override
  void initState() {
    super.initState();
    _ownsLogger = widget.logger == null;
    _logger = widget.logger ?? PainterLog.memory();
    _settings = PainterSettingsController(
      initial: widget.initialSettings,
      persist: widget.persistSettings,
    );
    _lifecycle = AppLifecycleListener(onExitRequested: _onExitRequested);
    _attachContent(ContentDocument.create(_backend));
    _attachSession(_createSession());
  }

  /// Records that Painter is quitting and lets it exit once the record is in
  /// the log file (LOG-24).
  Future<AppExitResponse> _onExitRequested() async {
    await _logger.info('app.quit');
    return AppExitResponse.exit;
  }

  /// Records a directory the file picker could not list (LOG-13).
  void _onPickerListError(String path, Object error) => unawaited(
    _logger.warn(
      'document.picker.list_failed',
      arguments: {'path': path, 'error': error.toString()},
    ),
  );

  /// Makes [session] the session document and shows the local
  /// Participant's workspace. [_replaceSession] frees the previous pair.
  void _attachSession(SessionDocument session) {
    _session = session;
    session.addListener(_onSessionChanged);
    _workspace = _newWorkspace(session.localParticipant!.workspace);
  }

  Workspace _newWorkspace(String workspaceId) => Workspace(
    session: _session,
    workspaceId: workspaceId,
    onPaneRemoved: _onPaneRemoved,
    afterDetach: _afterDetach,
    log: _logger,
  );

  /// Runs [dispose] after the next frame, when the widgets of panes a
  /// Workspace stopped showing have been rebuilt away; schedules that frame.
  static void _afterDetach(VoidCallback dispose) {
    WidgetsBinding.instance
      ..addPostFrameCallback((_) => dispose())
      ..ensureVisualUpdate();
  }

  /// Replaces the session document and its Workspace (a successful join, or
  /// leaving the Session), then frees the old pair and the renderers of
  /// panes no longer shown. Not called from a document listener.
  void _replaceSession(SessionDocument session) {
    final previousSession = _session;
    final previousWorkspace = _workspace;
    previousSession.removeListener(_onSessionChanged);
    setState(() => _attachSession(session));
    previousWorkspace.dispose();
    previousSession.document.dispose();
    _releaseHiddenRenderers();
  }

  /// Shows workspace [workspaceId] of the current session document in place
  /// of the current one; see the Session paragraph of the overview.
  void _bindWorkspace(String workspaceId) {
    final previous = _workspace;
    setState(() => _workspace = _newWorkspace(workspaceId));
    previous.dispose();
    _releaseHiddenRenderers();
  }

  /// Releases the renderer of every pane the current workspace does not
  /// show; a replaced Workspace does not report its panes as removed.
  void _releaseHiddenRenderers() {
    final shown = _workspace.paneIds.toSet();
    final hidden = [
      for (final id in _renderers.keys)
        if (!shown.contains(id)) id,
    ];
    hidden.forEach(_onPaneRemoved);
  }

  /// Any session document change, local or remote: schedules
  /// [_followMembership]. Remote changes to the shown workspace reach the
  /// panes through [_workspace]'s own listener, and the roster through
  /// SessionNetwork.roster.
  void _onSessionChanged(CrdtChangeOrigin origin) {
    if (_membershipCheckDue) return;
    _membershipCheckDue = true;
    scheduleMicrotask(_followMembership);
  }

  /// Recreates the local workspace if a peer deleted it (PNT-A0015-04),
  /// then rebinds [_workspace] when the local Participant's `workspace` no
  /// longer names it (WKSP-32, WKSP-36, WKSP-37).
  void _followMembership() {
    _membershipCheckDue = false;
    if (!mounted) return;
    if (_session.localWorkspaceMissing) {
      final shown = _workspace.lastShownNodes;
      final document = _session.document;
      _session.restoreLocalWorkspace(
        shown.isNotEmpty
            ? shown
            : createDefaultLayout(
                newId: document.newId,
                actor: document.actorId,
              ),
      );
    }
    final workspaceId = _session.localParticipant?.workspace;
    if (workspaceId != null && workspaceId != _workspace.workspaceId) {
      _bindWorkspace(workspaceId);
    }
  }

  /// Makes [content] the drawn document with a new, empty undo history
  /// (PNT-A0018-05). [_replaceContent] frees the previous pair first. Content
  /// that peers make unusable, and unreadable strokes they send, are logged
  /// whichever way the document was made (LOG-13).
  void _attachContent(ContentDocument content) {
    content.attach(_controller);
    content.onRejected = (error) => unawaited(
      _logSessionError('follow the session content', error, StackTrace.current),
    );
    content.onUnreadable = (count) => unawaited(
      _logger.warn(
        'document.strokes.unreadable',
        arguments: {'count': count, 'source': 'the session'},
      ),
    );
    _content = content;
    _history = EditHistory(
      controller: _controller,
      content: content,
      log: _logger,
    );
    _undoState = Listenable.merge([_controller, _history]);
  }

  /// Replaces the document after a successful Open or join; see
  /// [_attachContent].
  void _replaceContent(ContentDocument content) {
    final previous = _content;
    _history.dispose();
    _attachContent(content);
    previous.dispose();
  }

  /// Undoes the local user's latest gesture (UNDO-1); a no-op when there is
  /// none or a stroke is in progress (UNDO-2, UNDO-4).
  void _undo() => _history.undo();

  /// Redoes the latest undone gesture (UNDO-9), under the same conditions.
  void _redo() => _history.redo();

  /// Releases the renderer of a pane that left the workspace, after the
  /// next frame ([_afterDetach]) so its CanvasView has detached first, and
  /// only if the pane is still not shown: a workspace recreated from the
  /// layout last shown (PNT-A0015-04) shows the same pane ids again, and
  /// their CanvasViews keep the renderer they had.
  void _onPaneRemoved(String paneId) => _afterDetach(() {
    if (mounted && !_workspace.paneIds.contains(paneId)) {
      _renderers.remove(paneId)?.dispose();
    }
  });

  TiledRenderer _rendererFor(String paneId) => _renderers.putIfAbsent(
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
      PaneKind.log => LogPane(
        log: _logger,
        lowest: _workspace.logLowest(pane.id),
        onLowestChanged: (level) => _workspace.setLogLowest(pane.id, level),
      ),
      PaneKind.session => SessionPane(
        network: _network,
        busy: _sessionOperationInProgress,
        onStart: () => _startSession(context),
        onJoin: () => _joinSession(context),
        onLeave: () => _leaveSession(context),
        onJoinWorkspace: (participantId) => _sessionAction(
          context,
          'join the workspace',
          () => _session.joinWorkspace(participantId),
          succeeded: 'workspace.join.succeeded',
          arguments: {'participant': _participantName(participantId)},
        ),
        onLeaveWorkspace: () => _sessionAction(
          context,
          'leave the workspace',
          _session.leaveJoinedWorkspace,
          succeeded: 'workspace.leave.succeeded',
        ),
        onPromote: (participantId) => _sessionAction(
          context,
          'make the participant host',
          () => _network?.promote(participantId),
          succeeded: 'session.promote.succeeded',
          arguments: {'participant': _participantName(participantId)},
        ),
      ),
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

  /// Shows the Session pane the way F1 shows the Manual
  /// ([Workspace.openPane]).
  void _showSessionPane() {
    _workspace.openPane(PaneKind.session);
  }

  /// Start session (MPLY-1, MPLY-2, MPLY-10): see the Session paragraph of
  /// the overview. A cancelled dialog changes nothing; a failure to listen
  /// is logged and shown, and leaves the app outside a Session. The name
  /// and `storedWorkspace` written before listening stay in the
  /// one-Participant session document, where nobody sees them.
  Future<void> _startSession(BuildContext context) async {
    if (_sessionOperationInProgress || _network != null) return;
    final name = await showStartSessionDialog(
      context,
      initialName: _accountName,
    );
    if (name == null) {
      unawaited(_logger.debug('session.start.cancelled'));
      return;
    }
    if (!mounted || _sessionOperationInProgress) return;
    setState(() => _sessionOperationInProgress = true);
    final network = SessionNetwork(
      content: _content.crdt,
      session: _session,
      name: name,
      engine: strokeEngineVersion,
      log: _logger,
    );
    try {
      _session.setLocalName(name);
      final section = DocumentFileContents.workspaceJson(_preservedSections);
      _session.setStoredWorkspace(section == null ? null : jsonEncode(section));
      await network.start(
        bindAddress: widget.sessionBindAddress,
        port: widget.sessionPort,
      );
      if (mounted) {
        _network = network;
        unawaited(
          _logger.info(
            'session.start.succeeded',
            arguments: {'addresses': network.addresses.join(', ')},
          ),
        );
      } else {
        await network.leave();
      }
    } catch (error, stackTrace) {
      await network.leave();
      await _logSessionError('start the session', error, stackTrace);
      if (context.mounted) {
        await showSessionErrorDialog(context, 'start the session', error);
      }
    } finally {
      if (mounted) setState(() => _sessionOperationInProgress = false);
    }
  }

  /// Join session (MPLY-3, MPLY-4, MPLY-8, MPLY-14, WKSP-31): see the
  /// Session paragraph of the overview. The joined documents are new; the
  /// app's documents, file and workspace are replaced only after the join
  /// succeeded, so a refusal (shown with both Engine versions) or a failed
  /// connection changes nothing.
  Future<void> _joinSession(BuildContext context) async {
    if (_sessionOperationInProgress || _network != null) return;
    final request = await showJoinSessionDialog(
      context,
      initialName: _accountName,
    );
    if (request == null) {
      unawaited(_logger.debug('session.join.cancelled'));
      return;
    }
    if (!mounted || _sessionOperationInProgress) return;
    setState(() => _sessionOperationInProgress = true);
    final contentCrdt = _backend.create();
    final session = SessionDocument(_backend.create());
    final network = SessionNetwork(
      content: contentCrdt,
      session: session,
      name: request.name,
      engine: strokeEngineVersion,
      log: _logger,
    );
    // WKSP-11's "workspace that was active when it was opened".
    final loadStored = _settings.settings.loadStoredWorkspaces;
    final active = _workspace.toJson();
    var storedUnusable = false;
    ContentDocument? content;
    try {
      await network.join(
        request.address,
        nodes: () => _joinedWorkspaceNodes(
          session,
          loadStored: loadStored,
          active: active,
          onUnusable: () => storedUnusable = true,
        ),
        bindAddress: widget.sessionBindAddress,
        port: widget.sessionPort,
      );
      content = ContentDocument.adopt(contentCrdt);
      if (!mounted) throw StateError('The app closed while joining.');
    } catch (error, stackTrace) {
      await network.leave();
      if (content != null) {
        content.dispose();
      } else {
        contentCrdt.dispose();
      }
      session.document.dispose();
      if (mounted) setState(() => _sessionOperationInProgress = false);
      if (error is SessionJoinRefused) {
        await _logSessionError('join the session', error, stackTrace);
        if (context.mounted) await showSessionRefusedDialog(context, error);
      } else {
        await _logSessionError('join the session', error, stackTrace);
        if (context.mounted) {
          await showSessionErrorDialog(context, 'join the session', error);
        }
      }
      return;
    }
    _replaceContent(content);
    _documentPath = null;
    _preservedSections = const [];
    _network = network;
    _sessionOperationInProgress = false;
    _replaceSession(session);
    unawaited(
      _logger.info(
        'session.join.succeeded',
        arguments: {'address': request.address},
      ),
    );
    if (storedUnusable) {
      unawaited(
        _logger.warn(
          'workspace.stored.unusable',
          arguments: {'source': 'the session'},
        ),
      );
    }
    if (content.unreadableOnAdopt > 0) {
      unawaited(
        _logger.warn(
          'document.strokes.unreadable',
          arguments: {
            'count': content.unreadableOnAdopt,
            'source': 'the session',
          },
        ),
      );
    }
  }

  /// The joiner's first node table, built after the first sync with ids of
  /// [session]'s document: the Session's `storedWorkspace` when [loadStored]
  /// and it is usable (WKSP-9), else a copy of [active], the workspace
  /// section of the workspace shown before joining, else the Default
  /// workspace (WKSP-10, WKSP-11). [onUnusable] is called when a
  /// `storedWorkspace` was considered but is Unusable, so it can be logged
  /// (LOG-13).
  static LayoutNodes _joinedWorkspaceNodes(
    SessionDocument session, {
    required bool loadStored,
    required Object? active,
    required void Function() onUnusable,
  }) {
    final document = session.document;
    final stored = loadStored ? session.storedWorkspace : null;
    if (stored != null) {
      Object? json;
      try {
        json = jsonDecode(stored);
      } on FormatException {
        // Undecodable is Unusable; reported through onUnusable below.
        json = null;
      }
      final nodes = Workspace.nodesFromJson(json, document);
      if (nodes != null) return nodes;
      onUnusable();
    }
    return Workspace.nodesFromJson(active, document) ??
        createDefaultLayout(newId: document.newId, actor: document.actorId);
  }

  /// Leave session (MPLY-15, MPLY-16, MPLY-18, WKSP-38): see the Session
  /// paragraph of the overview. The content and the shown layout stay; the
  /// pane returns to the not-in-session state, also when leaving failed
  /// (the network is closed either way), and the failure is then shown.
  Future<void> _leaveSession(BuildContext context) async {
    final network = _network;
    if (network == null || _sessionOperationInProgress) return;
    setState(() => _sessionOperationInProgress = true);
    Object? failure;
    try {
      await network.leave();
    } catch (error, stackTrace) {
      failure = error;
      await _logSessionError('leave the session', error, stackTrace);
    }
    if (!mounted) return;
    _network = null;
    _sessionOperationInProgress = false;
    _replaceSession(
      _createSession(
        name: _session.localParticipant?.name ?? '',
        nodes: _session.workspaceNodes(_workspace.workspaceId),
      ),
    );
    if (failure == null) {
      unawaited(_logger.info('session.leave.succeeded'));
    } else if (context.mounted) {
      await showSessionErrorDialog(context, 'leave the session', failure);
    }
  }

  /// The shown name of Participant [participantId], or its id.
  String _participantName(String participantId) {
    final name = _session.participant(participantId)?.name;
    return name == null || name.isEmpty ? participantId : name;
  }

  /// Runs a Session pane action that writes the session document or
  /// promotes, recording [succeeded] with [arguments] when it returns
  /// (LOG-10); a failure (for example joining a workspace that was just
  /// discarded) is logged and shown (LOG-11).
  void _sessionAction(
    BuildContext context,
    String operation,
    void Function() action, {
    required String succeeded,
    Map<String, Object?> arguments = const {},
  }) {
    try {
      action();
      unawaited(_logger.info(succeeded, arguments: arguments));
    } catch (error, stackTrace) {
      unawaited(_reportSessionError(context, operation, error, stackTrace));
    }
  }

  /// Logs a Session failure, then shows it if [context] is still mounted.
  Future<void> _reportSessionError(
    BuildContext context,
    String operation,
    Object error,
    StackTrace stackTrace,
  ) async {
    await _logSessionError(operation, error, stackTrace);
    if (context.mounted) {
      await showSessionErrorDialog(context, operation, error);
    }
  }

  Future<void> _logSessionError(
    String operation,
    Object error,
    StackTrace stackTrace,
  ) => _logger.error(
    'session.operation.failed',
    arguments: {'operation': operation, 'error': error.toString()},
    stackTrace: stackTrace.toString(),
  );

  /// Releases app-owned settings, logger, renderers, viewports, help state,
  /// undo history, the Session and both documents. [DocumentFileService] is
  /// not disposed; it may be injected and holds no resources.
  @override
  void dispose() {
    // leave() detaches from both documents before its first await, so they
    // can be freed right after.
    final network = _network;
    if (network != null) unawaited(network.leave());
    _lifecycle.dispose();
    _settings.dispose();
    for (final renderer in _renderers.values) {
      renderer.dispose();
    }
    _debugOptions.dispose();
    _helpState.dispose();
    _history.dispose();
    _content.dispose();
    _controller.dispose();
    _workspace.dispose();
    _session.removeListener(_onSessionChanged);
    _session.document.dispose();
    if (_ownsLogger) _logger.dispose();
    super.dispose();
  }

  /// Runs the Open flow described in the overview at the top of this file.
  ///
  /// [context] is the AppBar's [Builder] context (see [build]); it must be
  /// below the [MaterialApp] so the picker and error dialogs can find a
  /// Navigator. A cancelled picker (null path) is not an error and changes
  /// nothing. Any other failure, including the FormatException or
  /// StrokeEngineMismatch from [DocumentFileContents.read] and I/O errors
  /// from [DocumentFileService.readDocument], is reported through
  /// [_showFileOperationError]. The `mounted` checks guard the awaits: the
  /// widget can be disposed while a dialog or file read is pending.
  Future<void> _openDocument(BuildContext context) async {
    if (_fileOperationInProgress) return;
    setState(() => _fileOperationInProgress = true);
    String? path;
    try {
      path = await _fileService.chooseOpenPath(context);
      if (path == null) {
        unawaited(_logger.debug('document.open.cancelled'));
        return;
      }
      if (!mounted) return;
      final bytes = await _fileService.readDocument(path);
      final file = DocumentFileContents.read(bytes, _backend);
      if (!mounted) {
        file.content.dispose();
        return;
      }
      _replaceContent(file.content);
      _preservedSections = file.sections;
      final storedUnusable =
          _settings.settings.loadStoredWorkspaces &&
          !_workspace.applyJson(file.workspaceSection) &&
          file.hasWorkspaceSection;
      _documentPath = path;
      unawaited(
        _logger.info('document.open.succeeded', arguments: {'path': path}),
      );
      if (file.content.unreadableOnAdopt > 0) {
        unawaited(
          _logger.warn(
            'document.strokes.unreadable',
            arguments: {
              'count': file.content.unreadableOnAdopt,
              'source': path,
            },
          ),
        );
      }
      if (storedUnusable) {
        unawaited(
          _logger.warn(
            'workspace.stored.unusable',
            arguments: {'source': path},
          ),
        );
      }
    } catch (error, stackTrace) {
      await _logFileOperationError('open', error, stackTrace, path: path);
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
  /// before showing details if the action context remains mounted). If a
  /// path is already associated the picker is skipped; cancelling it changes
  /// nothing and is logged as a debug record (DOCF-8, LOG-12).
  Future<void> _saveDocument(BuildContext context) async {
    if (_fileOperationInProgress) return;
    setState(() => _fileOperationInProgress = true);
    String? path;
    try {
      path = _documentPath;
      path ??= await _fileService.chooseSavePath(context, 'Untitled.paint');
      if (path == null) {
        unawaited(_logger.debug('document.save.cancelled'));
        return;
      }
      if (!mounted) return;
      final bytes = DocumentFileContents.encode(_content, _preservedSections);
      await _fileService.writeDocument(path, bytes);
      if (mounted) _documentPath = path;
      unawaited(
        _logger.info('document.save.succeeded', arguments: {'path': path}),
      );
    } catch (error, stackTrace) {
      await _logFileOperationError('save', error, stackTrace, path: path);
      if (context.mounted) {
        await _showFileOperationError(context, 'save', error, stackTrace);
      }
    } finally {
      if (mounted) setState(() => _fileOperationInProgress = false);
    }
  }

  /// Writes the current workspace into the opened document's file (WKSP-2).
  ///
  /// Only the file's workspace section changes: the file is read, its
  /// section replaced, and the bytes written back
  /// ([DocumentFileContents.withWorkspaceSection]), so strokes the user has
  /// not saved stay out of the file. Needs [_documentPath]; the Flash button
  /// is disabled until the document has a file. Failures are reported like
  /// Open and Save failures.
  Future<void> _flashWorkspace(BuildContext context) async {
    if (_fileOperationInProgress) return;
    final path = _documentPath;
    if (path == null) return;
    setState(() => _fileOperationInProgress = true);
    try {
      final section = _workspace.toJson();
      if (section == null) {
        throw StateError('The workspace shows no pane to flash.');
      }
      final bytes = await _fileService.readDocument(path);
      await _fileService.writeDocument(
        path,
        DocumentFileContents.withWorkspaceSection(bytes, section),
      );
      _preservedSections = DocumentFileContents.withWorkspace(
        _preservedSections,
        section,
      );
      unawaited(
        _logger.info('document.flash.succeeded', arguments: {'path': path}),
      );
    } catch (error, stackTrace) {
      await _logFileOperationError('flash', error, stackTrace, path: path);
      if (context.mounted) {
        await _showFileOperationError(context, 'flash', error, stackTrace);
      }
    } finally {
      if (mounted) setState(() => _fileOperationInProgress = false);
    }
  }

  /// Records a failed open, save or flash, naming [path] when one was chosen
  /// (LOG-11), before any mounted-context check.
  ///
  /// This keeps failures in the shared history if the pane was removed while
  /// I/O was pending.
  Future<void> _logFileOperationError(
    String operation,
    Object error,
    StackTrace stackTrace, {
    required String? path,
  }) => _logger.error(
    'document.operation.failed',
    arguments: {
      'operation': operation,
      'error': error.toString(),
      'path': ?path,
    },
    stackTrace: stackTrace.toString(),
  );

  /// Shows the failure and its reason in a popup with expandable details
  /// (docs/spec/document-file.md DOCF-6, DOCF-7).
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
                // docs/spec/keybinds.md KEY-3. Text fields that have focus
                // handle these keys themselves first.
                const SingleActivator(LogicalKeyboardKey.keyZ, meta: true):
                    _undo,
                const SingleActivator(
                  LogicalKeyboardKey.keyZ,
                  meta: true,
                  shift: true,
                ): _redo,
              },
              child: Focus(autofocus: true, child: child!),
            ),
          ),
          home: Builder(
            builder: (context) => Scaffold(
              appBar: AppBar(
                title: const Text('Painter'),
                actions: [
                  ListenableBuilder(
                    listenable: _undoState,
                    builder: (context, _) => PainterActionButton(
                      icon: Icons.undo,
                      label: 'Undo',
                      topic: HelpIds.undo,
                      onPressed: _history.canUndo ? _undo : null,
                    ),
                  ),
                  ListenableBuilder(
                    listenable: _undoState,
                    builder: (context, _) => PainterActionButton(
                      icon: Icons.redo,
                      label: 'Redo',
                      topic: HelpIds.redo,
                      onPressed: _history.canRedo ? _redo : null,
                    ),
                  ),
                  PainterActionButton(
                    icon: Icons.folder_open,
                    label: 'Open',
                    topic: HelpIds.openDocument,
                    onPressed:
                        _fileOperationInProgress ||
                            _network != null ||
                            _sessionOperationInProgress
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
                  PainterActionButton(
                    icon: PaneKind.session.icon,
                    label: 'Session',
                    topic: HelpIds.openSession,
                    onPressed: _showSessionPane,
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
