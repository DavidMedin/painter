// What: `CanvasView`, the widget that turns mouse, stylus and trackpad
// pointer events into `CanvasController` calls, and `_CanvasPainter`, which
// draws the controller's document and viewport through a `TiledRenderer`.
//
// Why: Input handling and painting live here, apart from the state model
// (canvas_controller.dart) and the tile pipeline (tiled_renderer.dart,
// tile_cache.dart). The widget owns no document state; it is the only place
// that knows which button or gesture means "draw", "pan", "zoom" or "rotate",
// so changing controls (ADR 0001, ADR 0003) never touches the model or the
// renderer.

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../debug/canvas_debug_options.dart';
import '../debug/tile_overlay.dart';
import 'canvas_controller.dart';
import '../help/contextual_help.dart';
import '../settings/painter_settings.dart';
import 'tile_grid.dart';
import 'tiled_renderer.dart';

// ---------------------------------------------------------------------------
// Input handling (overview)
//
// What: One `Listener` (built in `_CanvasViewState.build`) receives raw Flutter
// pointer events and maps them to controller calls. Flutter pointer events are
// used directly, with no native input plugin (ADR 0001).
//
//   Mouse (PointerDeviceKind.mouse), chosen at pointer-down by
//   `_mouseInteraction` and fixed for the whole drag:
//     primary button drag    -> draw at weight 1.0   (beginStroke/extendStroke)
//     secondary button drag  -> pan                  (panBy)
//     middle button drag     -> rotate about pointer (rotateAt, dx / 100 rad)
//     vertical wheel         -> zoom about pointer   (zoomAt, exp(-dy / 500))
//   If several buttons are down at once, secondary wins over middle over
//   primary.
//   Stylus: always draws; weight comes from pressure (below).
//   Trackpad (PointerDeviceKind.trackpad, PointerPanZoom* events, ADR 0003):
//     two-finger scroll -> pan   (event.panDelta)
//     pinch             -> zoom  (cumulative event.scale -> incremental factor)
//     two-finger twist  -> rotate (cumulative event.rotation -> incremental)
//   Zoom and rotate are anchored at the gesture's focal point, recorded once
//   at `_onPanZoomStart` in `_TrackpadGesture`, so the gesture stays pinned
//   to where it began. The trackpad stream is separate from the mouse
//   down/move/signal stream and is additive to it. The rotation sign is taken
//   from Flutter unchanged; if it feels reversed on hardware, only the sign
//   in `_onPanZoomUpdate` needs to change (ADR 0003).
//   Other device kinds (e.g. touch) are ignored by `_onPointerDown`.
//
// Pressure -> weight (`_weightFor`): pressure is normalized with the event's
// pressureMin/pressureMax and mapped linearly to weight 0.05-1.0. These are
// prototype values (ADR 0001, docs/architecture.md "Prototype parameters"),
// not a resolved product mapping, and physical stylus behavior is unverified.
// Weight changes brush size only. `CanvasController._clampWeight` and
// `CanvasDocument.fromJson` use the same 0.05-1 range.
//
// Coordinate spaces: event.localPosition is in screen (widget-local) space.
// Strokes are stored in document space, so draw events go through
// `CanvasController.toDocument` (which needs the viewport size, hence
// `_viewportSize`). Pan is in screen pixels. Zoom and rotate use screen-space
// anchors and the controller adjusts pan to keep the anchored document point
// fixed. `_CanvasPainter.paint` applies the forward mapping to the canvas
// (pan, then centre, rotate, scale) and must stay in sync with
// `CanvasController.toScreen`/`toDocument`; both rotate and scale about the
// viewport centre.
//
// Painting: the painter repaints when the controller changes or when the tile
// cache finishes a tile (`renderer.cache` is a Listenable), so tiles arriving
// asynchronously need no widget rebuild. See tile_cache.dart for that system.
// ---------------------------------------------------------------------------

/// The painting surface: draws the controller's document and handles pointer
/// input as described in the overview above.
///
/// The state object owns one `TiledRenderer` (sprite, tile cache and
/// active-stroke stream) and disposes it with the view. [onRenderer] hands
/// that renderer to tools such as the debug pane (`_PainterAppState` in
/// main.dart).
class CanvasView extends StatefulWidget {
  const CanvasView({
    super.key,
    required this.controller,
    this.debugOptions,
    this.onRenderer,
  });

  final CanvasController controller;

  /// When set, the canvas draws the overlays these options enable.
  final CanvasDebugOptions? debugOptions;

  /// Called once with the renderer this view owns, so tools can read its tile
  /// cache and frame statistics. The renderer is disposed with the view.
  final ValueChanged<TiledRenderer>? onRenderer;

  @override
  State<CanvasView> createState() => _CanvasViewState();
}

/// What a pointer that went down is doing. Decided at pointer-down so a drag
/// keeps its meaning even if other buttons change mid-drag.
enum _Interaction { draw, pan, rotate }

