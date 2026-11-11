// What: The writes a Layout tree edit makes to the stored node table
//   (LayoutWrite and applyLayoutWrites), and LayoutPlanner, which plans add,
//   join, swap, mode and state changes, and splitter drags against a
//   LayoutProjection, plus the canAdd, canJoin and canSwap checks.
// Why: Edits must be expressed as per-field writes so the CRDT can merge
//   concurrent edits key by key, and they must target stored anchors rather
//   than the shown tree (docs/decisions/010-pane-layout-tree.md). Keeping
//   planning separate from the projection keeps the projection read-only.
// Coupled to: layout_tree.dart (the projection, its LayoutFrame structure,
//   PaneEdge and the overview of the whole system), fractional_index.dart
//   (order keys for new and moved nodes), and workspace.dart (applies the
//   writes to the session document).
//
// Every planner returns null when the edit is not allowed (the matching can*
// check is false or the pane is not shown) and otherwise a list of writes
// that, applied in order, produce the edited layout. No planner deletes the
// last pane (PANE-9): join deletes only the neighbor, never the pane itself.

import 'dart:ui' show Rect;

import 'fractional_index.dart';
import 'layout_tree.dart';

/// One write to a stored node table.
sealed class LayoutWrite {
  const LayoutWrite(this.node);

  /// Id of the node written.
  final String node;
}

/// Sets [field] of [node] to [value]; a null [value] removes the field.
final class SetNodeField extends LayoutWrite {
  const SetNodeField(super.node, this.field, this.value);

  final String field;
  final Object? value;
}

/// Creates [node] with [fields].
final class CreateNode extends LayoutWrite {
  const CreateNode(super.node, this.fields);

  final Map<String, Object?> fields;
}

/// Sets the Per-mode state of [mode] inside the `state` map of pane [node],
/// leaving the other modes' states untouched, so that concurrent changes to
/// different modes' states both survive a merge.
final class SetModeState extends LayoutWrite {
  const SetModeState(super.node, this.mode, this.state);

  final String mode;
  final Map<String, Object?> state;
}

/// Applies [writes] in order to the mutable table [nodes], as a caller that
/// is not backed by a CRDT would. Values are copied, so later changes to a
/// write do not reach the table.
void applyLayoutWrites(LayoutNodes nodes, Iterable<LayoutWrite> writes) {
  for (final write in writes) {
    switch (write) {
      case SetNodeField(:final node, :final field, :final value):
        final record = nodes[node] ??= <String, Object?>{};
        if (value == null) {
          record.remove(field);
        } else {
          record[field] = copyLayoutValue(value);
        }
      case CreateNode(:final node, :final fields):
        nodes[node] = copyLayoutValue(fields) as Map<String, Object?>;
      case SetModeState(:final node, :final mode, :final state):
        final record = nodes[node] ??= <String, Object?>{};
        final current = record[LayoutField.state];
        final states = current is Map<String, Object?>
            ? current
            : record[LayoutField.state] = <String, Object?>{};
        states[mode] = copyLayoutValue(state);
    }
  }
}

/// Whether 'add' is enabled on [edge] of pane [paneId]: the pane is shown and
/// its extent across [edge] is at least [minimumAddFraction] of the
/// workspace's (PANE-27).
bool canAdd(LayoutProjection layout, String paneId, PaneEdge edge) {
  final pane = layout.pane(paneId);
  if (pane == null) return false;
  final extent = LayoutAxis.across(edge).extent(pane.rect);
  return extent >= minimumAddFraction - layoutEpsilon;
}

/// Whether 'swap' is enabled on [edge] of pane [paneId]: the edge has a
/// Neighbor (PANE-14).
bool canSwap(LayoutProjection layout, String paneId, PaneEdge edge) =>
    layout.neighbor(paneId, edge) != null;

/// Whether 'join' is enabled on [edge] of pane [paneId]: the edge has a
/// Neighbor (PANE-14) and the joined panes can still be held by a Layout tree
/// (PANE-25).
bool canJoin(LayoutProjection layout, String paneId, PaneEdge edge) =>
    _joinShape(layout, paneId, edge) != null;

