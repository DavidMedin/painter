# Use a vector canvas with Flutter pointer input

## Status

Accepted

## Context

The MVP runs on macOS and requires a blank paint-ready surface, round mouse and pressure-sensitive stylus strokes, and mouse pan, zoom, and rotation. The project had no canvas implementation or canvas-state dependencies. File persistence is assigned to T-005 and its format is unresolved.

The focused Flutter prototype renders completed vector strokes with `CustomPainter`. Widget tests send mouse and stylus pointer events through `CanvasView`, inspect the resulting document, and exercise pan, pointer-anchored wheel zoom, middle-button rotation, and pressure-dependent stroke weight. The macOS Release app was built and launched. Tests assert document behavior rather than raster pixel output.

## Decision

- Render the white canvas and round strokes with Flutter's `CustomPainter`; store marks as vector strokes rather than a raster image.
- Keep a controller-owned `CanvasDocument` of immutable completed `CanvasStroke` values, each containing document-space points and per-point brush weight. Keep pan, zoom, rotation, and the in-progress stroke in a `CanvasController` extending Flutter's `ChangeNotifier`.
- Keep the view and input handling in `CanvasView`. Use Flutter pointer events on macOS; do not add a native input or rendering plugin for this path.
- Use primary mouse drag to draw at weight `1.0`, secondary-button drag to pan, middle-button drag to rotate, and vertical mouse-wheel movement to zoom about the pointer.
- For the prototype, map normalized stylus pressure linearly to weight `0.05`–`1.0`; weight affects stroke width only. The prototype uses an 8-logical-pixel brush diameter.
- Keep document coordinates independent of viewport transforms. Clamp prototype zoom to `0.1`–`16`.

## Consequences

- Vector strokes preserve per-point stylus weight and support viewport transforms without changing the document. The focused implementation paints each segment with round caps and joins its endpoints with circles; stroke interpolation, caching, and large-document performance remain to be validated as the workflow grows.
- `ChangeNotifier` avoids a state-management dependency while keeping document and viewport mutations outside widget painting code. The canvas model currently uses Flutter geometry types and is not yet a persistence contract.
- Mouse gesture assignments are explicit and testable, but middle-button rotation requires a mouse with that button. T-004 can revise the controls if macOS usability evidence warrants it.
- The 8-pixel diameter and pressure-to-weight mapping are prototype values, not resolved production brush defaults. T-004 must validate those open product details.
- Flutter pointer-event pressure is exercised with synthetic events; physical stylus hardware behavior is not established by this prototype. Future platform behavior is also unverified.
- File format, serialization, save/open flows, and error handling remain outside this decision and belong to T-005.
