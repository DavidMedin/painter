import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:painter/canvas/canvas_controller.dart';
import 'package:painter/canvas/pencil_renderer.dart';

const _width = 200;
const _height = 40;

Future<ByteData> _renderWith(
  PencilRenderer renderer,
  List<CanvasStroke> strokes, {
  List<CanvasPoint> active = const [],
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(Colors.white, BlendMode.src);
  renderer.paint(canvas, strokes, active);
  final image = await recorder.endRecording().toImage(_width, _height);
  addTearDown(image.dispose);
  return (await image.toByteData())!;
}

Future<ByteData> _render(List<CanvasStroke> strokes) async {
  final renderer = PencilRenderer();
  addTearDown(renderer.dispose);
  return _renderWith(renderer, strokes);
}

int _red(ByteData bytes, int x, int y) => bytes.getUint8((y * _width + x) * 4);

CanvasStroke _horizontal(double weight) => CanvasStroke([
  CanvasPoint(position: const Offset(20, 20), weight: weight),
  CanvasPoint(position: const Offset(180, 20), weight: weight),
]);

void main() {
  test('a stroke renders as grainy specks, not a solid bar', () async {
    final bytes = await _render([_horizontal(1)]);
    final radius = CanvasController.brushDiameter / 2;

    // Count pixel tones inside the central band of the stroke, away from the
    // round ends, where a solid line would be uniformly black.
    var dark = 0, light = 0, total = 0;
    for (var y = 20 - radius.toInt() + 1; y < 20 + radius.toInt(); y++) {
      for (var x = 40; x < 160; x++) {
        final v = _red(bytes, x, y);
        total++;
        if (v < 80) dark++;
        if (v > 200) light++;
      }
    }

    expect(dark, greaterThan(total * 0.05), reason: 'graphite must be visible');
    expect(light, greaterThan(total * 0.05), reason: 'paper must show through');
    // A solid stroke would be >95% dark; pencil leaves a real mix.
    expect(dark, lessThan(total * 0.7));
  });

  test('nothing is painted far from the stroke', () async {
    final bytes = await _render([_horizontal(1)]);

    for (var x = 0; x < _width; x++) {
      expect(_red(bytes, x, 2), 255, reason: 'row 2, x=$x');
      expect(_red(bytes, x, _height - 3), 255, reason: 'row 37, x=$x');
    }
    expect(_red(bytes, 3, 20), 255);
    expect(_red(bytes, _width - 4, 20), 255);
  });

  test('lighter pressure marks fewer pixels than full pressure', () async {
    int inked(ByteData bytes) {
      var n = 0;
      for (var y = 0; y < _height; y++) {
        for (var x = 0; x < _width; x++) {
          if (_red(bytes, x, y) < 200) n++;
        }
      }
      return n;
    }

    final light = inked(await _render([_horizontal(0.2)]));
    final full = inked(await _render([_horizontal(1)]));

    expect(light, greaterThan(0));
    expect(light, lessThan(full));
  });

  test('committing a stroke does not change its grain', () async {
    final stroke = _horizontal(1);
    final renderer = PencilRenderer();
    addTearDown(renderer.dispose);

    // Draw it as the in-progress stroke, then as the committed stroke, with the
    // same renderer, as CanvasView does on pointer-up.
    final drawing = await _renderWith(
      renderer,
      const [],
      active: stroke.points,
    );
    final committed = await _renderWith(renderer, [stroke]);

    expect(
      committed.buffer.asUint8List(),
      drawing.buffer.asUint8List(),
      reason: 'grain must not visibly re-roll on pointer-up',
    );
  });
}
