// What: The set of debug switches (tile grid, tile-state tint, visible
//   rectangle, tile coordinates, pause readouts) as one ChangeNotifier.
// Why: The switches are written by the debug pane (canvas_debug_pane.dart)
//   and read by the canvas painter (via `paintTileOverlay` in
//   tile_overlay.dart, called from CanvasView in ../canvas/canvas_view.dart).
//   Keeping them in their own file means the canvas imports only this small
//   model, never the pane widget (CanvasDebugPane); it still reaches the
//   imgui kit indirectly, because tile_overlay.dart takes its colors from
//   ImTheme (design/diagnostics/debug-pane.md, "Overlays"). The pane and the
//   canvas share one instance, created in lib/main.dart.
import 'package:flutter/foundation.dart';

/// The debug switches the pane edits and the canvas reads.
///
/// Only boolean switches live here. The tile cache limits the pane also edits
/// (`maxInFlight`, `maxTiles`) are written straight to `TileCache`, not
/// stored in this object.
///
/// Kept separate from the pane widget so the canvas can honour the overlay
/// flags without importing any debug UI.
class CanvasDebugOptions extends ChangeNotifier {
  bool _showTileGrid = false;
  bool _showTileState = false;
  bool _showVisibleRect = false;
  bool _showCoordinates = false;
  bool _paused = false;

  /// Outlines every visible tile.
  bool get showTileGrid => _showTileGrid;

  /// Tints each visible tile by how it was drawn (current, stale, fallback,
  /// missing, blank). `paintTileOverlay` also outlines the tile whenever this
  /// is on, so it does not need [showTileGrid] to be readable. Colors come
  /// from `tileDrawColor`, the same function the pane's legend uses.
  bool get showTileState => _showTileState;

  /// Outlines the document-space rectangle the last frame considered visible.
  bool get showVisibleRect => _showVisibleRect;

  /// Prints each visible tile's `x,y` index in its corner.
  bool get showCoordinates => _showCoordinates;

  /// When true the pane stops refreshing its readouts (the canvas is
  /// unaffected). Lets you read a transient state such as a fallback frame.
  bool get paused => _paused;

  /// True when at least one overlay switch is on. `paintTileOverlay` returns
  /// immediately when this is false, skipping all overlay work.
  /// [paused] is deliberately not part of it: it is not an overlay.
  bool get anyOverlay =>
      _showTileGrid || _showTileState || _showVisibleRect || _showCoordinates;

  set showTileGrid(bool v) => _set(_showTileGrid, v, () => _showTileGrid = v);
  set showTileState(bool v) =>
      _set(_showTileState, v, () => _showTileState = v);
  set showVisibleRect(bool v) =>
      _set(_showVisibleRect, v, () => _showVisibleRect = v);
  set showCoordinates(bool v) =>
      _set(_showCoordinates, v, () => _showCoordinates = v);
  set paused(bool v) => _set(_paused, v, () => _paused = v);

  /// Setter helper: skips redundant writes so listeners (the pane's
  /// `_onOptions`, and the canvas's repaint listenable in CanvasView's
  /// painter) are notified only on a real change.
  void _set(bool old, bool value, VoidCallback apply) {
    if (old == value) return;
    apply();
    notifyListeners();
  }
}
