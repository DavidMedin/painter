// What: Unit tests for the Layout tree: projectLayout's rules on well-formed
//   and malformed node tables, neighbor lookup, and the add, join, swap,
//   mode, state and splitter planners, including the acceptance examples of
//   docs/spec/panes.md.
// Why: Every peer must show the same valid layout for any merged table
//   (PANE-1, PANE-9, WKSP-35), and the planners must keep the pane rules
//   (PANE-13 to PANE-16, PANE-20, PANE-25 to PANE-27) as specified by
//   docs/decisions/010-pane-layout-tree.md.
// Covers: lib/workspace/layout_tree.dart and lib/workspace/layout_ops.dart.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:painter/workspace/layout_ops.dart';
import 'package:painter/workspace/layout_tree.dart';

import 'layout_test_support.dart';

/// The 2x2 grid of the panes.md acceptance examples, built through the
/// planners: top and bottom halves split separately. Returns the table and
/// the pane ids top-left, top-right, bottom-left, bottom-right.
(LayoutNodes, List<String>) _grid() {
  final planner = plannerFor('aa');
  final nodes = createDefaultLayout(newId: () => 'tl', actor: 'aa');
  var layout = projectLayout(nodes);
  layout = applyAndProject(nodes, planner.add(layout, 'tl', PaneEdge.bottom));
  final bottomLeft = layout.panes.last.id;
  layout = applyAndProject(nodes, planner.add(layout, 'tl', PaneEdge.right));
  final topRight = layout.panes[1].id;
  layout = applyAndProject(
    nodes,
    planner.add(layout, bottomLeft, PaneEdge.right),
  );
  final bottomRight = layout.panes.last.id;
  return (nodes, ['tl', topRight, bottomLeft, bottomRight]);
}

/// A tree layout in which joining a1 with its right neighbor a2 would leave
/// a pinwheel of five panes around e, which no Layout tree can hold. In
/// thirds of the square: a1 and a2 top left, d left, e center, b right, c
/// bottom.
LayoutNodes _pinwheelMinusOneJoin() => buildTable(
  row(layoutRootId, [
    column('l', [pane('a1'), pane('d', share: 2)]),
    column('r', share: 2, [
      row('u', share: 2, [
        column('v', [pane('a2'), pane('e')]),
        pane('b'),
      ]),
      pane('c'),
    ]),
  ]),
);

