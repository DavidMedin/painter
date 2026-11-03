import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../canvas/canvas_controller.dart';
import '../canvas/pencil_splats.dart';
import '../canvas/tile_grid.dart';
import '../canvas/tile_stats.dart';
import '../canvas/tiled_renderer.dart';
import 'canvas_debug_options.dart';
import 'imgui.dart';
import 'tile_overlay.dart';

/// Bytes one cached tile texture occupies (RGBA8).
const int _tileBytes = TileGrid.texturePixels * TileGrid.texturePixels * 4;

/// The tool window that shows the tile cache's internals and exposes a few
/// controls. Pure presentation: it reads [renderer] and [controller] and edits
/// [options] and the cache's limits; it has no state the app depends on.
///
/// Readouts refresh on a short timer rather than on every canvas frame so the
/// pane costs almost nothing while you draw, and freeze while
/// [CanvasDebugOptions.paused] is set.
class CanvasDebugPane extends StatefulWidget {
  const CanvasDebugPane({
    super.key,
    required this.renderer,
    required this.controller,
    required this.options,
    this.onClose,
    this.refresh = const Duration(milliseconds: 250),
  });

  final TiledRenderer renderer;
  final CanvasController controller;
  final CanvasDebugOptions options;
  final VoidCallback? onClose;
  final Duration refresh;

  @override
  State<CanvasDebugPane> createState() => _CanvasDebugPaneState();
}

