// What: The stored node table of a workspace's Layout tree (field names,
//   kinds, axes), PaneEdge, the default table, and projectLayout, which turns
//   any table into the shown layout: splits and panes with unit-square
//   rectangles, the splitters between parts, and neighbor lookup.
// Why: Workspaces are shared through a CRDT that merges values per key, not
//   invariants, so the stored layout can be any merge result. A pure read-time
//   projection that every peer computes the same way keeps the shown layout a
//   valid tree without ever writing repairs
//   (docs/decisions/010-pane-layout-tree.md).
// Coupled to: layout_ops.dart (edit planners that read a LayoutProjection and
//   return writes to the table), layout_flash.dart (Flash JSON to and from a
//   table), fractional_index.dart (order keys), and workspace.dart (keeps a
//   table in the session document and shows its projection).
//
// ---------------------------------------------------------------------------
// Layout tree overview
//
// What: a workspace's layout is a table `node id -> fields` (PNT-A0016-01).
// The root is the split `root`; every other node names its `parent`. Splits
// hold an `axis`; panes hold `mode`, `state` and `deleted`; every node has an
// `order` key among its siblings and a `share` of its parent's extent.
//
// Why not rectangles: per-key merges of rectangles can overlap or leave gaps
// (PANE-1). A tree has no gaps by construction, and the projection below
// turns every table, however malformed, into a valid tree.
//
// How: projectLayout walks down from `root` (PNT-A0016-02). Deleted panes,
// nodes of unknown kind, splits with an unknown axis and nodes reached twice
// are skipped; empty splits are dropped; a split with one shown child is
// replaced by that child, which keeps the split's share and records the split
// as its anchor (PNT-A0016-04); a child split with its parent's axis is
// flattened into the parent. Shares are normalized per stored split, a bad
// share counting as the mean of the good ones. If no pane shows, the pane
// node with the smallest id is shown alone (PNT-A0016-03).
//
// Invariants: the result depends only on the table's contents (never on map
// iteration order), never throws, and its pane rectangles partition the unit
// square exactly: adjacent parts share one computed boundary value. Edits
// never mutate the table here; layout_ops.dart plans writes against the
// LayoutFrame structure that the projection exposes.
// ---------------------------------------------------------------------------

import 'dart:ui' show Rect;

import 'fractional_index.dart';

/// One side of a pane's frame (a Frame edge of docs/spec/panes.md).
enum PaneEdge {
  top,
  right,
  bottom,
  left;

  /// Whether the frame edge is a vertical line (left or right).
  bool get isVertical => this == left || this == right;
}

/// A workspace's stored layout: node id to that node's fields.
typedef LayoutNodes = Map<String, Map<String, Object?>>;

/// Id of the root split (PNT-A0016-01).
const String layoutRootId = 'root';

/// Mode of the default workspace's pane; equals `PaneKind.canvas.name` in
/// pane_kind.dart, which this file does not import to stay free of Flutter.
const String defaultPaneMode = 'canvas';

/// Tolerance for comparing unit coordinates.
const double layoutEpsilon = 1e-9;

/// The smallest pane extent a splitter drag may leave, as a fraction of the
/// workspace extent in the drag direction (PANE-26).
const double minimumPaneFraction = 0.1;

/// The smallest pane extent across an edge that still allows 'add' on it, as a
/// fraction of the workspace extent in that direction (PANE-27).
const double minimumAddFraction = 0.2;

/// Field names and kind values of a stored node (PNT-A0016-01).
abstract final class LayoutField {
  static const String parent = 'parent';
  static const String kind = 'kind';
  static const String order = 'order';
  static const String share = 'share';
  static const String axis = 'axis';
  static const String mode = 'mode';
  static const String state = 'state';
  static const String deleted = 'deleted';

  /// [kind] value of a split.
  static const String split = 'split';

  /// [kind] value of a pane.
  static const String pane = 'pane';
}

/// The direction a split places its parts in: [row] left to right, [column]
/// top to bottom. [name] is the stored `axis` value.
enum LayoutAxis {
  row,
  column;

  /// The axis named by a stored `axis` value, or null for anything else.
  static LayoutAxis? parse(Object? value) => switch (value) {
    'row' => row,
    'column' => column,
    _ => null,
  };

  /// The axis whose parts are separated by lines parallel to [edge]: [row]
  /// for left and right edges, [column] for top and bottom edges.
  static LayoutAxis across(PaneEdge edge) => edge.isVertical ? row : column;

