// What: Unit tests for Workspace over a real Automerge session document:
//   per-mode state across mode changes, add, join, swap, splitter clamps,
//   Manual placement, remote edits (including a vanished pane's live view
//   staying alive until afterDetach runs, and the last shown table
//   surviving a deleted workspace), live Canvas views and their commit
//   timing, and reading and writing the workspace section.
// Why: The pane UI is a thin layer over this model, so the behavior the specs
//   promise (PANE-13 to PANE-16, PANE-20, PANE-26, PANE-27, CNVS-6,
//   WKSP-11, WKSP-12, WKSP-33, PNT-A0015-05, PNT-A0015-07) is tested here
//   without widgets. Timing tests run under testWidgets for its fake clock.
// Covers: lib/workspace/workspace.dart (and its use of layout_ops.dart,
//   layout_flash.dart and CanvasViewportController).

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:painter/canvas/canvas_viewport.dart';
import 'package:painter/crdt/crdt_document.dart';
import 'package:painter/session/session_document.dart';
import 'package:painter/help/manual_catalog.dart';
import 'package:painter/workspace/layout_tree.dart';
import 'package:painter/workspace/pane_kind.dart';
import 'package:painter/workspace/workspace.dart';

import 'workspace_test_support.dart';

/// A Canvas pane size at which the default view maps pixels 1:1, so a pan by
/// `d` moves the view center by `-d`.
const _pane = Size(1024, 1024);

const _view = {
  'center': {'x': 12.0, 'y': -5.0},
  'extent': 512.0,
  'rotation': 0.5,
};

/// A version 2 section whose root is the single pane [pane].
Map<String, Object?> _single(Map<String, Object?> pane) => {
  'version': 2,
  'root': {'pane': pane},
};

/// A version 2 section of a row split into [panes] with equal shares.
Map<String, Object?> _row(List<Map<String, Object?>> panes) => {
  'version': 2,
  'root': {
    'split': 'row',
    'parts': [
      for (final pane in panes)
        {
          'share': 1,
          'node': {'pane': pane},
        },
    ],
  },
};

/// The stored Per-mode state of [mode] of pane [id], read from [session].
Object? _stored(SessionDocument session, String id, String mode) {
  final nodes = storedNodes(session);
  final state = nodes[id]?[LayoutField.state];
  return state is Map ? state[mode] : null;
}

/// Counts local commits of [session].
int Function() _localCommits(SessionDocument session) {
  var count = 0;
  session.addListener((origin) {
    if (origin == CrdtChangeOrigin.local) count++;
  });
  return () => count;
}

