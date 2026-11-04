// What: PaneKind, PaneDescriptor, and PaneSystem provide selectable content
//   panes, split/close controls, and a draggable horizontal divider.
// Why: docs/project-brief.md requires modular panes with per-pane content
//   selectors. A floating diagnostics overlay cannot provide independent
//   side-by-side content; ADR 0010 records the docked layout decision.
// Coupled to: main.dart (content builder and renderer ownership),
//   contextual_help.dart (pane controls), and touch_target_settings.dart.
//
// ---------------------------------------------------------------------------
// Pane-system overview
//
// Each pane has a stable identity and one implemented content kind: Canvas,
// Diagnostics, or Settings. The first pane is a Canvas. Its top-left selector
// can change content, Split creates a neighboring pane, and Close removes a
// pane while at least one remains. Canvas splits into Diagnostics; Diagnostics
// and Settings split into Canvas. F3 adds or removes a Diagnostics pane beside
// Canvas; if Diagnostics is the sole pane, F3 changes it to Canvas. A row of
// panes shares available width by positive weights. Dragging a divider
// redistributes only its adjacent pair, preserving their combined width and
// every other pane's weight. Clicking a pane focuses it for the active border
// and F3 target. The owner builds content from PaneDescriptor and owns
// content-specific state, including one TiledRenderer per Canvas pane. This
// widget owns pane kinds, identities, focus, and relative widths; layout state
// is runtime-only, and the widget never knows about documents or drawing.
// ---------------------------------------------------------------------------

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../help/contextual_help.dart';
import 'painter_action_button.dart';
import 'touch_target_settings.dart';

/// Content types currently implemented by the app's pane host.
enum PaneKind {
  canvas('Canvas', Icons.brush_outlined),
  diagnostics('Diagnostics', Icons.analytics_outlined),
  settings('Settings', Icons.settings_outlined);

