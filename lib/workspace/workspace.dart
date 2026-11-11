// What: Workspace, the observable view and editor of one workspace's Layout
//   tree as stored in the session document: it projects the node table,
//   performs pane edits through LayoutPlanner, keeps a live
//   CanvasViewportController per Canvas pane in step with the stored view,
//   and reads and writes the workspace section a Flash stores.
// Why: Members of a workspace edit it together through a CRDT
//   (docs/decisions/009-shared-workspaces.md), so the layout lives in the
//   session document and every peer shows the same projection of it
//   (docs/decisions/010-pane-layout-tree.md). One model owns the CRDT side so
//   the pane UI, F1 manual and Session pane placement, file Open/Flash and
//   joining a Session share the same rules.
// Coupled to: layout_tree.dart (projection and the Layout tree overview),
//   layout_ops.dart (edit planning and LayoutWrite), layout_flash.dart (the
//   workspace section), pane_kind.dart (modes),
//   ../session/session_document.dart (reads the node table; its schema and
//   paths), ../crdt/crdt_document.dart (writes and change notifications),
//   ../canvas/canvas_viewport.dart (a Canvas pane's
//   view), ../help/manual_catalog.dart (a Manual pane's page),
//   ../ui/pane_system.dart (draws a Workspace) and ../main.dart (creates one
//   per workspace the local Participant is a Member of, applies and flashes
//   sections, builds a joiner's first node table with
//   [Workspace.nodesFromJson], disposes per-pane renderers through
//   [Workspace.onPaneRemoved]).
//
// ---------------------------------------------------------------------------
// Workspace overview
//
// What it is: a ChangeNotifier over one workspace of a SessionDocument, whose
// `nodes` map is at `['workspaces', <id>, 'nodes']` (PNT-A0015-02). It holds
// a copy of the node table and its projection (projectLayout); the pane UI
// reads only the projection.
//
// Data flow: an edit asks LayoutPlanner for writes against the current
// projection, translates them into put/putMap/delete calls on the document,
// applies them to the local table copy, re-projects, and commits. Every
// document change, local or remote, re-reads the table and re-projects, so a
// remote edit shows exactly like a local one (WKSP-33, WKSP-35). Listeners
// are notified only when something besides a Canvas view changed: views
// reach their panes through the live controllers instead.
//
// Canvas views (PNT-A0015-05): a Canvas pane's live CanvasViewportController
// is the pane's view while it is shown. A local view change marks the pane
// dirty; one shared timer writes every dirty view and commits at most every
// [viewCommitInterval], and once more after the last change. A remote change
// to a view calls setView on the live controller with local tracking off, so
// it is not written back. A dirty pane ignores remote views until its own
// view is committed, which then wins. Before any other edit the dirty views
// are written first, so add and swap copy the views the user sees. Splitter
// drags commit on the same timer.
//
// Per-mode state stays in each pane's `state` map across mode changes
// (PANE-20). Changes to a Workspace never touch the content document, so
// they are neither document modifications nor undo steps (WKSP-5, WKSP-6).
//
// Persistence: [Workspace.toJson] is the version 2 section of PNT-A0015-07
// built from the projection with live views. [Workspace.applyJson] replaces
// the node table only when the whole section is usable (WKSP-11, WKSP-12).
// ---------------------------------------------------------------------------

import 'dart:async';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';

import '../canvas/canvas_viewport.dart';
import '../crdt/crdt_document.dart';
import '../help/manual_catalog.dart';
import '../session/session_document.dart';
import 'layout_flash.dart';
import 'layout_ops.dart';
import 'layout_ops.dart' as ops show canAdd, canJoin, canSwap;
import 'layout_tree.dart';
import 'pane_kind.dart';

/// The longest a local view change or splitter drag waits before it is
/// committed to the session document (PNT-A0015-05).
const Duration viewCommitInterval = Duration(milliseconds: 50);

/// Stores [value] at [path] of [document] without committing: maps become
/// CRDT maps (replacing what was there), null deletes the key, and other
/// leaves are put as they are. Lists are outside the CRDT port and are
/// skipped; no Per-mode state this build reads holds one.
void _putLayoutValue(CrdtDocument document, List<String> path, Object? value) {
  switch (value) {
    case null:
      document.delete(path);
    case Map():
      document.putMap(path);
      for (final entry in value.entries) {
        final key = entry.key;
        if (key is String && entry.value != null) {
          _putLayoutValue(document, [...path, key], entry.value);
        }
      }
    case List():
      break;
    default:
      document.put(path, value);
  }
}

