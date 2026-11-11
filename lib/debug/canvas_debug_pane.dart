// What: The debug pane widget (CanvasDebugPane) and its private snapshot type
//   (`_Reading`). It lays out the tile-cache readouts and controls using the
//   imgui kit and produces the plain-text report. This file also holds the
//   debug-pane system overview (below).
// Why: design/diagnostics/debug-pane.md wanted the tile cache's private,
// asynchronous state visible
//   in the running app. The pane is the only consumer of the core's
//   diagnostic counters (../canvas/tile_stats.dart) and is separate from them
//   so the core never imports debug UI. Layout primitives are in imgui.dart,
//   overlay painting in tile_overlay.dart, and shared switches in
//   canvas_debug_options.dart.
//
// ---------------------------------------------------------------------------
// OVERVIEW: the debug pane
// ---------------------------------------------------------------------------
// What it is: a docked tool pane, shown when a pane's content selector chooses
//   Diagnostics. It shows
//   how the tiled texture cache (design/canvas/tile-cache.md) is behaving:
//   which level of detail is drawn, how every visible tile was drawn (current,
//   stale, coarser/finer fallback, missing, blank), cache occupancy, build
//   queue, counters, splat memory, and viewport. It also has overlays drawn
//   inside the canvas and a few controls.
//
// Why it exists: the cache is asynchronous and keeps most state private, so
//   its claims (a stale tile stays visible, a coarser level shows scaled
//   until the right one lands, only touched tiles rebuild) could be checked
//   only with pixel tests. The pane makes them visible in a running app,
//   allows tuning maxInFlight / maxTiles, and gives a text report for bug
//   reports (design/diagnostics/debug-pane.md, Context).
//
// The boundary rule (data flows one way):
//   - TileCache, TiledRenderer, and tile statistics only record diagnostic
//     data; core files do not import this pane. CanvasView imports only the
//     overlay painter and option switches needed to display diagnostics.
//   - The pane reads the shared document and renderer, resets only the supplied
//     CanvasViewportController, and edits cache limits/invalidation and
//     CanvasDebugOptions switches.
//
// How it works:
//   - A Timer (default every 250 ms, not per canvas frame) builds one
//     `_Reading`, an immutable copy of every value the pane shows, and calls
//     setState. Every readout and the text report come from that one object,
//     so they cannot disagree, and a fast-changing counter cannot make two
//     rows inconsistent.
//   - Pause: while CanvasDebugOptions.paused is set, the timer tick skips
//     replacing the reading. Because every readout reads only from it, they all
//     freeze together, which lets you inspect a transient state such as a
//     fallback frame. Pausing does not affect the canvas or the overlays,
//     which read the live TiledRenderer.frame. Pane actions (sliders, buttons,
//     Copy report) take a new reading anyway.
//   - Report: `_Reading.report()` formats the same snapshot as plain text;
//     the "Copy report" button refreshes, then sends it to the clipboard with
//     imCopy.
//   - Overlays: the pane only flips CanvasDebugOptions switches. The canvas
//     (CanvasView's painter) calls paintTileOverlay inside the document
//     transform. Both the overlay tint and the pane's legend/rows take their
//     colors from tileDrawColor in tile_overlay.dart.
//   - Cost: the core keeps its counters at all times; while a diagnostics pane
//     is visible, one snapshot and widget rebuild occur per timer tick.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../canvas/canvas_controller.dart';
import '../canvas/pencil_splats.dart';
import '../canvas/tile_grid.dart';
import '../canvas/tile_stats.dart';
import '../canvas/tiled_renderer.dart';
import '../help/contextual_help.dart';
import '../settings/painter_settings.dart';
import 'canvas_debug_options.dart';
import 'imgui.dart';
import 'tile_overlay.dart';

/// Bytes one cached tile texture occupies, assuming RGBA8 (4 bytes per
/// pixel): `TileGrid.texturePixels` squared times 4. Used for the "texture
/// memory" row and the report line. It is an estimate computed from the tile
/// size, not a measurement of GPU allocation.
const int _tileBytes = TileGrid.texturePixels * TileGrid.texturePixels * 4;

