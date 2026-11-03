import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'canvas_controller.dart';
import 'pencil_splats.dart';

/// Draws strokes as instanced gaussian splats ("pencil specks").
///
/// One small gaussian sprite is rasterized once and then drawn thousands of
/// times per stroke through a single `drawRawAtlas` call. Batches for completed
/// strokes are cached because strokes are immutable.
class PencilRenderer {
  ui.Image? _sprite;
  Float32List _spriteRects = Float32List(0);

  // Completed strokes are immutable, so their batch is built once. Keyed by
  // identity; no state leaks into the document model or saved format.
  final Expando<SplatBatch> _batches = Expando<SplatBatch>('pencil batches');
  final Expando<int> _seeds = Expando<int>('pencil seeds');
  int _nextSeed = 1;

  /// Rasterizes the gaussian sprite on first use.
  ui.Image get sprite => _sprite ??= _buildSprite();

  /// Paints all [strokes] plus the in-progress [active] points.
  void paint(
    Canvas canvas,
    Iterable<CanvasStroke> strokes,
    List<CanvasPoint> active,
  ) {
    final paint = Paint()
      ..isAntiAlias = true
      ..filterQuality = FilterQuality.medium;
    for (final stroke in strokes) {
      final batch = _batches[stroke] ??= PencilSplats.build(
        stroke.points,
        strokeSeed: _seeds[stroke] ??= _nextSeed++,
      );
      _draw(canvas, batch, paint);
    }
    if (active.isNotEmpty) {
      // The active stroke becomes the next committed stroke, which will take
      // `_nextSeed`. Using it now keeps the grain identical on pointer-up.
      _draw(canvas, PencilSplats.build(active, strokeSeed: _nextSeed), paint);
    }
  }

  void _draw(Canvas canvas, SplatBatch batch, Paint paint) {
    if (batch.count == 0) return;
    canvas.drawRawAtlas(
      sprite,
      batch.transforms,
      _rectsFor(batch.count),
      batch.colors,
      // Sprite is black with gaussian alpha; modulate multiplies that alpha by
      // each splat's own colour alpha, giving per-speck opacity.
      BlendMode.modulate,
      null,
      paint,
    );
  }

  /// Every splat samples the whole sprite, so the source-rect buffer is just
  /// the same four numbers repeated. Reuse a growing buffer across draws.
  Float32List _rectsFor(int count) {
    if (_spriteRects.length < count * 4) {
      final size = PencilSplats.spritePixels.toDouble();
      final grown = Float32List(math.max(count * 4, _spriteRects.length * 2));
      for (var i = 0; i < grown.length; i += 4) {
        grown[i] = 0;
        grown[i + 1] = 0;
        grown[i + 2] = size;
        grown[i + 3] = size;
      }
      _spriteRects = grown;
    }
    return Float32List.sublistView(_spriteRects, 0, count * 4);
  }

  ui.Image _buildSprite() {
    const size = PencilSplats.spritePixels;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    // exp(-r^2 / 2) sampled in r = 0..2.2 sigma, so alpha reaches ~0.09 at the
    // sprite edge; the final stop forces it to exactly 0 to avoid a visible
    // square. Eight stops are visually smooth under linear interpolation.
    const stops = 8;
    final colors = <Color>[];
    final offsets = <double>[];
    for (var i = 0; i <= stops; i++) {
      final r = i / stops;
      final a = i == stops ? 0.0 : math.exp(-(r * r * 2.2 * 2.2) / 2);
      colors.add(Color.fromRGBO(0, 0, 0, a));
      offsets.add(r);
    }
    final paint = Paint()
      ..shader = ui.Gradient.radial(
        const Offset(size / 2, size / 2),
        size / 2,
        colors,
        offsets,
      );
    canvas.drawRect(const Rect.fromLTWH(0, 0, size * 1.0, size * 1.0), paint);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(size, size);
    picture.dispose();
    return image;
  }

  void dispose() {
    _sprite?.dispose();
    _sprite = null;
  }
}
