// What: Helpers shared by the Layout tree tests: a builder for node tables
//   from a nested description, an id source, applying planned writes, and
//   checks that a projection partitions the unit square.
// Why: Several test files build tables and check PANE-1 the same way; one
//   copy keeps the checks identical.
// Coupled to: lib/workspace/layout_tree.dart and lib/workspace/layout_ops.dart
//   (the tables and writes built and applied here); used by
//   layout_tree_test.dart, layout_flash_test.dart and
//   layout_convergence_test.dart.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:painter/workspace/fractional_index.dart';
import 'package:painter/workspace/layout_ops.dart';
import 'package:painter/workspace/layout_tree.dart';

/// A node in a table description for [buildTable].
sealed class NodeSpec {
  NodeSpec(this.id, this.share);

  final String id;
  final Object? share;
}

final class PaneSpec extends NodeSpec {
  PaneSpec(super.id, super.share, this.mode, this.state, this.deleted);

  final String mode;
  final Map<String, Object?> state;
  final bool deleted;
}

final class SplitSpec extends NodeSpec {
  SplitSpec(super.id, super.share, this.axis, this.parts);

  final LayoutAxis axis;
  final List<NodeSpec> parts;
}

/// A pane [id] with stored [share].
PaneSpec pane(
  String id, {
  Object? share = 1.0,
  String mode = 'canvas',
  Map<String, Object?> state = const {},
  bool deleted = false,
}) => PaneSpec(id, share, mode, state, deleted);

/// A row split [id] with stored [share].
SplitSpec row(String id, List<NodeSpec> parts, {Object? share = 1.0}) =>
    SplitSpec(id, share, LayoutAxis.row, parts);

/// A column split [id] with stored [share].
SplitSpec column(String id, List<NodeSpec> parts, {Object? share = 1.0}) =>
    SplitSpec(id, share, LayoutAxis.column, parts);

/// A table whose root split is [root] (its id must be `root`), with order
/// keys following the order of each parts list.
LayoutNodes buildTable(SplitSpec root) {
  assert(root.id == layoutRootId);
  final nodes = <String, Map<String, Object?>>{
    layoutRootId: {
      LayoutField.kind: LayoutField.split,
      LayoutField.axis: root.axis.name,
    },
  };
  void addParts(SplitSpec split) {
    final keys = orderKeysAfter(null, split.parts.length, 'test');
    for (var i = 0; i < split.parts.length; i++) {
      final part = split.parts[i];
      final fields = <String, Object?>{
        LayoutField.parent: split.id,
        LayoutField.order: keys[i],
        LayoutField.share: part.share,
      };
      switch (part) {
        case PaneSpec():
          fields[LayoutField.kind] = LayoutField.pane;
          fields[LayoutField.mode] = part.mode;
          fields[LayoutField.state] = copyLayoutValue(part.state);
          fields[LayoutField.deleted] = part.deleted;
        case SplitSpec():
          fields[LayoutField.kind] = LayoutField.split;
          fields[LayoutField.axis] = part.axis.name;
      }
      nodes[part.id] = fields;
      if (part is SplitSpec) addParts(part);
    }
  }

  addParts(root);
  return nodes;
}

/// An id source producing `<actor>:<n>` ids, like a peer would.
String Function() idSource(String actor) {
  var counter = 0;
  return () => '$actor:${counter++}';
}

/// A planner for [actor] with its own id source.
LayoutPlanner plannerFor(String actor) =>
    LayoutPlanner(newId: idSource(actor), actor: actor);

/// Applies [writes] (which must not be null) to [nodes] and returns the new
/// projection.
LayoutProjection applyAndProject(LayoutNodes nodes, List<LayoutWrite>? writes) {
  expect(writes, isNotNull, reason: 'the edit should be allowed');
  applyLayoutWrites(nodes, writes!);
  return projectLayout(nodes);
}

/// Pane rectangles by pane id.
Map<String, Rect> rectsOf(LayoutProjection layout) => {
  for (final pane in layout.panes) pane.id: pane.rect,
};

/// Whether [actual] equals [expected] within 1e-9 on every side.
Matcher rectNear(Rect expected) => predicate<Rect>(
  (actual) =>
      (actual.left - expected.left).abs() < 1e-9 &&
      (actual.top - expected.top).abs() < 1e-9 &&
      (actual.right - expected.right).abs() < 1e-9 &&
      (actual.bottom - expected.bottom).abs() < 1e-9,
  'within 1e-9 of $expected',
);

/// Expects [layout] to show at least one pane and its pane rectangles to
/// partition the unit square: inside it, with positive area, not
/// overlapping, and with areas summing to 1 (so there are no gaps).
void expectPartition(LayoutProjection layout) {
  expect(layout.panes, isNotEmpty, reason: 'PANE-9');
  var area = 0.0;
  final rects = [for (final pane in layout.panes) pane.rect];
  for (final rect in rects) {
    expect(rect.left, greaterThanOrEqualTo(-1e-12));
    expect(rect.top, greaterThanOrEqualTo(-1e-12));
    expect(rect.right, lessThanOrEqualTo(1 + 1e-12));
    expect(rect.bottom, lessThanOrEqualTo(1 + 1e-12));
    expect(rect.width, greaterThan(0));
    expect(rect.height, greaterThan(0));
    area += rect.width * rect.height;
  }
  expect(area, closeTo(1, 1e-9));
  for (var i = 0; i < rects.length; i++) {
    for (var j = i + 1; j < rects.length; j++) {
      final overlap = rects[i].intersect(rects[j]);
      final shared = overlap.width > 0 && overlap.height > 0
          ? overlap.width * overlap.height
          : 0.0;
      expect(shared, lessThan(1e-12), reason: 'panes overlap');
    }
  }
  final ids = [for (final pane in layout.panes) pane.id];
  expect(ids.toSet(), hasLength(ids.length));
}

/// A text form of everything a projection shows, for comparing two
/// projections exactly.
String describeLayout(LayoutProjection layout) {
  final out = StringBuffer('rescued=${layout.rescued}\n');
  for (final pane in layout.panes) {
    final r = pane.rect;
    out.writeln(
      'pane ${pane.id} @${pane.anchor} ${r.left} ${r.top} ${r.right} '
      '${r.bottom} ${pane.mode} ${pane.state}',
    );
  }
  for (final s in layout.splitters) {
    out.writeln(
      'splitter ${s.key} ${s.axis.name} ${s.position} ${s.start} ${s.end}',
    );
  }
  return out.toString();
}
