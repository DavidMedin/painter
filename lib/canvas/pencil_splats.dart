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

  /// Largest distance in document units from a stroke point to any ink it can
  /// produce: the brush radius plus the largest (1.5x) splat half-diagonal.
  static const double inkMargin =
      CanvasController.brushDiameter / 2 + spriteSize * 1.5 * 0.7072;

  /// Builds splats for [points], treating them as one stroke.
  ///
  /// [strokeSeed] differentiates strokes so two strokes over the same path do
  /// not share an identical speck pattern.
  static SplatBatch build(List<CanvasPoint> points, {int strokeSeed = 0}) {
    final stream = SplatStream(strokeSeed);
    stream.extend(points);
    return stream.batch;
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

/// Grows the splat cloud of one stroke as points are appended, without
/// regenerating earlier splats.
///
/// Splat values are a pure function of `(seed, sampleIndex, splatIndex)`, so
/// extending only emits the samples contributed by the new points; the
/// resulting buffers are identical to building the whole stroke at once.
class SplatStream {
  SplatStream(this.strokeSeed);

  final int strokeSeed;

  Float32List _transforms = Float32List(0);
  Int32List _colors = Int32List(0);
  int _count = 0;
  int _sampleIndex = 0;
  int _pointsConsumed = 0;
  CanvasPoint? _last;

  /// Number of splats emitted so far.
  int get count => _count;

  /// All splats emitted so far, as views over the stream's buffers. Valid only
  /// until the next [extend].
  SplatBatch get batch => SplatBatch._(
    _count,
    Float32List.sublistView(_transforms, 0, _count * 4),
    Int32List.sublistView(_colors, 0, _count),
  );

  /// Number of stroke points already consumed by [extend].
  int get pointsConsumed => _pointsConsumed;

  /// Consumes `points[pointsConsumed..]`, emitting their splats. [points] must
  /// be the same growing list on every call.
  void extend(List<CanvasPoint> points) {
    if (points.length <= _pointsConsumed) return;

    var newSamples = 0;
    var previous = _last;
    for (var i = _pointsConsumed; i < points.length; i++) {
      if (previous == null) {
        newSamples += 1;
      } else {
        final length = (points[i].position - previous.position).distance;
        newSamples += math.max(1, (length / PencilSplats.sampleSpacing).ceil());
      }
      previous = points[i];
    }
    _reserve(_count + newSamples * PencilSplats.splatsPerSample);

    var from = _last;
    for (var i = _pointsConsumed; i < points.length; i++) {
      final b = points[i];
      if (from == null) {
        _emit(b.position.dx, b.position.dy, b.weight);
      } else {
        final length = (b.position - from.position).distance;
        final steps = math.max(1, (length / PencilSplats.sampleSpacing).ceil());
        for (var s = 1; s <= steps; s++) {
          final t = s / steps;
          _emit(
            from.position.dx + (b.position.dx - from.position.dx) * t,
            from.position.dy + (b.position.dy - from.position.dy) * t,
            from.weight + (b.weight - from.weight) * t,
          );
        }
      }
      from = b;
    }
    _last = from;
    _pointsConsumed = points.length;
  }

  void _reserve(int splats) {
    if (_colors.length >= splats) return;
    final capacity = math.max(splats, _colors.length * 2);
    _transforms = Float32List(capacity * 4)
      ..setRange(0, _count * 4, _transforms);
    _colors = Int32List(capacity)..setRange(0, _count, _colors);
  }

  void _emit(double x, double y, double weight) {
    // Sprite quad edge -> scale factor so scale 1 is `spriteSize` document
    // units wide, and the anchor that puts the sprite centre on the splat.
    const unit = PencilSplats.spriteSize / PencilSplats.spritePixels;
    const anchor = PencilSplats.spritePixels / 2.0;
    final radius = CanvasController.brushDiameter * weight / 2;
    // Fewer specks for thin strokes keeps coverage density roughly constant.
    final count = math.max(1, (PencilSplats.splatsPerSample * weight).round());
    for (var k = 0; k < count; k++) {
      final h = PencilSplats._mix(strokeSeed, _sampleIndex, k);
      // Uniform disc sampling: sqrt gives uniform area density.
      final r = radius * math.sqrt(PencilSplats._unit(h, 0));
      final theta = 2 * math.pi * PencilSplats._unit(h, 1);
      final scale = 0.5 + 1.0 * PencilSplats._unit(h, 2);
      final rotation = 2 * math.pi * PencilSplats._unit(h, 3);
      final alpha =
          PencilSplats.minAlpha +
          ((PencilSplats.maxAlpha - PencilSplats.minAlpha) *
                  PencilSplats._unit(h, 4))
              .round();
      final base = _count * 4;
      final s = scale * unit;
      final scos = s * math.cos(rotation);
      final ssin = s * math.sin(rotation);
      final px = x + r * math.cos(theta);
      final py = y + r * math.sin(theta);
      // RSTransform maps source (u, v) to
      // (scos*u - ssin*v + tx, ssin*u + scos*v + ty); pick tx, ty so the
      // sprite centre (anchor, anchor) lands on (px, py).
      _transforms[base] = scos;
      _transforms[base + 1] = ssin;
      _transforms[base + 2] = px - (scos * anchor - ssin * anchor);
      _transforms[base + 3] = py - (ssin * anchor + scos * anchor);
      // Opaque-black speck; only alpha varies. Packed as 0xAARRGGBB.
      _colors[_count] = alpha << 24;
      _count++;
    }
    _sampleIndex++;
  }
}