void main() {
  group('projection', () {
    test('of the default table is one canvas pane filling the square', () {
      final nodes = createDefaultLayout(newId: idSource('aa'), actor: 'aa');
      final layout = projectLayout(nodes);
      expect(layout.panes, hasLength(1));
      final only = layout.panes.single;
      expect(only.rect, const Rect.fromLTRB(0, 0, 1, 1));
      expect(only.mode, defaultPaneMode);
      expect(only.anchor, layoutRootId);
      expect(layout.splitters, isEmpty);
      expect(layout.rescued, isFalse);
    });

    test('drops a split with no shown children', () {
      final layout = projectLayout(
        buildTable(
          row(layoutRootId, [
            pane('a'),
            column('empty', []),
            column('onlyDeleted', [pane('x', deleted: true)]),
            pane('b'),
          ]),
        ),
      );
      final rects = rectsOf(layout);
      expect(rects.keys, ['a', 'b']);
      expect(rects['a'], const Rect.fromLTRB(0, 0, 0.5, 1));
      expect(rects['b'], const Rect.fromLTRB(0.5, 0, 1, 1));
    });

    test('replaces a single-child split by the child, keeping its share', () {
      final layout = projectLayout(
        buildTable(
          row(layoutRootId, [
            pane('a'),
            column('s', share: 3, [
              row('t', [pane('b', share: 0.001)]),
            ]),
          ]),
        ),
      );
      final b = layout.pane('b')!;
      expect(
        layout.pane('a')!.rect,
        rectNear(const Rect.fromLTRB(0, 0, 0.25, 1)),
      );
      expect(b.rect, rectNear(const Rect.fromLTRB(0.25, 0, 1, 1)));
      expect(b.anchor, 's', reason: 'the outermost collapsed node');
      expect(layout.splits, hasLength(1));
    });

    test('flattens a child split with its parent axis, scaling shares', () {
      final layout = projectLayout(
        buildTable(
          row(layoutRootId, [
            pane('a'),
            row('s', [pane('b'), pane('c', share: 3)]),
          ]),
        ),
      );
      expect(layout.splits, hasLength(1));
      final root = layout.splits.single;
      expect(
        [for (final p in root.parts) (p as ShownPane).id],
        ['a', 'b', 'c'],
      );
      expect(root.shares[0], closeTo(0.5, 1e-12));
      expect(root.shares[1], closeTo(0.125, 1e-12));
      expect(root.shares[2], closeTo(0.375, 1e-12));
      expect(layout.pane('b')!.anchor, 'b');
      expect(layout.splitters, hasLength(2));
    });

    test('counts a bad share as the mean of the valid ones', () {
      final layout = projectLayout(
        buildTable(
          row(layoutRootId, [
            pane('a', share: 2),
            pane('b', share: -1),
            pane('c', share: 'wide'),
            pane('d', share: double.nan),
            pane('e', share: 4),
            pane('f', share: null),
            pane('g', share: 0),
            pane('h', share: double.infinity),
          ]),
        ),
      );
      final shares = layout.splits.single.shares;
      // Valid: 2 and 4, mean 3; the six others count as 3 each: total 24.
      final expected = [2, 3, 3, 3, 4, 3, 3, 3].map((s) => s / 24).toList();
      for (var i = 0; i < shares.length; i++) {
        expect(shares[i], closeTo(expected[i], 1e-12));
      }
    });

    test('shares equally when no share is valid', () {
      final layout = projectLayout(
        buildTable(
          column(layoutRootId, [pane('a', share: 0), pane('b', share: 'x')]),
        ),
      );
      expect(layout.pane('a')!.rect, const Rect.fromLTRB(0, 0, 1, 0.5));
      expect(layout.pane('b')!.rect, const Rect.fromLTRB(0, 0.5, 1, 1));
    });

    test('orders children by order key, then by id', () {
      Map<String, Object?> child(Object? order) => {
        LayoutField.parent: layoutRootId,
        LayoutField.kind: LayoutField.pane,
        LayoutField.order: order,
        LayoutField.share: 1,
      };
      final layout = projectLayout({
        layoutRootId: {
          LayoutField.kind: LayoutField.split,
          LayoutField.axis: 'row',
        },
        'z': child('b'),
        'y': child('a'),
        'x': child('a'),
        'w': child(7),
      });
      // A non-String order sorts as the empty string.
      expect([for (final p in layout.panes) p.id], ['w', 'x', 'y', 'z']);
    });

    test('skips cycles, self parents, unknown kinds and axes', () {
      final nodes = buildTable(row(layoutRootId, [pane('a')]));
      nodes[layoutRootId]![LayoutField.parent] = 'a';
      nodes['p'] = {
        LayoutField.kind: LayoutField.split,
        LayoutField.axis: 'row',
        LayoutField.parent: 'q',
      };
      nodes['q'] = {
        LayoutField.kind: LayoutField.split,
        LayoutField.axis: 'row',
        LayoutField.parent: 'p',
      };
      nodes['inCycle'] = {
        LayoutField.kind: LayoutField.pane,
        LayoutField.parent: 'p',
      };
      nodes['self'] = {
        LayoutField.kind: LayoutField.pane,
        LayoutField.parent: 'self',
      };
      nodes['blob'] = {LayoutField.kind: 'blob', LayoutField.parent: 'root'};
      nodes['diagonal'] = {
        LayoutField.kind: LayoutField.split,
        LayoutField.axis: 'diagonal',
        LayoutField.parent: 'root',
      };
      nodes['underDiagonal'] = {
        LayoutField.kind: LayoutField.pane,
        LayoutField.parent: 'diagonal',
      };
      nodes['noParent'] = {
        LayoutField.kind: LayoutField.pane,
        LayoutField.parent: 42,
      };
      final layout = projectLayout(nodes);
      expect(rectsOf(layout), {'a': const Rect.fromLTRB(0, 0, 1, 1)});
      expect(layout.rescued, isFalse);
    });

    test('shows the smallest-id pane when no pane shows', () {
      final allDeleted = projectLayout(
        buildTable(
          row(layoutRootId, [
            pane('m', deleted: true),
            pane('k', deleted: true),
          ]),
        ),
      );
      expect(allDeleted.rescued, isTrue);
      expect(rectsOf(allDeleted), {'k': const Rect.fromLTRB(0, 0, 1, 1)});

      final noRoot = buildTable(row(layoutRootId, [pane('b'), pane('a')]))
        ..remove(layoutRootId);
      expect(rectsOf(projectLayout(noRoot)).keys, ['a']);
    });

    test('shows nothing only for a table without pane nodes', () {
      final layout = projectLayout({});
      expect(layout.root, isNull);
      expect(layout.panes, isEmpty);
    });

    test('does not depend on the table iteration order', () {
      final (nodes, _) = _grid();
      final reversed = <String, Map<String, Object?>>{
        for (final key in nodes.keys.toList().reversed) key: nodes[key]!,
      };
      expect(
        describeLayout(projectLayout(reversed)),
        describeLayout(projectLayout(nodes)),
      );
    });

    test('lists one splitter per pair of adjacent parts', () {
      final layout = projectLayout(
        buildTable(
          row(layoutRootId, [
            pane('a'),
            column('s', [pane('b'), pane('c')]),
          ]),
        ),
      );
      expect(layout.splitters, hasLength(2));
      final vertical = layout.splitters.firstWhere((s) => s.vertical);
      expect(vertical.split, layoutRootId);
      expect(vertical.index, 0);
      expect(vertical.position, 0.5);
      expect((vertical.start, vertical.end), (0.0, 1.0));
      final horizontal = layout.splitters.firstWhere((s) => !s.vertical);
      expect(horizontal.split, 's');
      expect(horizontal.position, 0.5);
      expect((horizontal.start, horizontal.end), (0.5, 1.0));
    });
  });

  group('neighbor', () {
    test('of A beside B over C does not exist (panes.md example 1)', () {
      final planner = plannerFor('aa');
      final nodes = createDefaultLayout(newId: () => 'A', actor: 'aa');
      var layout = projectLayout(nodes);
      layout = applyAndProject(nodes, planner.add(layout, 'A', PaneEdge.right));
      final b = layout.panes.last.id;
      layout = applyAndProject(nodes, planner.add(layout, b, PaneEdge.bottom));
      final c = layout.panes.last.id;

      expect(layout.neighbor('A', PaneEdge.right), isNull);
      expect(canJoin(layout, 'A', PaneEdge.right), isFalse);
      expect(canSwap(layout, 'A', PaneEdge.right), isFalse);
      expect(planner.join(layout, 'A', PaneEdge.right), isNull);
      expect(layout.neighbor(b, PaneEdge.left), isNull);
      expect(layout.neighbor(b, PaneEdge.bottom), c);
      expect(layout.neighbor('A', PaneEdge.left), isNull);
    });
  });

  group('add', () {
    test('gives the new pane the half touching each edge', () {
      for (final edge in PaneEdge.values) {
        final nodes = createDefaultLayout(newId: () => 'p', actor: 'aa');
        final layout = applyAndProject(
          nodes,
          plannerFor('bb').add(projectLayout(nodes), 'p', edge),
        );
        final added = layout.panes.firstWhere((pane) => pane.id != 'p').rect;
        final kept = layout.pane('p')!.rect;
        final (expectAdded, expectKept) = switch (edge) {
          PaneEdge.top => (
            const Rect.fromLTRB(0, 0, 1, 0.5),
            const Rect.fromLTRB(0, 0.5, 1, 1),
          ),
          PaneEdge.bottom => (
            const Rect.fromLTRB(0, 0.5, 1, 1),
            const Rect.fromLTRB(0, 0, 1, 0.5),
          ),
          PaneEdge.left => (
            const Rect.fromLTRB(0, 0, 0.5, 1),
            const Rect.fromLTRB(0.5, 0, 1, 1),
          ),
          PaneEdge.right => (
            const Rect.fromLTRB(0.5, 0, 1, 1),
            const Rect.fromLTRB(0, 0, 0.5, 1),
          ),
        };
        expect(added, expectAdded, reason: '$edge');
        expect(kept, expectKept, reason: '$edge');
        expectPartition(layout);
      }
    });

    test('copies the mode and every Per-mode state into the new pane', () {
      final nodes = buildTable(
        row(layoutRootId, [
          pane(
            'a',
            mode: 'manual',
            state: {
              'manual': {'help': 'general'},
              'canvas': {'extent': 2},
            },
          ),
        ]),
      );
      final layout = applyAndProject(
        nodes,
        plannerFor('bb').add(projectLayout(nodes), 'a', PaneEdge.right),
      );
      final added = layout.panes.firstWhere((pane) => pane.id != 'a');
      expect(added.mode, 'manual');
      expect(added.state, layout.pane('a')!.state);
      final a = nodes['a']![LayoutField.state]! as Map;
      final copy = nodes[added.id]![LayoutField.state]! as Map;
      expect(identical(a['canvas'], copy['canvas']), isFalse);
    });

    test('inserts beside the anchor in a split along the edge normal', () {
      final nodes = buildTable(row(layoutRootId, [pane('a'), pane('b')]));
      final writes = plannerFor('bb')
          .add(projectLayout(nodes), 'a', PaneEdge.right);
      final layout = applyAndProject(nodes, writes);
      final splitsCreated = writes!.whereType<CreateNode>().where(
        (w) => w.fields[LayoutField.kind] == LayoutField.split,
      );
      expect(splitsCreated, isEmpty);
      final ids = [for (final pane in layout.panes) pane.id];
      expect(ids.first, 'a');
      expect(ids.last, 'b');
      expect(layout.pane('a')!.rect, const Rect.fromLTRB(0, 0, 0.25, 1));
      expect(layout.pane(ids[1])!.rect, const Rect.fromLTRB(0.25, 0, 0.5, 1));
      expect(layout.pane('b')!.rect, const Rect.fromLTRB(0.5, 0, 1, 1));
    });

    test('wraps the anchor in a new split across the parent axis', () {
      final nodes = buildTable(row(layoutRootId, [pane('a'), pane('b')]));
      final writes = plannerFor('bb')
          .add(projectLayout(nodes), 'a', PaneEdge.bottom);
      final layout = applyAndProject(nodes, writes);
      final wrapper = writes!.whereType<CreateNode>().singleWhere(
        (w) => w.fields[LayoutField.kind] == LayoutField.split,
      );
      expect(wrapper.fields[LayoutField.axis], 'column');
      final added = layout.panes.firstWhere((p) => p.id != 'a' && p.id != 'b');
      expect(nodes[added.id]![LayoutField.parent], wrapper.node);
      expect(nodes['a']![LayoutField.parent], wrapper.node);
      expect(layout.pane('a')!.rect, const Rect.fromLTRB(0, 0, 0.5, 0.5));
      expect(added.rect, const Rect.fromLTRB(0, 0.5, 0.5, 1));
      expect(layout.pane('b')!.rect, const Rect.fromLTRB(0.5, 0, 1, 1));
    });

    test('keeps the other parts when the anchor share was invalid', () {
      final nodes = buildTable(
        row(layoutRootId, [
          pane('a', share: 'bad'),
          pane('b', share: 1),
          pane('c', share: -5),
          pane('d', share: 2),
        ]),
      );
      final before = rectsOf(projectLayout(nodes));
      final layout = applyAndProject(
        nodes,
        plannerFor('bb').add(projectLayout(nodes), 'a', PaneEdge.right),
      );
      for (final id in ['b', 'c', 'd']) {
        expect(layout.pane(id)!.rect, rectNear(before[id]!), reason: id);
      }
      expect(
        layout.pane('a')!.rect.width,
        closeTo(before['a']!.width / 2, 1e-12),
      );
    });

    test('is enabled only while the pane spans 20% across the edge', () {
      final wide = projectLayout(
        buildTable(
          row(layoutRootId, [pane('a', share: 0.2), pane('b', share: 0.8)]),
        ),
      );
      expect(canAdd(wide, 'a', PaneEdge.right), isTrue);
      expect(canAdd(wide, 'a', PaneEdge.left), isTrue);

      final narrow = projectLayout(
        buildTable(
          row(layoutRootId, [pane('a', share: 0.19), pane('b', share: 0.81)]),
        ),
      );
      expect(canAdd(narrow, 'a', PaneEdge.right), isFalse);
      expect(canAdd(narrow, 'a', PaneEdge.left), isFalse);
      expect(plannerFor('bb').add(narrow, 'a', PaneEdge.left), isNull);
      // Across a top or bottom edge the pane's height counts, which is 100%.
      expect(canAdd(narrow, 'a', PaneEdge.top), isTrue);
    });

    test('on a rescued pane restores it into the tree first', () {
      final nodes = buildTable(
        row(layoutRootId, [pane('m', deleted: true), pane('k', deleted: true)]),
      );
      final layout = applyAndProject(
        nodes,
        plannerFor('bb').add(projectLayout(nodes), 'k', PaneEdge.right),
      );
      expect(layout.rescued, isFalse);
      expect(layout.panes, hasLength(2));
      expect(layout.pane('k')!.rect, const Rect.fromLTRB(0, 0, 0.5, 1));
      expectPartition(layout);
    });
  });

  group('join', () {
    test('of adjacent parts adds the neighbor share to the pane', () {
      final nodes = buildTable(
        row(layoutRootId, [pane('a'), pane('b'), pane('c')]),
      );
      final writes = plannerFor('bb')
          .join(projectLayout(nodes), 'a', PaneEdge.right);
      expect(writes, hasLength(2));
      final layout = applyAndProject(nodes, writes);
      expect(nodes['b']![LayoutField.deleted], isTrue);
      expect(
        layout.pane('a')!.rect,
        rectNear(const Rect.fromLTRB(0, 0, 2 / 3, 1)),
      );
      expect(
        layout.pane('c')!.rect,
        rectNear(const Rect.fromLTRB(2 / 3, 0, 1, 1)),
      );
    });

    test('of aligned non-siblings rebuilds the tree (panes.md example 2)', () {
      final (nodes, ids) = _grid();
      final [topLeft, topRight, bottomLeft, bottomRight] = ids;
      var layout = projectLayout(nodes);
      expect(layout.neighbor(topLeft, PaneEdge.bottom), bottomLeft);
      expect(canJoin(layout, topLeft, PaneEdge.bottom), isTrue);

      layout = applyAndProject(
        nodes,
        plannerFor('bb').join(layout, topLeft, PaneEdge.bottom),
      );
      expect(rectsOf(layout).keys.toSet(), {topLeft, topRight, bottomRight});
      expect(layout.pane(topLeft)!.rect, const Rect.fromLTRB(0, 0, 0.5, 1));
      expect(layout.pane(topLeft)!.mode, defaultPaneMode);
      expect(layout.pane(topRight)!.rect, const Rect.fromLTRB(0.5, 0, 1, 0.5));
      expect(
        layout.pane(bottomRight)!.rect,
        const Rect.fromLTRB(0.5, 0.5, 1, 1),
      );
      expect(nodes[bottomLeft]![LayoutField.deleted], isTrue);
      expectPartition(layout);
    });

    test('is disabled once a splitter drag misaligns the panes '
        '(panes.md example 3)', () {
      final (nodes, ids) = _grid();
      final [topLeft, _, bottomLeft, _] = ids;
      var layout = projectLayout(nodes);
      final bottomSplitter = layout.splitters.singleWhere(
        (s) => s.vertical && s.start == 0.5,
      );
      layout = applyAndProject(
        nodes,
        plannerFor('bb').moveSplitter(layout, bottomSplitter, 0.1),
      );
      expect(layout.pane(bottomLeft)!.rect.right, closeTo(0.6, 1e-12));
      expect(layout.neighbor(topLeft, PaneEdge.bottom), isNull);
      expect(canJoin(layout, topLeft, PaneEdge.bottom), isFalse);
    });

    test('is disabled when the result would be a pinwheel', () {
      final layout = projectLayout(_pinwheelMinusOneJoin());
      expectPartition(layout);
      expect(layout.neighbor('a1', PaneEdge.right), 'a2');
      expect(canSwap(layout, 'a1', PaneEdge.right), isTrue);
      expect(canJoin(layout, 'a1', PaneEdge.right), isFalse);
      expect(plannerFor('bb').join(layout, 'a1', PaneEdge.right), isNull);
      // Joining a2 with e below it still forms a tree.
      expect(canJoin(layout, 'a2', PaneEdge.bottom), isTrue);
    });

    test('removes a neighbor that sits in a collapsed split', () {
      final nodes = buildTable(
        row(layoutRootId, [
          pane('a'),
          column('s', [pane('b')]),
        ]),
      );
      final layout = applyAndProject(
        nodes,
        plannerFor('bb').join(projectLayout(nodes), 'a', PaneEdge.right),
      );
      expect(rectsOf(layout), {'a': const Rect.fromLTRB(0, 0, 1, 1)});
    });
  });

  group('swap', () {
    test('exchanges modes and states and keeps rectangles', () {
      final nodes = buildTable(
        row(layoutRootId, [
          pane(
            'a',
            state: {
              'canvas': {'extent': 3},
            },
          ),
          pane(
            'b',
            mode: 'manual',
            state: {
              'manual': {'help': 'general'},
            },
          ),
        ]),
      );
      final before = projectLayout(nodes);
      final layout = applyAndProject(
        nodes,
        plannerFor('bb').swap(before, 'a', PaneEdge.right),
      );
      expect(layout.pane('a')!.mode, 'manual');
      expect(layout.pane('a')!.state, {
        'manual': {'help': 'general'},
      });
      expect(layout.pane('b')!.mode, 'canvas');
      expect(layout.pane('b')!.state, {
        'canvas': {'extent': 3},
      });
      expect(rectsOf(layout), rectsOf(before));
    });

    test('is disabled without a neighbor', () {
      final layout = projectLayout(buildTable(row(layoutRootId, [pane('a')])));
      expect(canSwap(layout, 'a', PaneEdge.left), isFalse);
      expect(plannerFor('bb').swap(layout, 'a', PaneEdge.left), isNull);
    });
  });

  group('mode and state', () {
    test('changing mode keeps the states of other modes (PANE-20)', () {
      final nodes = buildTable(
        row(layoutRootId, [
          pane(
            'a',
            state: {
              'canvas': {'extent': 3},
            },
          ),
        ]),
      );
      final planner = plannerFor('bb');
      var layout = applyAndProject(
        nodes,
        planner.setMode(projectLayout(nodes), 'a', 'manual'),
      );
      layout = applyAndProject(
        nodes,
        planner.setModeState(layout, 'a', 'manual', {'help': 'general'}),
      );
      layout = applyAndProject(nodes, planner.setMode(layout, 'a', 'canvas'));
      expect(layout.pane('a')!.mode, 'canvas');
      expect(layout.pane('a')!.state, {
        'canvas': {'extent': 3},
        'manual': {'help': 'general'},
      });
    });

    test('replaces a malformed state with a map of the one mode', () {
      final nodes = buildTable(row(layoutRootId, [pane('a')]));
      nodes['a']![LayoutField.state] = 'garbage';
      final layout = applyAndProject(
        nodes,
        plannerFor('bb')
            .setModeState(projectLayout(nodes), 'a', 'canvas', {'extent': 1}),
      );
      expect(layout.pane('a')!.state, {
        'canvas': {'extent': 1},
      });
    });

    test('is refused for a pane that does not show', () {
      final layout = projectLayout(buildTable(row(layoutRootId, [pane('a')])));
      expect(plannerFor('bb').setMode(layout, 'gone', 'canvas'), isNull);
    });
  });

  group('splitter', () {
    test('moves the boundary between two parts', () {
      final nodes = buildTable(row(layoutRootId, [pane('a'), pane('b')]));
      final before = projectLayout(nodes);
      final layout = applyAndProject(
        nodes,
        plannerFor('bb').moveSplitter(before, before.splitters.single, 0.2),
      );
      expect(layout.pane('a')!.rect.right, closeTo(0.7, 1e-12));
      expect(layout.splitters.single.key, before.splitters.single.key);
    });

    test('stops when a pane reaches 10% of the workspace', () {
      for (final delta in [-1.0, 1.0]) {
        final nodes = buildTable(row(layoutRootId, [pane('a'), pane('b')]));
        final before = projectLayout(nodes);
        final layout = applyAndProject(
          nodes,
          plannerFor('bb').moveSplitter(before, before.splitters.single, delta),
        );
        final smaller = delta < 0 ? 'a' : 'b';
        expect(layout.pane(smaller)!.rect.width, closeTo(0.1, 1e-12));
      }
    });

    test('stops when a nested pane reaches 10% of the workspace', () {
      final nodes = buildTable(
        row(layoutRootId, [
          pane('a'),
          column('s', [
            pane('b'),
            row('t', [pane('c'), pane('d')]),
          ]),
        ]),
      );
      final before = projectLayout(nodes);
      final outer = before.splitters.firstWhere((s) => s.split == layoutRootId);
      final layout = applyAndProject(
        nodes,
        plannerFor('bb').moveSplitter(before, outer, 1),
      );
      // c and d each take half of s, so s stops at 20%.
      expect(layout.pane('c')!.rect.width, closeTo(0.1, 1e-12));
      expect(layout.pane('d')!.rect.width, closeTo(0.1, 1e-12));
      expect(layout.pane('a')!.rect.width, closeTo(0.8, 1e-12));
      expectPartition(layout);
    });

    test('never forces a pane already under 10% to grow', () {
      final nodes = buildTable(
        row(layoutRootId, [pane('a', share: 0.05), pane('b', share: 0.95)]),
      );
      final before = projectLayout(nodes);
      final planner = plannerFor('bb');
      expect(planner.moveSplitter(before, before.splitters.single, -0.2), []);
      final layout = applyAndProject(
        nodes,
        planner.moveSplitter(before, before.splitters.single, 0.01),
      );
      expect(layout.pane('a')!.rect.width, closeTo(0.06, 1e-12));
    });

    test('moves only its two parts in a flattened split', () {
      final nodes = buildTable(
        row(layoutRootId, [
          pane('a'),
          row('s', [pane('b'), pane('c')]),
        ]),
      );
      final planner = plannerFor('bb');
      var layout = projectLayout(nodes);
      final first = layout.splitters.firstWhere((s) => s.index == 0);
      layout = applyAndProject(nodes, planner.moveSplitter(layout, first, 0.1));
      expect(layout.pane('a')!.rect.width, closeTo(0.6, 1e-12));
      expect(layout.pane('b')!.rect.width, closeTo(0.15, 1e-12));
      expect(layout.pane('c')!.rect.width, closeTo(0.25, 1e-12));

      final second = layout.splitters.firstWhere((s) => s.index == 1);
      layout = applyAndProject(
        nodes,
        planner.moveSplitter(layout, second, -0.03),
      );
      expect(layout.pane('a')!.rect.width, closeTo(0.6, 1e-12));
      expect(layout.pane('b')!.rect.width, closeTo(0.12, 1e-12));
      expect(layout.pane('c')!.rect.width, closeTo(0.28, 1e-12));
    });

    test('is refused when the splitter no longer exists', () {
      final layout = projectLayout(buildTable(row(layoutRootId, [pane('a')])));
      const stale = LayoutSplitter(
        split: layoutRootId,
        index: 0,
        axis: LayoutAxis.row,
        position: 0.5,
        start: 0,
        end: 1,
      );
      expect(plannerFor('bb').moveSplitter(layout, stale, 0.1), isNull);
    });
  });
}
