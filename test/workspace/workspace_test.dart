// What: Unit tests for Workspace: per-mode state across mode changes, add,
//   join, swap, Manual placement, and reading and writing the stored section.
// Why: The pane UI is a thin layer over this model, so the behavior the specs
//   promise (PANE-13 to PANE-16, PANE-20, CNVS-6, WKSP-11, WKSP-12) is tested
//   here without widgets.
// Covers: lib/workspace/workspace.dart (and its use of PaneLayout and
//   CanvasViewportController).

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:painter/help/manual_catalog.dart';
import 'package:painter/workspace/pane_kind.dart';
import 'package:painter/workspace/pane_layout.dart';
import 'package:painter/workspace/workspace.dart';

/// A workspace laid out at 1000x800 so the pixel rules apply.
Workspace _workspace({List<int>? removed}) {
  final workspace = Workspace(onPaneRemoved: removed?.add);
  workspace.area = const Size(1000, 800);
  return workspace;
}

Map<String, Object?> _entry(
  int id,
  List<double> rect,
  String mode, [
  Map<String, Object?> state = const {},
]) => {
  'id': id,
  'left': rect[0],
  'top': rect[1],
  'right': rect[2],
  'bottom': rect[3],
  'mode': mode,
  'state': state,
};

Map<String, Object?> _section(List<Map<String, Object?>> panes) => {
  'version': 1,
  'panes': panes,
};

const _view = {
  'pan': {'dx': 12.0, 'dy': -5.0},
  'zoom': 2.0,
  'rotation': 0.5,
};

