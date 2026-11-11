// What: Pure-Dart generation of the pencil "splat" cloud for a stroke:
// `PencilSplats` (constants, the one-shot `build`, the hash), `SplatStream`
// (incremental generation as points are appended) and `SplatBatch` (the flat
// output buffers). Also the primary file for the pencil splat system; see the
// overview below.
//
// Why: Splat generation is the CPU-heavy part of rendering and must be
// deterministic and independent of any GPU object so it can run in a worker
// isolate (splat_worker.dart) and be unit-tested without a GPU
// (design/canvas/pencil-splats.md). Keeping it separate from drawing
// (tiled_renderer.dart, tile_cache.dart) means the look of the brush is defined
// in exactly one place.

import 'dart:math' as math;
import 'dart:typed_data';

import 'canvas_controller.dart';

// ---------------------------------------------------------------------------
// Pencil splat system (overview)
//
// What: A splat is one tiny speck of graphite: a copy of a single soft
// gaussian sprite (32x32 px, black, alpha following exp(-r^2 / 2); built by
// `TiledRenderer._buildSprite`) drawn with its own position, rotation, scale
// and opacity. A stroke is a cloud of thousands of them (about 13 per document
// unit at full weight, design/canvas/pencil-splats.md).
//
// Why: The brush has to read as a pencil line from a distance while each mark
// is a grain. The earlier renderer drew solid round-capped segments joined by
// circles (design/canvas/vector-canvas.md), which cannot look grainy. Splats
// are derived at paint time from the stroke's points and weights and are never
// stored, so the saved-document format is unchanged and old `.paint` files
// render as pencil without migration (design/document/file-format-and-flow.md
// and design/canvas/pencil-splats.md). Drawing all splats of a stroke with one
// `Canvas.drawRawAtlas` call (see `SplatBatch`) is GPU instancing instead of
// thousands of draw calls.
//
// How:
//   - `SplatStream.extend` walks each segment every `sampleSpacing` (0.5)
//     document units, interpolating position and weight. Each sample emits
//     round(splatsPerSample * weight) splats (at least 1) placed uniformly in
//     a disc of radius `brushDiameter * weight / 2`, with random scale
//     (0.5-1.5x), rotation and alpha (`minAlpha`..`maxAlpha`). Weight changes
//     brush size only: it scales the disc and the splat count so thin strokes
//     are not denser than thick ones.
//   - Randomness is a counter-based hash (`PencilSplats._mix`) of
//     (stroke seed, sample index, splat index), with no generator state. So
//     the same stroke always gives the same specks, and appending points
//     never moves earlier specks, because a segment's sample count depends
//     only on its own endpoints (prefix stability).
//   - Why determinism and prefix stability matter: a splat near a tile edge
//     is drawn into both neighbouring tiles and must be identical in each or a
//     seam shows; a tile rebuilt after eviction must reproduce the same
//     specks; and each live chunk must look the same when committed
//     (docs/decisions/004-tile-cache.md). Seeds come from `CanvasStroke.seed`,
//     which is stored with the stroke (see the overview in
//     canvas_controller.dart).
//   - Every peer and every later run must turn the same stroke data into the
//     same splats, so `strokeEngineVersion` names this generation; a file or
//     Session with another value is to be refused
//     (docs/decisions/008-document-file-format.md PNT-A0014-07).
//   - Two consumers. Committed chunks: `TileCache._splatsFor` asks
//     `SplatWorker.generate` (splat_worker.dart), whose isolate runs
//     `PencilSplats.build` and returns `StrokeSplats`; `TileCache._build`
//     draws them into tile pictures. The splats are document-space, so one
//     generation serves every tile and level of detail. The active chunk is
//     drawn live by `TiledRenderer._paintActive`, which extends a `SplatStream`
//     with new points. Completed chunks enter `CanvasDocument` and are
//     rasterized by `TileCache` during a long gesture.
//   - Isolate boundary: points go to the worker as a flat Float64List
//     (x, y, weight per point) and the buffers come back as
//     `TransferableTypedData`; no per-point objects are copied.
//
// Shared constants: `spritePixels` and the sprite source rectangles
// (`TiledRenderer._rectsFor`, `TileCache._rectsFor`) must describe the same
// sprite. `inkMargin` is the bound `TileCache._touches` uses to decide which
// tiles a stroke can reach. The spacing, density, size and alpha values are
// first-pass choices judged on offscreen renders, not reviewed by an artist
// (design/canvas/pencil-splats.md).
// ---------------------------------------------------------------------------

