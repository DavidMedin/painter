// What: PaneLayout, an immutable partition of the unit square into pane
//   rectangles, plus PaneEdge and PaneSplitter. It implements the geometry of
//   add, join, neighbor lookup, splitter lines, and splitter moves.
// Why: docs/spec/panes.md asks for Blender-style layouts, in which panes tile
//   the workspace and a join may combine any two panes that share a whole
//   edge. A binary split tree cannot represent the result of joining panes
//   that are not siblings, so the layout is a set of rectangles instead
//   (docs/decisions/006-workspace-in-file.md records that layouts are stored
//   as fractions of the workspace area).
// Coupled to: workspace.dart (owns the current PaneLayout and calls every
//   operation here), pane_system.dart (reads rectangles and splitters to
//   place panes and handles), and the workspace section format in
//   workspace.dart (PaneLayout.toJson / fromJson).
//
// ---------------------------------------------------------------------------
// Layout overview
//
// Every pane is a Rect in unit coordinates: (0, 0) is the workspace's top
// left and (1, 1) its bottom right, so a layout does not depend on window
// size (WKSP-7). Pixel rules (100 px minimum pane, 200 px to add) take the
// workspace's pixel size as an argument.
//
// Invariant: the rectangles do not overlap and cover the unit square
// (PANE-1). Every operation here preserves it: add splits one rectangle in
// two, join replaces two rectangles that share a whole edge by their union,
// and a splitter move shifts one coordinate of every rectangle on that line
// to the same new value.
//
// Coordinates that must coincide are assigned the same double, so equality
// holds exactly; comparisons still go through _near so a stored layout that
// was rounded by another tool is read leniently.
//
// A splitter is a maximal run of pane borders on one line, connected end to
// end. Moving it moves every border in the run, because moving only one
// border would make a neighboring pane non-rectangular.
// ---------------------------------------------------------------------------

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// One side of a pane's frame.
enum PaneEdge {
  top,
  right,
  bottom,
  left;

  /// Whether the frame edge is a vertical line (left or right).
  bool get isVertical => this == left || this == right;
}

/// The smallest width or height of a pane, in pixels (PANE-18).
const double minimumPaneExtent = 100;

/// Tolerance when comparing unit coordinates.
const double _epsilon = 1e-9;

bool _near(double a, double b) => (a - b).abs() <= _epsilon;

/// A line shared by panes, with the panes on each side of it.
///
/// [vertical] lines have a constant x ([position]) and span y from [start] to
/// [end]; horizontal lines are the transpose. [before] holds the panes whose
/// right (or bottom) border lies on the line and [after] those whose left (or
/// top) border does. [key] identifies the splitter while a drag changes its
/// [position], because the two pane sets do not change during a drag.
@immutable
class PaneSplitter {
  const PaneSplitter({
    required this.vertical,
    required this.position,
    required this.start,
    required this.end,
    required this.before,
    required this.after,
  });

  final bool vertical;
  final double position;
  final double start;
  final double end;
  final Set<int> before;
  final Set<int> after;

  /// Stable identity for widget keys.
  String get key {
    final first = (before.toList()..sort()).join(',');
    final second = (after.toList()..sort()).join(',');
    return '${vertical ? 'v' : 'h'}:$first|$second';
  }
}

/// An immutable partition of the unit square into pane rectangles.
///
/// See the layout overview at the top of this file. Operations return a new
/// layout, or null when the request is not allowed.
@immutable
class PaneLayout {
  /// A layout of the single pane [id] filling the workspace.
  PaneLayout.single(int id) : _rects = {id: const Rect.fromLTWH(0, 0, 1, 1)};

  PaneLayout._(Map<int, Rect> rects) : _rects = Map.unmodifiable(rects);

  final Map<int, Rect> _rects;

  /// Pane ids in insertion order.
  Iterable<int> get ids => _rects.keys;

  int get length => _rects.length;

  bool contains(int id) => _rects.containsKey(id);

  /// The rectangle of pane [id] in unit coordinates.
  Rect rect(int id) => _rects[id]!;

  /// The pane's extent perpendicular to [edge] in pixels: its height for a top
  /// or bottom edge and its width for a left or right edge.
  double extentAcross(int id, PaneEdge edge, Size area) {
    final r = rect(id);
    return edge.isVertical ? r.width * area.width : r.height * area.height;
  }

  /// Whether 'add' may split pane [id] along [edge]: both halves must be at
  /// least [minimumPaneExtent] (PANE-19). An empty [area] means the workspace
  /// has not been laid out yet, so the pixel rule cannot be checked and the
  /// request is allowed.
  bool canAdd(int id, PaneEdge edge, Size area) {
    if (area.isEmpty) return true;
    return extentAcross(id, edge, area) >= 2 * minimumPaneExtent - _epsilon;
  }

