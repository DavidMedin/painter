// What: The version 2 workspace section a Flash writes: layoutToFlashJson
//   turns a shown layout into `{"version": 2, "root": node}`, and
//   layoutFromFlashJson reads such a section into a fresh node table.
// Why: A file stores the shown Layout tree, not the session's node table, so
//   that a file carries no peer ids, deleted panes or merge leftovers
//   (docs/decisions/009-shared-workspaces.md, PNT-A0015-07). Reading checks
//   the whole section before making any node, so an Unusable section
//   (docs/spec/workspace.md) leaves nothing behind.
// Coupled to: layout_tree.dart (projection, field names, system overview),
//   fractional_index.dart (order keys of the new nodes), and pane_kind.dart,
//   whose enum names the caller passes as the known modes.

import 'fractional_index.dart';
import 'layout_tree.dart';

/// The workspace section version written and accepted here (PNT-A0015-07).
const int flashLayoutVersion = 2;

/// Deepest nesting of splits a section may have; deeper sections are
/// Unusable, which bounds the recursion of [layoutFromFlashJson].
const int _maximumDepth = 64;

/// The workspace section for [layout]: shown splits with their normalized
/// shares and shown panes with copies of their mode and states. Null only for
/// a layout without panes, which a table made by this system never has.
Map<String, Object?>? layoutToFlashJson(LayoutProjection layout) {
  final root = layout.root;
  if (root == null) return null;
  return {'version': flashLayoutVersion, 'root': _nodeToJson(root)};
}

Map<String, Object?> _nodeToJson(ShownNode node) => switch (node) {
  // A pane whose stored mode is malformed shows as the default mode, so it
  // is flashed as that mode rather than as a null the reader rejects.
  ShownPane() => {
    'pane': {
      'mode': node.mode ?? defaultPaneMode,
      'state': copyLayoutValue(node.state),
    },
  },
  ShownSplit() => {
    'split': node.axis.name,
    'parts': [
      for (var i = 0; i < node.parts.length; i++)
        {'share': node.shares[i], 'node': _nodeToJson(node.parts[i])},
    ],
  },
};

/// A fresh node table holding the layout in workspace section [json], or
/// null when the section is Unusable: not a map, a version other than
/// [flashLayoutVersion], a node that is neither one split with a known axis
/// and at least one part nor one pane, a share that is not a positive
/// finite number, a mode or state key not in [knownModes], a state that is
/// not a map, or a state that [isUsableState] rejects.
///
/// Node ids come from [newId] and order keys end in [actor]'s suffix; no id
/// is taken when the result is null. A section whose root is a pane gives a
/// root split holding that pane.
LayoutNodes? layoutFromFlashJson(
  Object? json, {
  required Set<String> knownModes,
  required String Function() newId,
  required String actor,
  bool Function(String mode, Map<String, Object?> state)? isUsableState,
}) {
  if (json is! Map || json['version'] != flashLayoutVersion) return null;
  final root = _parseNode(json['root'], knownModes, isUsableState, 0);
  if (root == null) return null;

  final nodes = <String, Map<String, Object?>>{};
  final top = root is _ParsedSplit
      ? root
      : _ParsedSplit(LayoutAxis.row, [(1.0, root)]);
  nodes[layoutRootId] = {
    LayoutField.kind: LayoutField.split,
    LayoutField.axis: top.axis.name,
  };

  void addChildren(String parent, _ParsedSplit split) {
    final keys = orderKeysAfter(null, split.parts.length, actor);
    for (var i = 0; i < split.parts.length; i++) {
      final (share, node) = split.parts[i];
      final id = newId();
      switch (node) {
        case _ParsedPane(:final mode, :final state):
          nodes[id] = {
            LayoutField.parent: parent,
            LayoutField.kind: LayoutField.pane,
            LayoutField.order: keys[i],
            LayoutField.share: share,
            LayoutField.mode: mode,
            LayoutField.state: state,
            LayoutField.deleted: false,
          };
        case _ParsedSplit(:final axis):
          nodes[id] = {
            LayoutField.parent: parent,
            LayoutField.kind: LayoutField.split,
            LayoutField.order: keys[i],
            LayoutField.share: share,
            LayoutField.axis: axis.name,
          };
          addChildren(id, node);
      }
    }
  }

  addChildren(layoutRootId, top);
  return nodes;
}

/// A validated section node, before ids are assigned.
sealed class _ParsedNode {}

final class _ParsedPane extends _ParsedNode {
  _ParsedPane(this.mode, this.state);

  final String mode;
  final Map<String, Object?> state;
}

final class _ParsedSplit extends _ParsedNode {
  _ParsedSplit(this.axis, this.parts);

  final LayoutAxis axis;
  final List<(double, _ParsedNode)> parts;
}

_ParsedNode? _parseNode(
  Object? json,
  Set<String> knownModes,
  bool Function(String mode, Map<String, Object?> state)? isUsableState,
  int depth,
) {
  if (json is! Map || depth > _maximumDepth) return null;
  // A node is either a pane or a split, never both.
  if (json.containsKey('pane') == json.containsKey('split')) return null;
  final pane = json['pane'];
  if (pane is Map) {
    final mode = pane['mode'];
    final state = pane['state'];
    if (mode is! String || !knownModes.contains(mode) || state is! Map) {
      return null;
    }
    final states = <String, Object?>{};
    for (final MapEntry(:key, :value) in state.entries) {
      if (key is! String || !knownModes.contains(key) || value is! Map) {
        return null;
      }
      final copy = copyLayoutValue(value) as Map<String, Object?>;
      if (isUsableState != null && !isUsableState(key, copy)) return null;
      states[key] = copy;
    }
    return _ParsedPane(mode, states);
  }
  final axis = LayoutAxis.parse(json['split']);
  final parts = json['parts'];
  if (axis == null || parts is! List || parts.isEmpty) return null;
  final parsed = <(double, _ParsedNode)>[];
  for (final part in parts) {
    if (part is! Map) return null;
    final share = part['share'];
    if (!isValidShare(share)) return null;
    final node = _parseNode(part['node'], knownModes, isUsableState, depth + 1);
    if (node == null) return null;
    parsed.add(((share as num).toDouble(), node));
  }
  return _ParsedSplit(axis, parsed);
}