/// Plans Layout tree edits. [newId] makes ids for new nodes (strings
/// `<actorHex>:<counter>`, docs/decisions/007-crdt-automerge.md) and [actor]
/// ends every generated order key (PNT-A0016-09).
final class LayoutPlanner {
  LayoutPlanner({required this.newId, required this.actor});

  final String Function() newId;
  final String actor;

  /// Splits pane [paneId] along a line parallel to [edge], giving the half
  /// touching [edge] to a new pane with a copy of the pane's mode and states
  /// (PANE-13, PNT-A0016-05).
  ///
  /// When the pane's anchor sits in a stored split along [edge]'s normal, the
  /// new pane is inserted beside the anchor and the anchor's share halved;
  /// otherwise a new split takes the anchor's place and holds the anchor and
  /// the new pane at share 1 each. When the shown root is the pane itself,
  /// the root split plays that new split's role, since `root` cannot move.
  List<LayoutWrite>? add(
    LayoutProjection layout,
    String paneId,
    PaneEdge edge,
  ) {
    if (!canAdd(layout, paneId, edge)) return null;
    if (layout.rescued) {
      return _afterRestore(layout, (restored) => add(restored, paneId, edge));
    }
    final pane = layout.pane(paneId)!;
    final nodes = layout.nodes;
    final axis = LayoutAxis.across(edge);
    final after = edge == PaneEdge.right || edge == PaneEdge.bottom;
    final source = nodes[paneId]!;
    final state = source[LayoutField.state];
    final added = newId();
    Map<String, Object?> newPane(String parent, String order, double share) => {
      LayoutField.parent: parent,
      LayoutField.kind: LayoutField.pane,
      LayoutField.order: order,
      LayoutField.share: share,
      LayoutField.mode: ?copyLayoutValue(source[LayoutField.mode]),
      LayoutField.state: state is Map
          ? copyLayoutValue(state)
          : <String, Object?>{},
      LayoutField.deleted: false,
    };

    final anchor = pane.anchor;
    if (anchor == layoutRootId) {
      final only = layout.soleRootChild!;
      final (key, renumber) = _insertKey(nodes, [only], after ? 1 : 0);
      return [
        if (LayoutAxis.parse(nodes[layoutRootId]![LayoutField.axis]) != axis)
          SetNodeField(layoutRootId, LayoutField.axis, axis.name),
        ...renumber,
        SetNodeField(only, LayoutField.share, 1.0),
        CreateNode(added, newPane(layoutRootId, key, 1.0)),
      ];
    }

    final frame = layout.frameOf(anchor)!;
    if (frame.axis == axis) {
      final siblings = [for (final child in frame.children) child.anchor];
      final index = siblings.indexOf(anchor);
      final half = frame.children[index].share / 2;
      final (key, renumber) = _insertKey(
        nodes,
        siblings,
        after ? index + 1 : index,
      );
      return [
        ..._materializeShares(frame, skip: anchor),
        ...renumber,
        SetNodeField(anchor, LayoutField.share, half),
        CreateNode(added, newPane(frame.body, key, half)),
      ];
    }

    final wrapper = newId();
    final stored = nodes[anchor]!;
    final keys = orderKeysAfter(null, 2, actor);
    return [
      CreateNode(wrapper, {
        LayoutField.parent: frame.body,
        LayoutField.kind: LayoutField.split,
        LayoutField.order: ?stored[LayoutField.order],
        LayoutField.share: ?stored[LayoutField.share],
        LayoutField.axis: axis.name,
      }),
      SetNodeField(anchor, LayoutField.parent, wrapper),
      SetNodeField(anchor, LayoutField.order, keys[after ? 0 : 1]),
      SetNodeField(anchor, LayoutField.share, 1.0),
      CreateNode(added, newPane(wrapper, keys[after ? 1 : 0], 1.0)),
    ];
  }

