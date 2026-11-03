# Architecture

## Current Constraints

- The application is intended to use Flutter and Dart.
- macOS is the current target; Linux, Windows, and Android are future targets with no rollout order decided.

## Architectural Priorities

- Prefer cohesive components with clear responsibilities and narrow interfaces. Minimize unnecessary dependencies and cross-component knowledge so changes can be developed, tested, and revised with limited impact on unrelated parts.
- Make component ownership, public contracts, and permitted dependencies clear when planning work, especially when work may be implemented independently.
- Treat modularity as a priority, not as a requirement to use a particular architecture or split code into packages. Choose concrete boundaries and mechanisms based on the product requirements and runnable evidence.

## Canvas Architecture (T-003/T-004)

- **Rendering:** `CanvasView` draws a white canvas and composes the document from cached tiles. Each stroke is a cloud of instanced gaussian "pencil speck" splats: `PencilSplats`/`SplatStream` (pure Dart) derive splat transforms and opacities deterministically from a stroke's points, weights, and seed, and are not stored in the document. A `SplatWorker` isolate generates them off the UI thread. `TileCache` rasterizes document-space tiles (512×512 px each, several power-of-two resolutions) in the background with `drawRawAtlas`, updates a tile by drawing only newly added strokes over its old image, and keeps stale or wrong-resolution tiles on screen, scaled, until their replacement lands. `TiledRenderer` draws the visible tiles each frame and the in-progress stroke live, so frame cost does not grow with stroke count. See [ADR 0005](decisions/0005-tiled-texture-cache.md) and [ADR 0004](decisions/0004-pencil-splat-stroke-rendering.md).
- **Document:** `CanvasDocument` stores immutable strokes made of document-space points and per-point brush weights. Viewport pan, zoom, rotation, and the active stroke are separate controller state.
- **State:** `CanvasController` owns document and viewport changes and extends Flutter `ChangeNotifier`; no state-management package is required.
- **Input:** `CanvasView` consumes Flutter pointer events on macOS without a native input/rendering plugin. Primary mouse drag draws at weight `1.0`; secondary drag pans; middle drag rotates; vertical mouse-wheel movement zooms about the pointer. Trackpad two-finger gestures (`PointerPanZoom*` events, `PointerDeviceKind.trackpad`) drive the same viewport: two-finger scroll pans, pinch zooms about the gesture's focal point, and two-finger rotate rotates about that same point. Stylus pressure controls weight only.
- **Prototype parameters:** an 8-logical-pixel brush diameter, linear normalized pressure-to-weight range `0.05`–`1.0`, and zoom limits `0.1`–`16` make the focused prototype runnable. The brush diameter and exact pressure mapping remain open production choices.
- **Evidence and record:** widget tests cover isolated pointer behavior and the combined painting/viewport workflow; `flutter test` runs them headlessly. Unit tests cover splat-generation invariants (determinism, prefix stability, containment, pressure response) and tile-grid geometry. Renderer tests assert pixel statistics of an offscreen render (grainy rather than solid, contained to the brush), that tiled output matches drawing the same splats directly, that tile edges show no seam, that adding a stroke updates a tile without losing earlier strokes, that a zoomed view shows a scaled old tile immediately and then the new resolution, and that tiles on screen are not evicted. The Release app builds. See [ADR 0001](decisions/0001-vector-canvas-and-flutter-input.md), [ADR 0004](decisions/0004-pencil-splat-stroke-rendering.md), and [ADR 0005](decisions/0005-tiled-texture-cache.md) for tradeoffs and limitations.

## Document and File Architecture (T-005)

- **Format:** `CanvasDocument.toJson`/`.fromJson` serialize ordered strokes of document-space points and weights to UTF-8 JSON with a `painter-document` format identifier and integer version. See [ADR 0002](decisions/0002-saved-document-format-and-flow.md).
- **Picking:** `DocumentFileService` (in `lib/document/`) separates file I/O from path picking. The production implementation, `InAppDocumentFileService`, shows `InAppFilePicker`, an in-app dialog built from ordinary Flutter widgets (directory listing, navigation, a filename field) instead of a native file dialog or a platform plugin.
- **Wiring:** `PainterApp` in `lib/main.dart` owns the current document path and in-flight file-operation state, and shows a details-expandable error dialog on failure without replacing the current document or crashing.
- **Evidence and record:** because picking is ordinary Flutter UI, `flutter test` drives and verifies the full open/save flow headlessly, including the picker dialog itself (navigate, type a name, confirm, cancel); no native dialog, VM, or file-picker plugin dependency is required.

## Debug Pane (developer tool)

- **Purpose:** show the tile cache's internals in the running app and expose a few controls. Hidden by default (the app still opens to the blank canvas); an AppBar bug icon or `F3` toggles it. See [ADR 0006](decisions/0006-debug-pane.md).
- **Layers:** `lib/debug/imgui.dart` is a reusable, painter-agnostic widget kit in the style of Dear ImGui (window, collapsible sections, rows, checkbox, button, integer slider, plot, stacked bar). `lib/debug/canvas_debug_pane.dart` composes it into the pane; `lib/debug/tile_overlay.dart` paints canvas overlays; `CanvasDebugOptions` carries the overlay switches.
- **Boundary:** the core (`TileCache`, `TiledRenderer`, `lib/canvas/tile_stats.dart`) only records counters and per-frame tile classification and never imports debug UI. The pane reads one frozen snapshot per refresh and writes only `maxInFlight`, `maxTiles`, `invalidateAll()`, `resetViewport()`, and the overlay switches.
- **Evidence:** unit tests drive a real `TiledRenderer` to check the per-frame classification and counters; widget tests cover the kit and the pane in the real `PainterApp` (toggle, live numbers, pause, controls, overlays, report, no interference with drawing).

## Code Documentation

- All code in `lib/` and `test/` follows the [code commenting standard](decisions/0007-code-commenting-standard.md): a What/Why header per file, an overview in the primary file of each general system, doc comments on non-obvious functions, named coupling, and comments kept in step with the code.

## Decisions Not Yet Made