/// The Engine version: which way of turning stroke data (points, weights,
/// seed) into splats this build uses
/// (docs/decisions/008-document-file-format.md PNT-A0014-07).
///
/// Any change to how stroke data becomes splats (sampling, the hash, the
/// splat count, placement, size, rotation or alpha) must increment it, or
/// stored strokes would render differently from how they were drawn.
const int strokeEngineVersion = 1;

/// Flat, GPU-ready buffers describing many small gaussian "pencil specks".
///
/// Layout matches `Canvas.drawRawAtlas`: [transforms] holds four floats per
/// splat (`scos, ssin, tx, ty`, with the sprite-centre anchor already folded
/// into `tx, ty`) and [colors] holds one packed ARGB int per splat. All splats
/// sample the same gaussian sprite, so a whole stroke is a single instanced
/// draw call.
///
/// Produced by [SplatStream.batch] and `PencilSplats.build`. The buffers from
/// [SplatStream.batch] are views, valid only until the stream's next
/// [SplatStream.extend]. `StrokeSplats` (splat_worker.dart) is the same data
/// as an owned copy received from the worker isolate.
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
/// of (stroke seed, sample index, splat index), where the sample index counts
/// samples along the stroke from its first point. So the same stroke always
/// produces the same specks, extending a stroke never moves earlier specks,
/// and output is reproducible in tests. See the overview at the top of this
/// file.
class PencilSplats {
  const PencilSplats._();

  /// Distance in document units between consecutive sample positions along a
  /// stroke. Smaller values give a denser, smoother line.
  static const double sampleSpacing = 0.5;

  /// Splats emitted per sample at full weight; scaled down with the brush
  /// radius so thin strokes are not denser than thick ones.
  static const int splatsPerSample = 6;

  /// Pixel edge length of the gaussian sprite the transforms are authored
  /// against. Must match the sprite the renderer rasterizes
  /// (`TiledRenderer._buildSprite`) and the source rectangles passed to
  /// `drawRawAtlas` (`TiledRenderer._rectsFor`, `TileCache._rectsFor`).
  static const int spritePixels = 32;

  /// Edge length in document units of the gaussian sprite quad at scale 1
  /// (equal to logical pixels at the default viewport).
  static const double spriteSize = 1.6;

  /// Splat opacity range (0-255) before gaussian falloff in the sprite.
  static const int minAlpha = 40;
  static const int maxAlpha = 190;

  /// Largest distance in document units from a stroke point to any ink it can
  /// produce: the brush radius plus the largest (1.5x) splat half-diagonal.
  ///
  /// The 0.7072 factor is about sqrt(2)/2, the half-diagonal of a square
  /// sprite (a rotated sprite reaches that far). `TileCache._touches` inflates
  /// stroke bounds by this value; if the brush diameter or splat scale range
  /// changes it must stay an upper bound.
  static const double inkMargin =
      CanvasController.brushDiameter / 2 + spriteSize * 1.5 * 0.7072;

  /// Builds splats for [points], treating them as one stroke.
  ///
  /// [strokeSeed] differentiates strokes so two strokes over the same path do
  /// not share an identical speck pattern.
  ///
  /// This is one [SplatStream] extended once, so there is a single generation
  /// path. The worker isolate (`_workerMain` in splat_worker.dart) calls it.
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
///
/// Used directly on the UI isolate for the in-progress chunk
/// (`TiledRenderer._paintActive`); `PencilSplats.build` runs one stream to
/// completion for committed strokes and one-shot generation. Splats are
/// emitted sample by sample in order, so the stream only keeps the last point
/// and counters, not the earlier points.
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
  ///
  /// Pass 1 counts the new samples so the buffers are grown once ([_reserve]);
  /// pass 2 emits them. Each point after the first contributes
  /// `max(1, ceil(length / sampleSpacing))` samples, the last of which lies
  /// exactly on the point.
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

  /// Grows the buffers to hold at least [splats] splats, doubling to keep
  /// repeated growth amortized. Reallocation invalidates earlier [batch] views.
  void _reserve(int splats) {
    if (_colors.length >= splats) return;
    final capacity = math.max(splats, _colors.length * 2);
    _transforms = Float32List(capacity * 4)
      ..setRange(0, _count * 4, _transforms);
    _colors = Int32List(capacity)..setRange(0, _count, _colors);
  }

  /// Emits the splats of one sample at ([x], [y]) with interpolated [weight].
  /// The sample index, not the point index, feeds the hash, so output does not
  /// depend on how points were batched across [extend] calls.
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