void main() {
  test('starts with one Canvas pane', () {
    final workspace = _workspace();
    expect(workspace.paneIds, [0]);
    expect(workspace.kindOf(0), PaneKind.canvas);
  });

  group('mode changes', () {
    test('keep the per-mode state of a pane (PANE-20, CNVS-6)', () {
      final workspace = _workspace();
      final view = workspace.canvasViewport(0)..panBy(const Offset(30, 40));
      workspace.setManualHelpId(0, HelpId.openDocument);

      workspace.setKind(0, PaneKind.settings);
      workspace.setKind(0, PaneKind.manual);
      workspace.setKind(0, PaneKind.canvas);

      expect(workspace.canvasViewport(0), same(view));
      expect(workspace.canvasViewport(0).pan, const Offset(30, 40));
      expect(workspace.manualHelpId(0), HelpId.openDocument);
    });
  });

  group('add', () {
    test('copies the mode and an independent copy of the state', () {
      final workspace = _workspace();
      workspace.canvasViewport(0).panBy(const Offset(7, 9));

      final added = workspace.add(0, PaneEdge.right)!;

      expect(workspace.kindOf(added), PaneKind.canvas);
      expect(workspace.canvasViewport(added).pan, const Offset(7, 9));
      workspace.canvasViewport(added).panBy(const Offset(1, 1));
      expect(workspace.canvasViewport(0).pan, const Offset(7, 9));
    });

    test('is refused when the pane would split below 100 px (PANE-19)', () {
      final workspace = _workspace();
      workspace.area = const Size(199, 800);
      expect(workspace.add(0, PaneEdge.right), isNull);
      expect(workspace.paneCount, 1);
    });
  });

  group('join', () {
    test('removes the neighbor, keeps the survivor mode, and reports it', () {
      final removed = <int>[];
      final workspace = _workspace(removed: removed);
      final added = workspace.add(0, PaneEdge.right)!;
      workspace.setKind(added, PaneKind.log);

      expect(workspace.join(0, PaneEdge.right), isTrue);

      expect(workspace.paneIds, [0]);
      expect(workspace.kindOf(0), PaneKind.canvas);
      expect(removed, [added]);
      expect(workspace.layout.rect(0), const Rect.fromLTRB(0, 0, 1, 1));
    });

    test('does nothing without a neighbor and never removes the last pane', () {
      final removed = <int>[];
      final workspace = _workspace(removed: removed);
      expect(workspace.join(0, PaneEdge.right), isFalse);
      expect(workspace.paneCount, 1);
      expect(removed, isEmpty);
    });
  });

  group('swap', () {
    test('exchanges mode and state but not rectangles (PANE-16)', () {
      final workspace = _workspace();
      final right = workspace.add(0, PaneEdge.right)!;
      workspace.canvasViewport(0).panBy(const Offset(5, 5));
      workspace.setKind(right, PaneKind.manual);
      workspace.setManualHelpId(right, HelpId.saveDocument);
      final leftRect = workspace.layout.rect(0);
      final rightRect = workspace.layout.rect(right);

      expect(workspace.swap(0, PaneEdge.right), isTrue);

      expect(workspace.kindOf(0), PaneKind.manual);
      expect(workspace.manualHelpId(0), HelpId.saveDocument);
      expect(workspace.kindOf(right), PaneKind.canvas);
      expect(workspace.canvasViewport(right).pan, const Offset(5, 5));
      expect(workspace.layout.rect(0), leftRect);
      expect(workspace.layout.rect(right), rightRect);
    });

    test('does nothing without a neighbor', () {
      final workspace = _workspace();
      expect(workspace.swap(0, PaneEdge.left), isFalse);
    });
  });

  group('openManual', () {
    test('adds a Manual pane beside the widest pane, then reuses it', () {
      final workspace = _workspace();
      final first = workspace.openManual(HelpId.openDocument);

      expect(first, isNot(0));
      expect(workspace.kindOf(first), PaneKind.manual);
      expect(workspace.manualHelpId(first), HelpId.openDocument);

      final second = workspace.openManual(HelpId.canvas);
      expect(second, first);
      expect(workspace.paneCount, 2);
      expect(workspace.manualHelpId(first), HelpId.canvas);
    });

    test('switches the widest pane when nothing can be split', () {
      final workspace = _workspace();
      workspace.area = const Size(150, 600);
      final id = workspace.openManual(HelpId.canvas);
      expect(id, 0);
      expect(workspace.kindOf(0), PaneKind.manual);
      expect(workspace.paneCount, 1);
    });
  });

  group('stored section', () {
    test('round-trips layout, modes, views, and Manual page', () {
      final workspace = _workspace();
      final right = workspace.add(0, PaneEdge.right)!;
      workspace.canvasViewport(0)
        ..panBy(const Offset(3, 4))
        ..zoomAt(Offset.zero, const Size(100, 100), 2);
      workspace.setKind(right, PaneKind.manual);
      workspace.setManualHelpId(right, HelpId.paneBoundary);
      final stored = workspace.toJson();

      final restored = _workspace();
      expect(restored.applyJson(stored), isTrue);

      expect(restored.paneIds, workspace.paneIds);
      expect(restored.layout.rect(right), workspace.layout.rect(right));
      expect(restored.kindOf(right), PaneKind.manual);
      expect(restored.manualHelpId(right), HelpId.paneBoundary);
      expect(restored.canvasViewport(0).zoom, workspace.canvasViewport(0).zoom);
      expect(restored.canvasViewport(0).pan, workspace.canvasViewport(0).pan);
      // New panes continue after the highest stored id.
      expect(restored.add(0, PaneEdge.bottom), right + 1);
    });

    test('tells the owner about panes that disappear', () {
      final removed = <int>[];
      final workspace = _workspace(removed: removed);
      workspace.add(0, PaneEdge.right);
      workspace.add(0, PaneEdge.bottom);

      workspace.applyJson(
        _section([
          _entry(0, [0, 0, 1, 1], 'canvas'),
        ]),
      );

      expect(removed, unorderedEquals([1, 2]));
      expect(workspace.paneIds, [0]);
    });

    final unusable = <String, Object?>{
      'not a map': 'workspace',
      'wrong version': {..._section([]), 'version': 2},
      'no panes': _section([]),
      'overlapping panes': _section([
        _entry(0, [0, 0, 0.6, 1], 'canvas'),
        _entry(1, [0.4, 0, 1, 1], 'canvas'),
      ]),
      'unknown mode': _section([
        _entry(0, [0, 0, 1, 1], 'node-graph'),
      ]),
      'unknown state key': _section([
        _entry(0, [0, 0, 1, 1], 'canvas', {'node-graph': <String, Object?>{}}),
      ]),
      'state for a mode without state': _section([
        _entry(0, [0, 0, 1, 1], 'canvas', {'log': <String, Object?>{}}),
      ]),
      'zoom out of range': _section([
        _entry(
          0,
          [0, 0, 1, 1],
          'canvas',
          {
            'canvas': {..._view, 'zoom': 100.0},
          },
        ),
      ]),
      'unknown manual page': _section([
        _entry(
          0,
          [0, 0, 1, 1],
          'manual',
          {
            'manual': {'help': 'noSuchArticle'},
          },
        ),
      ]),
    };
    for (final entry in unusable.entries) {
      test('an unusable section (${entry.key}) changes nothing', () {
        final removed = <int>[];
        final workspace = _workspace(removed: removed);
        final added = workspace.add(0, PaneEdge.right)!;
        final before = workspace.toJson();

        expect(workspace.applyJson(entry.value), isFalse);

        expect(workspace.toJson(), before);
        expect(workspace.paneIds, [0, added]);
        expect(removed, isEmpty);
      });
    }

    test('accepts a section whose panes have no stored state', () {
      final workspace = _workspace();
      final ok = workspace.applyJson(
        _section([
          _entry(3, [0, 0, 0.5, 1], 'canvas'),
          _entry(7, [0.5, 0, 1, 1], 'settings'),
        ]),
      );
      expect(ok, isTrue);
      expect(workspace.paneIds, [3, 7]);
      expect(workspace.kindOf(7), PaneKind.settings);
      expect(workspace.canvasViewport(3).zoom, 1);
    });
  });
}