  /// Removes the Neighbor of [edge] of pane [paneId] and extends the pane over
  /// its space (PANE-15, PNT-A0016-06).
  ///
  /// Adjacent parts of one shown split: the neighbor is marked deleted and
  /// its share added to the pane's anchor. Aligned non-siblings: the panes of
  /// their lowest common shown split are rebuilt by guillotine cuts into a
  /// tree written under that split's stored body, with new split nodes.
  List<LayoutWrite>? join(
    LayoutProjection layout,
    String paneId,
    PaneEdge edge,
  ) {
    final shape = _joinShape(layout, paneId, edge);
    if (shape == null) return null;
    final writes = <LayoutWrite>[];
    switch (shape) {
      case _SiblingJoin(:final parent, :final pane, :final neighbor):
        final i = parent.parts.indexOf(pane);
        final j = parent.parts.indexOf(neighbor);
        writes.addAll(
          _retarget(
            parent.frame,
            {pane.anchor: parent.shares[i] + parent.shares[j]},
            removed: {neighbor.anchor},
          ),
        );
        writes.add(SetNodeField(neighbor.id, LayoutField.deleted, true));
      case _RebuildJoin(:final split, :final tree, :final neighbor):
        _writeTree(tree, split.frame.body, split.frame.axis, writes);
        writes.add(SetNodeField(neighbor, LayoutField.deleted, true));
    }
    return writes;
  }

  /// Exchanges the mode and Per-mode states of pane [paneId] and the Neighbor
  /// of its [edge], writing copies so panes never share state (PANE-16,
  /// PNT-A0016-07).
  List<LayoutWrite>? swap(
    LayoutProjection layout,
    String paneId,
    PaneEdge edge,
  ) {
    final other = layout.neighbor(paneId, edge);
    if (other == null) return null;
    final a = layout.nodes[paneId]!;
    final b = layout.nodes[other]!;
    return [
      SetNodeField(
        paneId,
        LayoutField.mode,
        copyLayoutValue(b[LayoutField.mode]),
      ),
      SetNodeField(
        paneId,
        LayoutField.state,
        copyLayoutValue(b[LayoutField.state]),
      ),
      SetNodeField(
        other,
        LayoutField.mode,
        copyLayoutValue(a[LayoutField.mode]),
      ),
      SetNodeField(
        other,
        LayoutField.state,
        copyLayoutValue(a[LayoutField.state]),
      ),
    ];
  }

  /// Puts pane [paneId] in [mode]; its states for other modes stay (PANE-20).
  List<LayoutWrite>? setMode(
    LayoutProjection layout,
    String paneId,
    String mode,
  ) {
    if (layout.pane(paneId) == null) return null;
    return [SetNodeField(paneId, LayoutField.mode, mode)];
  }

  /// Stores [state] as pane [paneId]'s Per-mode state for [mode]. A stored
  /// `state` that is not a map is replaced by a map holding only [mode].
  List<LayoutWrite>? setModeState(
    LayoutProjection layout,
    String paneId,
    String mode,
    Map<String, Object?> state,
  ) {
    if (layout.pane(paneId) == null) return null;
    if (layout.nodes[paneId]![LayoutField.state] is Map<String, Object?>) {
      return [SetModeState(paneId, mode, state)];
    }
    return [
      SetNodeField(paneId, LayoutField.state, {mode: copyLayoutValue(state)}),
    ];
  }

  /// Moves [splitter] by [delta], a fraction of the workspace extent across
  /// the splitter, writing the shares of the parts on either side (PANE-3,
  /// PNT-A0016-08).
  ///
  /// The move is clamped so every pane inside either part keeps at least
  /// [minimumPaneFraction] of the workspace extent along the split's axis
  /// (PANE-26); nested panes shrink in proportion to their part. A pane that
  /// is already smaller may not shrink further but is never forced to grow.
  /// Returns null when [splitter] no longer exists, and no writes when the
  /// clamped move is zero.
  List<LayoutWrite>? moveSplitter(
    LayoutProjection layout,
    LayoutSplitter splitter,
    double delta,
  ) {
    final split = layout.splitAt(splitter.split);
    if (split == null ||
        split.axis != splitter.axis ||
        splitter.index < 0 ||
        splitter.index + 1 >= split.parts.length ||
        !delta.isFinite) {
      return null;
    }
    final axis = split.axis;
    final before = split.parts[splitter.index];
    final after = split.parts[splitter.index + 1];
    final position = axis.end(before.rect);
    final lowest =
        axis.start(before.rect) + _minimumExtent(layout, before, axis);
    final highest = axis.end(after.rect) - _minimumExtent(layout, after, axis);
    final target = (position + delta)
        .clamp(
          lowest < position ? lowest : position,
          highest > position ? highest : position,
        )
        .toDouble();
    if ((target - position).abs() <= layoutEpsilon) return const [];
    final extent = axis.extent(split.rect);
    return _retarget(split.frame, {
      before.anchor: (target - axis.start(before.rect)) / extent,
      after.anchor: (axis.end(after.rect) - target) / extent,
    });
  }

