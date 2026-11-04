// What: PaneKind, PaneDescriptor, and PaneSystem provide selectable content
//   panes, rounded borders, resizable boundaries, and boundary context menus.
// Why: docs/project-brief.md requires modular panes with per-pane content
//   selectors. A floating diagnostics overlay cannot provide independent
//   side-by-side content; ADR 0010 records the docked layout decision.
// Coupled to: main.dart (content builder and renderer ownership), logging/
//   (Log content mode), contextual_help.dart, and touch_target_settings.dart.
//
// ---------------------------------------------------------------------------
// Pane-system overview
//
// Each pane has a stable identity and one implemented content kind: Canvas,
// Diagnostics, Settings, or Log. The first pane is a Canvas. Each top bar
// selects its mode. Boundary menus add a Canvas pane beside a boundary or
// delete the pane beside it; deleting the final pane shows an Open Canvas Pane
// action. Inner boundaries resize their adjacent pair while preserving
// combined width. F3 adds or removes Diagnostics beside the focused pane; if
// Diagnostics is the only pane, F3 changes it to Canvas. Pane widths are
// runtime-only. The owner builds content from PaneDescriptor and owns content-
// specific state; this widget knows nothing about documents or drawing.
// ---------------------------------------------------------------------------

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../help/contextual_help.dart';
import 'touch_target_settings.dart';

/// Content types currently implemented by the app's pane host.
enum PaneKind {
  canvas('Canvas', Icons.brush_outlined),
  diagnostics('Diagnostics', Icons.analytics_outlined),
  settings('Settings', Icons.settings_outlined),
  log('Log', Icons.receipt_long_outlined);

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
  });

  final PaneContentBuilder contentBuilder;
  final ValueChanged<int> onPaneRemoved;

  @override
  PaneSystemState createState() => PaneSystemState();
}

/// Owns pane identities, content choices, focus, and horizontal split weights.
class PaneSystemState extends State<PaneSystem> {
  final List<_Pane> _panes = [_Pane(id: 0, kind: PaneKind.canvas)];
  final List<double> _weights = [1];
  int _nextPaneId = 1;
  int? _focusedPaneId = 0;

  /// Adds or removes a Diagnostics pane for the F3 shortcut.
  void toggleDiagnostics() {
    if (_panes.isEmpty) return;
    final diagnosticsIndex = _panes.indexWhere(
      (pane) => pane.kind == PaneKind.diagnostics,
    );
    if (diagnosticsIndex >= 0) {
      if (_panes.length == 1) {
        _setPaneKind(diagnosticsIndex, PaneKind.canvas);
      } else {
        _removePaneAt(diagnosticsIndex);
      }
      return;
    }

    final focusedIndex = _panes.indexWhere((pane) => pane.id == _focusedPaneId);
    _insertPane(
      focusedIndex < 0 ? _panes.length : focusedIndex + 1,
      kind: PaneKind.diagnostics,
    );
  }

  /// Replaces one pane's content without changing its identity or width.
  void _setPaneKind(int index, PaneKind kind) {
    final pane = _panes[index];
    if (pane.kind == kind) return;
    setState(() => pane.kind = kind);
  }

  /// Inserts a Canvas pane at [boundaryIndex], splitting the pane to its left
  /// or the first pane when inserting at the outer left edge.
  void _insertPane(int boundaryIndex, {PaneKind kind = PaneKind.canvas}) {
    final newPane = _Pane(id: _nextPaneId++, kind: kind);
    if (_panes.isEmpty) {
      setState(() {
        _panes.add(newPane);
        _weights.add(1);
        _focusedPaneId = newPane.id;
      });
      return;
    }

    final donorIndex = boundaryIndex == 0 ? 0 : boundaryIndex - 1;
    final newWeight = _weights[donorIndex] / 2;
    setState(() {
      _weights[donorIndex] = newWeight;
      _weights.insert(boundaryIndex, newWeight);
      _panes.insert(boundaryIndex, newPane);
      _focusedPaneId = newPane.id;
    });
  }

