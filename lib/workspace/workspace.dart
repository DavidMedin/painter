// What: Workspace, the observable set of panes for one document (layout, a
//   Pane Mode per pane, and Per-mode state), and the PaneModeState classes for
//   the modes that keep state. It also reads and writes the workspace section
//   of a document file.
// Why: docs/spec/panes.md and docs/spec/workspace.md define layout operations
//   (add, join, swap, splitter drags), mode changes that keep state, and
//   per-file persistence. One model owns all of it so the pane UI, F1 manual
//   placement, and file open/Flash share the same rules.
// Coupled to: pane_layout.dart (geometry), pane_kind.dart (modes),
//   ../ui/pane_system.dart (renders and edits a Workspace),
//   ../canvas/canvas_controller.dart (CanvasViewportController is a Canvas
//   pane's view), ../help/manual_catalog.dart (a Manual pane's page), and
//   ../main.dart (creates the Workspace, applies and flashes sections, and
//   disposes per-pane renderers through [Workspace.onPaneRemoved]).
//
// ---------------------------------------------------------------------------
// Workspace overview
//
// What it is: a ChangeNotifier holding a PaneLayout, and for each pane its
// current PaneKind plus a PaneModeState for each mode the pane has used.
// Canvas keeps a view (pan, zoom, rotation) and Manual keeps its selected
// page; the other modes keep no state.
//
// Why state is per pane and per mode: changing a pane to Settings and back to
// Canvas must restore its view (PANE-20, CNVS-6), so a mode change only
// switches [WorkspacePane.kind]; the states stay in the pane. Add copies a
// pane's states into the new pane (PANE-13) and swap exchanges them between
// two panes (PANE-16). A pane removed by join disposes its states.
//
// Persistence (docs/spec/workspace.md, docs/decisions/006-workspace-in-file.md):
// [Workspace.toJson] writes the section that a Flash stores. Layouts are unit
// fractions, so a stored workspace fits any window size. [Workspace.applyJson]
// replaces the whole workspace only if the section is readable in full and
// names only known modes; otherwise it changes nothing and returns false
// (WKSP-11, WKSP-12). Changes to a Workspace are never document changes and
// are not recorded in undo history (WKSP-5, WKSP-6).
//
// Section shape (version 1):
//   {"version": 1, "panes": [{"id": 0, "left": 0, "top": 0, "right": 1,
//     "bottom": 1, "mode": "canvas",
//     "state": {"canvas": {"pan": {"dx": 0, "dy": 0}, "zoom": 1,
//                          "rotation": 0},
//               "manual": {"help": "general"}}}]}
// ---------------------------------------------------------------------------

import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../canvas/canvas_controller.dart';
import '../help/manual_catalog.dart';
import 'pane_kind.dart';
import 'pane_layout.dart';

/// The workspace section version written and accepted by [Workspace].
const int workspaceSectionVersion = 1;

/// State a pane keeps for one Pane Mode, which survives mode changes.
sealed class PaneModeState {
  /// An independent copy, so a new pane starts where this one is.
  PaneModeState copy();

  /// The value stored under this mode's name in a workspace section.
  Object? toJson();

  /// Releases resources; called when the pane that holds the state goes away.
  void dispose() {}
}

/// A Canvas pane's view of the canvas.
final class CanvasModeState extends PaneModeState {
  CanvasModeState([CanvasViewportController? viewport])
    : viewport = viewport ?? CanvasViewportController();

  final CanvasViewportController viewport;

  @override
  CanvasModeState copy() => CanvasModeState(viewport.copy());

  @override
  Object? toJson() => viewport.toJson();

  @override
  void dispose() => viewport.dispose();
}

/// A Manual pane's selected article.
final class ManualModeState extends PaneModeState {
  ManualModeState([this.helpId = HelpId.general]);

  HelpId helpId;

  @override
  ManualModeState copy() => ManualModeState(helpId);

  @override
  Object? toJson() => {'help': helpId.name};
}

/// One pane's mode and the state it keeps per mode.
class WorkspacePane {
  WorkspacePane(this.id, this.kind, [Map<PaneKind, PaneModeState>? states])
    : states = states ?? {};

  final int id;
  PaneKind kind;
  Map<PaneKind, PaneModeState> states;

  /// Deep copy of [states] for a new pane (PANE-13).
  Map<PaneKind, PaneModeState> copyStates() => {
    for (final entry in states.entries) entry.key: entry.value.copy(),
  };

  void disposeStates() {
    for (final state in states.values) {
      state.dispose();
    }
  }
}

