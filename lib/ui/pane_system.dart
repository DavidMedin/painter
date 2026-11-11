// What: PaneSystem draws a Workspace: every shown pane inside its frame with a
//   mode toolbar and four frame-edge toolbars (add, join, swap), and every
//   splitter of the Layout tree with a draggable handle. PaneDescriptor tells
//   the content builder which pane and mode to build.
// Why: docs/spec/panes.md defines the pane chrome and the operations on it.
//   The layout is the projection of a node table shared through the session
//   document (docs/decisions/010-pane-layout-tree.md), drawn as panes
//   positioned in one Stack rather than nested widgets, so a pane keeps its
//   widget state when the tree around it is reshaped.
// Coupled to: ../workspace/workspace.dart (all layout and mode state; this
//   file only draws it and forwards user actions), ../workspace/layout_tree.dart
//   (PaneEdge, LayoutSplitter), ../workspace/pane_kind.dart (mode labels),
//   ../main.dart (content builder and Workspace owner),
//   ../help/contextual_help.dart (control help ids), and touch_target.dart
//   (toolbar height).
//
// ---------------------------------------------------------------------------
// Pane-system overview
//
// The Workspace's projection gives each pane a rectangle and each splitter a
// line in unit coordinates, fractions of the Workspace area. This widget
// multiplies them by the size it is given, then:
//   - insets each pane by half a splitter on every side that is not on the
//     workspace boundary, leaving a gap, and draws each splitter over its gap;
//   - frames each pane (PANE-2) with a border whose color marks the pane that
//     last received a pointer press;
//   - places inside the frame a strip along every edge with add, join, and
//     swap buttons, rotated on the left and right (PANE-10 to PANE-12), and
//     below the top strip the pane toolbar, whose far-left dropdown selects
//     the Pane Mode (PANE-4, PANE-7);
//   - draws a handle in the middle of each splitter; dragging it moves the
//     boundary between the two parts of that split (PANE-3), the drag in
//     pixels turned into a fraction of the workspace extent across it.
// Buttons are enabled from the Workspace's planner checks: add needs 20% of
// the workspace across the edge (PANE-27), join and swap a Neighbor
// (PANE-14), and join a result a Layout tree can hold (PANE-25).
//
// Keys: a pane's frame and slot are keyed by its id, so its widgets survive
// layout changes. Its chrome (mode dropdown, frame buttons) is keyed by the
// pane's position in tree order, because pane ids are generated per peer
// (`<actorHex>:<counter>`) while tests and help need a stable address.
// The owner builds content from PaneDescriptor and owns content-specific
// state; this widget knows nothing about documents or drawing.
// ---------------------------------------------------------------------------

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../help/contextual_help.dart';
import '../workspace/layout_tree.dart';
import '../workspace/pane_kind.dart';
import '../workspace/workspace.dart';
import 'touch_target.dart';

/// Thickness of the gap between two panes, which holds the splitter.
const double _splitterThickness = 8;

/// Thickness of a frame-edge toolbar strip.
const double _stripThickness = 20;

/// Width of the frame border.
const double _frameWidth = 2;

/// The identity and current mode of one pane.
class PaneDescriptor {
  const PaneDescriptor({required this.id, required this.kind});

  /// The pane's node id, stable for the lifetime of the pane including mode
  /// changes and moves in the Layout tree.
  final String id;

  final PaneKind kind;
}

/// Builds app-owned content for one pane.
typedef PaneContentBuilder = Widget Function(
  BuildContext context,
  PaneDescriptor pane,
);

/// Draws [workspace] and forwards user edits to it. Pane content stays owned
/// by the caller.
class PaneSystem extends StatefulWidget {
  const PaneSystem({
    super.key,
    required this.workspace,
    required this.contentBuilder,
  });

  final Workspace workspace;
  final PaneContentBuilder contentBuilder;

  @override
  State<PaneSystem> createState() => _PaneSystemState();
}

class _PaneSystemState extends State<PaneSystem> {
  /// The pane whose frame is highlighted; the first pane while this is null
  /// or names a pane that no longer shows.
  String? _focusedPaneId;

  /// Marks pane [paneId] as the one whose frame is highlighted.
  void _focusPane(String paneId) {
    if (_focusedPaneId == paneId) return;
    setState(() => _focusedPaneId = paneId);
  }

