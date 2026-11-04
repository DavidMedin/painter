// What: The in-canvas half of the debug tools: `paintTileOverlay`, which draws
//   tile tints, grid outlines, tile coordinates, and the visible rectangle in
//   document space, plus `tileDrawColor` / `tileDrawName`, which map each
//   TileDraw state to its theme color and display name.
// Why: The overlays follow pan, zoom, rotation, and the selected palette. This
//   file shares the color/name mapping with the diagnostics pane so the legend
//   cannot drift from what the canvas shows.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../canvas/tile_grid.dart';
import '../canvas/tile_stats.dart';
import '../settings/painter_settings.dart';
import 'canvas_debug_options.dart';

/// Shared theme color for each tile state, used by the canvas and diagnostics
/// pane so the overlay and legend cannot disagree.
Color tileDrawColor(
  TileDraw draw,
  ColorScheme scheme,
  PainterThemeColors colors,
) => switch (draw) {
  TileDraw.current => colors.success,
  TileDraw.stale => colors.warning,
  TileDraw.coarser => scheme.secondary,
  TileDraw.finer => colors.info,
  TileDraw.missing => scheme.error,
  TileDraw.blank => scheme.onSurfaceVariant,
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
  required ColorScheme colorScheme,
  required PainterThemeColors themeColors,
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
      ..color = colorScheme.outline.withValues(alpha: 0.8);
    // frame.draws holds exactly the visible tiles at frame.level, filled in
    // by TiledRenderer.paint, which CanvasView's painter calls just before
    // this function in the same paint.
    for (final entry in frame.draws.entries) {
      final rect = TileGrid.rectOf(entry.key);
      if (options.showTileState) {
        fill.color = tileDrawColor(
          entry.value,
          colorScheme,
          themeColors,
        ).withValues(alpha: 0.22);
        canvas.drawRect(rect, fill);
      }
      if (options.showTileGrid || options.showTileState) {
        canvas.drawRect(rect, line);
      }
      if (options.showCoordinates) {
        _label(
          canvas,
          '${entry.key.x},${entry.key.y}',
          rect.topLeft,
          px,
          colorScheme.onSurface,
        );
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
        ..color = colorScheme.primary,
    );
  }
}

/// Draws [text] at [at] (document space) in the supplied theme color. [px]
/// document units per screen pixel keeps the glyphs about 11 logical pixels
/// tall at any zoom. Allocates and disposes a TextPainter per visible tile.
void _label(ui.Canvas canvas, String text, Offset at, double px, Color color) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(fontSize: 11 * px, color: color),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(canvas, at + Offset(3 * px, 2 * px));
  painter.dispose();
}