  LayoutAxis get other => this == row ? column : row;

  /// Start of [rect] along this axis.
  double start(Rect rect) => this == row ? rect.left : rect.top;

  /// End of [rect] along this axis.
  double end(Rect rect) => this == row ? rect.right : rect.bottom;

  /// Extent of [rect] along this axis.
  double extent(Rect rect) => end(rect) - start(rect);
}

/// Whether [value] is a usable share: a finite positive number.
bool isValidShare(Object? value) => value is num && value.isFinite && value > 0;

/// A deep copy of a JSON-like value: maps (keeping only String keys) and lists
/// are copied, everything else is returned as is. Used so that tables, writes
/// and projections never share mutable maps.
Object? copyLayoutValue(Object? value) => switch (value) {
  Map() => <String, Object?>{
    for (final entry in value.entries)
      if (entry.key is String)
        entry.key as String: copyLayoutValue(entry.value),
  },
  List() => [for (final item in value) copyLayoutValue(item)],
  _ => value,
};

/// The order key of a stored node as used for sorting: its `order` if it is a
/// String, otherwise the empty string.
String layoutOrderOf(Map<String, Object?>? record) {
  final order = record?[LayoutField.order];
  return order is String ? order : '';
}

/// A new table holding the root split and one pane in [mode] with no stored
/// Per-mode state, so every mode starts from its defaults (the Default
/// workspace of docs/spec/workspace.md). The pane's id comes from [newId] and
/// its order key ends in [actor]'s suffix.
LayoutNodes createDefaultLayout({
  required String Function() newId,
  required String actor,
  String mode = defaultPaneMode,
}) {
  final pane = newId();
  return {
    layoutRootId: {
      LayoutField.kind: LayoutField.split,
      LayoutField.axis: LayoutAxis.row.name,
    },
    pane: {
      LayoutField.parent: layoutRootId,
      LayoutField.kind: LayoutField.pane,
      LayoutField.order: orderKeysAfter(null, 1, actor).single,
      LayoutField.share: 1.0,
      LayoutField.mode: mode,
      LayoutField.state: <String, Object?>{},
      LayoutField.deleted: false,
    },
  };
}

// ---------------------------------------------------------------------------
// Projection output
// ---------------------------------------------------------------------------

/// A shown split or pane. [anchor] is the outermost stored node whose
/// position in the tree it occupies after collapsing (PNT-A0016-04); edits
/// write position and share to it. [rect] is in unit coordinates: (0, 0) is
/// the workspace's top left and (1, 1) its bottom right.
sealed class ShownNode {
  ShownNode(this.anchor, this.rect);

  final String anchor;
  final Rect rect;
}

/// A shown pane: stored node [id] with its mode and Per-mode states copied
/// from the table. [mode] is null when the stored value is not a String;
/// [state] is empty when the stored value is not a map.
final class ShownPane extends ShownNode {
  ShownPane({
    required String anchor,
    required Rect rect,
    required this.id,
    required this.mode,
    required this.state,
  }) : super(anchor, rect);

  final String id;
  final String? mode;
  final Map<String, Object?> state;
}

/// A shown split after flattening: [parts] in display order, each with the
/// normalized fraction in [shares] of this split's extent along [axis].
/// [frame] is the stored structure the parts come from.
final class ShownSplit extends ShownNode {
  ShownSplit({
    required String anchor,
    required Rect rect,
    required this.axis,
    required this.parts,
    required this.shares,
    required this.frame,
  }) : super(anchor, rect);

  final LayoutAxis axis;
  final List<ShownNode> parts;
  final List<double> shares;
  final LayoutFrame frame;
}

/// A stored split with two or more shown children, before flattening.
///
/// [body] is the stored split whose children these are; it differs from the
/// shown split's anchor when single-child splits collapsed onto it. Shares
/// here are effective values in the stored frame: valid shares as stored, a
/// bad one replaced by the mean of the valid ones. layout_ops.dart writes
/// shares in this frame so that only the changed parts are written.
final class LayoutFrame {
  LayoutFrame._(this.body, this.axis, this.children)
    : total = children.fold(0.0, (sum, child) => sum + child.share),
      hasInvalidShare = children.any((child) => !child.shareValid);

  final String body;
  final LayoutAxis axis;

