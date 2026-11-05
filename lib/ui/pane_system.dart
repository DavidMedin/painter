// What: PaneKind, PaneDescriptor, and PaneSystem provide selectable content
//   panes arranged as a resizable two-axis split tree.
// Why: docs/design/panes/behavior.md requires modular panes with per-pane
//   content selectors. A floating diagnostics overlay cannot provide
//   independent side-by-side and top-and-bottom content;
//   docs/design/panes/pane-system.md records the docked layout decision.
// Coupled to: main.dart (content builder and per-pane state ownership),
//   contextual_help.dart (pane control ids), manual_catalog.dart and
//   manual_pane.dart (manual navigation), logging/ (Log content mode), and
//   touch_target_settings.dart.
//
//
// ---------------------------------------------------------------------------
// Pane-system overview
//
// Each pane has a stable identity and one content kind: Canvas, Diagnostics,
// Settings, Manual, or Log. Splitting a leaf creates a binary split node with
// either side-by-side or top-and-bottom children; its divider changes only
// those child weights. Closing any leaf except the final pane collapses its
// parent into its sibling. F3 creates Diagnostics beside Canvas; if
// Diagnostics is the sole pane, F3 changes it to Canvas. F1 opens the hovered
// or focused article in an existing Manual pane, or inserts Manual beside the
// widest pane. Each pane's top bar selects its content mode. Boundary menus
// add Canvas panes or delete the adjacent pane, and the final-pane empty state
// offers an Open Canvas Pane action. Pane layout and widths are runtime-only.
// The owner builds content from PaneDescriptor and owns content-specific state;
// this widget knows nothing about documents or drawing.

// ---------------------------------------------------------------------------

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../help/contextual_help.dart';
import 'painter_action_button.dart';
import 'touch_target_settings.dart';

/// Content modes currently implemented by the app's pane host.
enum PaneKind {
  canvas('Canvas', Icons.brush_outlined),
  diagnostics('Diagnostics', Icons.analytics_outlined),
  settings('Settings', Icons.settings_outlined),
  manual('Manual', Icons.menu_book_outlined),
  log('Log', Icons.receipt_long_outlined);