/// The panes of one open document. See the overview at the top of this file.
class Workspace extends ChangeNotifier {
  /// A workspace with one Canvas pane (the Default workspace of
  /// docs/spec/workspace.md). [onPaneRemoved] is told the id of every pane
  /// that disappears so its owner can release per-pane resources.
  Workspace({this.onPaneRemoved})
    : _layout = PaneLayout.single(0),
      _panes = {0: WorkspacePane(0, PaneKind.canvas)},
      _nextId = 1;

  final ValueChanged<int>? onPaneRemoved;

  PaneLayout _layout;
  Map<int, WorkspacePane> _panes;
  int _nextId;

  /// Pixel size of the workspace area, set by the pane UI each layout pass.
  /// It is not notified because it is an input to layout, not workspace
  /// content; the pixel rules (100 px minimum, 200 px to add) read it.
  Size area = Size.zero;

  PaneLayout get layout => _layout;

  /// Pane ids in layout insertion order.
  Iterable<int> get paneIds => _layout.ids;

  int get paneCount => _panes.length;

  PaneKind kindOf(int id) => _panes[id]!.kind;

  /// The first pane in Canvas mode, or null.
  int? get firstCanvasPaneId {
    for (final id in paneIds) {
      if (_panes[id]!.kind == PaneKind.canvas) return id;
    }
    return null;
  }

  /// The pane's Canvas view, creating default Canvas state if the pane has
  /// not used Canvas mode yet. The controller is owned by the pane.
  CanvasViewportController canvasViewport(int id) {
    final pane = _panes[id]!;
    final state = pane.states.putIfAbsent(PaneKind.canvas, CanvasModeState.new);
    return (state as CanvasModeState).viewport;
  }

  /// The article shown by the pane when it is in Manual mode.
  HelpId manualHelpId(int id) {
    final state = _panes[id]!.states[PaneKind.manual];
    return state is ManualModeState ? state.helpId : HelpId.general;
  }

  /// Selects [helpId] in pane [id]'s Manual state.
  void setManualHelpId(int id, HelpId helpId) {
    final pane = _panes[id];
    if (pane == null) return;
    final state = pane.states.putIfAbsent(PaneKind.manual, ManualModeState.new);
    if ((state as ManualModeState).helpId == helpId) return;
    state.helpId = helpId;
    notifyListeners();
  }

  /// Puts pane [id] in [kind]. Per-mode state of the old and new mode stays
  /// in the pane (PANE-20).
  void setKind(int id, PaneKind kind) {
    final pane = _panes[id];
    if (pane == null || pane.kind == kind) return;
    pane.kind = kind;
    notifyListeners();
  }

  bool canAdd(int id, PaneEdge edge) => _layout.canAdd(id, edge, area);

  /// The neighbor across [edge] of pane [id] (see [PaneLayout.neighbor]).
  int? neighborOf(int id, PaneEdge edge) => _layout.neighbor(id, edge);

  /// Adds a pane against [edge] of pane [id], in the same mode with a copy of
  /// its per-mode state (PANE-13). Returns the new pane's id, or null when the
  /// pane is too small to split (PANE-19).
  int? add(int id, PaneEdge edge) {
    final pane = _panes[id];
    if (pane == null || !canAdd(id, edge)) return null;
    final newId = _nextId++;
    _layout = _layout.add(id, edge, newId);
    _panes[newId] = WorkspacePane(newId, pane.kind, pane.copyStates());
    notifyListeners();
    return newId;
  }

  /// Joins the neighbor across [edge] into pane [id] (PANE-15). Returns
  /// whether a neighbor existed.
  bool join(int id, PaneEdge edge) {
    final other = _layout.neighbor(id, edge);
    final next = _layout.join(id, edge);
    if (other == null || next == null) return false;
    _layout = next;
    _panes.remove(other)!.disposeStates();
    notifyListeners();
    onPaneRemoved?.call(other);
    return true;
  }

  /// Exchanges the mode and per-mode state of pane [id] and its neighbor
  /// across [edge], leaving both rectangles unchanged (PANE-16). Returns
  /// whether a neighbor existed.
  bool swap(int id, PaneEdge edge) {
    final other = _layout.neighbor(id, edge);
    if (other == null) return false;
    final a = _panes[id]!;
    final b = _panes[other]!;
    final kind = a.kind;
    final states = a.states;
    a.kind = b.kind;
    a.states = b.states;
    b.kind = kind;
    b.states = states;
    notifyListeners();
    return true;
  }

  /// Every splitter of the current layout.
  List<PaneSplitter> get splitters => _layout.splitters();

  /// Drags [splitter] by [deltaPixels] along its normal, clamped so panes keep
  /// at least 100 px (PANE-18). The splitter is looked up again by its key in
  /// the current layout, so several drag updates between frames each apply to
  /// the position the previous one produced.
  void moveSplitter(PaneSplitter splitter, double deltaPixels) {
    final extent = splitter.vertical ? area.width : area.height;
    if (extent <= 0) return;
    final current = _layout.splitters().where((s) => s.key == splitter.key);
    if (current.isEmpty) return;
    final next = _layout.moveSplitter(
      current.first,
      deltaPixels / extent,
      area,
    );
    if (identical(next, _layout)) return;
    _layout = next;
    notifyListeners();
  }