  /// When [layout] shows a rescued pane (PNT-A0016-03), writes that put that
  /// pane back under a usable root, followed by [plan] run on the restored
  /// table, so the edit starts from a layout that really holds the pane.
  List<LayoutWrite>? _afterRestore(
    LayoutProjection layout,
    List<LayoutWrite>? Function(LayoutProjection restored) plan,
  ) {
    final paneId = layout.panes.single.id;
    final nodes = layout.nodes;
    final root = nodes[layoutRootId];
    final pane = nodes[paneId]!;
    final restore = <LayoutWrite>[
      if (root == null)
        CreateNode(layoutRootId, {
          LayoutField.kind: LayoutField.split,
          LayoutField.axis: LayoutAxis.row.name,
        })
      else ...[
        if (root[LayoutField.kind] != LayoutField.split)
          SetNodeField(layoutRootId, LayoutField.kind, LayoutField.split),
        if (LayoutAxis.parse(root[LayoutField.axis]) == null)
          SetNodeField(layoutRootId, LayoutField.axis, LayoutAxis.row.name),
      ],
      if (pane[LayoutField.deleted] != false)
        SetNodeField(paneId, LayoutField.deleted, false),
      if (pane[LayoutField.parent] != layoutRootId)
        SetNodeField(paneId, LayoutField.parent, layoutRootId),
    ];
    final copy = copyLayoutValue(nodes) as Map<String, Object?>;
    final table = <String, Map<String, Object?>>{
      for (final entry in copy.entries)
        if (entry.value is Map<String, Object?>)
          entry.key: entry.value as Map<String, Object?>,
    };
    applyLayoutWrites(table, restore);
    final restored = projectLayout(table);
    if (restored.rescued) return null;
    final rest = plan(restored);
    return rest == null ? null : [...restore, ...rest];
  }

  /// An order key for a new child at [index] among the stored [siblings]
  /// (sorted anchors), plus writes renumbering the siblings when no key fits
  /// between their stored keys (equal or malformed keys).
  (String, List<LayoutWrite>) _insertKey(
    LayoutNodes nodes,
    List<String> siblings,
    int index,
  ) {
    final low = index > 0 ? layoutOrderOf(nodes[siblings[index - 1]]) : null;
    final high = index < siblings.length
        ? layoutOrderOf(nodes[siblings[index]])
        : null;
    final key = orderKeyBetween(low, high, actor);
    if (key != null) return (key, const []);
    final keys = orderKeysAfter(null, siblings.length + 1, actor);
    return (
      keys[index],
      [
        for (var j = 0; j < siblings.length; j++)
          SetNodeField(
            siblings[j],
            LayoutField.order,
            keys[j < index ? j : j + 1],
          ),
      ],
    );
  }

  /// Writes [tree] as the content of stored split [body], whose stored axis
  /// is [axis]: panes are moved under it, and inner cuts become new splits.
  void _writeTree(
    _Guillotine tree,
    String body,
    LayoutAxis storedAxis,
    List<LayoutWrite> writes,
  ) {
    switch (tree) {
      case _GuillotinePane(:final pane):
        final key = orderKeysAfter(null, 1, actor).single;
        writes.addAll(_placePane(pane, body, key, 1));
      case _GuillotineCut(:final axis, :final parts, :final extents):
        if (axis != storedAxis) {
          writes.add(SetNodeField(body, LayoutField.axis, axis.name));
        }
        final keys = orderKeysAfter(null, parts.length, actor);
        for (var i = 0; i < parts.length; i++) {
          final part = parts[i];
          switch (part) {
            case _GuillotinePane(:final pane):
              writes.addAll(_placePane(pane, body, keys[i], extents[i]));
            case _GuillotineCut():
              final id = newId();
              writes.add(
                CreateNode(id, {
                  LayoutField.parent: body,
                  LayoutField.kind: LayoutField.split,
                  LayoutField.order: keys[i],
                  LayoutField.share: extents[i],
                  LayoutField.axis: part.axis.name,
                }),
              );
              _writeTree(part, id, part.axis, writes);
          }
        }
    }
  }
}