/// Translates [writes] into edits of the `nodes` map at [nodesPath] of
/// [document], without committing; the CRDT counterpart of
/// applyLayoutWrites in layout_ops.dart, which must stay equivalent to it.
void _writeLayoutWrites(
  CrdtDocument document,
  List<String> nodesPath,
  Iterable<LayoutWrite> writes,
) {
  for (final write in writes) {
    final node = [...nodesPath, write.node];
    switch (write) {
      case CreateNode(:final fields):
        _putLayoutValue(document, node, fields);
      case SetNodeField(:final field, :final value):
        if (document.get(node) is! CrdtMap) document.putMap(node);
        _putLayoutValue(document, [...node, field], value);
      case SetModeState(:final mode, :final state):
        if (document.get(node) is! CrdtMap) document.putMap(node);
        final states = [...node, LayoutField.state];
        if (document.get(states) is! CrdtMap) document.putMap(states);
        _putLayoutValue(document, [...states, mode], state);
    }
  }
}

/// The panes of one workspace of the session document. See the overview at
/// the top of this file.
class Workspace extends ChangeNotifier {
  /// Shows and edits workspace [workspaceId] of [session]. Its `nodes` map
  /// should exist; while it is absent (not yet synced, or discarded) the
  /// workspace shows no pane. [onPaneRemoved] is told the id of every pane
  /// that disappears from the projection, whoever removed it, so its owner
  /// can release per-pane resources. [afterDetach] decides when the live
  /// views of vanished panes, and of every pane on [dispose], are disposed:
  /// it is given the disposal and runs it once the widgets showing those
  /// panes have detached, so a pointer event arriving before the rebuild
  /// cannot reach a disposed controller. main.dart passes a post-frame
  /// callback; null disposes at once, for models without widgets.
  Workspace({
    required SessionDocument session,
    required this.workspaceId,
    this.onPaneRemoved,
    this.afterDetach,
  }) : _session = session,
       _document = session.document,
       _nodesPath = SessionDocument.nodesPath(workspaceId),
       _planner = LayoutPlanner(
         newId: session.document.newId,
         actor: session.document.actorId,
       ) {
    _table = _session.workspaceNodes(workspaceId);
    _layout = projectLayout(_table);
    if (_layout.panes.isNotEmpty) _lastShown = _table;
    _signature = _describe(_layout);
    _document.addListener(_onDocumentChanged);
  }

  /// The id of the shown workspace in the session document's `workspaces`.
  final String workspaceId;

  final ValueChanged<String>? onPaneRemoved;

  final void Function(VoidCallback dispose)? afterDetach;

  final SessionDocument _session;
  final CrdtDocument _document;
  final List<String> _nodesPath;
  final LayoutPlanner _planner;

  /// The last table whose projection showed a pane; empty until one did.
  LayoutNodes _lastShown = const {};

  /// A copy of the last node table that showed at least one pane. main.dart
  /// recreates a workspace deleted under it from this
  /// (docs/decisions/009-shared-workspaces.md PNT-A0015-04), so the
  /// workspace area never stays blank. Empty if no pane was ever shown.
  LayoutNodes get lastShownNodes => _copyTable(_lastShown);

  /// Copy of the stored table; replaced, never mutated, so [_layout] (which
  /// keeps a reference to it for planning) stays consistent.
  late LayoutNodes _table;
  late LayoutProjection _layout;

  /// What listeners see of [_layout]; see [_describe].
  late String _signature;

  /// Live views of Canvas panes, created on first request.
  final Map<String, CanvasViewportController> _viewports = {};

  /// Panes whose live view changed locally and is not yet written.
  final Set<String> _dirtyViews = {};

  /// Whether writes were made to the document since the last commit.
  bool _uncommitted = false;

  /// True while a stored view is copied into a live controller, so that the
  /// change is not mistaken for a local one and written back.
  bool _applyingStoredView = false;

  Timer? _commitTimer;

  /// The shown layout: panes with unit rectangles and splitters.
  LayoutProjection get layout => _layout;

  /// Shown pane ids in tree order.
  List<String> get paneIds => [for (final pane in _layout.panes) pane.id];