class _CanvasDebugPaneState extends State<CanvasDebugPane> {
  Timer? _timer;
  late _Reading _reading = _Reading.of(widget.renderer, widget.controller);
  String? _notice;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.refresh, (_) => _tick());
    widget.options.addListener(_onOptions);
  }

  @override
  void didUpdateWidget(CanvasDebugPane old) {
    super.didUpdateWidget(old);
    if (old.options != widget.options) {
      old.options.removeListener(_onOptions);
      widget.options.addListener(_onOptions);
    }
    if (old.refresh != widget.refresh) {
      _timer?.cancel();
      _timer = Timer.periodic(widget.refresh, (_) => _tick());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.options.removeListener(_onOptions);
    super.dispose();
  }

  void _onOptions() {
    if (mounted) setState(() {});
  }

  void _tick() {
    if (!mounted || widget.options.paused) return;
    setState(() => _reading = _Reading.of(widget.renderer, widget.controller));
  }

  void _refreshNow() => setState(
    () => _reading = _Reading.of(widget.renderer, widget.controller),
  );

  Future<void> _copyReport() async {
    _refreshNow();
    await imCopy(_reading.report());
    if (mounted) setState(() => _notice = 'Report copied to clipboard');
  }

  @override
  Widget build(BuildContext context) {
    final r = _reading;
    final cache = widget.renderer.cache;
    final options = widget.options;
    return ImWindow(
      title: 'Painter debug  [F3]',
      initialOffset: const Offset(12, 12),
      width: 340,
      onClose: widget.onClose,
      children: [
        ImSection(
          title: 'Frame',
          children: [
            ImValue(
              'level of detail',
              'L${r.frame.level}  (${r.scale} px/unit)',
            ),
            ImValue(
              'record time',
              '${r.frame.recordMillis.toStringAsFixed(3)} ms',
              color: _budget(r.frame.recordMillis),
            ),
            ImValue('active stroke splats', '${r.frame.activeSplats}'),
            ImPlot(label: 'record ms', samples: r.recordHistory, unit: 'ms'),
          ],
        ),
        ImSection(
          title: 'Viewport',
          children: [
            ImValue('zoom', r.zoom.toStringAsFixed(3)),
            ImValue(
              'rotation',
              '${(r.rotation * 180 / math.pi).toStringAsFixed(1)}\u00B0',
            ),
            ImValue(
              'pan',
              '${r.pan.dx.toStringAsFixed(1)}, ${r.pan.dy.toStringAsFixed(1)}',
            ),
            ImValue(
              'visible (doc units)',
              '${r.frame.visibleRect.width.toStringAsFixed(0)} x '
                  '${r.frame.visibleRect.height.toStringAsFixed(0)}',
            ),
            ImButton(
              label: 'Reset view',
              onPressed: () {
                widget.controller.resetViewport();
                _refreshNow();
              },
            ),
          ],
        ),
        ImSection(
          title: 'Visible tiles',
          children: [
            ImValue('visible', '${r.frame.visible}'),
            ImStackedBar(
              segments: [
                for (final d in TileDraw.values)
                  ImSegment(
                    r.drawCount(d).toDouble(),
                    tileDrawColor(d),
                    tileDrawName(d),
                  ),
              ],
            ),
            for (final d in TileDraw.values)
              ImValue(
                tileDrawName(d),
                '${r.drawCount(d)}',
                color: tileDrawColor(d),
              ),
          ],
        ),
        ImSection(
          title: 'Tile cache',
          children: [
            ImValue('cached tiles', '${r.cached} / ${r.maxTiles}'),
            ImValue('with image', '${r.imageTiles}'),
            ImValue('texture memory', _bytes(r.imageTiles * _tileBytes)),
            ImValue('working set', '${r.wanted}'),
            ImValue('evictions', '${r.counters.evictions}'),
            ImSeparator(),
            ImValue(
              'building',
              '${r.building} / ${r.maxInFlight}',
              color: r.building > 0 ? ImTheme.warn : null,
            ),
            ImValue(
              'queued',
              '${r.queued}',
              color: r.queued > 0 ? ImTheme.warn : null,
            ),
            ImValue(
              'idle',
              r.idle ? 'yes' : 'no',
              color: r.idle ? ImTheme.good : ImTheme.warn,
            ),
            ImSeparator(),
            ImValue('requests', '${r.counters.requests}'),
            ImValue('dropped from queue', '${r.counters.droppedFromQueue}'),
            ImValue('builds', '${r.counters.builds}'),
            ImValue('  full', '${r.counters.fullBuilds}'),
            ImValue('  incremental', '${r.counters.incrementalBuilds}'),
            ImValue('  skipped (no ink)', '${r.counters.skippedBuilds}'),
            ImPlot(label: 'tile build', samples: r.buildHistory, unit: 'ms'),
          ],
        ),
        ImSection(
          title: 'Document and splats',
          initiallyOpen: false,
          children: [
            ImValue('strokes', '${r.strokes}'),
            ImValue('points', '${r.points}'),
            ImValue('strokes with splats', '${r.generatedStrokes}'),
            ImValue('splats generated', '${r.counters.splatsGenerated}'),
            ImValue('splats rastered', '${r.counters.splatsRastered}'),
            ImValue('splat memory', _bytes(r.splatBytes)),
            ImValue(
              'splats / unit of stroke',
              '${PencilSplats.splatsPerSample} / ${PencilSplats.sampleSpacing}',
            ),
          ],
        ),
        ImSection(
          title: 'Overlays',
          children: [
            ImCheckbox(
              label: 'tile state tint',
              value: options.showTileState,
              onChanged: (v) => options.showTileState = v,
            ),
            if (options.showTileState)
              ImLegend([
                for (final d in TileDraw.values)
                  (tileDrawColor(d), tileDrawName(d)),
              ]),
            ImCheckbox(
              label: 'tile grid',
              value: options.showTileGrid,
              onChanged: (v) => options.showTileGrid = v,
            ),
            ImCheckbox(
              label: 'tile coordinates',
              value: options.showCoordinates,
              onChanged: (v) => options.showCoordinates = v,
            ),
            ImCheckbox(
              label: 'visible rectangle',
              value: options.showVisibleRect,
              onChanged: (v) => options.showVisibleRect = v,
            ),
          ],
        ),
        ImSection(
          title: 'Controls',
          children: [
            ImSliderInt(
              label: 'max in flight',
              value: cache.maxInFlight,
              min: 1,
              max: 8,
              onChanged: (v) {
                cache.maxInFlight = v;
                _refreshNow();
              },
            ),
            ImSliderInt(
              label: 'max tiles',
              value: cache.maxTiles,
              min: 16,
              max: 1024,
              onChanged: (v) {
                cache.maxTiles = v;
                _refreshNow();
              },
            ),
            ImCheckbox(
              label: 'pause readouts',
              value: options.paused,
              onChanged: (v) => options.paused = v,
            ),
            ImButton(
              label: 'Discard all tiles (rebuild)',
              onPressed: () {
                cache.invalidateAll();
                _refreshNow();
              },
            ),
            ImButton(label: 'Copy report', onPressed: _copyReport),
            if (_notice != null) ImText(_notice!, color: ImTheme.good),
          ],
        ),
        ImText('double-click title to collapse', dim: true),
      ],
    );
  }

  Color? _budget(double ms) => ms > 8
      ? ImTheme.bad
      : ms > 2
      ? ImTheme.warn
      : null;
}

String _bytes(int n) {
  if (n < 1024) return '$n B';
  if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KiB';
  return '${(n / (1024 * 1024)).toStringAsFixed(1)} MiB';
}

/// An immutable copy of everything the pane shows, taken at one instant, so a
/// paused pane and the copied report agree.
class _Reading {
  _Reading({
    required this.frame,
    required this.counters,
    required this.zoom,
    required this.rotation,
    required this.pan,
    required this.imageTiles,
    required this.strokes,
    required this.points,
    required this.cached,
    required this.maxTiles,
    required this.building,
    required this.queued,
    required this.maxInFlight,
    required this.wanted,
    required this.splatBytes,
    required this.generatedStrokes,
    required this.idle,
    required this.recordHistory,
    required this.buildHistory,
    required this.draws,
  });