/// The docked tool pane shows tile-cache internals and exposes a few controls.
/// It reads [renderer], [controller], and this pane's [viewport], edits
/// [options] and cache limits, and owns no state the app depends on.
///
/// Readouts refresh on a short timer rather than on every canvas frame so the
/// pane costs almost nothing while you draw, and freeze while
/// [CanvasDebugOptions.paused] is set (actions the user takes in the pane
/// itself still refresh it; see `_refreshNow`).
///
/// Constructed by lib/main.dart for a Diagnostics pane when the app shell has
/// a renderer from a Canvas pane; the system overview is at the top of this
/// file.
class CanvasDebugPane extends StatefulWidget {
  const CanvasDebugPane({
    super.key,
    required this.renderer,
    required this.controller,
    required this.viewport,
    required this.options,
    this.refresh = const Duration(milliseconds: 250),
  });

  final TiledRenderer renderer;
  final CanvasController controller;
  final CanvasViewportController viewport;
  final CanvasDebugOptions options;
  final Duration refresh;

  @override
  State<CanvasDebugPane> createState() => _CanvasDebugPaneState();
}

class _CanvasDebugPaneState extends State<CanvasDebugPane> {
  Timer? _timer;
  late _Reading _reading = _Reading.of(
    widget.renderer,
    widget.controller,
    widget.viewport,
  );

  /// Status line shown under the buttons after a copy; never cleared while the
  /// pane stays open.
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

  /// Rebuilds when any [CanvasDebugOptions] switch changes (for example the
  /// pause checkbox, or an overlay checkbox) so the checkboxes reflect it.
  void _onOptions() {
    if (mounted) setState(() {});
  }

  /// Timer callback: replaces the snapshot unless the pane is paused (the
  /// timer keeps running while paused; it just skips). This is the only place
  /// the snapshot advances on its own.
  void _tick() {
    if (!mounted || widget.options.paused) return;
    setState(
      () => _reading = _Reading.of(
        widget.renderer,
        widget.controller,
        widget.viewport,
      ),
    );
  }

  /// Takes a reading immediately, ignoring [CanvasDebugOptions.paused]. Called
  /// after every write the pane makes to the core or the controller
  /// (`resetViewport`, `maxInFlight`, `maxTiles`, `invalidateAll`) so the
  /// effect is shown at once rather than at the next timer tick, and by
  /// [_copyReport].
  void _refreshNow() => setState(
    () => _reading = _Reading.of(
      widget.renderer,
      widget.controller,
      widget.viewport,
    ),
  );

  /// Takes a fresh reading, then copies its text report. The refresh happens
  /// first so the clipboard text and the numbers on screen are the same
  /// reading; this also updates the display when readouts are paused.
  Future<void> _copyReport() async {
    _refreshNow();
    await imCopy(_reading.report());
    if (mounted) setState(() => _notice = 'Report copied to clipboard');
  }