  /// Shown children sorted by order key, then id.
  final List<FrameChild> children;

  /// Sum of the children's effective shares.
  final double total;

  /// Whether any child's stored share is not [isValidShare].
  final bool hasInvalidShare;
}

/// One shown child of a [LayoutFrame]: the stored node [anchor] whose share
/// positions it, and what shows there: a stored [frame] (a split) or a
/// [pane] id.
final class FrameChild {
  FrameChild._({
    required this.anchor,
    required this.share,
    required this.shareValid,
    required this.frame,
    required this.pane,
  });

  final String anchor;

  /// The effective share in the parent frame.
  final double share;

  /// Whether the stored share was valid; when false [share] is the mean.
  final bool shareValid;
  final LayoutFrame? frame;
  final String? pane;
}

/// The boundary between parts [index] and [index] + 1 of the shown split
/// anchored at [split]. A [LayoutAxis.row] split has vertical splitters at x
/// = [position] spanning y from [start] to [end]; a column split the
/// transpose.
final class LayoutSplitter {
  const LayoutSplitter({
    required this.split,
    required this.index,
    required this.axis,
    required this.position,
    required this.start,
    required this.end,
  });

  final String split;
  final int index;
  final LayoutAxis axis;
  final double position;
  final double start;
  final double end;

  /// Whether the splitter is a vertical line.
  bool get vertical => axis == LayoutAxis.row;

  /// Identity that survives drags, for widget keys.
  String get key => '$split#$index';
}

/// The shown layout of a node table, computed by [projectLayout].
final class LayoutProjection {
  LayoutProjection._({
    required this.nodes,
    required this.root,
    required this.panes,
    required this.splits,
    required this.splitters,
    required this.rescued,
    required this.soleRootChild,
    required this._parents,
    required this._frames,
  }) : _paneById = {for (final pane in panes) pane.id: pane},
       _splitByAnchor = {for (final split in splits) split.anchor: split};

  /// The table this projection was computed from. Planners read stored
  /// values from it, so the caller must not change it while the projection
  /// is in use.
  final LayoutNodes nodes;

  /// The whole shown tree; null only when the table holds no pane node.
  final ShownNode? root;

  /// Shown panes in tree order.
  final List<ShownPane> panes;

  /// Shown splits in tree order.
  final List<ShownSplit> splits;

  final List<LayoutSplitter> splitters;

  /// Whether no pane showed and the smallest-id pane is shown by the rescue
  /// rule (PNT-A0016-03). layout_ops.dart restores it into the tree before
  /// changing the layout.
  final bool rescued;

  /// The root's only shown child before it collapsed onto `root`, or null
  /// when the root shows two or more children. layout_ops.dart adds beside it
  /// when the shown root is a single pane.
  final String? soleRootChild;

  final Map<ShownNode, ShownSplit> _parents;
  final Map<String, LayoutFrame> _frames;
  final Map<String, ShownPane> _paneById;
  final Map<String, ShownSplit> _splitByAnchor;

  /// The shown pane with stored id [id], or null.
  ShownPane? pane(String id) => _paneById[id];

  /// The shown split anchored at [anchor], or null.
  ShownSplit? splitAt(String anchor) => _splitByAnchor[anchor];

  /// The shown split that has [node] as a part, or null for the root.
  ShownSplit? parentOf(ShownNode node) => _parents[node];

  /// The stored frame that holds [anchor] as a child, or null when [anchor]
  /// is `root` or not shown.
  LayoutFrame? frameOf(String anchor) => _frames[anchor];

  /// The Neighbor of [edge] of pane [paneId] (docs/spec/panes.md): the pane
  /// whose opposite frame edge coincides with it along its whole length,
  /// within [layoutEpsilon]. Null on the workspace boundary and when several
  /// panes border the edge.
  String? neighbor(String paneId, PaneEdge edge) {
    final self = _paneById[paneId];
    if (self == null) return null;
    final r = self.rect;
    bool near(double a, double b) => (a - b).abs() <= layoutEpsilon;
    for (final other in panes) {
      if (other.id == paneId) continue;
      final o = other.rect;
      final coincides = switch (edge) {
        PaneEdge.right =>
          near(o.left, r.right) &&
              near(o.top, r.top) &&
              near(o.bottom, r.bottom),
        PaneEdge.left =>
          near(o.right, r.left) &&
              near(o.top, r.top) &&
              near(o.bottom, r.bottom),
        PaneEdge.bottom =>
          near(o.top, r.bottom) &&
              near(o.left, r.left) &&
              near(o.right, r.right),
        PaneEdge.top =>
          near(o.bottom, r.top) &&
              near(o.left, r.left) &&
              near(o.right, r.right),
      };
      if (coincides) return other.id;
    }
    return null;
  }