  int get paneCount => _layout.panes.length;

  /// The unit rectangle of shown pane [id]: (0, 0) is the workspace's top
  /// left and (1, 1) its bottom right.
  Rect rectOf(String id) => _layout.pane(id)!.rect;

  /// The Pane Mode of pane [id]. A mode this build does not know (written
  /// by a newer peer or a malformed merge) shows as Canvas, the mode of the
  /// Default workspace.
  PaneKind kindOf(String id) =>
      PaneKind.values.asNameMap()[_layout.pane(id)?.mode] ?? PaneKind.canvas;

  /// The first shown pane in Canvas mode, or null.
  String? get firstCanvasPaneId {
    for (final id in paneIds) {
      if (kindOf(id) == PaneKind.canvas) return id;
    }
    return null;
  }

  /// The live Canvas view of shown pane [id], created from its stored Canvas
  /// state (or the default view) on first request. It stays the pane's view
  /// across mode changes and is disposed when the pane disappears.
  CanvasViewportController canvasViewport(String id) {
    final existing = _viewports[id];
    if (existing != null) return existing;
    if (_layout.pane(id) == null) {
      throw ArgumentError.value(id, 'id', 'is not a shown pane');
    }
    final viewport = CanvasViewportController();
    _viewports[id] = viewport;
    _showStoredView(id, viewport);
    viewport.addListener(() => _onViewChanged(id));
    return viewport;
  }

  /// The article shown by pane [id] in Manual mode; the general article when
  /// the pane has no usable Manual state.
  HelpId manualHelpId(String id) {
    final state = _layout.pane(id)?.state[PaneKind.manual.name];
    final help = state is Map ? state['help'] : null;
    return HelpId.values.asNameMap()[help] ?? HelpId.general;
  }

  /// Selects [helpId] in pane [id]'s Manual state.
  void setManualHelpId(String id, HelpId helpId) {
    if (_layout.pane(id) == null || manualHelpId(id) == helpId) return;
    _edit(
      (layout) => _planner.setModeState(layout, id, PaneKind.manual.name, {
        'help': helpId.name,
      }),
    );
  }

  /// Puts pane [id] in [kind]; the states of every mode stay in the pane
  /// (PANE-20).
  void setKind(String id, PaneKind kind) {
    if (_layout.pane(id) == null || _layout.pane(id)!.mode == kind.name) {
      return;
    }
    _edit((layout) => _planner.setMode(layout, id, kind.name));
  }

  /// Whether 'add' is enabled on [edge] of pane [id] (PANE-27).
  bool canAdd(String id, PaneEdge edge) => ops.canAdd(_layout, id, edge);

  /// Whether 'join' is enabled on [edge] of pane [id] (PANE-14, PANE-25).
  bool canJoin(String id, PaneEdge edge) => ops.canJoin(_layout, id, edge);

  /// Whether 'swap' is enabled on [edge] of pane [id] (PANE-14).
  bool canSwap(String id, PaneEdge edge) => ops.canSwap(_layout, id, edge);

  /// The Neighbor across [edge] of pane [id], or null.
  String? neighborOf(String id, PaneEdge edge) => _layout.neighbor(id, edge);

  /// Adds a pane against [edge] of pane [id], in the same mode with a copy of
  /// its Per-mode states (PANE-13). Returns the new pane's id, or null when
  /// 'add' is disabled there (PANE-27).
  String? add(String id, PaneEdge edge) {
    String? added;
    _edit((layout) {
      final writes = _planner.add(layout, id, edge);
      if (writes != null) added = _addedPane(writes);
      return writes;
    });
    return added;
  }

  /// Joins the Neighbor across [edge] into pane [id] (PANE-15). Returns
  /// whether the join was allowed (PANE-14, PANE-25).
  bool join(String id, PaneEdge edge) =>
      _edit((layout) => _planner.join(layout, id, edge));

  /// Exchanges the mode and Per-mode states of pane [id] and its Neighbor
  /// across [edge], leaving both rectangles unchanged (PANE-16). Returns
  /// whether a Neighbor existed.
  bool swap(String id, PaneEdge edge) =>
      _edit((layout) => _planner.swap(layout, id, edge));

  /// Every splitter of the shown layout.
  List<LayoutSplitter> get splitters => _layout.splitters;

