// What: `SplatWorker`, a lazily started long-lived background isolate that
// runs `PencilSplats.build` for committed strokes, and `StrokeSplats`, the
// buffers it returns.
//
// Why: Generating splats (about 13 per document unit of stroke) is CPU-bound
// pure Dart; doing it on the UI isolate would stall frames while tiles are
// built (design/canvas/tile-cache.md). Keeping the isolate plumbing (ports,
// request ids, message layout) in this one file leaves pencil_splats.dart free
// of any isolate code, so generation stays unit-testable on its own. See the
// overview in pencil_splats.dart for the splat system; the only consumer is
// `TileCache` (tile_cache.dart), which owns and disposes a worker.

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'canvas_controller.dart';
import 'pencil_splats.dart';

// Message protocol between `SplatWorker` (UI isolate) and `_workerMain`:
//   handshake: worker sends a SendPort for commands.
//   request:   [id, stroke seed, Float64List of x, y, weight per point]
//   success:   [id, 'ok', splat count, transforms, colors]
//   failure:   [id, 'error', message, stack trace]
// Replies are matched to requests by id through `_pending`, so they need not
// arrive in order.

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
///
/// Owned by `TileCache`, which calls [generate] from `TileCache._splatsFor` and
/// caches the results per stroke index; [dispose] is called from
/// `TileCache.dispose`. The isolate is started on the first [generate], not on
/// construction. The worker handles one request at a time, so callers start
/// several [generate] calls first and await them afterward to keep it busy
/// (see `TileCache._build`).
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

  /// Spawns the isolate once and completes when its command port has arrived.
  /// Concurrent callers share the same startup via [_starting]. If [dispose]
  /// ran while the isolate was still spawning, the new isolate is killed
  /// immediately and [generate] then fails with a [StateError].
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
      if (reply[1] == 'error') {
        request.completeError(
          Exception('Splat worker failed: ${reply[2]}'),
          StackTrace.fromString(reply[3]! as String),
        );
        return;
      }
      final count = reply[2]! as int;
      request.complete(
        StrokeSplats(
          count,
          (reply[3]! as TransferableTypedData).materialize().asFloat32List(),
          (reply[4]! as TransferableTypedData).materialize().asInt32List(),
        ),
      );
    });
    return completer.future;
  }

  /// Packs points as `x, y, weight` triples, the layout `_workerMain` unpacks.
  /// The two must be kept in sync.
  static Float64List _flatten(List<CanvasPoint> points) {
    final flat = Float64List(points.length * 3);
    for (var i = 0; i < points.length; i++) {
      flat[i * 3] = points[i].position.dx;
      flat[i * 3 + 1] = points[i].position.dy;
      flat[i * 3 + 2] = points[i].weight;
    }
    return flat;
  }

  /// Kills the isolate and fails every outstanding [generate] with a
  /// [StateError]. Safe to call before the isolate ever started.
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

/// Isolate entry point (must be top-level for `Isolate.spawn`). Rebuilds
/// `CanvasPoint`s from the flat request, runs `PencilSplats.build` with the
/// stroke's seed, and replies with the id, count and the two buffers as
/// [TransferableTypedData]. Unpacking must match `SplatWorker._flatten`.
void _workerMain(SendPort replies) {
  final commands = ReceivePort();
  replies.send(commands.sendPort);
  commands.listen((Object? message) {
    final request = message! as List<Object?>;
    try {
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
        'ok',
        batch.count,
        TransferableTypedData.fromList([batch.transforms]),
        TransferableTypedData.fromList([batch.colors]),
      ]);
    } catch (error, stackTrace) {
      replies.send(<Object>[
        request[0]!,
        'error',
        error.toString(),
        stackTrace.toString(),
      ]);
    }
  });
}