  /// Every shown pane inside [node], in tree order.
  List<ShownPane> panesUnder(ShownNode node) => switch (node) {
    ShownPane() => [node],
    ShownSplit() => [for (final part in node.parts) ...panesUnder(part)],
  };
}

// ---------------------------------------------------------------------------
// Projection
// ---------------------------------------------------------------------------

/// The shown layout of [nodes] (PNT-A0016-02 to PNT-A0016-04). See the
/// overview at the top of this file. Pure and deterministic: equal tables
/// give equal projections on every peer.
LayoutProjection projectLayout(LayoutNodes nodes) {
  // Children per parent, skipping nodes that cannot show: unknown kind, a
  // split without a known axis, a deleted pane, the root itself (it has no
  // parent), or a parent that is not a String.
  final children = <String, List<String>>{};
  for (final entry in nodes.entries) {
    final id = entry.key;
    final record = entry.value;
    if (id == layoutRootId || !_isShowable(record)) continue;
    final parent = record[LayoutField.parent];
    if (parent is! String) continue;
    (children[parent] ??= []).add(id);
  }
  for (final list in children.values) {
    list.sort((a, b) {
      final byOrder = layoutOrderOf(nodes[a])
          .compareTo(layoutOrderOf(nodes[b]));
      return byOrder != 0 ? byOrder : a.compareTo(b);
    });
  }

  final builder = _Builder(nodes, children);
  final rootRecord = nodes[layoutRootId];
  final top =
      rootRecord != null &&
          rootRecord[LayoutField.kind] == LayoutField.split &&
          _isShowable(rootRecord)
      ? builder.build(layoutRootId)
      : null;

  final panes = <ShownPane>[];
  final splits = <ShownSplit>[];
  final splitters = <LayoutSplitter>[];
  final parents = <ShownNode, ShownSplit>{};
  const unit = Rect.fromLTRB(0, 0, 1, 1);

  ShownNode show(String anchor, LayoutFrame? frame, String? paneId, Rect rect) {
    if (frame == null) {
      final pane = _shownPane(nodes, paneId!, anchor, rect);
      panes.add(pane);
      return pane;
    }
    final flat = <(FrameChild, double)>[];
    _flatten(frame, 1, flat);
    final axis = frame.axis;
    final start = axis.start(rect);
    final extent = axis.extent(rect);
    final shares = [for (final (_, fraction) in flat) fraction];
    // Boundaries are computed once and shared by both neighbors, and the last
    // part ends exactly at the split's end, so parts tile without gaps.
    final bounds = <double>[start];
    var sum = 0.0;
    for (var i = 0; i < flat.length - 1; i++) {
      sum += shares[i];
      bounds.add(start + extent * sum);
    }
    bounds.add(axis.end(rect));
    final split = ShownSplit(
      anchor: anchor,
      rect: rect,
      axis: axis,
      parts: [],
      shares: shares,
      frame: frame,
    );
    splits.add(split);
    for (var i = 0; i < flat.length; i++) {
      final child = flat[i].$1;
      final partRect = axis == LayoutAxis.row
          ? Rect.fromLTRB(bounds[i], rect.top, bounds[i + 1], rect.bottom)
          : Rect.fromLTRB(rect.left, bounds[i], rect.right, bounds[i + 1]);
      final part = show(child.anchor, child.frame, child.pane, partRect);
      split.parts.add(part);
      parents[part] = split;
      if (i > 0) {
        splitters.add(
          LayoutSplitter(
            split: anchor,
            index: i - 1,
            axis: axis,
            position: bounds[i],
            start: axis.other.start(rect),
            end: axis.other.end(rect),
          ),
        );
      }
    }
    return split;
  }

  ShownNode? root;
  var rescued = false;
  if (top != null) {
    root = show(top.anchor, top.frame, top.pane, unit);
  } else {
    final rescue = _smallestPaneId(nodes);
    if (rescue != null) {
      root = show(rescue, null, rescue, unit);
      rescued = true;
    }
  }

  return LayoutProjection._(
    nodes: nodes,
    root: root,
    panes: List.unmodifiable(panes),
    splits: List.unmodifiable(splits),
    splitters: List.unmodifiable(splitters),
    rescued: rescued,
    soleRootChild: builder.collapsedChild[layoutRootId],
    parents: parents,
    frames: builder.frameOfAnchor,
  );
}