  /// Splits pane [id] in two along a line parallel to [edge]. The new pane
  /// [newId] takes the half touching [edge] and [id] keeps the other half
  /// (PANE-13). The caller has checked [canAdd].
  PaneLayout add(int id, PaneEdge edge, int newId) {
    final r = rect(id);
    final Rect kept;
    final Rect added;
    switch (edge) {
      case PaneEdge.top:
        final middle = r.top + r.height / 2;
        added = Rect.fromLTRB(r.left, r.top, r.right, middle);
        kept = Rect.fromLTRB(r.left, middle, r.right, r.bottom);
      case PaneEdge.bottom:
        final middle = r.top + r.height / 2;
        kept = Rect.fromLTRB(r.left, r.top, r.right, middle);
        added = Rect.fromLTRB(r.left, middle, r.right, r.bottom);
      case PaneEdge.left:
        final middle = r.left + r.width / 2;
        added = Rect.fromLTRB(r.left, r.top, middle, r.bottom);
        kept = Rect.fromLTRB(middle, r.top, r.right, r.bottom);
      case PaneEdge.right:
        final middle = r.left + r.width / 2;
        kept = Rect.fromLTRB(r.left, r.top, middle, r.bottom);
        added = Rect.fromLTRB(middle, r.top, r.right, r.bottom);
    }
    return PaneLayout._({..._rects, id: kept, newId: added});
  }

  /// The pane whose frame edge coincides exactly, along its whole length, with
  /// [edge] of pane [id], or null (the Neighbor of docs/spec/panes.md). Edges
  /// on the workspace boundary, and edges bordered by several panes, have no
  /// neighbor.
  int? neighbor(int id, PaneEdge edge) {
    final r = rect(id);
    for (final entry in _rects.entries) {
      if (entry.key == id) continue;
      final o = entry.value;
      final bool coincides;
      switch (edge) {
        case PaneEdge.right:
          coincides =
              _near(o.left, r.right) &&
              _near(o.top, r.top) &&
              _near(o.bottom, r.bottom);
        case PaneEdge.left:
          coincides =
              _near(o.right, r.left) &&
              _near(o.top, r.top) &&
              _near(o.bottom, r.bottom);
        case PaneEdge.bottom:
          coincides =
              _near(o.top, r.bottom) &&
              _near(o.left, r.left) &&
              _near(o.right, r.right);
        case PaneEdge.top:
          coincides =
              _near(o.bottom, r.top) &&
              _near(o.left, r.left) &&
              _near(o.right, r.right);
      }
      if (coincides) return entry.key;
    }
    return null;
  }

  /// Removes the neighbor across [edge] of pane [id] and extends [id] over
  /// the space it occupied (PANE-15), or returns null when there is no
  /// neighbor.
  PaneLayout? join(int id, PaneEdge edge) {
    final other = neighbor(id, edge);
    if (other == null) return null;
    final a = rect(id);
    final b = rect(other);
    final union = Rect.fromLTRB(
      math.min(a.left, b.left),
      math.min(a.top, b.top),
      math.max(a.right, b.right),
      math.max(a.bottom, b.bottom),
    );
    final next = {..._rects}
      ..remove(other)
      ..[id] = union;
    return PaneLayout._(next);
  }

  /// Every splitter in the layout: each maximal run of borders shared by two
  /// panes on one line. Vertical splitters come first.
  List<PaneSplitter> splitters() => [
    ..._splittersOn(vertical: true),
    ..._splittersOn(vertical: false),
  ];

  List<PaneSplitter> _splittersOn({required bool vertical}) {
    // One segment per ordered pair of panes whose borders touch along a line
    // for a positive length.
    final segments = <_Segment>[];
    for (final a in _rects.entries) {
      for (final b in _rects.entries) {
        if (a.key == b.key) continue;
        final ra = a.value;
        final rb = b.value;
        final touching = vertical
            ? _near(ra.right, rb.left)
            : _near(ra.bottom, rb.top);
        if (!touching) continue;
        final start = vertical
            ? math.max(ra.top, rb.top)
            : math.max(ra.left, rb.left);
        final end = vertical
            ? math.min(ra.bottom, rb.bottom)
            : math.min(ra.right, rb.right);
        if (end - start <= _epsilon) continue;
        segments.add(
          _Segment(
            position: vertical ? ra.right : ra.bottom,
            start: start,
            end: end,
            before: a.key,
            after: b.key,
          ),
        );
      }
    }
    segments.sort((x, y) {
      final byPosition = x.position.compareTo(y.position);
      return byPosition != 0 ? byPosition : x.start.compareTo(y.start);
    });

    // Merge consecutive segments on the same line that touch end to end.
    final result = <PaneSplitter>[];
    _Run? run;
    void flush() {
      final done = run;
      if (done == null) return;
      result.add(
        PaneSplitter(
          vertical: vertical,
          position: done.position,
          start: done.start,
          end: done.end,
          before: done.before,
          after: done.after,
        ),
      );
    }

    for (final segment in segments) {
      final current = run;
      if (current != null &&
          _near(current.position, segment.position) &&
          segment.start <= current.end + _epsilon) {
        current.end = math.max(current.end, segment.end);
        current.before.add(segment.before);
        current.after.add(segment.after);
      } else {
        flush();
        run = _Run(segment);
      }
    }
    flush();
    return result;
  }

