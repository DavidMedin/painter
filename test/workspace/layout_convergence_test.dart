// What: A randomized test of concurrent Layout tree edits: replicas fork a
//   shared node table, each applies random edits, and their writes are merged
//   per (node, field) with a deterministic winner, the way a CRDT merges.
// Why: Concurrent edits must converge to one layout on every peer (WKSP-35)
//   and that layout must still be a valid partition with at least one pane
//   (PANE-1, PANE-9) whatever the merge picks
//   (docs/decisions/010-pane-layout-tree.md).
// Covers: lib/workspace/layout_tree.dart and lib/workspace/layout_ops.dart.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:painter/workspace/layout_ops.dart';
import 'package:painter/workspace/layout_tree.dart';

import 'layout_test_support.dart';

/// The register a write lands in: a node field, or one mode's state inside a
/// pane's `state` map (then [mode] is set).
typedef _Key = ({String node, String field, String? mode});

/// One replica: a fork of the shared table, the values it wrote last per
/// register, and its own id source.
final class _Replica {
  _Replica(this.actor, LayoutNodes base, int round)
    : nodes = _copy(base),
      planner = LayoutPlanner(newId: idSource('$actor.$round'), actor: actor);

  final String actor;
  final LayoutNodes nodes;
  final LayoutPlanner planner;
  final Map<_Key, Object?> written = {};

  void apply(List<LayoutWrite> writes) {
    applyLayoutWrites(nodes, writes);
    for (final write in writes) {
      switch (write) {
        case SetNodeField(:final node, :final field, :final value):
          written[(node: node, field: field, mode: null)] = value;
        case CreateNode(:final node, :final fields):
          for (final MapEntry(:key, :value) in fields.entries) {
            written[(node: node, field: key, mode: null)] = value;
          }
        case SetModeState(:final node, :final mode, :final state):
          written[(node: node, field: LayoutField.state, mode: mode)] = state;
      }
    }
  }
}

LayoutNodes _copy(LayoutNodes nodes) => {
  for (final MapEntry(:key, :value) in nodes.entries)
    key: copyLayoutValue(value) as Map<String, Object?>,
};

/// FNV-1a, so the winner does not depend on Dart's String.hashCode.
int _hash(String text) {
  var hash = 0x811c9dc5;
  for (final unit in text.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return hash;
}

/// Merges the replicas' registers into [base]: per register the replica
/// with the largest hash of (register, actor) wins, whatever order the
/// replicas come in. Whole-field registers are applied before mode-state
/// registers, and [replicas] order decides only map insertion order.
LayoutNodes _merge(LayoutNodes base, List<_Replica> replicas) {
  final winners = <_Key, (int, Object?)>{};
  for (final replica in replicas) {
    for (final MapEntry(:key, :value) in replica.written.entries) {
      final rank = _hash(
        '${key.node}|${key.field}|${key.mode}|${replica.actor}',
      );
      final current = winners[key];
      if (current == null || rank > current.$1) winners[key] = (rank, value);
    }
  }
  final merged = _copy(base);
  final ordered = winners.entries.toList()
    ..sort(
      (a, b) => (a.key.mode == null ? 0 : 1) - (b.key.mode == null ? 0 : 1),
    );
  for (final MapEntry(key: key, value: (_, value)) in ordered) {
    if (key.mode == null) {
      applyLayoutWrites(merged, [SetNodeField(key.node, key.field, value)]);
    } else {
      applyLayoutWrites(merged, [
        SetModeState(key.node, key.mode!, value! as Map<String, Object?>),
      ]);
    }
  }
  return merged;
}

/// Applies one random allowed edit to [replica], if any is allowed.
void _randomEdit(_Replica replica, Random random) {
  final layout = projectLayout(replica.nodes);
  final pane = layout.panes[random.nextInt(layout.panes.length)].id;
  final edge = PaneEdge.values[random.nextInt(PaneEdge.values.length)];
  final planner = replica.planner;
  final List<LayoutWrite>? writes;
  switch (random.nextInt(7)) {
    case 0 || 1:
      writes = planner.add(layout, pane, edge);
    case 2 || 3:
      writes = planner.join(layout, pane, edge);
    case 4:
      writes = planner.swap(layout, pane, edge);
    case 5:
      if (layout.splitters.isEmpty) return;
      final splitter =
          layout.splitters[random.nextInt(layout.splitters.length)];
      writes = planner.moveSplitter(
        layout,
        splitter,
        random.nextDouble() - 0.5,
      );
    default:
      writes = random.nextBool()
          ? planner.setMode(
              layout,
              pane,
              ['canvas', 'manual'][random.nextInt(2)],
            )
          : planner.setModeState(layout, pane, 'canvas', {
              'extent': random.nextInt(9),
            });
  }
  if (writes == null) return;
  replica.apply(writes);
  expectPartition(projectLayout(replica.nodes));
}

void main() {
  test('concurrent edits converge to one valid layout', () {
    for (var seed = 0; seed < 300; seed++) {
      final random = Random(seed);
      var base = createDefaultLayout(newId: () => 'origin', actor: 'origin');
      for (var round = 0; round < 4; round++) {
        final replicas = [
          for (final actor in ['a1', 'b2', 'c3'].take(2 + random.nextInt(2)))
            _Replica(actor, base, round),
        ];
        for (final replica in replicas) {
          final edits = 1 + random.nextInt(6);
          for (var i = 0; i < edits; i++) {
            _randomEdit(replica, random);
          }
        }
        final forward = _merge(base, replicas);
        final backward = _merge(base, replicas.reversed.toList());
        final reversedTable = <String, Map<String, Object?>>{
          for (final key in forward.keys.toList().reversed) key: forward[key]!,
        };
        final layout = projectLayout(forward);
        final description = describeLayout(layout);
        expect(
          describeLayout(projectLayout(backward)),
          description,
          reason: 'seed $seed round $round',
        );
        expect(
          describeLayout(projectLayout(reversedTable)),
          description,
          reason: 'seed $seed round $round',
        );
        expectPartition(layout);
        base = forward;
      }
    }
  });
}