  const PaneKind(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// The identity, content selection, and manual page for one app pane.
class PaneDescriptor {
  const PaneDescriptor({
    required this.id,
    required this.kind,
    required this.canvasPaneId,
    required this.manualHelpId,
    required this.onManualHelpSelected,
  });

  /// Stable for the lifetime of the pane, including content-mode changes.
  final int id;

  final PaneKind kind;

  /// The first visible Canvas pane, or null when no Canvas pane exists.
  final int? canvasPaneId;

  final HelpId manualHelpId;
  final ValueChanged<HelpId> onManualHelpSelected;
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

/// Owns pane identities, content choices, focus, and split weights.
class PaneSystemState extends State<PaneSystem> {
  _LayoutNode _layout = _Pane(id: 0, kind: PaneKind.canvas);
  int _nextPaneId = 1;
  int _focusedPaneId = 0;

  Iterable<_Pane> get _panes sync* {
    yield* _leafPanes(_layout);
  }

  /// Opens [helpId] in the existing Manual pane or beside the widest pane.
  void openManual(HelpId helpId) {
    final panes = _panes.toList();
    for (final pane in panes) {
      if (pane.kind != PaneKind.manual) continue;
      if (pane.manualHelpId == helpId && _focusedPaneId == pane.id) return;
      setState(() {
        pane.manualHelpId = helpId;
        _focusedPaneId = pane.id;
      });
      return;
    }

    var widestPane = panes.first;
    var widestWidth = _paneWidth(_layout, widestPane.id, 1);
    for (final pane in panes.skip(1)) {
      final width = _paneWidth(_layout, pane.id, 1);
      if (width > widestWidth) {
        widestPane = pane;
        widestWidth = width;
      }
    }
    _splitPane(
      widestPane.id,
      kind: PaneKind.manual,
      manualHelpId: helpId,
      axis: Axis.horizontal,
    );
  }

  /// Returns a leaf's proportional width through the nested split tree.
  double _paneWidth(_LayoutNode node, int paneId, double width) {
    if (node is _Pane) return node.id == paneId ? width : 0;
    final split = node as _PaneSplit;
    final totalWeight = split.firstWeight + split.secondWeight;
    final firstWidth = split.axis == Axis.horizontal
        ? width * split.firstWeight / totalWeight
        : width;
    final secondWidth = split.axis == Axis.horizontal
        ? width * split.secondWeight / totalWeight
        : width;
    return _paneWidth(split.first, paneId, firstWidth) +
        _paneWidth(split.second, paneId, secondWidth);
  }

  /// Selects a page from the manual tree for the pane at [paneId].
  void _selectManualHelpId(int paneId, HelpId helpId) {
    final pane = _findPane(_layout, paneId);
    if (pane == null ||
        pane.kind != PaneKind.manual ||
        pane.manualHelpId == helpId) {
      return;
    }
    setState(() => pane.manualHelpId = helpId);
  }

  /// Adds or removes a Diagnostics pane for the F3 shortcut.
  void toggleDiagnostics() {
    final panes = _panes.toList();
    final diagnostics = panes.where(
      (pane) => pane.kind == PaneKind.diagnostics,
    );
    if (diagnostics.isNotEmpty) {
      final pane = diagnostics.first;
      if (panes.length == 1) {
        _setPaneKind(pane.id, PaneKind.canvas);
      } else {
        _closePane(pane.id);
      }
      return;
    }

    final canvas = panes.where((pane) => pane.kind == PaneKind.canvas);
    final target = canvas.isNotEmpty ? canvas.first : panes.last;
    _splitPane(target.id, kind: PaneKind.diagnostics, axis: Axis.horizontal);
  }

  /// Replaces one pane's content without changing its identity or layout.
  void _setPaneKind(int paneId, PaneKind kind) {
    final pane = _findPane(_layout, paneId);
    if (pane == null || pane.kind == kind) return;
    setState(() => pane.kind = kind);
    widget.onPaneTypeChanged(pane.id, kind);
  }

  /// Replaces [paneId] with a split whose children initially share its extent.
  void _splitPane(
    int paneId, {
    PaneKind? kind,
    HelpId manualHelpId = HelpId.general,
    required Axis axis,
  }) {
    final pane = _findPane(_layout, paneId);
    if (pane == null) return;
    final newPane = _Pane(
      id: _nextPaneId++,
      kind:
          kind ??
          switch (pane.kind) {
            PaneKind.canvas => PaneKind.diagnostics,
            PaneKind.diagnostics ||
            PaneKind.settings ||
            PaneKind.manual ||
            PaneKind.log => PaneKind.canvas,
          },
      manualHelpId: manualHelpId,
    );
    final split = _PaneSplit(axis: axis, first: pane, second: newPane);
    setState(() {
      _layout = _replacePane(_layout, paneId, split);
      _focusedPaneId = newPane.id;
    });
    widget.onPaneTypeChanged(newPane.id, newPane.kind);
  }

  /// Removes [paneId] and collapses its parent split into the other child.
  void _closePane(int paneId) {
    final panes = _panes.toList();
    if (panes.length == 1) return;
    final pane = _findPane(_layout, paneId);
    if (pane == null) return;
    setState(() {
      _layout = _removePane(_layout, paneId)!;
      if (_focusedPaneId == paneId) {
        final remaining = _panes.toList();
        _focusedPaneId =
            remaining[math.min(panes.indexOf(pane), remaining.length - 1)].id;
      }
    });
    widget.onPaneRemoved(paneId);
  }

  /// Makes the clicked pane the target of F3 and highlights its border.
  void _focusPane(int paneId) {
    if (_focusedPaneId == paneId) return;
    setState(() => _focusedPaneId = paneId);
  }

  /// Adjusts a split while preserving its two children's combined extent.
  void _resizeSplit(_PaneSplit split, double delta, double availableExtent) {
    if (availableExtent <= 0) return;
    final totalWeight = split.firstWeight + split.secondWeight;
    final firstExtent = availableExtent * split.firstWeight / totalWeight;
    final minimum = math.min(160.0, availableExtent / 2);
    final nextFirstExtent = (firstExtent + delta)
        .clamp(minimum, availableExtent - minimum)
        .toDouble();
    final nextFirstWeight = totalWeight * nextFirstExtent / availableExtent;
    setState(() {
      split.firstWeight = nextFirstWeight;
      split.secondWeight = totalWeight - nextFirstWeight;
    });
  }

  /// Builds the nested split tree within the available workspace.
  @override
  Widget build(BuildContext context) => _buildNode(context, _layout);

  /// Builds one leaf pane or recursively lays out both children of a split.
  Widget _buildNode(BuildContext context, _LayoutNode node) {
    if (node is _Pane) return _buildPane(context, node);
    final split = node as _PaneSplit;
    return LayoutBuilder(
      builder: (context, constraints) {
        final extent = split.axis == Axis.horizontal
            ? constraints.maxWidth
            : constraints.maxHeight;
        final minimumDividerExtent = split.axis == Axis.vertical
            ? TouchTargetSettings.height(context)
            : 12.0;
        final dividerExtent = math.min(
          minimumDividerExtent,
          math.max(0.0, extent),
        );
        final available = math.max(0.0, extent - dividerExtent);
        final firstFlex = math.max(1, (split.firstWeight * 1000).round());
        final secondFlex = math.max(1, (split.secondWeight * 1000).round());
        final first = Expanded(
          flex: firstFlex,
          child: _buildNode(context, split.first),
        );
        final second = Expanded(
          flex: secondFlex,
          child: _buildNode(context, split.second),
        );
        final divider = _buildDivider(split, available, dividerExtent);
        return split.axis == Axis.horizontal
            ? Row(children: [first, divider, second])
            : Column(children: [first, divider, second]);
      },
    );
  }

  /// Builds a bordered pane and its local type/split/close controls.
  Widget _buildPane(BuildContext context, _Pane pane) {
    final canvas = _panes.where(
      (candidate) => candidate.kind == PaneKind.canvas,
    );
    final firstCanvas = canvas.isEmpty ? null : canvas.first.id;
    final descriptor = PaneDescriptor(
      id: pane.id,
      kind: pane.kind,
      canvasPaneId: firstCanvas,
      manualHelpId: pane.manualHelpId,
      onManualHelpSelected: (helpId) => _selectManualHelpId(pane.id, helpId),
    );
    final theme = Theme.of(context);
    return Listener(
      key: ValueKey('pane-${pane.id}'),
      onPointerDown: (_) => _focusPane(pane.id),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(
            color: pane.id == _focusedPaneId
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            _buildHeader(context, pane),
            Expanded(
              child: Material(
                color: theme.colorScheme.surface,
                child: widget.contentBuilder(context, descriptor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the visible pane-mode selector and pane-local split/close actions.
  Widget _buildHeader(BuildContext context, _Pane pane) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final height = TouchTargetSettings.height(context);
    final paneCount = _panes.length;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 48) return const SizedBox.expand();
            if (constraints.maxWidth < 180) {
              return _buildCompactHeader(context, pane, height, scheme);
            }
            return Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: HelpTarget(
                      topic: HelpIds.paneType,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          border: Border.all(color: scheme.primary),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<PaneKind>(
                            key: ValueKey('pane-mode-${pane.id}'),
                            value: pane.kind,
                            isExpanded: true,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: scheme.onPrimaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                            iconEnabledColor: scheme.onPrimaryContainer,
                            dropdownColor: scheme.surface,
                            borderRadius: BorderRadius.circular(4),
                            itemHeight: height,
                            items: [
                              for (final kind in PaneKind.values)
                                DropdownMenuItem(
                                  value: kind,
                                  child: Row(
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
                                ),
                            ],
                            selectedItemBuilder: (context) => [
                              for (final kind in PaneKind.values)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(kind.icon, size: 12),
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
                              if (kind != null) _setPaneKind(pane.id, kind);
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: HelpTarget(
                    topic: HelpIds.paneBoundary,
                    child: PopupMenuButton<Axis>(
                      key: ValueKey('split-menu-${pane.id}'),
                      padding: EdgeInsets.zero,
                      onSelected: (axis) => _splitPane(pane.id, axis: axis),
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: Axis.horizontal,
                          height: TouchTargetSettings.height(context),
                          child: Text('Side by side'),
                        ),
                        PopupMenuItem(
                          value: Axis.vertical,
                          height: TouchTargetSettings.height(context),
                          child: Text('Top and bottom'),
                        ),
                      ],
                      child: Material(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(4),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: height),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.call_split,
                                  size: 18,
                                  color: scheme.onPrimary,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    'Split',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: scheme.onPrimary),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (paneCount > 1) ...[
                  const SizedBox(width: 4),
                  Flexible(
                    child: PainterActionButton(
                      icon: Icons.close,
                      label: 'Close',
                      topic: HelpIds.paneBoundary,
                      onPressed: () => _closePane(pane.id),
                      minimumHeight: height,
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  /// Keeps mode and split actions available when a pane is too narrow for labels.
  Widget _buildCompactHeader(
    BuildContext context,
    _Pane pane,
    double height,
    ColorScheme scheme,
  ) {
    return HelpTarget(
      topic: HelpIds.paneBoundary,
      child: PopupMenuButton<_CompactPaneAction>(
        key: ValueKey('pane-actions-${pane.id}'),
        onSelected: (action) {
          switch (action) {
            case _CompactPaneAction.canvas:
              _setPaneKind(pane.id, PaneKind.canvas);
            case _CompactPaneAction.diagnostics:
              _setPaneKind(pane.id, PaneKind.diagnostics);
            case _CompactPaneAction.settings:
              _setPaneKind(pane.id, PaneKind.settings);
            case _CompactPaneAction.manual:
              _setPaneKind(pane.id, PaneKind.manual);
            case _CompactPaneAction.log:
              _setPaneKind(pane.id, PaneKind.log);
            case _CompactPaneAction.splitSideBySide:
              _splitPane(pane.id, axis: Axis.horizontal);
            case _CompactPaneAction.splitTopAndBottom:
              _splitPane(pane.id, axis: Axis.vertical);
            case _CompactPaneAction.close:
              _closePane(pane.id);
          }
        },
        itemBuilder: (context) => [
          for (final kind in PaneKind.values)
            PopupMenuItem(
              value: switch (kind) {
                PaneKind.canvas => _CompactPaneAction.canvas,
                PaneKind.diagnostics => _CompactPaneAction.diagnostics,
                PaneKind.settings => _CompactPaneAction.settings,
                PaneKind.manual => _CompactPaneAction.manual,
                PaneKind.log => _CompactPaneAction.log,
              },
              height: height,
              child: Text(kind.label),
            ),
          PopupMenuItem(
            value: _CompactPaneAction.splitSideBySide,
            height: height,
            child: Text('Split side-by-side'),
          ),
          PopupMenuItem(
            value: _CompactPaneAction.splitTopAndBottom,
            height: height,
            child: Text('Split top-and-bottom'),
          ),
          if (_panes.length > 1)
            PopupMenuItem(
              value: _CompactPaneAction.close,
              height: height,
              child: Text('Close pane'),
            ),
        ],
        child: SizedBox(
          height: height,
          child: Center(child: Icon(pane.kind.icon, color: scheme.primary)),
        ),
      ),
    );
  }

  /// Builds a visible resize handle whose context menu also edits adjacent panes.
  Widget _buildDivider(
    _PaneSplit split,
    double availableExtent,
    double dividerExtent,
  ) {
    final isSideBySide = split.axis == Axis.horizontal;
    return HelpTarget(
      topic: HelpIds.paneBoundary,
      child: MouseRegion(
        cursor: isSideBySide
            ? SystemMouseCursors.resizeColumn
            : SystemMouseCursors.resizeRow,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onSecondaryTapDown: (details) =>
              _showBoundaryMenu(context, split, details.globalPosition),
          onHorizontalDragUpdate: isSideBySide
              ? (details) =>
                    _resizeSplit(split, details.delta.dx, availableExtent)
              : null,
          onVerticalDragUpdate: isSideBySide
              ? null
              : (details) =>
                    _resizeSplit(split, details.delta.dy, availableExtent),
          child: Semantics(
            label: 'Resize pane boundary',
            child: SizedBox(
              width: isSideBySide ? dividerExtent : double.infinity,
              height: isSideBySide ? double.infinity : dividerExtent,
              child: ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Center(
                  child: Container(
                    width: isSideBySide ? math.min(4.0, dividerExtent) : 32,
                    height: isSideBySide ? 32 : math.min(4.0, dividerExtent),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Opens edit actions for the panes nearest the clicked divider.
  Future<void> _showBoundaryMenu(
    BuildContext context,
    _PaneSplit split,
    Offset globalPosition,
  ) async {
    final firstPane = _edgePane(split.first, trailing: true);
    final secondPane = _edgePane(split.second, trailing: false);
    final firstSide = split.axis == Axis.horizontal ? 'left' : 'top';
    final secondSide = split.axis == Axis.horizontal ? 'right' : 'bottom';
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final localPosition = overlay.globalToLocal(globalPosition);
    final action = await showMenu<_BoundaryAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        localPosition.dx,
        localPosition.dy,
        overlay.size.width - localPosition.dx,
        overlay.size.height - localPosition.dy,
      ),
      items: [
        PopupMenuItem(
          value: _BoundaryAction(firstPane.id, axis: Axis.horizontal),
          height: TouchTargetSettings.height(context),
          child: Text('Split $firstSide pane side-by-side'),
        ),
        PopupMenuItem(
          value: _BoundaryAction(firstPane.id, axis: Axis.vertical),
          height: TouchTargetSettings.height(context),
          child: Text('Split $firstSide pane top-and-bottom'),
        ),
        PopupMenuItem(
          value: _BoundaryAction(firstPane.id),
          height: TouchTargetSettings.height(context),
          child: Text('Close $firstSide pane'),
        ),
        PopupMenuItem(
          value: _BoundaryAction(secondPane.id, axis: Axis.horizontal),
          height: TouchTargetSettings.height(context),
          child: Text('Split $secondSide pane side-by-side'),
        ),
        PopupMenuItem(
          value: _BoundaryAction(secondPane.id, axis: Axis.vertical),
          height: TouchTargetSettings.height(context),
          child: Text('Split $secondSide pane top-and-bottom'),
        ),
        PopupMenuItem(
          value: _BoundaryAction(secondPane.id),
          height: TouchTargetSettings.height(context),
          child: Text('Close $secondSide pane'),
        ),
      ],
    );
    if (!mounted || action == null) return;
    if (action.axis == null) {
      _closePane(action.paneId);
    } else {
      _splitPane(action.paneId, axis: action.axis!);
    }
  }
}

/// One split or close operation selected from a divider's context menu.
class _BoundaryAction {
  const _BoundaryAction(this.paneId, {this.axis});

  final int paneId;
  final Axis? axis;
}

/// Returns the leaf at the edge of [node] facing its parent divider.
_Pane _edgePane(_LayoutNode node, {required bool trailing}) {
  if (node is _Pane) return node;
  final split = node as _PaneSplit;
  return _edgePane(trailing ? split.second : split.first, trailing: trailing);
}

/// Finds leaves in visual order, which also defines the Diagnostics source.
Iterable<_Pane> _leafPanes(_LayoutNode node) sync* {
  if (node is _Pane) {
    yield node;
  } else {
    final split = node as _PaneSplit;
    yield* _leafPanes(split.first);
    yield* _leafPanes(split.second);
  }
}

/// Finds one pane by its stable identity.
_Pane? _findPane(_LayoutNode node, int paneId) {
  if (node is _Pane) return node.id == paneId ? node : null;
  final split = node as _PaneSplit;
  return _findPane(split.first, paneId) ?? _findPane(split.second, paneId);
}

/// Replaces one leaf with a split while retaining the leaf as its first child.
_LayoutNode _replacePane(_LayoutNode node, int paneId, _PaneSplit replacement) {
  if (node is _Pane) return node.id == paneId ? replacement : node;
  final split = node as _PaneSplit;
  split.first = _replacePane(split.first, paneId, replacement);
  split.second = _replacePane(split.second, paneId, replacement);
  return split;
}

/// Removes a leaf, returning null for that branch so its parent can collapse.
_LayoutNode? _removePane(_LayoutNode node, int paneId) {
  if (node is _Pane) return node.id == paneId ? null : node;
  final split = node as _PaneSplit;
  if (split.first is _Pane && (split.first as _Pane).id == paneId) {
    return split.second;
  }
  if (split.second is _Pane && (split.second as _Pane).id == paneId) {
    return split.first;
  }
  final first = _removePane(split.first, paneId);
  if (first == null) return split.second;
  final second = _removePane(split.second, paneId);
  if (second == null) return first;
  split
    ..first = first
    ..second = second;
  return split;
}

/// A pane or split node in the runtime-only binary layout tree.
abstract class _LayoutNode {}

/// Mutable mode and selected manual page attached to a stable pane id.
class _Pane extends _LayoutNode {
  _Pane({
    required this.id,
    required this.kind,
    this.manualHelpId = HelpId.general,
  });

  final int id;
  PaneKind kind;
  HelpId manualHelpId;
}

/// Two children arranged on one axis with independently resizable weights.
class _PaneSplit extends _LayoutNode {
  _PaneSplit({required this.axis, required this.first, required this.second});

  final Axis axis;
  _LayoutNode first;
  _LayoutNode second;
  double firstWeight = 1;
  double secondWeight = 1;
}

enum _CompactPaneAction {
  canvas,
  diagnostics,
  settings,
  manual,
  log,
  splitSideBySide,
  splitTopAndBottom,
  close,
}
