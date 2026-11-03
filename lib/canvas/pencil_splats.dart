import 'dart:math' as math;
import 'dart:typed_data';

import 'canvas_controller.dart';

/// Flat, GPU-ready buffers describing many small gaussian "pencil specks".
///
/// Layout matches `Canvas.drawRawAtlas`: [transforms] holds four floats per
/// splat (`scos, ssin, tx, ty`, with the sprite-centre anchor already folded
/// into `tx, ty`) and [colors] holds one packed ARGB int per splat. All splats
/// sample the same gaussian sprite, so a whole stroke is a single instanced
/// draw call.
class SplatBatch {
  SplatBatch._(this.count, this.transforms, this.colors);

  static final SplatBatch empty = SplatBatch._(0, Float32List(0), Int32List(0));

  final int count;
  final Float32List transforms;
  final Int32List colors;
}

/// Turns a stroke's vector points into a deterministic cloud of tiny splats.
///
/// Splats are derived from the stroke geometry rather than stored, so the saved
/// document format is unchanged. Every random-looking value is a pure function
/// of (segment index, splat index), so the same stroke always produces the same
/// specks, extending a stroke never moves earlier specks, and output is
/// reproducible in tests.
class PencilSplats {
  const PencilSplats._();

  /// Distance in document units between consecutive sample positions along a
  /// stroke. Smaller values give a denser, smoother line.
  static const double sampleSpacing = 0.5;

  /// Splats emitted per sample at full weight; scaled down with the brush
  /// radius so thin strokes are not denser than thick ones.
  static const int splatsPerSample = 6;

  /// Pixel edge length of the gaussian sprite the transforms are authored
  /// against. Must match the sprite the renderer rasterizes.
  static const int spritePixels = 32;

  /// Edge length in logical pixels of the gaussian sprite quad at scale 1.
  static const double spriteSize = 1.6;

  /// Splat opacity range (0-255) before gaussian falloff in the sprite.
  static const int minAlpha = 40;
  static const int maxAlpha = 190;

  /// Builds splats for [points], treating them as one stroke.
  ///
  /// [strokeSeed] differentiates strokes so two strokes over the same path do
  /// not share an identical speck pattern.
  static SplatBatch build(List<CanvasPoint> points, {int strokeSeed = 0}) {
    if (points.isEmpty) return SplatBatch.empty;

    // First pass: count samples so buffers are allocated exactly once.
    var sampleCount = 1; // The first point is always sampled.
    for (var i = 1; i < points.length; i++) {
      final length = (points[i].position - points[i - 1].position).distance;
      sampleCount += math.max(1, (length / sampleSpacing).ceil());
    }
    final maxSplats = sampleCount * splatsPerSample;
    final transforms = Float32List(maxSplats * 4);
    final colors = Int32List(maxSplats);
    // Sprite quad edge -> scale factor so scale 1 is `spriteSize` document
    // units wide, and the anchor that puts the sprite centre on the splat.
    final unit = spriteSize / spritePixels;
    const anchor = spritePixels / 2.0;

    var splat = 0;
    var sampleIndex = 0;

    void emit(double x, double y, double weight) {
      final radius = CanvasController.brushDiameter * weight / 2;
      // Fewer specks for thin strokes keeps coverage density roughly constant.
      final count = math.max(1, (splatsPerSample * weight).round());
      for (var k = 0; k < count; k++) {
        final h = _mix(strokeSeed, sampleIndex, k);
        // Uniform disc sampling: sqrt gives uniform area density.
        final r = radius * math.sqrt(_unit(h, 0));
        final theta = 2 * math.pi * _unit(h, 1);
        final scale = 0.5 + 1.0 * _unit(h, 2);
        final rotation = 2 * math.pi * _unit(h, 3);
        final alpha = minAlpha + ((maxAlpha - minAlpha) * _unit(h, 4)).round();
        final base = splat * 4;
        final s = scale * unit;
        final scos = s * math.cos(rotation);
        final ssin = s * math.sin(rotation);
        final px = x + r * math.cos(theta);
        final py = y + r * math.sin(theta);
        // RSTransform maps source (u, v) to
        // (scos*u - ssin*v + tx, ssin*u + scos*v + ty); pick tx, ty so the
        // sprite centre (anchor, anchor) lands on (px, py).
        transforms[base] = scos;
        transforms[base + 1] = ssin;
        transforms[base + 2] = px - (scos * anchor - ssin * anchor);
        transforms[base + 3] = py - (ssin * anchor + scos * anchor);
        // Opaque-black speck; only alpha varies. Packed as 0xAARRGGBB.
        colors[splat] = alpha << 24;
        splat++;
      }
      sampleIndex++;
    }

    emit(
      points.first.position.dx,
      points.first.position.dy,
      points.first.weight,
    );
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1];
      final b = points[i];
      final length = (b.position - a.position).distance;
      final steps = math.max(1, (length / sampleSpacing).ceil());
      for (var s = 1; s <= steps; s++) {
        final t = s / steps;
        emit(
          a.position.dx + (b.position.dx - a.position.dx) * t,
          a.position.dy + (b.position.dy - a.position.dy) * t,
          a.weight + (b.weight - a.weight) * t,
        );
      }
    }

    return SplatBatch._(
      splat,
      Float32List.sublistView(transforms, 0, splat * 4),
      Int32List.sublistView(colors, 0, splat),
    );
  }

  /// SplitMix64-style counter hash over (seed, sample, splat). Pure function,
  /// so splat appearance never depends on call order or prior state.
  static int _mix(int seed, int sample, int splat) {
    var z =
        (seed * 0x9E3779B97F4A7C15) ^
        (sample * 0xBF58476D1CE4E5B9) ^
        (splat * 0x94D049BB133111EB);
    z = (z ^ (z >>> 30)) * 0xBF58476D1CE4E5B9;
    z = (z ^ (z >>> 27)) * 0x94D049BB133111EB;
    return z ^ (z >>> 31);
  }

  /// Derives an independent value in [0, 1) from hash [h] and channel
  /// [channel] by re-mixing, so one hash feeds several attributes.
  static double _unit(int h, int channel) {
    var z = h + channel * 0x9E3779B97F4A7C15;
    z = (z ^ (z >>> 30)) * 0xBF58476D1CE4E5B9;
    z = (z ^ (z >>> 27)) * 0x94D049BB133111EB;
    z = z ^ (z >>> 31);
    // Top 53 bits -> double in [0, 1).
    return (z >>> 11) / 9007199254740992.0;
  }
}