  factory _Reading.of(TiledRenderer renderer, CanvasController controller) {
    final cache = renderer.cache;
    final f = renderer.frame;
    final copy = TileFrameStats()
      ..level = f.level
      ..visible = f.visible
      ..drawnCurrent = f.drawnCurrent
      ..drawnStale = f.drawnStale
      ..fallbackCoarser = f.fallbackCoarser
      ..fallbackFiner = f.fallbackFiner
      ..missing = f.missing
      ..blank = f.blank
      ..activeSplats = f.activeSplats
      ..recordMillis = f.recordMillis
      ..visibleRect = f.visibleRect;
    final c = cache.counters;
    final snapshot = TileCacheCounters()
      ..requests = c.requests
      ..builds = c.builds
      ..fullBuilds = c.fullBuilds
      ..incrementalBuilds = c.incrementalBuilds
      ..skippedBuilds = c.skippedBuilds
      ..evictions = c.evictions
      ..droppedFromQueue = c.droppedFromQueue
      ..splatsGenerated = c.splatsGenerated
      ..splatsRastered = c.splatsRastered;
    var points = 0;
    for (final s in controller.document.strokes) {
      points += s.points.length;
    }
    return _Reading(
      frame: copy,
      counters: snapshot,
      zoom: controller.zoom,
      rotation: controller.rotation,
      pan: controller.pan,
      imageTiles: cache.imageTiles,
      strokes: controller.document.strokeCount,
      points: points,
      cached: cache.cachedTiles,
      maxTiles: cache.maxTiles,
      building: cache.building,
      queued: cache.queued,
      maxInFlight: cache.maxInFlight,
      wanted: cache.wantedTiles,
      splatBytes: cache.splatBytes,
      generatedStrokes: cache.generatedStrokes,
      idle: cache.idle,
      recordHistory: List.of(renderer.recordHistory),
      buildHistory: List.of(cache.counters.buildMillis),
      draws: {
        TileDraw.current: f.drawnCurrent,
        TileDraw.stale: f.drawnStale,
        TileDraw.coarser: f.fallbackCoarser,
        TileDraw.finer: f.fallbackFiner,
        TileDraw.missing: f.missing,
        TileDraw.blank: f.blank,
      },
    );
  }

  final TileFrameStats frame;
  final TileCacheCounters counters;
  final double zoom;
  final double rotation;
  final Offset pan;
  final int imageTiles;
  final int strokes;
  final int points;
  final int cached;
  final int maxTiles;
  final int building;
  final int queued;
  final int maxInFlight;
  final int wanted;
  final int splatBytes;
  final int generatedStrokes;
  final bool idle;
  final List<double> recordHistory;
  final List<double> buildHistory;
  final Map<TileDraw, int> draws;

  int drawCount(TileDraw d) => draws[d] ?? 0;

  String get scale => TileGrid.scaleOf(frame.level).toString();

  /// Plain-text dump for bug reports.
  String report() {
    final b = StringBuffer()
      ..writeln('painter tile cache report')
      ..writeln(
        'viewport: zoom=${zoom.toStringAsFixed(3)} '
        'rotation=${rotation.toStringAsFixed(3)}rad '
        'pan=${pan.dx.toStringAsFixed(1)},${pan.dy.toStringAsFixed(1)}',
      )
      ..writeln(
        'frame: level=L${frame.level} visible=${frame.visible} '
        'record=${frame.recordMillis.toStringAsFixed(3)}ms '
        'activeSplats=${frame.activeSplats}',
      );
    for (final d in TileDraw.values) {
      b.writeln('  ${tileDrawName(d)}: ${drawCount(d)}');
    }
    b
      ..writeln(
        'cache: cached=$cached/$maxTiles images=$imageTiles '
        '(${_bytes(imageTiles * _tileBytes)}) wanted=$wanted '
        'building=$building/$maxInFlight queued=$queued',
      )
      ..writeln(
        'counters: requests=${counters.requests} '
        'dropped=${counters.droppedFromQueue} builds=${counters.builds} '
        '(full=${counters.fullBuilds} incremental=${counters.incrementalBuilds} '
        'skipped=${counters.skippedBuilds}) evictions=${counters.evictions}',
      )
      ..writeln(
        'splats: generated=${counters.splatsGenerated} '
        'rastered=${counters.splatsRastered} memory=${_bytes(splatBytes)}',
      )
      ..writeln('document: strokes=$strokes points=$points');
    return b.toString();
  }
}
