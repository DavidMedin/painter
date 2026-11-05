// What: unit tests of splat generation: PencilSplats.build turns a stroke's
//   points into flat atlas buffers (SplatBatch) whose count, determinism,
//   placement, pressure dependence, and opacity are checked numerically.
// Why: design/canvas/pencil-splats.md renders strokes as a cloud of gaussian
// splats derived from
//   the vector points, not stored. The look (a line that reads as pencil
//   from afar, specks up close) and the guarantees later systems rely on
//   (same stroke -> same specks, extending a stroke never moves earlier
//   specks) are properties of this pure-Dart generator, so they can be
//   tested without a GPU or any rendering.
// Covers: lib/canvas/pencil_splats.dart (PencilSplats.build, which runs
//   SplatStream once; SplatBatch layout). Pixels are checked elsewhere, in
//   tiled_renderer_test.dart.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:painter/canvas/canvas_controller.dart';
import 'package:painter/canvas/pencil_splats.dart';

/// A two-point horizontal stroke from (10, 20) to (10 + [length], 20) with a
/// constant pressure [weight].
List<CanvasPoint> _line(double length, double weight) => [
  CanvasPoint(position: const Offset(10, 20), weight: weight),
  CanvasPoint(position: Offset(10 + length, 20), weight: weight),
];

/// Recovers the document-space centre of splat [i] from its atlas transform
/// by undoing the sprite-centre anchor folded into tx/ty.
Offset _centre(SplatBatch batch, int i) {
  const anchor = PencilSplats.spritePixels / 2.0;
  final scos = batch.transforms[i * 4];
  final ssin = batch.transforms[i * 4 + 1];
  return Offset(
    batch.transforms[i * 4 + 2] + scos * anchor - ssin * anchor,
    batch.transforms[i * 4 + 3] + ssin * anchor + scos * anchor,
  );
}

// The splat buffers are plain Float32List/Int32List in drawRawAtlas layout
// (four floats and one packed ARGB per splat), so tests read them directly.
void main() {
  test('a stroke becomes many splats, enough to read as a pencil line', () {
    final batch = PencilSplats.build(_line(100, 1));

    // 100 units of full-weight stroke should be thousands of specks, not a
    // handful of dots.
    expect(batch.count, greaterThan(1000));
    expect(batch.transforms.length, batch.count * 4);
    expect(batch.colors.length, batch.count);
  });

  test('empty input produces no splats', () {
    expect(PencilSplats.build(const []).count, 0);
  });

  test('a single tap still leaves specks', () {
    final batch = PencilSplats.build([
      const CanvasPoint(position: Offset(5, 5), weight: 1),
    ]);

    expect(batch.count, greaterThan(0));
  });

  test('the same stroke always yields identical splats', () {
    final a = PencilSplats.build(_line(40, 0.6), strokeSeed: 3);
    final b = PencilSplats.build(_line(40, 0.6), strokeSeed: 3);

    expect(b.count, a.count);
    expect(b.transforms, a.transforms);
    expect(b.colors, a.colors);
  });

  test('different strokes over the same path get different speck patterns', () {
    final a = PencilSplats.build(_line(40, 1), strokeSeed: 1);
    final b = PencilSplats.build(_line(40, 1), strokeSeed: 2);

    expect(b.transforms, isNot(a.transforms));
  });

  // PencilSplats.build is SplatStream run once, and TiledRenderer draws the
  // in-progress stroke by extending a SplatStream
  // (design/canvas/tile-cache.md). Appending points must emit only new splats
  // and leave the existing prefix of the buffers bit-identical; this test pins
  // that prefix property.
  test('extending a stroke does not move specks already laid down', () {
    // The active stroke grows by one point per pointer move and is extended
    // through SplatStream; earlier specks must stay put or the line would
    // shimmer while drawing.
    final shortStroke = _line(30, 1);
    final longStroke = [
      ...shortStroke,
      const CanvasPoint(position: Offset(60, 35), weight: 1),
    ];

    final before = PencilSplats.build(shortStroke);
    final after = PencilSplats.build(longStroke);

    expect(after.count, greaterThan(before.count));
    expect(
      after.transforms.sublist(0, before.transforms.length),
      before.transforms,
    );
    expect(after.colors.sublist(0, before.colors.length), before.colors);
  });

  // Each splat is placed on a disc of radius brushDiameter * weight / 2
  // around a sample (SplatStream._emit), so every splat centre, recovered
  // with _centre, must lie within the brush radius of the segment.
  test('specks stay within the brush radius of the stroke path', () {
    const weight = 0.75;
    final radius = CanvasController.brushDiameter * weight / 2;
    final batch = PencilSplats.build(_line(50, weight));

    for (var i = 0; i < batch.count; i++) {
      final c = _centre(batch, i);
      expect(c.dy, inInclusiveRange(20 - radius - 1e-3, 20 + radius + 1e-3));
      expect(c.dx, inInclusiveRange(10 - radius - 1e-3, 60 + radius + 1e-3));
    }
  });

  // Guards the "uniform disc sampling" in SplatStream._emit: a stroke whose
  // specks all sat on the centre line would look like a hairline, not a
  // brush-width pencil mark.
  test(
    'specks fill the brush width rather than clumping on the centre line',
    () {
      final batch = PencilSplats.build(_line(200, 1));
      final radius = CanvasController.brushDiameter / 2;

      var minDy = double.infinity, maxDy = -double.infinity;
      var upper = 0, lower = 0;
      for (var i = 0; i < batch.count; i++) {
        final dy = _centre(batch, i).dy - 20;
        minDy = math.min(minDy, dy);
        maxDy = math.max(maxDy, dy);
        if (dy < 0) upper++;
        if (dy > 0) lower++;
      }

      expect(minDy, lessThan(-radius * 0.9));
      expect(maxDy, greaterThan(radius * 0.9));
      // Roughly symmetric: neither side holds more than 55% of the specks.
      expect(upper / (upper + lower), inInclusiveRange(0.45, 0.55));
    },
  );

  test('lighter pressure lays fewer, narrower specks than full pressure', () {
    final light = PencilSplats.build(_line(100, 0.2));
    final full = PencilSplats.build(_line(100, 1));

    expect(light.count, lessThan(full.count));
    var lightSpread = 0.0, fullSpread = 0.0;
    for (var i = 0; i < light.count; i++) {
      lightSpread = math.max(lightSpread, (_centre(light, i).dy - 20).abs());
    }
    for (var i = 0; i < full.count; i++) {
      fullSpread = math.max(fullSpread, (_centre(full, i).dy - 20).abs());
    }
    expect(lightSpread, lessThan(fullSpread));
  });

  test('speck opacity varies and spans the configured range', () {
    final batch = PencilSplats.build(_line(100, 1));

    // Alpha is the top byte of each packed colour. Read it as unsigned so
    // values above 127 (sign bit set in Int32) are not misread as negative.
    final alphas = [for (final c in batch.colors) (c >> 24) & 0xFF];
    final minAlpha = alphas.reduce(math.min);
    final maxAlpha = alphas.reduce(math.max);

    expect(minAlpha, greaterThanOrEqualTo(PencilSplats.minAlpha));
    expect(maxAlpha, lessThanOrEqualTo(PencilSplats.maxAlpha));
    expect(
      maxAlpha,
      greaterThan(127),
      reason: 'high alphas must survive packing',
    );
    expect(maxAlpha - minAlpha, greaterThan(80));
    // Colour channels stay black; only alpha carries the speck's tone.
    expect(batch.colors.every((c) => c & 0x00FFFFFF == 0), isTrue);
  });
}