  /// Drags [splitter] by [delta], a fraction of the workspace extent across
  /// it, clamped so every pane keeps 10% of the workspace extent in the drag
  /// direction (PANE-26). The split is looked up again in the current
  /// layout, so several updates between frames each apply to the position the
  /// previous one produced. The change is shown at once and committed on the
  /// view timer (PNT-A0015-05).
  void moveSplitter(LayoutSplitter splitter, double delta) {
    final writes = _planner.moveSplitter(_layout, splitter, delta);
    if (writes == null || writes.isEmpty) return;
    _stage(writes);
    _scheduleCommit();
  }

  /// Shows [helpId] in a Manual pane: the first existing one, else a pane
  /// placed by [openPane]'s rule. Returns the id of the pane that shows the
  /// page, or null when the workspace shows no pane.
  String? openManual(HelpId helpId) {
    final existing = _firstPaneOf(PaneKind.manual);
    if (existing != null) {
      setManualHelpId(existing, helpId);
      return existing;
    }
    return _placePane(PaneKind.manual, state: {'help': helpId.name});
  }

  /// Shows a pane in [kind]: the first existing one, else a new pane right
  /// of the widest pane that allows it, else the widest pane itself, put in
  /// [kind]. F1 uses it through [openManual]; main.dart's AppBar 'Session'
  /// button uses it for [PaneKind.session]. Returns the pane's id, or null
  /// when the workspace shows no pane.
  String? openPane(PaneKind kind) => _firstPaneOf(kind) ?? _placePane(kind);

  String? _firstPaneOf(PaneKind kind) {
    for (final id in paneIds) {
      if (kindOf(id) == kind) return id;
    }
    return null;
  }

  /// The placement rule of [openPane] for a [kind] no pane shows yet; also
  /// stores [state] as the pane's state for [kind], in the same commit.
  String? _placePane(PaneKind kind, {Map<String, Object?>? state}) {
    if (_layout.panes.isEmpty) return null;
    final order = paneIds;
    final byWidth = [..._layout.panes]
      ..sort((a, b) {
        // Widths within layoutEpsilon count as equal, so rounding in the
        // projection does not decide; tree order does.
        final difference = b.rect.width - a.rect.width;
        if (difference.abs() > layoutEpsilon) return difference.sign.toInt();
        return order.indexOf(a.id) - order.indexOf(b.id);
      });
    _stageDirtyViews();
    String? target;
    for (final pane in byWidth) {
      final writes = _planner.add(_layout, pane.id, PaneEdge.right);
      if (writes == null) continue;
      target = _addedPane(writes);
      _stage(writes);
      break;
    }
    final id = target ?? byWidth.first.id;
    _stage([
      ..._planner.setMode(_layout, id, kind.name)!,
      if (state != null)
        ..._planner.setModeState(_layout, id, kind.name, state)!,
    ]);
    _commitNow();
    return id;
  }

  /// The workspace section a Flash writes (WKSP-2, PNT-A0015-07): the shown
  /// layout with each live view as it is now, committed or not. Null only
  /// while the workspace shows no pane. Changes nothing (WKSP-29).
  Map<String, Object?>? toJson() {
    if (_dirtyViews.isEmpty) return layoutToFlashJson(_layout);
    final table = _copyTable(_table);
    applyLayoutWrites(table, _dirtyViewWrites());
    return layoutToFlashJson(projectLayout(table));
  }

  /// Replaces this workspace's node table with the stored workspace in
  /// [json] and returns true, or returns false and changes nothing when the
  /// section is Unusable (WKSP-11, WKSP-12); see [nodesFromJson]. Every
  /// shown pane is replaced, so [onPaneRemoved] hears about each of them.
  bool applyJson(Object? json) {
    final nodes = nodesFromJson(json, _document);
    if (nodes == null) return false;
    _dirtyViews.clear();
    // Delete the old nodes and create the new ones under fresh ids. The
    // `root` map is kept and rewritten field by field rather than replaced:
    // every peer may hold it, and only a document's creator creates maps
    // that others could also create (docs/decisions/007-crdt-automerge.md).
    for (final id in _document.keys(_nodesPath)) {
      if (id != layoutRootId) _document.delete([..._nodesPath, id]);
    }
    final rootPath = [..._nodesPath, layoutRootId];
    final root = nodes[layoutRootId]!;
    if (_document.get(rootPath) is CrdtMap) {
      for (final field in _document.keys(rootPath)) {
        if (!root.containsKey(field)) _document.delete([...rootPath, field]);
      }
      for (final field in root.entries) {
        _putLayoutValue(_document, [...rootPath, field.key], field.value);
      }
    } else {
      _putLayoutValue(_document, rootPath, root);
    }
    for (final entry in nodes.entries) {
      if (entry.key == layoutRootId) continue;
      _putLayoutValue(_document, [..._nodesPath, entry.key], entry.value);
    }
    _uncommitted = true;
    _table = nodes;
    _refresh();
    _commitNow();
    return true;
  }