  const PaneKind(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// The identity and content selection for one pane passed to the app shell.
class PaneDescriptor {
  const PaneDescriptor({
    required this.id,
    required this.kind,
    required this.canvasPaneId,
  });

  /// Stable for the lifetime of the pane, including content-type changes.
  final int id;

  final PaneKind kind;

  /// The first visible Canvas pane, or null when no Canvas pane exists.
  final int? canvasPaneId;
}

/// Builds app-owned content for one pane.
typedef PaneContentBuilder = Widget Function(
  BuildContext context,
  PaneDescriptor pane,
);

/// Selectable, resizable pane layout. Pane content stays owned by the caller.
class PaneSystem extends StatefulWidget {
  const PaneSystem({
    super.key,
    required this.contentBuilder,
    required this.onPaneRemoved,
    required this.onPaneTypeChanged,
  });

  final PaneContentBuilder contentBuilder;
  final ValueChanged<int> onPaneRemoved;
  final void Function(int paneId, PaneKind kind) onPaneTypeChanged;

  @override
  PaneSystemState createState() => PaneSystemState();
}

/// Owns pane identities, content choices, focus, and horizontal split weights.
class PaneSystemState extends State<PaneSystem> {
  final List<_Pane> _panes = [_Pane(id: 0, kind: PaneKind.canvas)];
  final List<double> _weights = [1];
  int _nextPaneId = 1;
  int _focusedPaneId = 0;

  /// Adds or removes a Diagnostics pane for the F3 shortcut.
  void toggleDiagnostics() {
    final diagnosticsIndex = _panes.indexWhere(
      (pane) => pane.kind == PaneKind.diagnostics,
    );
    if (diagnosticsIndex >= 0) {
      if (_panes.length == 1) {
        _setPaneKind(diagnosticsIndex, PaneKind.canvas);
      } else {
        _closePane(diagnosticsIndex);
      }
      return;
    }

    final canvasIndex = _panes.indexWhere(
      (pane) => pane.kind == PaneKind.canvas,
    );
    _splitPane(
      canvasIndex >= 0 ? canvasIndex : _panes.length - 1,
      kind: PaneKind.diagnostics,
    );
  }

  /// Replaces one pane's content without changing its identity or width.
  void _setPaneKind(int index, PaneKind kind) {
    final pane = _panes[index];
    if (pane.kind == kind) return;
    setState(() => pane.kind = kind);
    widget.onPaneTypeChanged(pane.id, kind);
  }

  /// Inserts a useful content kind beside [index] and divides its width.
  void _splitPane(int index, {PaneKind? kind}) {
    final pane = _panes[index];
    final newPane = _Pane(
      id: _nextPaneId++,
      kind:
          kind ??
          switch (pane.kind) {
            PaneKind.canvas => PaneKind.diagnostics,
            PaneKind.diagnostics || PaneKind.settings => PaneKind.canvas,
          },
    );
    final weight = _weights[index];
    setState(() {
      _weights[index] = weight / 2;
      _weights.insert(index + 1, weight / 2);
      _panes.insert(index + 1, newPane);
      _focusedPaneId = newPane.id;
    });
    widget.onPaneTypeChanged(newPane.id, newPane.kind);
  }

  /// Removes a pane and transfers its width to a neighbor.
  void _closePane(int index) {
    if (_panes.length == 1) return;
    final pane = _panes[index];
    setState(() {
      if (index > 0) {
        _weights[index - 1] += _weights[index];
      } else {
        _weights[1] += _weights[0];
      }
      _weights.removeAt(index);
      _panes.removeAt(index);
      if (_focusedPaneId == pane.id) {
        _focusedPaneId = _panes[math.max(0, index - 1)].id;
      }
    });
    widget.onPaneRemoved(pane.id);
  }

  /// Makes the clicked pane the target of F3 and highlights its border.
  void _focusPane(int index) {
    final paneId = _panes[index].id;
    if (_focusedPaneId == paneId) return;
    setState(() => _focusedPaneId = paneId);
  }

  /// Adjusts a divider while preserving the adjacent panes' total width.
  void _resizeDivider(int index, double delta, double availableWidth) {
    if (availableWidth <= 0) return;
    final totalWeight = _weights.fold<double>(0, (sum, value) => sum + value);
    final pairWeight = _weights[index] + _weights[index + 1];
    final pairWidth = availableWidth * pairWeight / totalWeight;
    final leftWidth = availableWidth * _weights[index] / totalWeight;
    final minimum = math.min(160.0, pairWidth / 2);
    final nextLeftWidth = (leftWidth + delta)
        .clamp(minimum, pairWidth - minimum)
        .toDouble();
    final nextLeftWeight = pairWeight * nextLeftWidth / pairWidth;
    setState(() {
      _weights[index] = nextLeftWeight;
      _weights[index + 1] = pairWeight - nextLeftWeight;
    });
  }

  /// Builds each pane with an editor-type selector and a draggable boundary.
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const dividerWidth = 8.0;
        final availableWidth = math.max(
          0.0,
          constraints.maxWidth - dividerWidth * (_panes.length - 1),
        );
        return Row(
          children: [
            for (var index = 0; index < _panes.length; index++) ...[
              Expanded(
                flex: math.max(1, (_weights[index] * 1000).round()),
                child: _buildPane(context, index),
              ),
              if (index < _panes.length - 1)
                _buildDivider(index, availableWidth),
            ],
          ],
        );
      },
    );
  }

  /// Builds a bordered pane and its local type/split/close controls.
  Widget _buildPane(BuildContext context, int index) {
    final pane = _panes[index];
    final canvasIndex = _panes.indexWhere(
      (candidate) => candidate.kind == PaneKind.canvas,
    );
    final descriptor = PaneDescriptor(
      id: pane.id,
      kind: pane.kind,
      canvasPaneId: canvasIndex < 0 ? null : _panes[canvasIndex].id,
    );
    final theme = Theme.of(context);
    return Listener(
      key: ValueKey('pane-${pane.id}'),
      onPointerDown: (_) => _focusPane(index),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(
            color: pane.id == _focusedPaneId
                ? theme.colorScheme.primary
                : theme.dividerColor,
            width: 1,
          ),
        ),
        child: Column(
          children: [
            _buildHeader(context, index),
            Expanded(child: widget.contentBuilder(context, descriptor)),
          ],
        ),
      ),
    );
  }

  /// Builds the top-left content selector and pane-local split/close actions.
  Widget _buildHeader(BuildContext context, int index) {
    final pane = _panes[index];
    final height = TouchTargetSettings.height(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            Expanded(
              child: HelpTarget(
                topic: HelpTopics.paneType,
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<PaneKind>(
                    value: pane.kind,
                    isExpanded: true,
                    items: [
                      for (final kind in PaneKind.values)
                        DropdownMenuItem(
                          value: kind,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(kind.icon, size: 18),
                              const SizedBox(width: 8),
                              Text(kind.label),
                            ],
                          ),
                        ),
                    ],
                    selectedItemBuilder: (context) => [
                      for (final kind in PaneKind.values)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(kind.icon, size: 18),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                kind.label,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                    ],
                    onChanged: (kind) {
                      if (kind != null) _setPaneKind(index, kind);
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: PainterActionButton(
                icon: Icons.call_split,
                label: 'Split',
                topic: HelpTopics.splitPane,
                onPressed: () => _splitPane(index),
                minimumHeight: height,
              ),
            ),
            if (_panes.length > 1) ...[
              const SizedBox(width: 4),
              Flexible(
                child: PainterActionButton(
                  icon: Icons.close,
                  label: 'Close',
                  topic: HelpTopics.closePane,
                  onPressed: () => _closePane(index),
                  minimumHeight: height,
                ),
              ),
            ],
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  /// Provides a mouse/touch target for the divider and its width affordance.
  Widget _buildDivider(int index, double availableWidth) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) =>
            _resizeDivider(index, details.delta.dx, availableWidth),
        child: Semantics(
          label: 'Resize pane boundary',
          child: SizedBox(
            width: 8,
            child: Center(
              child: Container(width: 1, color: Theme.of(context).dividerColor),
            ),
          ),
        ),
      ),
    );
  }
}

/// Mutable kind attached to a stable pane id.
class _Pane {
  _Pane({required this.id, required this.kind});

  final int id;
  PaneKind kind;
}