/// Input state for [CanvasView]: per-pointer interaction modes, the active
/// trackpad gesture, and the renderer it owns.
class _CanvasViewState extends State<CanvasView> {
  final Map<int, _PointerInteraction> _interactions = {};
  _TrackpadGesture? _trackpadGesture;
  final GlobalKey _surfaceKey = GlobalKey();
  late final TiledRenderer _renderer = TiledRenderer();

  @override
  void initState() {
    super.initState();
    widget.onRenderer?.call(_renderer);
  }

  /// Size of the painting surface, read from the `Listener`'s render box via
  /// [_surfaceKey]. Needed because `CanvasController` transforms are about the
  /// viewport centre. `Size.zero` before the first layout.
  Size get _viewportSize {
    final renderObject = _surfaceKey.currentContext?.findRenderObject();
    return renderObject is RenderBox ? renderObject.size : Size.zero;
  }

  /// Starts an interaction for the pointer. Mouse buttons and stylus map to
  /// draw/pan/rotate; other device kinds are ignored. Drawing begins the
  /// controller's active stroke at the pointer's document-space position.
  void _onPointerDown(PointerDownEvent event) {
    final interaction = switch (event.kind) {
      PointerDeviceKind.mouse => _mouseInteraction(event.buttons),
      PointerDeviceKind.stylus => _Interaction.draw,
      _ => null,
    };
    if (interaction == null) return;

    _interactions[event.pointer] = _PointerInteraction(
      interaction,
      event.localPosition,
    );
    if (interaction == _Interaction.draw) {
      widget.controller.beginStroke(
        widget.controller.toDocument(event.localPosition, _viewportSize),
        _weightFor(event),
      );
    }
  }

  /// Picks the interaction for a mouse press; secondary > middle > primary if
  /// several buttons are down.
  _Interaction? _mouseInteraction(int buttons) {
    if ((buttons & kSecondaryMouseButton) != 0) return _Interaction.pan;
    if ((buttons & kMiddleMouseButton) != 0) return _Interaction.rotate;
    if ((buttons & kPrimaryMouseButton) != 0) return _Interaction.draw;
    return null;
  }

  /// Continues the pointer's interaction using the movement since the last
  /// event: extends the stroke (document space), pans by the screen-space
  /// delta, or rotates about the pointer by `delta.dx / 100` radians (a
  /// horizontal drag of 100 px is 1 rad).
  void _onPointerMove(PointerMoveEvent event) {
    final interaction = _interactions[event.pointer];
    if (interaction == null) return;

    final delta = event.localPosition - interaction.lastPosition;
    interaction.lastPosition = event.localPosition;
    switch (interaction.mode) {
      case _Interaction.draw:
        widget.controller.extendStroke(
          widget.controller.toDocument(event.localPosition, _viewportSize),
          _weightFor(event),
        );
      case _Interaction.pan:
        widget.controller.panBy(delta);
      case _Interaction.rotate:
        widget.controller.rotateAt(
          event.localPosition,
          _viewportSize,
          delta.dx / 100,
        );
    }
  }

  /// Maps a pointer event to brush weight: mouse is always 1.0; otherwise
  /// normalized pressure maps linearly to 0.05-1.0 (prototype values, see the
  /// overview above). A device that reports no pressure range counts as full
  /// pressure.
  double _weightFor(PointerEvent event) {
    if (event.kind == PointerDeviceKind.mouse) return 1;
    final pressureRange = event.pressureMax - event.pressureMin;
    final pressure = pressureRange > 0
        ? (event.pressure - event.pressureMin) / pressureRange
        : 1.0;
    return 0.05 + 0.95 * pressure.clamp(0, 1);
  }

  /// Pointer up or cancel: commits the stroke if this pointer was drawing.
  void _finishPointer(PointerEvent event) {
    final interaction = _interactions.remove(event.pointer);
    if (interaction?.mode == _Interaction.draw) {
      widget.controller.endStroke();
    }
  }