  /// A fresh node table for [document] holding the stored workspace in
  /// [json], or null when the section is Unusable: not version 2, not
  /// readable in full, naming a mode this build does not have, or holding a
  /// state that mode cannot read. [applyJson] uses it, and main.dart builds
  /// a joined Session's first workspace with it (WKSP-9, WKSP-11).
  static LayoutNodes? nodesFromJson(Object? json, CrdtDocument document) =>
      layoutFromFlashJson(
        json,
        knownModes: {for (final kind in PaneKind.values) kind.name},
        newId: document.newId,
        actor: document.actorId,
        isUsableState: _isUsableState,
      );

  @override
  void dispose() {
    _commitTimer?.cancel();
    _document.removeListener(_onDocumentChanged);
    final retired = List.of(_viewports.values);
    _viewports.clear();
    _retire(retired);
    super.dispose();
  }

  /// Disposes [viewports], the live views of panes no longer shown, through
  /// [afterDetach]. Until then their changes are ignored ([_onViewChanged]).
  void _retire(List<CanvasViewportController> viewports) {
    if (viewports.isEmpty) return;
    void disposeAll() {
      for (final viewport in viewports) {
        viewport.dispose();
      }
    }

    final schedule = afterDetach;
    schedule == null ? disposeAll() : schedule(disposeAll);
  }

  // -------------------------------------------------------------------------
  // Editing
  // -------------------------------------------------------------------------

  /// Runs one discrete edit: writes pending views first, then the writes
  /// [plan] makes against the resulting layout, and commits. Returns whether
  /// [plan] allowed the edit.
  bool _edit(List<LayoutWrite>? Function(LayoutProjection layout) plan) {
    _stageDirtyViews();
    final writes = plan(_layout);
    if (writes != null) _stage(writes);
    _commitNow();
    return writes != null;
  }

  /// Writes [writes] to the document without committing, applies them to the
  /// local table and re-projects.
  void _stage(List<LayoutWrite> writes) {
    if (writes.isEmpty) return;
    _writeLayoutWrites(_document, _nodesPath, writes);
    _uncommitted = true;
    final next = _copyTable(_table);
    applyLayoutWrites(next, writes);
    _table = next;
    _refresh();
  }

  /// The id of the pane a planned add creates.
  static String _addedPane(List<LayoutWrite> writes) => writes
      .whereType<CreateNode>()
      .firstWhere((write) => write.fields[LayoutField.kind] == LayoutField.pane)
      .node;

  /// Commits writes made since the last commit, if any. The document then
  /// notifies [_onDocumentChanged], which re-reads the table.
  void _commitNow() {
    _commitTimer?.cancel();
    _commitTimer = null;
    if (!_uncommitted) return;
    _uncommitted = false;
    _document.commit(message: 'workspace');
  }

  /// Starts the shared view timer unless it runs (PNT-A0015-05): changes made
  /// while it runs are committed together when it fires, so commits are at
  /// least [viewCommitInterval] apart and the last change is committed
  /// within that interval.
  void _scheduleCommit() {
    _commitTimer ??= Timer(viewCommitInterval, () {
      _commitTimer = null;
      _stageDirtyViews();
      _commitNow();
    });
  }

  // -------------------------------------------------------------------------
  // Canvas views
  // -------------------------------------------------------------------------

  void _onViewChanged(String id) {
    // A retired view (its pane vanished, or this workspace was disposed)
    // may still get input before its widgets detach; it is not stored.
    if (_applyingStoredView || !_viewports.containsKey(id)) return;
    _dirtyViews.add(id);
    _scheduleCommit();
  }