  /// Removes a pane and transfers its width to a neighbor, if one exists.
  void _removePaneAt(int index) {
    final pane = _panes[index];
    setState(() {
      if (_panes.length > 1) {
        if (index > 0) {
          _weights[index - 1] += _weights[index];
        } else {
          _weights[1] += _weights[0];
        }
      }
      _weights.removeAt(index);
      _panes.removeAt(index);
      if (_panes.isEmpty) {
        _focusedPaneId = null;
      } else if (_focusedPaneId == pane.id) {
        _focusedPaneId = _panes[math.min(index, _panes.length - 1)].id;
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

  /// Adjusts the two panes around an inner boundary, preserving their total.
  void _resizeBoundary(int boundaryIndex, double delta, double availableWidth) {
    if (availableWidth <= 0 ||
        boundaryIndex <= 0 ||
        boundaryIndex >= _panes.length) {
      return;
    }
    final leftIndex = boundaryIndex - 1;
    final totalWeight = _weights.fold<double>(0, (sum, value) => sum + value);
    final pairWeight = _weights[leftIndex] + _weights[boundaryIndex];
    final pairWidth = availableWidth * pairWeight / totalWeight;
    if (pairWidth <= 0) return;
    final leftWidth = availableWidth * _weights[leftIndex] / totalWeight;
    final minimum = math.min(160.0, pairWidth / 2);
    final nextLeftWidth = (leftWidth + delta)
        .clamp(minimum, pairWidth - minimum)
        .toDouble();
    final nextLeftWeight = pairWeight * nextLeftWidth / pairWidth;
    setState(() {
      _weights[leftIndex] = nextLeftWeight;
      _weights[boundaryIndex] = pairWeight - nextLeftWeight;
    });
  }

  /// Opens the actions that apply to the pane boundary at [globalPosition].
  Future<void> _showBoundaryMenu(
    int boundaryIndex,
    Offset globalPosition,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject();
    if (overlay is! RenderBox) return;
    final localPosition = overlay.globalToLocal(globalPosition);
    final menuPosition = RelativeRect.fromLTRB(
      localPosition.dx,
      localPosition.dy,
      overlay.size.width - localPosition.dx,
      overlay.size.height - localPosition.dy,
    );
    final theme = Theme.of(context);
    final action = await showMenu<_BoundaryAction>(
      context: context,
      position: menuPosition,
      color: theme.colorScheme.surfaceContainerHigh,
      items: [
        PopupMenuItem(
          value: _BoundaryAction.addPane,
          child: HelpTarget(
            topic: HelpTopics.paneBoundary,
            child: Text(
              boundaryIndex == 0
                  ? 'Add pane to the left'
                  : boundaryIndex == _panes.length
                  ? 'Add pane to the right'
                  : 'Add pane between panes',
            ),
          ),
        ),
        if (boundaryIndex > 0)
          PopupMenuItem(
            value: _BoundaryAction.deleteLeftPane,
            child: HelpTarget(
              topic: HelpTopics.paneBoundary,
              child: const Text('Delete left pane'),
            ),
          ),
        if (boundaryIndex < _panes.length)
          PopupMenuItem(
            value: _BoundaryAction.deleteRightPane,
            child: HelpTarget(
              topic: HelpTopics.paneBoundary,
              child: const Text('Delete right pane'),
            ),
          ),
      ],
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _BoundaryAction.addPane:
        _insertPane(boundaryIndex);
        break;
      case _BoundaryAction.deleteLeftPane:
        _removePaneAt(boundaryIndex - 1);
        break;
      case _BoundaryAction.deleteRightPane:
        _removePaneAt(boundaryIndex);
        break;
    }
  }

  /// Builds the empty action or a row of bounded panes and boundary targets.
  @override
  Widget build(BuildContext context) {
    if (_panes.isEmpty) {
      final theme = Theme.of(context);
      return Center(
        child: HelpTarget(
          topic: HelpTopics.openCanvasPane,
          child: FilledButton.icon(
            onPressed: () => _insertPane(0),
            icon: const Icon(Icons.brush_outlined),
            label: const Text('Open Canvas Pane'),
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
              minimumSize: Size(224, TouchTargetSettings.height(context)),
              padding: const EdgeInsets.symmetric(horizontal: 20),
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const outerBoundaryWidth = 10.0;
        const innerBoundaryWidth = 16.0;
        final availableWidth = math.max(
          0.0,
          constraints.maxWidth -
              outerBoundaryWidth * 2 -
              innerBoundaryWidth * (_panes.length - 1),
        );
        return Row(
          children: [
            _buildBoundary(0, availableWidth, outerBoundaryWidth),
            for (var index = 0; index < _panes.length; index++) ...[
              Expanded(
                flex: math.max(1, (_weights[index] * 1000).round()),
                child: _buildPane(index),
              ),
              _buildBoundary(
                index + 1,
                availableWidth,
                index == _panes.length - 1
                    ? outerBoundaryWidth
                    : innerBoundaryWidth,
              ),
            ],
          ],
        );
      },
    );
  }

  /// Builds one rounded pane and routes secondary clicks on its side borders.
  Widget _buildPane(int index) {
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
    return LayoutBuilder(
      builder: (context, constraints) => GestureDetector(
        onSecondaryTapDown: (details) {
          if (details.localPosition.dx <= 12) {
            _showBoundaryMenu(index, details.globalPosition);
          } else if (details.localPosition.dx >= constraints.maxWidth - 12) {
            _showBoundaryMenu(index + 1, details.globalPosition);
          }
        },
        child: Listener(
          key: ValueKey('pane-${pane.id}'),
          onPointerDown: (_) => _focusPane(index),
          child: Container(
            key: ValueKey('pane-frame-${pane.id}'),
            decoration: BoxDecoration(
              border: Border.all(
                color: pane.id == _focusedPaneId
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6.5),
              child: Column(
                children: [
                  _buildHeader(context, index),
                  Expanded(child: widget.contentBuilder(context, descriptor)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Builds a visible, compactable mode selector at the top of each pane.
  Widget _buildHeader(BuildContext context, int index) {
    final pane = _panes[index];
    final theme = Theme.of(context);
    final modeLabel = Text(
      'Pane Mode',
      style: theme.textTheme.labelLarge?.copyWith(
        color: theme.colorScheme.onSurface,
      ),
    );
    final modeSelector = HelpTarget(
      topic: HelpTopics.paneType,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<PaneKind>(
          key: ValueKey('pane-mode-${pane.id}'),
          value: pane.kind,
          isExpanded: true,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface,
          ),
          iconEnabledColor: theme.colorScheme.onSurface,
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
                    child: Text(kind.label, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
          ],
          onChanged: (kind) {
            if (kind != null) _setPaneKind(index, kind);
          },
        ),
      ),
    );

    return DecoratedBox(
      key: ValueKey('pane-header-${pane.id}'),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 250;
          return SizedBox(
            height: TouchTargetSettings.height(context) + (compact ? 24 : 0),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 10,
                vertical: compact ? 2 : 0,
              ),
              child: compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        modeLabel,
                        Expanded(child: modeSelector),
                      ],
                    )
                  : Row(
                      children: [
                        modeLabel,
                        const SizedBox(width: 8),
                        Expanded(child: modeSelector),
                      ],
                    ),
            ),
          );
        },
      ),
    );
  }

  /// Provides a resize handle and right-click menu at each pane boundary.
  Widget _buildBoundary(
    int boundaryIndex,
    double availableWidth,
    double width,
  ) {
    final inner = boundaryIndex > 0 && boundaryIndex < _panes.length;
    final theme = Theme.of(context);
    return HelpTarget(
      topic: HelpTopics.paneBoundary,
      child: MouseRegion(
        cursor: inner
            ? SystemMouseCursors.resizeColumn
            : SystemMouseCursors.basic,
        child: GestureDetector(
          key: ValueKey('pane-boundary-$boundaryIndex'),
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: inner
              ? (details) => _resizeBoundary(
                  boundaryIndex,
                  details.delta.dx,
                  availableWidth,
                )
              : null,
          onSecondaryTapDown: (details) =>
              _showBoundaryMenu(boundaryIndex, details.globalPosition),
          child: Semantics(
            label: inner ? 'Resize pane boundary' : 'Pane boundary menu',
            child: SizedBox(
              width: width,
              child: Center(
                child: Container(
                  width: inner ? 4 : 1.5,
                  height: inner ? 40 : 36,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outline,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _BoundaryAction { addPane, deleteLeftPane, deleteRightPane }

/// Mutable kind attached to a stable pane id.
class _Pane {
  _Pane({required this.id, required this.kind});

  final int id;
  PaneKind kind;
}
