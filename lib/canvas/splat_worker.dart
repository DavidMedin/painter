import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'canvas_controller.dart';
import 'pencil_splats.dart';

/// Splat buffers for one stroke, ready for `drawRawAtlas`.
///
/// Splats are document-space and independent of zoom, so one [StrokeSplats]
/// serves every tile and level of detail the stroke touches.
class StrokeSplats {
  const StrokeSplats(this.count, this.transforms, this.colors);

  final int count;
  final Float32List transforms;
  final Int32List colors;
}

/// Generates [StrokeSplats] off the UI isolate.
///
/// Splat generation is CPU-bound pure Dart, so it runs in one long-lived
/// worker isolate. Stroke points go in as a flat `Float64List` and the result
/// comes back as [TransferableTypedData], so neither direction copies per-point
/// objects.
class SplatWorker {
  SplatWorker();

  Isolate? _isolate;
  SendPort? _commands;
  ReceivePort? _replies;
  Completer<void>? _starting;
  final Map<int, Completer<StrokeSplats>> _pending = {};
  int _nextRequest = 0;
  bool _disposed = false;

  /// Generates splats for [stroke]. Completes with an error if the worker is
  /// disposed first.
  Future<StrokeSplats> generate(CanvasStroke stroke) async {
    await _ensureStarted();
    if (_disposed) throw StateError('SplatWorker disposed');
    final id = _nextRequest++;
    final completer = Completer<StrokeSplats>();
    _pending[id] = completer;
    _commands!.send(<Object>[id, stroke.seed, _flatten(stroke.points)]);
    return completer.future;
  }

  Future<void> _ensureStarted() {
    if (_commands != null) return Future.value();
    final starting = _starting;
    if (starting != null) return starting.future;
    final completer = _starting = Completer<void>();
    final replies = _replies = ReceivePort();
    Isolate.spawn(_workerMain, replies.sendPort).then((isolate) {
      if (_disposed) {
        isolate.kill(priority: Isolate.immediate);
        completer.complete();
        return;
      }
      _isolate = isolate;
    }, onError: completer.completeError);
    replies.listen((Object? message) {
      if (message is SendPort) {
        _commands = message;
        completer.complete();
        return;
      }
      final reply = message! as List<Object?>;
      final request = _pending.remove(reply[0]! as int);
      if (request == null) return;
      final count = reply[1]! as int;
      request.complete(
        StrokeSplats(
          count,
          (reply[2]! as TransferableTypedData).materialize().asFloat32List(),
          (reply[3]! as TransferableTypedData).materialize().asInt32List(),
        ),
      );
    });
    return completer.future;
  }

  static Float64List _flatten(List<CanvasPoint> points) {
    final flat = Float64List(points.length * 3);
    for (var i = 0; i < points.length; i++) {
      flat[i * 3] = points[i].position.dx;
      flat[i * 3 + 1] = points[i].position.dy;
      flat[i * 3 + 2] = points[i].weight;
    }
    return flat;
  }

  void dispose() {
    _disposed = true;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _replies?.close();
    _replies = null;
    for (final request in _pending.values) {
      request.completeError(StateError('SplatWorker disposed'));
    }
    _pending.clear();
  }
}

void _workerMain(SendPort replies) {
  final commands = ReceivePort();
  replies.send(commands.sendPort);
  commands.listen((Object? message) {
    final request = message! as List<Object?>;
    final flat = request[2]! as Float64List;
    final points = <CanvasPoint>[
      for (var i = 0; i < flat.length; i += 3)
        CanvasPoint(
          position: Offset(flat[i], flat[i + 1]),
          weight: flat[i + 2],
        ),
    ];
    final batch = PencilSplats.build(points, strokeSeed: request[1]! as int);
    replies.send(<Object>[
      request[0]!,
      batch.count,
      TransferableTypedData.fromList([batch.transforms]),
      TransferableTypedData.fromList([batch.colors]),
    ]);
  });
}