  /// Writes storing each dirty, shown pane's live view as its Canvas state.
  List<LayoutWrite> _dirtyViewWrites() => [
    for (final id in _dirtyViews)
      if (_viewports[id] case final viewport?)
        ...?_planner.setModeState(
          _layout,
          id,
          PaneKind.canvas.name,
          viewport.toJson(),
        ),
  ];

  /// Stages the dirty views and marks them clean.
  void _stageDirtyViews() {
    if (_dirtyViews.isEmpty) return;
    final writes = _dirtyViewWrites();
    _dirtyViews.clear();
    _stage(writes);
  }

  /// Sets [viewport] to pane [id]'s stored Canvas state, or the default view
  /// when it has none or it is malformed, without marking the pane dirty.
  void _showStoredView(String id, CanvasViewportController viewport) {
    final stored = CanvasViewportController.fromJson(
      _layout.pane(id)?.state[PaneKind.canvas.name],
    );
    final center = stored?.center ?? CanvasViewportController.defaultCenter;
    final extent = stored?.extent ?? CanvasViewportController.defaultExtent;
    final rotation = stored?.rotation ?? 0.0;
    stored?.dispose();
    if (viewport.center == center &&
        viewport.extent == extent &&
        viewport.rotation == rotation) {
      return;
    }
    _applyingStoredView = true;
    try {
      viewport.setView(center: center, extent: extent, rotation: rotation);
    } finally {
      _applyingStoredView = false;
    }
  }

  // -------------------------------------------------------------------------
  // Projection
  // -------------------------------------------------------------------------

  void _onDocumentChanged(CrdtChangeOrigin origin) {
    _table = _session.workspaceNodes(workspaceId);
    _refresh();
  }

  /// Re-projects [_table]: moves clean live views to their stored state,
  /// drops panes that no longer show, notifies listeners when what they see
  /// changed, and then reports removed panes to [onPaneRemoved].
  void _refresh() {
    final before = paneIds.toSet();
    _layout = projectLayout(_table);
    if (_layout.panes.isNotEmpty) _lastShown = _table;
    final removed = before.difference(paneIds.toSet());
    final retired = <CanvasViewportController>[];
    for (final id in removed) {
      final viewport = _viewports.remove(id);
      if (viewport != null) retired.add(viewport);
      _dirtyViews.remove(id);
    }
    for (final entry in _viewports.entries) {
      if (!_dirtyViews.contains(entry.key)) {
        _showStoredView(entry.key, entry.value);
      }
    }
    final signature = _describe(_layout);
    if (signature != _signature) {
      _signature = signature;
      notifyListeners();
    }
    for (final id in removed) {
      onPaneRemoved?.call(id);
    }
    _retire(retired);
  }

  /// Everything the pane UI shows of [layout] except Canvas views, which
  /// reach it through the live controllers; compared to skip notifications
  /// for view-only changes.
  static String _describe(LayoutProjection layout) {
    final out = StringBuffer();
    for (final pane in layout.panes) {
      final r = pane.rect;
      final states = {...pane.state}..remove(PaneKind.canvas.name);
      out.writeln(
        '${pane.id} ${r.left} ${r.top} ${r.right} ${r.bottom} '
        '${pane.mode} $states',
      );
    }
    for (final s in layout.splitters) {
      out.writeln('${s.key} ${s.position} ${s.start} ${s.end}');
    }
    return out.toString();
  }

  static LayoutNodes _copyTable(LayoutNodes table) => {
    for (final entry in table.entries)
      entry.key: copyLayoutValue(entry.value)! as Map<String, Object?>,
  };

  /// Whether a section's [state] for [mode] is one this build can read
  /// (docs/spec/workspace.md, Unusable): a Canvas view
  /// (docs/decisions/011-relative-canvas-view.md) or a Manual page name.
  /// Modes that keep no state accept none.
  static bool _isUsableState(String mode, Map<String, Object?> state) {
    switch (PaneKind.values.asNameMap()[mode]) {
      case PaneKind.canvas:
        final view = CanvasViewportController.fromJson(state);
        view?.dispose();
        return view != null;
      case PaneKind.manual:
        return HelpId.values.asNameMap().containsKey(state['help']);
      case PaneKind.diagnostics ||
          PaneKind.settings ||
          PaneKind.log ||
          PaneKind.session ||
          null:
        return false;
    }
  }
}