  /// Moves [splitter] by [delta] (a fraction of the workspace extent across
  /// the line) and returns the new layout. The move is clamped so no pane
  /// bordering the splitter becomes smaller than [minimumPaneExtent] in
  /// pixels (PANE-18); a pane that is already smaller may not shrink further
  /// but is never forced to grow. [area] is the workspace's pixel size.
  PaneLayout moveSplitter(PaneSplitter splitter, double delta, Size area) {
    final extent = splitter.vertical ? area.width : area.height;
    if (extent <= 0) return this;
    final minimum = minimumPaneExtent / extent;
    var lowest = double.negativeInfinity;
    for (final id in splitter.before) {
      final r = rect(id);
      lowest = math.max(lowest, (splitter.vertical ? r.left : r.top) + minimum);
    }
    var highest = double.infinity;
    for (final id in splitter.after) {
      final r = rect(id);
      highest = math.min(
        highest,
        (splitter.vertical ? r.right : r.bottom) - minimum,
      );
    }
    lowest = math.min(lowest, splitter.position);
    highest = math.max(highest, splitter.position);
    final target = (splitter.position + delta)
        .clamp(lowest, highest)
        .toDouble();
    if (_near(target, splitter.position)) return this;

    final next = {..._rects};
    for (final id in splitter.before) {
      final r = next[id]!;
      next[id] = splitter.vertical
          ? Rect.fromLTRB(r.left, r.top, target, r.bottom)
          : Rect.fromLTRB(r.left, r.top, r.right, target);
    }
    for (final id in splitter.after) {
      final r = next[id]!;
      next[id] = splitter.vertical
          ? Rect.fromLTRB(target, r.top, r.right, r.bottom)
          : Rect.fromLTRB(r.left, target, r.right, r.bottom);
    }
    return PaneLayout._(next);
  }

  /// The layout as stored in a workspace section: one entry per pane with its
  /// unit rectangle.
  List<Map<String, Object?>> toJson() => [
    for (final entry in _rects.entries)
      {
        'id': entry.key,
        'left': entry.value.left,
        'top': entry.value.top,
        'right': entry.value.right,
        'bottom': entry.value.bottom,
      },
  ];

  /// Parses a layout written by [toJson], or null when it cannot be read in
  /// full or is not a partition of the unit square: duplicate or negative
  /// ids, rectangles outside the square or without area, overlaps, or gaps.
  static PaneLayout? fromJson(Object? value) {
    if (value is! List || value.isEmpty) return null;
    final rects = <int, Rect>{};
    var totalArea = 0.0;
    for (final entry in value) {
      if (entry is! Map<String, dynamic>) return null;
      final id = entry['id'];
      final left = entry['left'];
      final top = entry['top'];
      final right = entry['right'];
      final bottom = entry['bottom'];
      if (id is! int || id < 0 || rects.containsKey(id)) return null;
      if (left is! num ||
          top is! num ||
          right is! num ||
          bottom is! num ||
          !left.isFinite ||
          !top.isFinite ||
          !right.isFinite ||
          !bottom.isFinite) {
        return null;
      }
      final rect = Rect.fromLTRB(
        left.toDouble(),
        top.toDouble(),
        right.toDouble(),
        bottom.toDouble(),
      );
      if (rect.left < -_epsilon ||
          rect.top < -_epsilon ||
          rect.right > 1 + _epsilon ||
          rect.bottom > 1 + _epsilon ||
          rect.width <= _epsilon ||
          rect.height <= _epsilon) {
        return null;
      }
      rects[id] = rect;
      totalArea += rect.width * rect.height;
    }
    // Rectangles inside the unit square that sum to area 1 and never overlap
    // cannot leave a gap.
    if ((totalArea - 1).abs() > 1e-6) return null;
    final list = rects.values.toList();
    for (var i = 0; i < list.length; i++) {
      for (var j = i + 1; j < list.length; j++) {
        final overlap = list[i].intersect(list[j]);
        if (overlap.width > _epsilon && overlap.height > _epsilon) return null;
      }
    }
    return PaneLayout._(rects);
  }
}

/// A shared border between two panes, before merging into a splitter.
class _Segment {
  _Segment({
    required this.position,
    required this.start,
    required this.end,
    required this.before,
    required this.after,
  });

  final double position;
  final double start;
  final double end;
  final int before;
  final int after;
}

/// A splitter under construction while merging touching segments.
class _Run {
  _Run(_Segment segment)
    : position = segment.position,
      start = segment.start,
      end = segment.end,
      before = {segment.before},
      after = {segment.after};

  final double position;
  final double start;
  double end;
  final Set<int> before;
  final Set<int> after;
}