  /// Adds a pane against [edge] of [paneId] and highlights it.
  void _addPane(String paneId, PaneEdge edge) {
    final added = widget.workspace.add(paneId, edge);
    if (added != null) _focusPane(added);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.workspace,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final area = constraints.biggest;
          final workspace = widget.workspace;
          final ids = workspace.paneIds;
          final focused = ids.contains(_focusedPaneId)
              ? _focusedPaneId
              : ids.firstOrNull;
          return Stack(
            children: [
              for (var index = 0; index < ids.length; index++)
                _positionedPane(
                  context,
                  workspace,
                  ids[index],
                  index,
                  area,
                  focused: ids[index] == focused,
                ),
              for (final splitter in workspace.splitters)
                _positionedSplitter(context, splitter, area),
            ],
          );
        },
      ),
    );
  }

  /// Places pane [id] at its rectangle, inset by half a splitter on every side
  /// that is not on the workspace boundary.
  Widget _positionedPane(
    BuildContext context,
    Workspace workspace,
    String id,
    int index,
    Size area, {
    required bool focused,
  }) {
    final rect = workspace.rectOf(id);
    const inset = _splitterThickness / 2;
    const edge = layoutEpsilon;
    final left = rect.left * area.width + (rect.left > edge ? inset : 0);
    final top = rect.top * area.height + (rect.top > edge ? inset : 0);
    final right = rect.right * area.width - (rect.right < 1 - edge ? inset : 0);
    final bottom =
        rect.bottom * area.height - (rect.bottom < 1 - edge ? inset : 0);
    return Positioned(
      key: ValueKey('slot-$id'),
      left: left,
      top: top,
      width: math.max(0.0, right - left),
      height: math.max(0.0, bottom - top),
      child: _buildPane(context, workspace, id, index, focused: focused),
    );
  }

  /// Builds a framed pane: edge strips, mode toolbar, and content.
  Widget _buildPane(
    BuildContext context,
    Workspace workspace,
    String id,
    int index, {
    required bool focused,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final kind = workspace.kindOf(id);
    Widget strip(PaneEdge edge) =>
        _buildStrip(context, workspace, id, index, edge);
    return Listener(
      key: ValueKey('pane-$id'),
      onPointerDown: (_) => _focusPane(id),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(
            color: focused ? scheme.primary : scheme.outlineVariant,
            width: _frameWidth,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(_frameWidth),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // The chrome needs a strip on each edge plus the mode toolbar.
              // A pane smaller than that (only possible while the window is
              // too small for 10% of it to hold the chrome, which is deferred
              // in docs/spec/panes.md) shows only its frame.
              const chromeHeight = 2 * _stripThickness + touchTargetHeight;
              const chromeWidth = 2 * _stripThickness + 48;
              if (constraints.maxHeight + 1e-6 < chromeHeight ||
                  constraints.maxWidth + 1e-6 < chromeWidth) {
                return const SizedBox.expand();
              }
              return Column(
                children: [
                  strip(PaneEdge.top),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        strip(PaneEdge.left),
                        Expanded(
                          child: Column(
                            children: [
                              _buildToolbar(context, workspace, id, index, kind),
                              Expanded(
                                child: Material(
                                  color: scheme.surface,
                                  child: ClipRect(
                                    child: widget.contentBuilder(
                                      context,
                                      PaneDescriptor(id: id, kind: kind),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        strip(PaneEdge.right),
                      ],
                    ),
                  ),
                  strip(PaneEdge.bottom),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Builds the frame-edge toolbar along [edge] of pane [id], which is the
  /// pane at [index] in tree order.
  Widget _buildStrip(
    BuildContext context,
    Workspace workspace,
    String id,
    int index,
    PaneEdge edge,
  ) {
    final scheme = Theme.of(context).colorScheme;
    Widget button(
      String action,
      IconData icon,
      String label,
      VoidCallback? on,
    ) {
      return _FrameButton(
        key: ValueKey('frame-${edge.name}-$action-$index'),
        icon: icon,
        label: '$label ${edge.name} edge',
        onPressed: on,
      );
    }

    final row = SizedBox(
      height: _stripThickness,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            button(
              'add',
              Icons.add,
              'Add pane at',
              workspace.canAdd(id, edge) ? () => _addPane(id, edge) : null,
            ),
            button(
              'join',
              Icons.call_merge,
              'Join pane across',
              workspace.canJoin(id, edge)
                  ? () => workspace.join(id, edge)
                  : null,
            ),
            button(
              'swap',
              Icons.swap_horiz,
              'Swap pane across',
              workspace.canSwap(id, edge)
                  ? () => workspace.swap(id, edge)
                  : null,
            ),
          ],
        ),
      ),
    );
    final strip = switch (edge) {
      PaneEdge.top || PaneEdge.bottom => row,
      // Rotated so the buttons read along the edge: counter-clockwise on the
      // left edge, clockwise on the right (PANE-11).
      PaneEdge.left => RotatedBox(quarterTurns: 3, child: row),
      PaneEdge.right => RotatedBox(quarterTurns: 1, child: row),
    };
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: edge.isVertical
          ? SizedBox(width: _stripThickness, child: strip)
          : SizedBox(width: double.infinity, child: strip),
    );
  }

  /// Builds the pane toolbar whose far-left dropdown selects the mode
  /// (PANE-4, PANE-7).
  Widget _buildToolbar(
    BuildContext context,
    Workspace workspace,
    String id,
    int index,
    PaneKind kind,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: SizedBox(
        height: touchTargetHeight,
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
                  key: ValueKey('pane-mode-$index'),
                  value: kind,
                  isExpanded: true,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                  iconEnabledColor: scheme.onPrimaryContainer,
                  dropdownColor: scheme.surface,
                  borderRadius: BorderRadius.circular(4),
                  itemHeight: touchTargetHeight,
                  items: [
                    for (final option in PaneKind.values)
                      DropdownMenuItem(
                        value: option,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(option.icon, size: 18),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                option.label,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  // In a narrow pane only the mode icon fits beside the arrow.
                  selectedItemBuilder: (context) => [
                    for (final option in PaneKind.values)
                      LayoutBuilder(
                        builder: (context, constraints) =>
                            constraints.maxWidth < 72
                            ? FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Icon(option.icon, size: 18),
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(option.icon, size: 12),
                                  Flexible(
                                    child: Text(
                                      option.label,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                  ],
                  onChanged: (option) {
                    if (option != null) workspace.setKind(id, option);
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Places [splitter] over the gap it occupies, extended by half a splitter
  /// at each end that is not on the workspace boundary, so that it meets the
  /// splitter it ends on and corners are filled.
  Widget _positionedSplitter(
    BuildContext context,
    LayoutSplitter splitter,
    Size area,
  ) {
    const half = _splitterThickness / 2;
    const edge = layoutEpsilon;
    final vertical = splitter.vertical;
    final extent = vertical ? area.height : area.width;
    final start = splitter.start * extent - (splitter.start > edge ? half : 0);
    final end = splitter.end * extent + (splitter.end < 1 - edge ? half : 0);
    final across =
        splitter.position * (vertical ? area.width : area.height) - half;
    return Positioned(
      key: ValueKey('splitter-${splitter.key}'),
      left: vertical ? across : start,
      top: vertical ? start : across,
      width: vertical ? _splitterThickness : end - start,
      height: vertical ? end - start : _splitterThickness,
      child: _buildSplitter(context, splitter, area),
    );
  }

  /// Builds a splitter: a gap-colored bar with a handle at its center that
  /// resizes the two parts it separates when dragged (PANE-3). A drag of d
  /// pixels moves it by d over the workspace extent across it, so the
  /// Workspace can clamp in fractions (PANE-26).
  Widget _buildSplitter(
    BuildContext context,
    LayoutSplitter splitter,
    Size area,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final vertical = splitter.vertical;
    void drag(double pixels, double extent) {
      if (extent > 0) widget.workspace.moveSplitter(splitter, pixels / extent);
    }

    return HelpTarget(
      topic: HelpIds.paneBoundary,
      child: MouseRegion(
        cursor: vertical
            ? SystemMouseCursors.resizeColumn
            : SystemMouseCursors.resizeRow,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: vertical
              ? (details) => drag(details.delta.dx, area.width)
              : null,
          onVerticalDragUpdate: vertical
              ? null
              : (details) => drag(details.delta.dy, area.height),
          child: Semantics(
            label: 'Resize pane boundary',
            child: ColoredBox(
              color: scheme.surfaceContainerHighest,
              child: Center(
                child: Container(
                  width: vertical ? 4 : 32,
                  height: vertical ? 32 : 4,
                  decoration: BoxDecoration(
                    color: scheme.primary,
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

/// One add, join, or swap button on a frame-edge strip. A null [onPressed]
/// disables it.
class _FrameButton extends StatelessWidget {
  const _FrameButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    return HelpTarget(
      topic: HelpIds.paneBoundary,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: label,
        onTap: onPressed,
        excludeSemantics: true,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: _stripThickness,
            height: _stripThickness,
            child: Icon(
              icon,
              size: 14,
              color: enabled
                  ? scheme.primary
                  : scheme.onSurface.withValues(alpha: 0.3),
            ),
          ),
        ),
      ),
    );
  }
}
