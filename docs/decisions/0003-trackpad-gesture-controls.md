# Add macOS trackpad pan, zoom, and rotate controls

## Status

Accepted

## Context

[ADR 0001](0001-vector-canvas-and-flutter-input.md) established mouse-only viewport controls: secondary-button drag pans, middle-button drag rotates, and the mouse wheel zooms about the pointer. This covers physical mice but gives no sane controls to the macOS trackpad, which has no middle or secondary button and does not generate wheel events for pinch/rotate gestures.

Flutter's engine reports macOS trackpad gestures as a dedicated `PointerDeviceKind.trackpad` stream (`PointerPanZoomStartEvent`, `PointerPanZoomUpdateEvent`, `PointerPanZoomEndEvent`), separate from mouse pointer-down/move/signal events. `PointerPanZoomUpdateEvent` carries, for a single continuous gesture: `panDelta` (incremental two-finger pan), and cumulative `scale` and `rotation` (pinch and twist) since gesture start.

## Decision

- Handle trackpad gestures in `CanvasView` via `Listener.onPointerPanZoomStart/Update/End`, independent of the existing mouse pointer-down/move handlers.
- On gesture start, record the gesture's focal point (`event.localPosition`) as the anchor for zoom and rotate for the remainder of that gesture.
- On each update: apply `event.panDelta` directly as a pan (two-finger scroll pans the canvas); convert cumulative `scale` to an incremental zoom factor (`event.scale / lastScale`) and apply it anchored at the focal point (pinch out zooms in, matching the existing wheel-zoom direction convention); convert cumulative `rotation` to an incremental radian delta (`event.rotation - lastRotation`) and apply it anchored at the same focal point (two-finger twist rotates the canvas).
- Keep this additive: existing mouse secondary-drag pan, middle-drag rotate, and wheel zoom are unchanged. Trackpad and mouse controls can be used interchangeably.

## Consequences

- The trackpad now has full, discoverable parity with mouse viewport controls (pan, zoom, rotate) using the OS-native two-finger gestures artists expect, with no middle-click requirement.
- The focal point is fixed for the lifetime of one trackpad gesture (set once on `PointerPanZoomStartEvent`), so zoom/rotate during a single gesture stay anchored to where the gesture began, consistent with the existing mouse wheel-zoom-about-pointer behavior.
- Verified with a synthetic widget test driving `TestPointer.panZoomStart/panZoomUpdate/panZoomEnd` through `CanvasView` and asserting `CanvasController.pan`, `.zoom`, and `.rotation` all change as expected; this exercises the Flutter-side event handling only; physical trackpad hardware and exact OS-reported scale/rotation magnitudes are not independently verified.
- The exact rotation sign/direction convention is taken as-is from Flutter's `PointerPanZoomUpdateEvent.rotation` without inversion; if live trackpad testing shows the rotation feels reversed, only the sign in `CanvasView._onPanZoomUpdate` needs to change.