/// Whether [record] is a node the projection can show: a pane that is not
/// deleted, or a split with a known axis.
bool _isShowable(Map<String, Object?> record) =>
    switch (record[LayoutField.kind]) {
      LayoutField.pane => record[LayoutField.deleted] != true,
      LayoutField.split => LayoutAxis.parse(record[LayoutField.axis]) != null,
      _ => false,
    };

/// The pane node with the smallest id, deleted or not (PNT-A0016-03).
String? _smallestPaneId(LayoutNodes nodes) {
  String? best;
  for (final entry in nodes.entries) {
    if (entry.value[LayoutField.kind] != LayoutField.pane) continue;
    if (best == null || entry.key.compareTo(best) < 0) best = entry.key;
  }
  return best;
}

ShownPane _shownPane(LayoutNodes nodes, String id, String anchor, Rect rect) {
  final record = nodes[id];
  final mode = record?[LayoutField.mode];
  final state = record?[LayoutField.state];
  return ShownPane(
    anchor: anchor,
    rect: rect,
    id: id,
    mode: mode is String ? mode : null,
    state: state is Map
        ? copyLayoutValue(state) as Map<String, Object?>
        : <String, Object?>{},
  );
}

/// Appends to [out] the parts [frame] shows after flattening child frames
/// with its axis, each with its fraction of the frame scaled by [scale].
void _flatten(LayoutFrame frame, double scale, List<(FrameChild, double)> out) {
  for (final child in frame.children) {
    final fraction = child.share / frame.total * scale;
    final inner = child.frame;
    if (inner != null && inner.axis == frame.axis) {
      _flatten(inner, fraction, out);
    } else {
      out.add((child, fraction));
    }
  }
}

/// A built subtree before layout: what shows at [anchor], with the stored
/// share that positions it.
final class _Item {
  _Item(this.anchor, this.share, this.frame, this.pane);

  final String anchor;
  final Object? share;
  final LayoutFrame? frame;
  final String? pane;
}

/// Walks the table from the root, collapsing single-child splits and
/// recording frames (PNT-A0016-02).
final class _Builder {
  _Builder(this.nodes, this.children);

  final LayoutNodes nodes;
  final Map<String, List<String>> children;
  final Set<String> _visited = {};

  /// Anchor of every child of every recorded frame, to its frame.
  final Map<String, LayoutFrame> frameOfAnchor = {};

  /// For each split with one shown child, that child's anchor before the
  /// split collapsed onto it.
  final Map<String, String> collapsedChild = {};

  _Item? build(String id) {
    // A node reached twice is skipped, so cycles from concurrent moves end.
    if (!_visited.add(id)) return null;
    final record = nodes[id]!;
    final share = record[LayoutField.share];
    if (record[LayoutField.kind] == LayoutField.pane) {
      return _Item(id, share, null, id);
    }
    final kids = <_Item>[
      for (final child in children[id] ?? const <String>[]) ?build(child),
    ];
    if (kids.isEmpty) return null;
    if (kids.length == 1) {
      final only = kids.single;
      collapsedChild[id] = only.anchor;
      return _Item(id, share, only.frame, only.pane);
    }
    final valid = [
      for (final kid in kids)
        if (isValidShare(kid.share)) (kid.share as num).toDouble(),
    ];
    final mean = valid.isEmpty
        ? 1.0
        : valid.fold(0.0, (a, b) => a + b) / valid.length;
    final frame = LayoutFrame._(
      id,
      LayoutAxis.parse(record[LayoutField.axis])!,
      List.unmodifiable([
        for (final kid in kids)
          FrameChild._(
            anchor: kid.anchor,
            share: isValidShare(kid.share)
                ? (kid.share as num).toDouble()
                : mean,
            shareValid: isValidShare(kid.share),
            frame: kid.frame,
            pane: kid.pane,
          ),
      ]),
    );
    for (final child in frame.children) {
      frameOfAnchor[child.anchor] = frame;
    }
    return _Item(id, share, frame, null);
  }
}
