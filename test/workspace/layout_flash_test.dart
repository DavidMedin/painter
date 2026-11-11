// What: Unit tests for the version 2 workspace section: writing a shown
//   layout, reading it back into a fresh node table, and rejecting Unusable
//   sections.
// Why: Flash must store the Layout tree as fractions (WKSP-7) in the format
//   of docs/decisions/009-shared-workspaces.md (PNT-A0015-07), and an
//   Unusable section must be refused in full (WKSP-11, WKSP-12).
// Covers: lib/workspace/layout_flash.dart.

import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:painter/workspace/layout_flash.dart';
import 'package:painter/workspace/layout_tree.dart';

import 'layout_test_support.dart';

const _modes = {'canvas', 'manual', 'settings'};

LayoutNodes? _read(Object? json, {String Function()? newId}) =>
    layoutFromFlashJson(
      json,
      knownModes: _modes,
      newId: newId ?? idSource('ff'),
      actor: 'ff',
    );

Map<String, Object?> _pane(String mode, [Map<String, Object?>? state]) => {
  'pane': {'mode': mode, 'state': state ?? <String, Object?>{}},
};

void main() {
  test('round-trips a layout through JSON text', () {
    final nodes = buildTable(
      row(layoutRootId, [
        pane(
          'a',
          share: 2,
          state: {
            'canvas': {
              'center': {'x': 1, 'y': 2},
              'extent': 3,
              'rotation': 0.5,
            },
          },
        ),
        column('s', [
          pane(
            'b',
            mode: 'manual',
            state: {
              'manual': {'help': 'general'},
            },
          ),
          row('t', [pane('c'), pane('d', share: 3)]),
        ]),
        // Hidden content never reaches the file.
        pane('gone', deleted: true),
      ]),
    );
    final original = projectLayout(nodes);
    final json = layoutToFlashJson(original)!;
    expect(json['version'], 2);

    final text = jsonEncode(json);
    final read = _read(jsonDecode(text))!;
    final restored = projectLayout(read);
    expectPartition(restored);
    expect(restored.panes, hasLength(4));
    for (var i = 0; i < 4; i++) {
      final before = original.panes[i];
      final after = restored.panes[i];
      expect(after.rect, rectNear(before.rect));
      expect(after.mode, before.mode);
      expect(after.state, before.state);
    }
    // Pane ids are new; nothing deleted is carried over.
    expect(read.keys, isNot(contains('a')));
    expect(read.values.where((n) => n[LayoutField.deleted] == true), isEmpty);
  });

  test('writes splits with normalized shares and panes with states', () {
    final json = layoutToFlashJson(
      projectLayout(
        buildTable(
          column(layoutRootId, [
            pane('a', share: 1),
            pane('b', share: 3, mode: 'settings'),
          ]),
        ),
      ),
    );
    expect(json, {
      'version': 2,
      'root': {
        'split': 'column',
        'parts': [
          {'share': 0.25, 'node': _pane('canvas')},
          {'share': 0.75, 'node': _pane('settings')},
        ],
      },
    });
  });

  test('reads a single-pane section as a root split holding the pane', () {
    final nodes = _read({
      'version': 2,
      'root': _pane('manual', {
        'manual': {'help': 'general'},
      }),
    })!;
    final layout = projectLayout(nodes);
    expect(layout.panes.single.mode, 'manual');
    expect(layout.panes.single.rect, const Rect.fromLTRB(0, 0, 1, 1));
    expect(nodes[layoutRootId]![LayoutField.kind], LayoutField.split);
  });

  test('a read table can be edited like any other', () {
    final nodes = _read({'version': 2, 'root': _pane('canvas')})!;
    final layout = projectLayout(nodes);
    final id = layout.panes.single.id;
    final next = applyAndProject(
      nodes,
      plannerFor('bb').add(layout, id, PaneEdge.right),
    );
    expect(next.panes, hasLength(2));
  });

  test('refuses Unusable sections without taking ids', () {
    Map<String, Object?> split(List<Object?> parts, [Object? axis = 'row']) => {
      'split': axis,
      'parts': parts,
    };
    Map<String, Object?> part(Object? node, [Object? share = 1]) => {
      'share': share,
      'node': node,
    };
    final sections = <String, Object?>{
      'not a map': [1, 2],
      'version 1': {'version': 1, 'root': _pane('canvas')},
      'no version': {'root': _pane('canvas')},
      'no root': {'version': 2},
      'unknown mode': {'version': 2, 'root': _pane('painting')},
      'unknown state mode': {
        'version': 2,
        'root': _pane('canvas', {'painting': {}}),
      },
      'state not a map': {
        'version': 2,
        'root': {
          'pane': {'mode': 'canvas', 'state': 'none'},
        },
      },
      'mode state not a map': {
        'version': 2,
        'root': _pane('canvas', {'canvas': 4}),
      },
      'no state': {
        'version': 2,
        'root': {
          'pane': {'mode': 'canvas'},
        },
      },
      'unknown axis': {
        'version': 2,
        'root': split([part(_pane('canvas'))], 'diagonal'),
      },
      'no parts': {'version': 2, 'root': split([])},
      'zero share': {
        'version': 2,
        'root': split([part(_pane('canvas'), 0), part(_pane('canvas'))]),
      },
      'text share': {
        'version': 2,
        'root': split([part(_pane('canvas'), 'half')]),
      },
      'bad nested node': {
        'version': 2,
        'root': split([
          part(_pane('canvas')),
          part(split([part('pane')])),
        ]),
      },
      'pane and split': {
        'version': 2,
        'root': {
          ..._pane('canvas'),
          ...split([part(_pane('canvas'))]),
        },
      },
      'too deep': {
        'version': 2,
        'root': List.generate(
          100,
          (_) => null,
        ).fold<Object?>(_pane('canvas'), (node, _) => split([part(node)])),
      },
    };
    for (final MapEntry(:key, :value) in sections.entries) {
      var taken = 0;
      expect(
        _read(
          value,
          newId: () {
            taken++;
            return 'id$taken';
          },
        ),
        isNull,
        reason: key,
      );
      expect(taken, 0, reason: key);
    }
  });

  test('refuses a state the caller finds unusable', () {
    final section = {
      'version': 2,
      'root': _pane('manual', {
        'manual': {'help': 42},
      }),
    };
    final nodes = layoutFromFlashJson(
      section,
      knownModes: _modes,
      newId: idSource('ff'),
      actor: 'ff',
      isUsableState: (mode, state) => state['help'] is String,
    );
    expect(nodes, isNull);
  });
}
