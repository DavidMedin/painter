// What: A randomized test of concurrent edits through Workspace on two or
//   three real Automerge replicas of one session document: each replica
//   makes random edits (add, join, swap, splitter drags, mode changes,
//   Manual pages, canvas pans) on its own, then all replicas sync to
//   quiescence.
// Why: Members of a workspace must see the same Layout tree, Pane Modes and
//   Per-mode state once they have the same changes, including concurrent
//   ones (docs/spec/workspace.md WKSP-35), and that layout must stay a valid
//   partition with at least one pane (PANE-1, PANE-9). This checks the whole
//   path: planner writes translated into CRDT operations, Automerge's merge,
//   re-projection on remote changes, and live views following them
//   (docs/decisions/009-shared-workspaces.md,
//   docs/decisions/010-pane-layout-tree.md).
// Covers: lib/workspace/workspace.dart over
//   lib/crdt/automerge_crdt_document.dart; layout_convergence_test.dart covers
//   the same merge with a simulated CRDT.

import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:painter/canvas/canvas_viewport.dart';
import 'package:painter/help/manual_catalog.dart';
import 'package:painter/workspace/layout_tree.dart';
import 'package:painter/workspace/pane_kind.dart';
import 'package:painter/workspace/workspace.dart';

import 'layout_test_support.dart';
import 'workspace_test_support.dart';

const _paneSize = Size(800, 600);

/// The default view (docs/decisions/011-relative-canvas-view.md) as stored.
final Map<String, Object?> _defaultView = {
  'center': {
    'x': CanvasViewportController.defaultCenter.dx,
    'y': CanvasViewportController.defaultCenter.dy,
  },
  'extent': CanvasViewportController.defaultExtent,
  'rotation': 0.0,
};

/// Applies one random edit to [workspace]; disallowed edits do nothing.
void _randomEdit(Workspace workspace, Random random) {
  final ids = workspace.paneIds;
  final id = ids[random.nextInt(ids.length)];
  final edge = PaneEdge.values[random.nextInt(PaneEdge.values.length)];
  switch (random.nextInt(9)) {
    case 0 || 1:
      workspace.add(id, edge);
    case 2 || 3:
      workspace.join(id, edge);
    case 4:
      workspace.swap(id, edge);
    case 5:
      final splitters = workspace.splitters;
      if (splitters.isEmpty) return;
      workspace.moveSplitter(
        splitters[random.nextInt(splitters.length)],
        random.nextDouble() - 0.5,
      );
    case 6:
      workspace.setKind(id, [
        PaneKind.canvas,
        PaneKind.manual,
        PaneKind.log,
      ][random.nextInt(3)]);
    case 7:
      workspace.setManualHelpId(
        id,
        HelpId.values[random.nextInt(HelpId.values.length)],
      );
    default:
      workspace.canvasViewport(id)
        ..panBy(
          Offset(random.nextDouble() * 80 - 40, random.nextDouble() * 80 - 40),
          _paneSize,
        )
        ..zoomAt(Offset.zero, _paneSize, 0.5 + random.nextDouble());
  }
  expectPartition(workspace.layout);
}

void main() {
  testWidgets('concurrent edits on Automerge replicas converge (WKSP-35)', (
    tester,
  ) async {
    for (var seed = 0; seed < 150; seed++) {
      final random = Random(seed);
      final origin = sessionWithDefaultWorkspace();
      final sessions = [
        origin,
        for (var i = 0; i < 1 + random.nextInt(2); i++) replicaOf(origin),
      ];
      final workspaces = [
        for (final session in sessions) openWorkspace(session: session),
      ];
      for (var round = 0; round < 4; round++) {
        for (final workspace in workspaces) {
          final edits = 1 + random.nextInt(6);
          for (var i = 0; i < edits; i++) {
            _randomEdit(workspace, random);
          }
        }
        // Let every replica commit its pending views and drags.
        await tester.pump(viewCommitInterval);
        syncAll(sessions);

        final reason = 'seed $seed round $round';
        final expected = describeLayout(workspaces.first.layout);
        expectPartition(workspaces.first.layout);
        for (final workspace in workspaces.skip(1)) {
          expect(describeLayout(workspace.layout), expected, reason: reason);
          expect(workspace.toJson(), workspaces.first.toJson(), reason: reason);
        }
        // Every live view shows its pane's stored view, so all Members see
        // the same canvas region.
        for (final workspace in workspaces) {
          for (final pane in workspace.layout.panes) {
            final stored = CanvasViewportController.fromJson(
              pane.state[PaneKind.canvas.name],
            );
            final live = workspace.canvasViewport(pane.id);
            expect(
              live.toJson(),
              stored?.toJson() ?? _defaultView,
              reason: reason,
            );
            stored?.dispose();
          }
        }
      }
    }
  });
}