  /// One readout section per source of data; each section's comment names the
  /// members it reads. Everything in the readouts comes from `_reading`, the
  /// frozen snapshot; only the slider values and the checkbox values are read
  /// live from `cache` / `options` because they are inputs the user is
  /// editing.
  @override
  Widget build(BuildContext context) {
    final r = _reading;
    final cache = widget.renderer.cache;
    final options = widget.options;
    final theme = Theme.of(context);
    final themeColors =
        theme.extension<PainterThemeColors>() ??
        PainterThemeColors.fromColorScheme(theme.colorScheme);
    return DecoratedBox(
      decoration: BoxDecoration(color: ImTheme.windowBg(context)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(ImTheme.padding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ImText('Tile cache diagnostics', color: ImTheme.text(context)),
            // Frame: TileFrameStats level, recordMillis, activeSplats, and the
            // TiledRenderer.recordHistory plot. `record time` is UI-thread time
            // spent recording draw calls, not raster or GPU time
            // (design/diagnostics/debug-pane.md).
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
                  color: _budget(
                    r.frame.recordMillis,
                    theme.colorScheme,
                    themeColors,
                  ),
                ),
                ImValue('active chunk splats', '${r.frame.activeSplats}'),
                ImPlot(
                  label: 'record ms',
                  samples: r.recordHistory,
                  unit: 'ms',
                ),
              ],
            ),
            // Viewport: the selected Canvas pane's zoom/rotation/pan plus the
            // size of TileFrameStats.visibleRect.
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
                  icon: Icons.center_focus_strong,
                  label: 'Reset view',
                  topic: HelpIds.resetView,
                  onPressed: () {
                    widget.viewport.resetViewport();
                    _refreshNow();
                  },
                ),
              ],
            ),
            // Visible tiles: how the last frame drew each visible tile. Counts
            // are TileFrameStats.visible and the per-state totals (drawnCurrent,
            // drawnStale, fallbackCoarser, fallbackFiner, missing, blank), via
            // [_Reading.draws]. The bar and rows take color and name from
            // tileDrawColor / tileDrawName (tile_overlay.dart), the same
            // functions the canvas overlay uses.
            ImSection(
              title: 'Visible tiles',
              children: [
                ImValue('visible', '${r.frame.visible}'),
                ImStackedBar(
                  segments: [
                    for (final d in TileDraw.values)
                      ImSegment(
                        r.drawCount(d).toDouble(),
                        tileDrawColor(d, theme.colorScheme, themeColors),
                        tileDrawName(d),
                      ),
                  ],
                ),
                for (final d in TileDraw.values)
                  ImValue(
                    tileDrawName(d),
                    '${r.drawCount(d)}',
                    color: tileDrawColor(d, theme.colorScheme, themeColors),
                  ),
              ],
            ),
            // Tile cache: TileCache getters cachedTiles, imageTiles, wantedTiles,
            // building, queued, idle, plus maxTiles/maxInFlight and the
            // TileCacheCounters fields. "cached tiles" can exceed its maxTiles
            // denominator: maxTiles is a floor of the eviction budget, not a hard
            // cap (see TileCache.maxTiles). "texture memory" is imageTiles times
            // _tileBytes (tiles without an image take no texture). `buildHistory`
            // is TileCacheCounters.buildMillis, which excludes skipped builds.
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
                  color: r.building > 0 ? ImTheme.warn(context) : null,
                ),
                ImValue(
                  'queued',
                  '${r.queued}',
                  color: r.queued > 0 ? ImTheme.warn(context) : null,
                ),
                ImValue(
                  'idle',
                  r.idle ? 'yes' : 'no',
                  color: r.idle ? ImTheme.good(context) : ImTheme.warn(context),
                ),
                ImSeparator(),
                ImValue('requests', '${r.counters.requests}'),
                ImValue('dropped from queue', '${r.counters.droppedFromQueue}'),
                ImValue('builds', '${r.counters.builds}'),
                ImValue('  full', '${r.counters.fullBuilds}'),
                ImValue('  incremental', '${r.counters.incrementalBuilds}'),
                ImValue('  skipped (no ink)', '${r.counters.skippedBuilds}'),
                ImPlot(
                  label: 'tile build',
                  samples: r.buildHistory,
                  unit: 'ms',
                ),
              ],
            ),
            // Document and splats: strokes/points from the document; the rest are
            // TileCache.generatedStrokes / splatBytes and the splatsGenerated /
            // splatsRastered counters. The last row prints the two PencilSplats
            // constants (splatsPerSample / sampleSpacing).
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
            // Overlays: writes CanvasDebugOptions switches; the canvas paints
            // them via paintTileOverlay (tile_overlay.dart). The legend uses the
            // same tileDrawColor/tileDrawName as that overlay.
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
                      (
                        tileDrawColor(d, theme.colorScheme, themeColors),
                        tileDrawName(d),
                      ),
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
            // Controls: the only section that writes to the core. The sliders
            // read the live `cache.maxInFlight` / `cache.maxTiles`, not the
            // snapshot, so the thumb follows the pointer at once; the "Tile
            // cache" readout rows come from the snapshot. Lowering `maxTiles`
            // evicts on the next completed build, not instantly
            // (design/diagnostics/debug-pane.md). `invalidateAll()` drops all
            // tiles and splats but keeps the document; the canvas rebuilds them
            // on the next frame.
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
                  icon: Icons.refresh,
                  label: 'Discard all tiles (rebuild)',
                  topic: HelpIds.rebuildTiles,
                  onPressed: () {
                    cache.invalidateAll();
                    _refreshNow();
                  },
                ),
                ImButton(
                  icon: Icons.copy_all,
                  label: 'Copy report',
                  topic: HelpIds.copyReport,
                  onPressed: _copyReport,
                ),
                if (_notice != null)
                  ImText(_notice!, color: ImTheme.good(context)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Color for the frame record time: red above 8 ms, yellow above 2 ms,
  /// default otherwise. The thresholds are fixed constants in this method;
  /// the repo does not say how they were chosen.
  Color? _budget(
    double ms,
    ColorScheme scheme,
    PainterThemeColors themeColors,
  ) => ms > 8
      ? scheme.error
      : ms > 2
      ? themeColors.warning
      : null;
}