void main() {
  test('starts with one Canvas pane filling the workspace', () {
    final workspace = openWorkspace();
    expect(workspace.paneIds, hasLength(1));
    final id = workspace.paneIds.single;
    expect(workspace.kindOf(id), PaneKind.canvas);
    expect(workspace.rectOf(id), const Rect.fromLTRB(0, 0, 1, 1));
    expect(workspace.firstCanvasPaneId, id);
  });

  group('mode changes', () {
    test('keep the per-mode state of a pane (PANE-20, CNVS-6)', () {
      final session = sessionWithDefaultWorkspace();
      final workspace = openWorkspace(session: session);
      final id = workspace.paneIds.single;
      final view = workspace.canvasViewport(id)
        ..panBy(const Offset(30, 40), _pane);
      workspace.setManualHelpId(id, HelpId.openDocument);

      workspace.setKind(id, PaneKind.settings);
      workspace.setKind(id, PaneKind.manual);
      workspace.setKind(id, PaneKind.canvas);

      expect(workspace.canvasViewport(id), same(view));
      expect(view.center, const Offset(482, 472));
      expect(workspace.manualHelpId(id), HelpId.openDocument);
      // Both states are in the session document, not only in memory.
      expect(_stored(session, id, 'canvas'), view.toJson());
      expect(_stored(session, id, 'manual'), {'help': 'openDocument'});
    });
  });

  group('add', () {
    test('copies the mode and an independent copy of the state (PANE-13)', () {
      final workspace = openWorkspace();
      final first = workspace.paneIds.single;
      workspace.canvasViewport(first).panBy(const Offset(7, 9), _pane);

      final added = workspace.add(first, PaneEdge.right)!;

      expect(workspace.paneIds, [first, added]);
      expect(workspace.kindOf(added), PaneKind.canvas);
      expect(workspace.canvasViewport(added).center, const Offset(505, 503));
      workspace.canvasViewport(added).panBy(const Offset(1, 1), _pane);
      expect(workspace.canvasViewport(first).center, const Offset(505, 503));
    });

    test('is refused once the pane is under 20% across the edge (PANE-27)', () {
      final workspace = openWorkspace();
      final id = workspace.paneIds.single;
      // Widths 1, 0.5 and 0.25 may be halved; 0.125 may not.
      for (var i = 0; i < 3; i++) {
        expect(workspace.canAdd(id, PaneEdge.right), isTrue);
        expect(workspace.add(id, PaneEdge.right), isNotNull);
      }
      expect(workspace.rectOf(id).width, closeTo(0.125, 1e-9));
      expect(workspace.canAdd(id, PaneEdge.right), isFalse);
      expect(workspace.add(id, PaneEdge.left), isNull);
      expect(workspace.paneCount, 4);
      // The pane is still tall enough to split the other way.
      expect(workspace.canAdd(id, PaneEdge.top), isTrue);
    });
  });

  group('splitters', () {
    test('clamp each pane at 10% of the workspace (PANE-26)', () {
      final workspace = openWorkspace();
      final left = workspace.paneIds.single;
      final right = workspace.add(left, PaneEdge.right)!;
      expect(workspace.splitters, hasLength(1));

      workspace.moveSplitter(workspace.splitters.single, 0.2);
      expect(workspace.rectOf(left).width, closeTo(0.7, 1e-9));

      workspace.moveSplitter(workspace.splitters.single, 2);
      expect(workspace.rectOf(right).width, closeTo(0.1, 1e-9));

      workspace.moveSplitter(workspace.splitters.single, -2);
      expect(workspace.rectOf(left).width, closeTo(0.1, 1e-9));
    });
  });

  group('join', () {
    test('removes the neighbor, keeps the survivor mode, and reports it', () {
      final removed = <String>[];
      final workspace = openWorkspace(removed: removed);
      final first = workspace.paneIds.single;
      final added = workspace.add(first, PaneEdge.right)!;
      workspace.setKind(added, PaneKind.log);

      expect(workspace.join(first, PaneEdge.right), isTrue);

      expect(workspace.paneIds, [first]);
      expect(workspace.kindOf(first), PaneKind.canvas);
      expect(removed, [added]);
      expect(workspace.rectOf(first), const Rect.fromLTRB(0, 0, 1, 1));
    });

    test('does nothing without a neighbor and never removes the last pane', () {
      final removed = <String>[];
      final workspace = openWorkspace(removed: removed);
      final id = workspace.paneIds.single;
      for (final edge in PaneEdge.values) {
        expect(workspace.canJoin(id, edge), isFalse);
        expect(workspace.join(id, edge), isFalse);
      }
      expect(workspace.paneCount, 1);
      expect(removed, isEmpty);
    });
  });

  group('swap', () {
    test('exchanges mode and state but not rectangles (PANE-16)', () {
      final workspace = openWorkspace();
      final left = workspace.paneIds.single;
      final right = workspace.add(left, PaneEdge.right)!;
      workspace.canvasViewport(left).panBy(const Offset(5, 5), _pane);
      workspace.setKind(right, PaneKind.manual);
      workspace.setManualHelpId(right, HelpId.saveDocument);
      final leftRect = workspace.rectOf(left);
      final rightRect = workspace.rectOf(right);

      expect(workspace.swap(left, PaneEdge.right), isTrue);

      expect(workspace.kindOf(left), PaneKind.manual);
      expect(workspace.manualHelpId(left), HelpId.saveDocument);
      expect(workspace.kindOf(right), PaneKind.canvas);
      expect(workspace.canvasViewport(right).center, const Offset(507, 507));
      expect(workspace.rectOf(left), leftRect);
      expect(workspace.rectOf(right), rightRect);
    });

    test('does nothing without a neighbor', () {
      final workspace = openWorkspace();
      final id = workspace.paneIds.single;
      expect(workspace.canSwap(id, PaneEdge.left), isFalse);
      expect(workspace.swap(id, PaneEdge.left), isFalse);
    });
  });

  group('openManual', () {
    test('adds a Manual pane beside the widest pane, then reuses it', () {
      final workspace = openWorkspace();
      final canvas = workspace.paneIds.single;
      final first = workspace.openManual(HelpId.openDocument)!;

      expect(first, isNot(canvas));
      expect(workspace.paneIds, [canvas, first]);
      expect(workspace.kindOf(first), PaneKind.manual);
      expect(workspace.manualHelpId(first), HelpId.openDocument);

      final second = workspace.openManual(HelpId.canvas);
      expect(second, first);
      expect(workspace.paneCount, 2);
      expect(workspace.manualHelpId(first), HelpId.canvas);
    });

    test('switches the widest pane when no pane may be split', () {
      final workspace = openWorkspace();
      // Six panes of 1/6 width: none reaches the 20% that add needs.
      expect(
        workspace.applyJson(
          _row([
            for (var i = 0; i < 6; i++) {'mode': 'canvas', 'state': {}},
          ]),
        ),
        isTrue,
      );
      final first = workspace.paneIds.first;

      expect(workspace.openManual(HelpId.canvas), first);
      expect(workspace.kindOf(first), PaneKind.manual);
      expect(workspace.paneCount, 6);
    });
  });

  group('remote edits', () {
    test('show on every replica and report panes they remove (WKSP-33)', () {
      final a = sessionWithDefaultWorkspace();
      final b = replicaOf(a);
      final removedOnB = <String>[];
      final onA = openWorkspace(session: a);
      final onB = openWorkspace(session: b, removed: removedOnB);
      var notified = 0;
      onB.addListener(() => notified++);

      final first = onA.paneIds.single;
      final added = onA.add(first, PaneEdge.bottom)!;
      onA.setKind(added, PaneKind.settings);
      syncAll([a, b]);

      expect(notified, greaterThan(0));
      expect(onB.paneIds, [first, added]);
      expect(onB.kindOf(added), PaneKind.settings);
      expect(onB.rectOf(added), onA.rectOf(added));

      onA.join(first, PaneEdge.bottom);
      syncAll([a, b]);
      expect(onB.paneIds, [first]);
      expect(removedOnB, [added]);
    });

    test("a vanished pane's live view is disposed only through afterDetach "
        'and ignores input until then', () {
      final a = sessionWithDefaultWorkspace();
      final b = replicaOf(a);
      final onA = openWorkspace(session: a);
      final first = onA.paneIds.single;
      final added = onA.add(first, PaneEdge.right)!;
      syncAll([a, b]);
      final pending = <VoidCallback>[];
      final onB = Workspace(
        session: b,
        workspaceId: testWorkspaceOf(b),
        afterDetach: pending.add,
      );
      addTearDown(onB.dispose);
      final viewport = onB.canvasViewport(added);

      onA.join(first, PaneEdge.right);
      syncAll([a, b]);
      expect(onB.paneIds, [first]);
      expect(pending, hasLength(1));
      // Still alive, so a late pointer event cannot hit a disposed
      // controller.
      viewport.panBy(const Offset(10, 0), _pane);

      pending.single();
      expect(() => viewport.addListener(() {}), throwsFlutterError);
    });

    test('lastShownNodes keeps the table after the workspace is deleted', () {
      final a = sessionWithDefaultWorkspace();
      final b = replicaOf(a);
      final onB = openWorkspace(session: b);
      final shown = storedNodes(b);

      a.document.delete([SessionKey.workspaces, testWorkspaceOf(a)]);
      a.document.commit();
      syncAll([a, b]);

      expect(onB.paneIds, isEmpty);
      expect(onB.lastShownNodes, shown);
    });
  });

  group('live Canvas views', () {
    testWidgets('local changes are committed within 50 ms and finally '
        'exactly (PNT-A0015-05)', (tester) async {
      final session = sessionWithDefaultWorkspace();
      final workspace = openWorkspace(session: session);
      final id = workspace.paneIds.single;
      final view = workspace.canvasViewport(id);
      final commits = _localCommits(session);

      view.panBy(const Offset(10, 0), _pane);
      expect(_stored(session, id, 'canvas'), isNull);
      await tester.pump(viewCommitInterval);
      expect(_stored(session, id, 'canvas'), view.toJson());
      expect(commits(), 1);

      // A 200 ms gesture with a change every 10 ms commits at most once per
      // 50 ms, and the last change reaches the document within 50 ms.
      for (var i = 0; i < 20; i++) {
        view.panBy(const Offset(1, 2), _pane);
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(commits(), lessThanOrEqualTo(1 + 200 ~/ 50));
      await tester.pump(viewCommitInterval);
      expect(_stored(session, id, 'canvas'), view.toJson());
      expect(view.center, const Offset(482, 472));
      final settled = commits();
      await tester.pump(const Duration(milliseconds: 200));
      expect(commits(), settled);
    });

    testWidgets('a remote change moves the live view without a write back', (
      tester,
    ) async {
      final a = sessionWithDefaultWorkspace();
      final b = replicaOf(a);
      final onA = openWorkspace(session: a);
      final onB = openWorkspace(session: b);
      final id = onA.paneIds.single;
      final viewA = onA.canvasViewport(id);
      final viewB = onB.canvasViewport(id);
      final commitsOnA = _localCommits(a);

      viewB
        ..panBy(const Offset(-40, 25), _pane)
        ..rotateAt(Offset.zero, _pane, 0.25);
      await tester.pump(viewCommitInterval);
      syncAll([a, b]);

      expect(viewA.toJson(), viewB.toJson());
      await tester.pump(const Duration(milliseconds: 200));
      expect(commitsOnA(), 0);
    });

    test('toJson includes a view change that is not yet committed', () {
      final session = sessionWithDefaultWorkspace();
      final workspace = openWorkspace(session: session);
      final id = workspace.paneIds.single;
      workspace.canvasViewport(id).panBy(const Offset(12, 0), _pane);

      final section = workspace.toJson()!;

      final pane = (section['root']! as Map)['pane'] as Map;
      expect((pane['state'] as Map)['canvas'], {
        'center': {'x': 500.0, 'y': 512.0},
        'extent': 1024.0,
        'rotation': 0.0,
      });
      // Writing the section changed nothing in the session (WKSP-29).
      expect(_stored(session, id, 'canvas'), isNull);
    });
  });

  group('stored section', () {
    test('is version 2 JSON of the shown tree (PNT-A0015-07)', () {
      final workspace = openWorkspace();
      final left = workspace.paneIds.single;
      final right = workspace.add(left, PaneEdge.right)!;
      workspace.setKind(right, PaneKind.manual);
      workspace.setManualHelpId(right, HelpId.paneBoundary);

      expect(workspace.toJson(), {
        'version': 2,
        'root': {
          'split': 'row',
          'parts': [
            {
              'share': 0.5,
              'node': {
                'pane': {'mode': 'canvas', 'state': {}},
              },
            },
            {
              'share': 0.5,
              'node': {
                'pane': {
                  'mode': 'manual',
                  'state': {
                    'manual': {'help': 'paneBoundary'},
                  },
                },
              },
            },
          ],
        },
      });
    });

    test('round-trips layout, modes, views, and Manual page', () {
      final workspace = openWorkspace();
      final left = workspace.paneIds.single;
      final right = workspace.add(left, PaneEdge.right)!;
      workspace.moveSplitter(workspace.splitters.single, 0.1);
      workspace.canvasViewport(left)
        ..panBy(const Offset(3, 4), _pane)
        ..zoomAt(Offset.zero, _pane, 2);
      workspace.setKind(right, PaneKind.manual);
      workspace.setManualHelpId(right, HelpId.paneBoundary);
      final stored = workspace.toJson();

      final restored = openWorkspace();
      expect(restored.applyJson(stored), isTrue);

      expect(restored.toJson(), stored);
      final [newLeft, newRight] = restored.paneIds;
      expect(restored.rectOf(newLeft).width, closeTo(0.6, 1e-9));
      expect(restored.kindOf(newRight), PaneKind.manual);
      expect(restored.manualHelpId(newRight), HelpId.paneBoundary);
      final view = workspace.canvasViewport(left);
      expect(restored.canvasViewport(newLeft).extent, view.extent);
      expect(restored.canvasViewport(newLeft).center, view.center);
    });

    test('replaces every pane and tells the owner about each', () {
      final removed = <String>[];
      final workspace = openWorkspace(removed: removed);
      final first = workspace.paneIds.single;
      final second = workspace.add(first, PaneEdge.right)!;
      final view = workspace.canvasViewport(first);

      expect(
        workspace.applyJson(_single({'mode': 'canvas', 'state': {}})),
        isTrue,
      );

      expect(removed, unorderedEquals([first, second]));
      expect(workspace.paneIds, hasLength(1));
      expect(workspace.paneIds.single, isNot(anyOf(first, second)));
      // The removed pane's view was released with it.
      expect(() => view.addListener(() {}), throwsFlutterError);
    });

    final unusable = <String, Object?>{
      'not a map': 'workspace',
      'version 1': {
        'version': 1,
        'panes': [
          {
            'id': 0,
            'left': 0,
            'top': 0,
            'right': 1,
            'bottom': 1,
            'mode': 'canvas',
            'state': {},
          },
        ],
      },
      'newer version': {
        ..._single({'mode': 'canvas', 'state': {}}),
        'version': 3,
      },
      'no root': {'version': 2},
      'empty split': {
        'version': 2,
        'root': {'split': 'row', 'parts': []},
      },
      'zero share': {
        'version': 2,
        'root': {
          'split': 'row',
          'parts': [
            {
              'share': 0,
              'node': {
                'pane': {'mode': 'canvas', 'state': {}},
              },
            },
          ],
        },
      },
      'unknown mode': _single({'mode': 'node-graph', 'state': {}}),
      'unknown state key': _single({
        'mode': 'canvas',
        'state': {'node-graph': <String, Object?>{}},
      }),
      'state for a mode without state': _single({
        'mode': 'canvas',
        'state': {'log': <String, Object?>{}},
      }),
      'extent out of range': _single({
        'mode': 'canvas',
        'state': {
          'canvas': {..._view, 'extent': 20000.0},
        },
      }),
      'earlier pan and zoom view': _single({
        'mode': 'canvas',
        'state': {
          'canvas': {
            'pan': {'dx': 12.0, 'dy': -5.0},
            'zoom': 2.0,
            'rotation': 0.5,
          },
        },
      }),
      'unknown manual page': _single({
        'mode': 'manual',
        'state': {
          'manual': {'help': 'noSuchArticle'},
        },
      }),
    };
    for (final entry in unusable.entries) {
      test('an unusable section (${entry.key}) changes nothing', () {
        final removed = <String>[];
        final session = sessionWithDefaultWorkspace();
        final workspace = openWorkspace(session: session, removed: removed);
        final first = workspace.paneIds.single;
        final added = workspace.add(first, PaneEdge.right)!;
        final before = workspace.toJson();
        final table = storedNodes(session);

        expect(workspace.applyJson(entry.value), isFalse);

        expect(workspace.toJson(), before);
        expect(storedNodes(session), table);
        expect(workspace.paneIds, [first, added]);
        expect(removed, isEmpty);
      });
    }

    test('accepts a section whose panes have no stored state', () {
      final workspace = openWorkspace();
      final ok = workspace.applyJson(
        _row([
          {'mode': 'canvas', 'state': {}},
          {'mode': 'settings', 'state': {}},
        ]),
      );
      expect(ok, isTrue);
      final [canvas, settings] = workspace.paneIds;
      expect(workspace.kindOf(settings), PaneKind.settings);
      expect(
        workspace.canvasViewport(canvas).extent,
        CanvasViewportController.defaultExtent,
      );
      expect(
        workspace.canvasViewport(canvas).center,
        CanvasViewportController.defaultCenter,
      );
    });
  });
}