  /// Mouse-wheel zoom about the pointer. Scroll events from other device kinds
  /// are ignored (trackpad scrolling arrives as `PointerPanZoom*` events
  /// instead). A positive `scrollDelta.dy` zooms out.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || event.kind != PointerDeviceKind.mouse) {
      return;
    }
    widget.controller.zoomAt(
      event.localPosition,
      _viewportSize,
      math.exp(-event.scrollDelta.dy / 500),
    );
  }

  /// Trackpad gesture start: remembers the focal point that every zoom and
  /// rotate in this gesture is anchored to (ADR 0003).
  void _onPanZoomStart(PointerPanZoomStartEvent event) {
    _trackpadGesture = _TrackpadGesture(event.localPosition);
  }

  /// Applies one trackpad update. `scale` and `rotation` in the event are
  /// cumulative since the gesture started, so the previous values stored in
  /// [_TrackpadGesture] are divided/subtracted out to get per-update
  /// increments for `CanvasController.zoomAt`/`rotateAt`.
  void _onPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    final gesture = _trackpadGesture;
    if (gesture == null) return;

    if (event.panDelta != Offset.zero) {
      widget.controller.panBy(event.panDelta);
    }

    final viewportSize = _viewportSize;
    if (event.scale != gesture.lastScale) {
      widget.controller.zoomAt(
        gesture.focalPoint,
        viewportSize,
        event.scale / gesture.lastScale,
      );
      gesture.lastScale = event.scale;
    }

    if (event.rotation != gesture.lastRotation) {
      widget.controller.rotateAt(
        gesture.focalPoint,
        viewportSize,
        event.rotation - gesture.lastRotation,
      );
      gesture.lastRotation = event.rotation;
    }
  }

  void _onPanZoomEnd(PointerPanZoomEndEvent event) {
    _trackpadGesture = null;
  }

  @override
  void dispose() {
    _renderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeColors =
        theme.extension<PainterThemeColors>() ??
        PainterThemeColors.fromColorScheme(theme.colorScheme);
    return HelpTarget(
      topic: HelpTopics.canvas,
      child: Semantics(
        label: 'Canvas',
        child: Listener(
          key: _surfaceKey,
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _finishPointer,
          onPointerCancel: _finishPointer,
          onPointerPanZoomStart: _onPanZoomStart,
          onPointerPanZoomUpdate: _onPanZoomUpdate,
          onPointerPanZoomEnd: _onPanZoomEnd,
          onPointerSignal: _onPointerSignal,
          child: CustomPaint(
            painter: _CanvasPainter(
              widget.controller,
              _renderer,
              MediaQuery.devicePixelRatioOf(context),
              widget.debugOptions,
              theme.colorScheme,
              themeColors,
            ),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

/// Tracks one active pointer: what it is doing and where it was last seen (to
/// compute per-event deltas).
class _PointerInteraction {
  _PointerInteraction(this.mode, this.lastPosition);

  final _Interaction mode;
  Offset lastPosition;
}

/// State of one trackpad pan/zoom gesture: the fixed focal point and the
/// cumulative scale and rotation already applied, used to turn the event's
/// cumulative values into increments.
class _TrackpadGesture {
  _TrackpadGesture(this.focalPoint);

  final Offset focalPoint;
  double lastScale = 1;
  double lastRotation = 0;
}

/// Paints the themed canvas surface, cached tiles and the active stroke.
/// Repaints whenever the controller (viewport, active stroke, document), the
/// tile cache (a tile finished) or the debug options change; [shouldRepaint]
/// only covers the constructor arguments changing. The actual tile drawing is
/// `TiledRenderer.paint`.
class _CanvasPainter extends CustomPainter {
  _CanvasPainter(
    this.controller,
    this.renderer,
    this.devicePixelRatio,
    this.debugOptions,
    this.colorScheme,
    this.themeColors,
  ) : super(
        repaint: Listenable.merge([controller, renderer.cache, ?debugOptions]),
      );

  final CanvasController controller;
  final TiledRenderer renderer;
  final double devicePixelRatio;
  final CanvasDebugOptions? debugOptions;
  final ColorScheme colorScheme;
  final PainterThemeColors themeColors;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(themeColors.canvasBackground, BlendMode.src);
    canvas.save();
    final center = Offset(size.width / 2, size.height / 2);
    // The canvas transform must equal CanvasController.toScreen: translate by
    // pan, then rotate and scale about the viewport centre. Document-space
    // drawing below is therefore placed correctly on screen.
    canvas.translate(controller.pan.dx, controller.pan.dy);
    canvas.translate(center.dx, center.dy);
    canvas.rotate(controller.rotation);
    canvas.scale(controller.zoom);
    canvas.translate(-center.dx, -center.dy);
    // `visible` is the document-space bounding box of the screen (all four
    // corners mapped, so it is exact under rotation). `pixelsPerUnit` is the
    // on-screen scale of one document unit, from which the renderer picks the
    // tile level of detail (`TileGrid.levelFor`).
    renderer.paint(
      canvas,
      document: controller.document,
      active: controller.activePoints,
      visible: TileGrid.visibleDocumentRect(
        size,
        (screen) => controller.toDocument(screen, size),
      ),
      pixelsPerUnit: controller.zoom * devicePixelRatio,
    );
    final options = debugOptions;
    if (options != null) {
      paintTileOverlay(
        canvas,
        frame: renderer.frame,
        options: options,
        zoom: controller.zoom,
        colorScheme: colorScheme,
        themeColors: themeColors,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CanvasPainter oldDelegate) =>
      oldDelegate.controller != controller ||
      oldDelegate.renderer != renderer ||
      oldDelegate.devicePixelRatio != devicePixelRatio ||
      oldDelegate.debugOptions != debugOptions ||
      oldDelegate.colorScheme != colorScheme ||
      oldDelegate.themeColors != themeColors;
}
