import 'package:flutter/foundation.dart';

/// Switches and limits the debug pane edits and the canvas reads.
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
  /// missing, blank). Implies tile outlines are readable but does not require
  /// them.
  bool get showTileState => _showTileState;

  /// Outlines the document-space rectangle the last frame considered visible.
  bool get showVisibleRect => _showVisibleRect;

  /// Prints each visible tile's `x,y` index in its corner.
  bool get showCoordinates => _showCoordinates;

  /// When true the pane stops refreshing its readouts (the canvas is
  /// unaffected). Lets you read a transient state such as a fallback frame.
  bool get paused => _paused;

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

  void _set(bool old, bool value, VoidCallback apply) {
    if (old == value) return;
    apply();
    notifyListeners();
  }
}
