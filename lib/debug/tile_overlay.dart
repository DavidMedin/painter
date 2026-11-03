import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../canvas/tile_grid.dart';
import '../canvas/tile_stats.dart';
import 'canvas_debug_options.dart';
import 'imgui.dart';

/// Colour a visible tile is tinted with when [CanvasDebugOptions.showTileState]
/// is on. Shared with the pane's legend so the two cannot disagree.
Color tileDrawColor(TileDraw draw) => switch (draw) {
  TileDraw.current => ImTheme.good,
  TileDraw.stale => ImTheme.warn,
  TileDraw.coarser => const Color(0xFF4296FA),
  TileDraw.finer => const Color(0xFF3BC9DB),
  TileDraw.missing => ImTheme.bad,
  TileDraw.blank => ImTheme.textDim,
};

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