List<LayoutWrite> _placePane(
  String pane,
  String parent,
  String order,
  double share,
) => [
  SetNodeField(pane, LayoutField.parent, parent),
  SetNodeField(pane, LayoutField.order, order),
  SetNodeField(pane, LayoutField.share, share),
];

/// Writes setting every invalid share in [frame] (except [skip]'s) to its
/// effective value, so that writing a valid share elsewhere in the frame does
/// not change the mean the invalid ones stand for.
List<LayoutWrite> _materializeShares(LayoutFrame frame, {String? skip}) => [
  for (final child in frame.children)
    if (!child.shareValid && child.anchor != skip)
      SetNodeField(child.anchor, LayoutField.share, child.share),
];

/// Share writes that give the parts of the shown split built from [top]
/// the fractions in [targets] (by anchor; parts not named keep theirs) while
/// the parts in [removed] disappear.
///
/// Each stored frame keeps its scale (stored shares per unit of shown
/// extent), so only the shares of changed children are written: the named
/// parts, and the flattened frames between them and [top], whose totals
/// change. Frames with invalid shares have those materialized first.
List<LayoutWrite> _retarget(
  LayoutFrame top,
  Map<String, double> targets, {
  Set<String> removed = const {},
}) {
  final writes = <LayoutWrite>[];

  // Returns the frame's new extent as a fraction of [top].
  double visit(LayoutFrame frame, double fraction) {
    final scale = frame.total / fraction;
    final next = <FrameChild, double>{};
    var changed = false;
    for (final child in frame.children) {
      if (removed.contains(child.anchor)) {
        changed = true;
        continue;
      }
      final current = child.share / scale;
      final inner = child.frame;
      final target = inner != null && inner.axis == frame.axis
          ? visit(inner, current)
          : targets[child.anchor] ?? current;
      next[child] = target;
    }
    final written = <String>{};
    for (final MapEntry(key: child, value: target) in next.entries) {
      final share = target * scale;
      if ((share - child.share).abs() <= 1e-12 * child.share) continue;
      changed = true;
      written.add(child.anchor);
      writes.add(SetNodeField(child.anchor, LayoutField.share, share));
    }
    if (changed) {
      writes.addAll([
        for (final write in _materializeShares(frame))
          if (!written.contains(write.node)) write,
      ]);
    }
    return next.values.fold(0.0, (a, b) => a + b);
  }

  visit(top, 1);
  return writes;
}

/// The smallest extent along [axis] that [node] may shrink to while every
/// pane in it keeps [minimumPaneFraction]: panes scale with their part.
double _minimumExtent(
  LayoutProjection layout,
  ShownNode node,
  LayoutAxis axis,
) {
  final extent = axis.extent(node.rect);
  var minimum = minimumPaneFraction;
  for (final pane in layout.panesUnder(node)) {
    final own = axis.extent(pane.rect);
    if (own <= 0) continue;
    final needed = minimumPaneFraction * extent / own;
    if (needed > minimum) minimum = needed;
  }
  return minimum;
}

// ---------------------------------------------------------------------------
// Join shapes and guillotine cuts
// ---------------------------------------------------------------------------

/// How a join will be written, decided without making ids so that canJoin
/// has no side effects.
sealed class _JoinShape {}

/// The pane and its neighbor are adjacent parts of [parent].
final class _SiblingJoin extends _JoinShape {
  _SiblingJoin(this.parent, this.pane, this.neighbor);

  final ShownSplit parent;
  final ShownPane pane;
  final ShownPane neighbor;
}

/// The panes of [split] are rebuilt as [tree] without [neighbor].
final class _RebuildJoin extends _JoinShape {
  _RebuildJoin(this.split, this.tree, this.neighbor);