  /// Shows [helpId] in a Manual pane: the first existing one, else a new pane
  /// beside the widest pane that is large enough to split, else the widest
  /// pane itself. Returns the id of the pane that shows the page.
  int openManual(HelpId helpId) {
    for (final id in paneIds) {
      if (_panes[id]!.kind == PaneKind.manual) {
        setManualHelpId(id, helpId);
        return id;
      }
    }
    final byWidth = paneIds.toList()
      ..sort((a, b) => _layout.rect(b).width.compareTo(_layout.rect(a).width));
    for (final id in byWidth) {
      final added = add(id, PaneEdge.right);
      if (added == null) continue;
      _panes[added]!.kind = PaneKind.manual;
      _panes[added]!.states[PaneKind.manual] = ManualModeState(helpId);
      notifyListeners();
      return added;
    }
    final widest = byWidth.first;
    _panes[widest]!.kind = PaneKind.manual;
    _panes[widest]!.states[PaneKind.manual] = ManualModeState(helpId);
    notifyListeners();
    return widest;
  }

  /// The section a Flash writes (WKSP-2).
  Map<String, Object?> toJson() => {
    'version': workspaceSectionVersion,
    'panes': [
      for (final entry in _layout.toJson())
        {
          ...entry,
          'mode': _panes[entry['id']]!.kind.name,
          'state': {
            for (final state in _panes[entry['id']]!.states.entries)
              state.key.name: state.value.toJson(),
          },
        },
    ],
  };

  /// Replaces this workspace with the stored workspace in [json] and returns
  /// true, or returns false and changes nothing when the section is
  /// unusable: not readable in full, wrong version, not a partition of the
  /// workspace, or naming an unknown mode (WKSP-11, WKSP-12).
  bool applyJson(Object? json) {
    final parsed = _parse(json);
    if (parsed == null) return false;
    final previous = _panes;
    _layout = parsed.layout;
    _panes = parsed.panes;
    _nextId = parsed.panes.keys.reduce((a, b) => a > b ? a : b) + 1;
    notifyListeners();
    for (final pane in previous.values) {
      pane.disposeStates();
      if (!_panes.containsKey(pane.id)) onPaneRemoved?.call(pane.id);
    }
    return true;
  }

  static ({PaneLayout layout, Map<int, WorkspacePane> panes})? _parse(
    Object? json,
  ) {
    if (json is! Map<String, dynamic> ||
        json['version'] != workspaceSectionVersion) {
      return null;
    }
    final rawPanes = json['panes'];
    final layout = PaneLayout.fromJson(rawPanes);
    if (layout == null) return null;
    final panes = <int, WorkspacePane>{};
    for (final raw in rawPanes as List) {
      final entry = raw as Map<String, dynamic>;
      final id = entry['id'] as int;
      final kind = PaneKind.values.asNameMap()[entry['mode']];
      final rawState = entry['state'];
      if (kind == null || rawState is! Map<String, dynamic>) {
        _disposeAll(panes);
        return null;
      }
      final states = <PaneKind, PaneModeState>{};
      for (final stored in rawState.entries) {
        final stateKind = PaneKind.values.asNameMap()[stored.key];
        final state = stateKind == null
            ? null
            : _stateFromJson(stateKind, stored.value);
        if (stateKind == null || state == null) {
          _disposeAll(panes);
          for (final partial in states.values) {
            partial.dispose();
          }
          return null;
        }
        states[stateKind] = state;
      }
      panes[id] = WorkspacePane(id, kind, states);
    }
    return (layout: layout, panes: panes);
  }

  static void _disposeAll(Map<int, WorkspacePane> panes) {
    for (final pane in panes.values) {
      pane.disposeStates();
    }
  }

  /// Reads the stored state of [kind], or null for a mode that keeps no state
  /// or a malformed value.
  static PaneModeState? _stateFromJson(PaneKind kind, Object? value) {
    switch (kind) {
      case PaneKind.canvas:
        final viewport = CanvasViewportController.fromJson(value);
        return viewport == null ? null : CanvasModeState(viewport);
      case PaneKind.manual:
        if (value is! Map<String, dynamic>) return null;
        final help = HelpId.values.asNameMap()[value['help']];
        return help == null ? null : ManualModeState(help);
      case PaneKind.diagnostics || PaneKind.settings || PaneKind.log:
        return null;
    }
  }

  @override
  void dispose() {
    _disposeAll(_panes);
    super.dispose();
  }
}
