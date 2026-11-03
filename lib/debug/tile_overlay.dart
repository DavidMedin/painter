// What: The in-canvas half of the debug tools: `paintTileOverlay`, which draws
//   tile tints, grid outlines, tile coordinates, and the visible rectangle in
//   document space, plus `tileDrawColor` / `tileDrawName`, the single mapping
//   from a TileDraw state (../canvas/tile_stats.dart) to a color and a name.
// Why: The overlays must follow pan, zoom, and rotation, so they are painted
//   by the canvas (called from ../canvas/canvas_view.dart inside the document
//   transform) rather than by the pane widget. The color/name mapping sits
//   here, shared by the overlay and the pane (canvas_debug_pane.dart), so the
//   legend cannot drift from what the canvas shows. Switches come from
//   canvas_debug_options.dart; the system overview is in
//   canvas_debug_pane.dart.
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../canvas/tile_grid.dart';
import '../canvas/tile_stats.dart';
import 'canvas_debug_options.dart';
import 'imgui.dart';

/// Colour a visible tile is tinted with when [CanvasDebugOptions.showTileState]
/// is on. Shared with the pane's legend so the two cannot disagree: the
/// overlay tint in [paintTileOverlay] and, in canvas_debug_pane.dart, the
/// "Visible tiles" stacked bar and rows and the "Overlays" legend all call
/// this one function. Lives here, not in the pane, so the canvas side does not
/// import the pane widget.
Color tileDrawColor(TileDraw draw) => switch (draw) {
  TileDraw.current => ImTheme.good,
  TileDraw.stale => ImTheme.warn,
  TileDraw.coarser => const Color(0xFF4296FA),
  TileDraw.finer => const Color(0xFF3BC9DB),
  TileDraw.missing => ImTheme.bad,
  TileDraw.blank => ImTheme.textDim,
};

/// Human-readable name for [draw]; used by the pane's rows, legend, and text
/// report (canvas_debug_pane.dart). Must cover every [TileDraw] value; the
/// switch has no default, so adding a value to the enum is a compile error
/// here until it is handled.
String tileDrawName(TileDraw draw) => switch (draw) {
  TileDraw.current => 'current',
  TileDraw.stale => 'stale',
  TileDraw.coarser => 'coarser fallback',
  TileDraw.finer => 'finer fallback',
  TileDraw.missing => 'missing',
  TileDraw.blank => 'blank',
};

/// Paints debug overlays in document space. [canvas] must already carry the
/// document-to-screen transform; [zoom] keeps line widths and text a constant
/// size on screen.
///
/// Reads the live [frame] (`TiledRenderer.frame`), not the pane's frozen
/// snapshot, so overlays always match the tiles painted in the same frame
/// even while the pane's readouts are paused. Which parts are drawn is
/// controlled by [options]. Only caller: `_CanvasPainter.paint` in
/// ../canvas/canvas_view.dart, which calls it inside the document transform.
void paintTileOverlay(
  ui.Canvas canvas, {
  required TileFrameStats frame,
  required CanvasDebugOptions options,
  required double zoom,
}) {
  if (!options.anyOverlay) return;
  final px = 1 / zoom;

  if (options.showTileState ||
      options.showTileGrid ||
      options.showCoordinates) {
    final fill = Paint();
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = px
      ..color = const Color(0xCC000000);
    // frame.draws holds exactly the visible tiles at frame.level, filled in
    // by TiledRenderer.paint, which CanvasView's painter calls just before
    // this function in the same paint.
    for (final entry in frame.draws.entries) {
      final rect = TileGrid.rectOf(entry.key);
      if (options.showTileState) {
        fill.color = tileDrawColor(entry.value).withValues(alpha: 0.22);
        canvas.drawRect(rect, fill);
      }
      if (options.showTileGrid || options.showTileState) {
        canvas.drawRect(rect, line);
      }
      if (options.showCoordinates) {
        _label(canvas, '${entry.key.x},${entry.key.y}', rect.topLeft, px);
      }
    }
  }

  // Inset by 2 screen pixels so the 2-pixel border lies inside the visible
  // rectangle instead of straddling its edge.
  if (options.showVisibleRect) {
    canvas.drawRect(
      frame.visibleRect.deflate(px * 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = px * 2
        ..color = ImTheme.accent,
    );
  }
}

/// Draws [text] at [at] (document space) in black, [px] document units per
/// screen pixel, so the glyphs stay about 11 logical pixels tall at any zoom.
/// Allocates and disposes a TextPainter on every call, i.e. once per visible
/// tile per frame while coordinates are on.
void _label(ui.Canvas canvas, String text, Offset at, double px) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: ImTheme.style.copyWith(
        fontSize: 11 * px,
        color: const Color(0xFF000000),
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(canvas, at + Offset(3 * px, 2 * px));
  painter.dispose();
}