  final ShownSplit split;
  final _Guillotine tree;
  final String neighbor;
}

_JoinShape? _joinShape(LayoutProjection layout, String paneId, PaneEdge edge) {
  final neighborId = layout.neighbor(paneId, edge);
  if (neighborId == null) return null;
  final pane = layout.pane(paneId)!;
  final neighbor = layout.pane(neighborId)!;
  final parent = layout.parentOf(pane);
  if (parent != null && identical(parent, layout.parentOf(neighbor))) {
    final gap = parent.parts.indexOf(pane) - parent.parts.indexOf(neighbor);
    if (gap.abs() == 1) return _SiblingJoin(parent, pane, neighbor);
  }

  // Lowest shown split holding both panes.
  final ancestors = <ShownSplit>{};
  for (
    var node = layout.parentOf(pane);
    node != null;
    node = layout.parentOf(node)
  ) {
    ancestors.add(node);
  }
  ShownSplit? common;
  for (
    var node = layout.parentOf(neighbor);
    node != null;
    node = layout.parentOf(node)
  ) {
    if (ancestors.contains(node)) {
      common = node;
      break;
    }
  }
  if (common == null) return null;

  final joined = pane.rect.expandToInclude(neighbor.rect);
  final rects = [
    for (final shown in layout.panesUnder(common))
      if (shown.id != neighborId)
        (shown.id, shown.id == paneId ? joined : shown.rect),
  ];
  final tree = _guillotine(rects, common.rect, common.axis);
  return tree == null ? null : _RebuildJoin(common, tree, neighborId);
}

/// A Layout tree rebuilt from rectangles.
sealed class _Guillotine {}

final class _GuillotinePane extends _Guillotine {
  _GuillotinePane(this.pane);

  final String pane;
}

/// A split along [axis] into [parts], with each part's extent in [extents].
final class _GuillotineCut extends _Guillotine {
  _GuillotineCut(this.axis, this.parts, this.extents);

  final LayoutAxis axis;
  final List<_Guillotine> parts;
  final List<double> extents;
}

/// The tree of recursive full-width cuts that produces [items], which tile
/// [region], or null when some sub-region has no such cut (a pinwheel,
/// PANE-25). At each level every cut along one axis is taken at once, trying
/// [preferred] first, so the sub-regions can only be cut along the other.
_Guillotine? _guillotine(
  List<(String, Rect)> items,
  Rect region,
  LayoutAxis preferred,
) {
  if (items.length == 1) return _GuillotinePane(items.single.$1);
  for (final axis in [preferred, preferred.other]) {
    final low = axis.start(region);
    final cuts = <double>[];
    final starts = [for (final (_, rect) in items) axis.start(rect)]..sort();
    for (final cut in starts) {
      if (cut <= low + layoutEpsilon) continue;
      if (cuts.isNotEmpty && cut <= cuts.last + layoutEpsilon) continue;
      final straddled = items.any(
        (item) =>
            axis.start(item.$2) < cut - layoutEpsilon &&
            axis.end(item.$2) > cut + layoutEpsilon,
      );
      if (!straddled) cuts.add(cut);
    }
    if (cuts.isEmpty) continue;
    final bounds = [low, ...cuts, axis.end(region)];
    final parts = <_Guillotine>[];
    final extents = <double>[];
    for (var i = 0; i + 1 < bounds.length; i++) {
      final group = [
        for (final item in items)
          if (axis.start(item.$2) >= bounds[i] - layoutEpsilon &&
              axis.start(item.$2) < bounds[i + 1] - layoutEpsilon)
            item,
      ];
      final sub = axis == LayoutAxis.row
          ? Rect.fromLTRB(bounds[i], region.top, bounds[i + 1], region.bottom)
          : Rect.fromLTRB(region.left, bounds[i], region.right, bounds[i + 1]);
      if (group.isEmpty) return null;
      final part = _guillotine(group, sub, axis.other);
      if (part == null) return null;
      parts.add(part);
      extents.add(bounds[i + 1] - bounds[i]);
    }
    return _GuillotineCut(axis, parts, extents);
  }
  return null;
}