/// Formats a byte count as B, KiB, or MiB (binary units, one decimal). Used
/// for the texture and splat memory rows and by [_Reading.report].
String _bytes(int n) {
  if (n < 1024) return '$n B';
  if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KiB';
  return '${(n / (1024 * 1024)).toStringAsFixed(1)} MiB';
}

/// An immutable copy of everything the pane shows, taken at one instant, so a
/// paused pane and the copied report agree. Created by [_Reading.of]; the
/// widget replaces its whole `_reading` on each refresh and never edits one.
/// See the overview at the top of this file for why one snapshot is used.
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

  /// Takes the snapshot: copies every field of `renderer.frame`
  /// (TileFrameStats) and `renderer.cache.counters` (TileCacheCounters) into
  /// fresh objects, copies the two history queues into lists, and reads the
  /// TileCache and CanvasController getters once, plus the selected pane's
  /// viewport values.
  ///
  /// Coupled to those core classes (lib/canvas/tile_stats.dart): the copies
  /// are written field by field, so a field added to TileFrameStats or
  /// TileCacheCounters must also be copied here or the pane will silently show
  /// zero for it. `TileFrameStats.draws` is deliberately not copied; the
  /// [draws] map of per-state counts is rebuilt from the copied counters.
  factory _Reading.of(
    TiledRenderer renderer,
    CanvasController controller,
    CanvasViewportController viewport,
  ) {
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
    // Counts every point of every stroke on each refresh, so this costs time
    // proportional to document size (design/diagnostics/debug-pane.md notes behavior with
    // very large documents was not verified).
    var points = 0;
    for (final s in controller.document.strokes) {
      points += s.points.length;
    }
    // Cache-side numbers: plain getters on TileCache, read in one go so they
    // describe the same instant as the copies above.
    return _Reading(
      frame: copy,
      counters: snapshot,
      zoom: viewport.zoom,
      rotation: viewport.rotation,
      pan: viewport.pan,
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

  // `frame` and `counters` hold only the scalar fields copied in
  // [_Reading.of]. `frame.draws` (the per-tile map) and `counters.buildMillis`
  // are left empty here: per-state totals are in [draws] and the build-time
  // samples are in [buildHistory]. The in-canvas overlay uses the live
  // `TiledRenderer.frame.draws`, not this snapshot.
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

  /// Number of visible tiles drawn in state [d] (0 when absent).
  int drawCount(TileDraw d) => draws[d] ?? 0;

  /// Pixels per document unit at the frame's level (`TileGrid.scaleOf`), as
  /// text for the "level of detail" row.
  String get scale => TileGrid.scaleOf(frame.level).toString();

  /// Plain-text dump for bug reports, copied to the clipboard by
  /// `_CanvasDebugPaneState._copyReport`.
  ///
  /// Built only from this snapshot's fields, so it prints exactly the numbers
  /// the pane showed at the moment of the reading. Lines, in order: viewport,
  /// frame (level, visible count, record time, active splats) followed by one
  /// indented line per [TileDraw] state, cache, counters, splats, document.
  /// The two history plots are not included. Labels mirror the pane's rows.
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
