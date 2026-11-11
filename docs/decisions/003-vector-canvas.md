# 003. Vector Canvas, Input, and Viewports

Design for how the Canvas stores marks, maps pointer and trackpad input, and separates the document from each pane's view.

## Status

Status: superseded (supersedes: none; superseded by: 005, 006)
Date: 2026-11-10
Relates to:


## Context

The MVP runs on macOS and needs a blank paint-ready surface, round mouse and pressure-sensitive stylus strokes, and mouse and trackpad pan, zoom, and rotation. Several Canvas panes can show one document at once, so a view transform stored with the document would couple their views.

The macOS trackpad has no middle or secondary button and does not generate wheel events for pinch and rotate. Flutter reports its gestures as a separate `PointerDeviceKind.trackpad` stream (`PointerPanZoomStartEvent`, `PointerPanZoomUpdateEvent`, `PointerPanZoomEndEvent`). An update carries `panDelta` (incremental two-finger pan) and cumulative `scale` and `rotation` since gesture start.

## Decision

### Document and rendering model

- **PNT-A0001-01** The Canvas shall render the white canvas and round strokes with Flutter's `CustomPainter`.
- **PNT-A0001-02** The Canvas shall store marks as vector strokes and shall not store them as a raster image.
- **PNT-A0001-03** The `CanvasController` shall own a `CanvasDocument` of immutable completed `CanvasStroke` values, each containing document-space points and a per-point brush weight.
- **PNT-A0001-04** The `CanvasController`, extending Flutter's `ChangeNotifier`, shall hold the in-progress stroke.
- **PNT-A0001-14** The Canvas shall keep document coordinates independent of viewport transforms.

### Viewports

- **PNT-A0012-01** The `CanvasController` shall own the shared `CanvasDocument` and the active stroke state.
- **PNT-A0012-02** Each Canvas pane shall get a distinct `CanvasViewportController` for pan, zoom, rotation, and coordinate conversion.
- **PNT-A0012-03** Every view shall observe the shared document and apply its own viewport transform.
- **PNT-A0012-04** WHEN a document is opened, the Painter shall reset every current pane viewport.
- **PNT-A0012-05** The Painter shall keep view transforms transient and shall not save them in the document format.

### Pointer input

- **PNT-A0001-05** The `CanvasView` shall own the view and input handling and shall use Flutter pointer events on macOS.
- **PNT-A0001-06** The Canvas shall not use a native input or rendering plugin for pointer input.
- **PNT-A0001-07** WHEN the user drags with the primary mouse button, the Canvas shall draw at weight `1.0`.
- **PNT-A0001-08** WHEN the user drags with the secondary mouse button, the Canvas shall pan.
- **PNT-A0001-09** WHEN the user drags with the middle mouse button, the Canvas shall rotate.
- **PNT-A0001-10** WHEN the user moves the vertical mouse wheel, the Canvas shall zoom about the pointer.
- **PNT-A0001-12** The Canvas shall apply weight to stroke width only.

### Trackpad input

- **PNT-A0003-01** The `CanvasView` shall handle trackpad gestures through `Listener.onPointerPanZoomStart/Update/End`, independent of the mouse pointer-down and pointer-move handlers.
- **PNT-A0003-02** WHEN a trackpad gesture starts, the `CanvasView` shall record the gesture's focal point (`event.localPosition`) and use it as the anchor for zoom and rotate for the remainder of that gesture.
- **PNT-A0003-03** WHEN a trackpad gesture updates, the `CanvasView` shall apply `event.panDelta` directly as a pan.
- **PNT-A0003-04** WHEN a trackpad gesture updates, the `CanvasView` shall convert the cumulative `scale` to an incremental zoom factor (`event.scale / lastScale`) and apply it anchored at the focal point, such that pinching out zooms in.
- **PNT-A0003-05** WHEN a trackpad gesture updates, the `CanvasView` shall convert the cumulative `rotation` to an incremental radian delta (`event.rotation - lastRotation`) and apply it anchored at the focal point.
- **PNT-A0003-06** The `CanvasView` shall keep the mouse secondary-drag pan, middle-drag rotate, and wheel zoom unchanged, so that trackpad and mouse controls are interchangeable.

### Prototype parameters

- **PNT-A0001-11** For the prototype, the Canvas shall map normalized stylus pressure linearly to a weight of `0.05` to `1.0`.
- **PNT-A0001-13** For the prototype, the Canvas shall use an 8-logical-pixel brush diameter.
- **PNT-A0001-15** For the prototype, the Canvas shall clamp zoom to `0.1` to `16`.

## Consequences

- Vector strokes keep per-point stylus weight and support viewport transforms without changing the document.
- `ChangeNotifier` avoids a state-management dependency and keeps mutation outside widget painting code. The canvas model uses Flutter geometry types.
- Mouse gestures are explicit and testable, but middle-button rotation needs a mouse with that button. The trackpad has full parity through two-finger pan, pinch, and twist.
- The focal point is fixed for one trackpad gesture, consistent with wheel zoom about the pointer.
- The rotation sign is taken as-is from `PointerPanZoomUpdateEvent.rotation`. If live testing shows it feels reversed, only the sign in `CanvasView._onPanZoomUpdate` changes.
- Canvas panes share edits while pan, zoom, and rotation stay independent. Opening a file returns every Canvas pane to its default view.
- The 8-pixel diameter and pressure mapping are prototype values and unresolved production choices.
- Not verified: physical stylus and trackpad hardware (only synthetic Flutter events were exercised), and exact OS-reported scale and rotation magnitudes.

## Regression Notes

- `painting_workflow_test.dart` computes pointer positions relative to the canvas's actual on-screen offset. It once assumed the canvas started at the window origin, which broke when the Open/Save `AppBar` was added above it.
