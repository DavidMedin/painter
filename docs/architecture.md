# Architecture

## Current Constraints

- The application is intended to use Flutter and Dart.
- macOS is the current target; Linux, Windows, and Android are future targets with no rollout order decided.

## Architectural Priorities

- Keep components cohesive, with narrow interfaces, clear ownership and contracts, and few dependencies.
- Choose boundaries from product needs and runnable evidence; modularity does not require a specific architecture or separate packages.

## Canvas Architecture (T-003/T-004)

- **Rendering:** `CanvasView` composes the document from cached tiles. Pure-Dart `PencilSplats`/`SplatStream` deterministically derive instanced splats from stroke points, weights, and seed; `SplatWorker` generates them in an isolate. `TileCache` asynchronously rasterizes 512×512 document-space tiles at power-of-two resolutions, draws only new strokes, and keeps scaled stale tiles visible until replacements land. `TiledRenderer` draws visible tiles and the current bounded chunk live; completed chunks enter the cache during long gestures. See [ADR 0004](decisions/0004-pencil-splat-stroke-rendering.md), [ADR 0005](decisions/0005-tiled-texture-cache.md), and [ADR 0009](decisions/0009-bounded-active-stroke-chunks.md).
- **Document:** `CanvasDocument` stores immutable strokes made of document-space points and per-point brush weights. Viewport pan, zoom, rotation, and the current active chunk are separate controller state; a long pointer gesture may append earlier chunks as document strokes before pointer-up.
- **State:** `CanvasController` owns document, viewport, and active-chunk changes and extends Flutter `ChangeNotifier`; no state-management package is required.
- **Input:** `CanvasView` consumes Flutter pointer events on macOS without a native input/rendering plugin. Primary mouse drag draws at weight `1.0`; secondary drag pans; middle drag rotates; vertical mouse-wheel movement zooms about the pointer. Trackpad two-finger gestures (`PointerPanZoom*` events, `PointerDeviceKind.trackpad`) drive the same viewport: two-finger scroll pans, pinch zooms about the gesture's focal point, and two-finger rotate rotates about that same point. Stylus pressure controls weight only.
- **Prototype parameters:** an 8-logical-pixel brush diameter, linear normalized pressure-to-weight range `0.05`–`1.0`, and zoom limits `0.1`–`16` make the focused prototype runnable. The brush diameter and exact pressure mapping remain open production choices.
- **Evidence and record:** headless widget tests cover pointer input and the painting workflow; unit and renderer tests cover splat generation, tile geometry, output fidelity, updates, fallbacks, eviction, and long-gesture chunk caching. The Release app builds. See [ADR 0001](decisions/0001-vector-canvas-and-flutter-input.md), [ADR 0004](decisions/0004-pencil-splat-stroke-rendering.md), [ADR 0005](decisions/0005-tiled-texture-cache.md), and [ADR 0009](decisions/0009-bounded-active-stroke-chunks.md) for details and limitations.

## Document and File Architecture (T-005)

- **Format:** `CanvasDocument.toJson`/`.fromJson` serialize ordered strokes of document-space points and weights to UTF-8 JSON with a `painter-document` format identifier and integer version. See [ADR 0002](decisions/0002-saved-document-format-and-flow.md).
- **Picking:** `DocumentFileService` (in `lib/document/`) separates file I/O from path picking. The production implementation, `InAppDocumentFileService`, shows `InAppFilePicker`, an in-app dialog built from ordinary Flutter widgets (directory listing, navigation, a filename field) instead of a native file dialog or a platform plugin.
- **Wiring:** `PainterApp` in `lib/main.dart` owns the current document path and in-flight file-operation state, and shows a details-expandable error dialog on failure without replacing the current document or crashing.
- **Evidence and record:** because picking is ordinary Flutter UI, `flutter test` drives and verifies the full open/save flow headlessly, including the picker dialog itself (navigate, type a name, confirm, cancel); no native dialog, VM, or file-picker plugin dependency is required.

## Debug Pane (developer tool)

- **Purpose:** show the tile cache's internals in the running app and expose a few controls. Hidden by default (the app still opens to the blank canvas); the workspace selector offers the diagnostics arrangement, and `F3` switches the same content. See [ADR 0006](decisions/0006-debug-pane.md).
- **Layers:** `lib/debug/imgui.dart` is a reusable, painter-agnostic widget kit in the style of Dear ImGui (window, collapsible sections, rows, checkbox, button, integer slider, plot, stacked bar). `lib/debug/canvas_debug_pane.dart` composes it into the pane; `lib/debug/tile_overlay.dart` paints canvas overlays; `CanvasDebugOptions` carries the overlay switches.
- **Boundary:** the core (`TileCache`, `TiledRenderer`, `lib/canvas/tile_stats.dart`) only records counters and per-frame tile classification and never imports debug UI. The pane reads one frozen snapshot per refresh and writes only `maxInFlight`, `maxTiles`, `invalidateAll()`, `resetViewport()`, and the overlay switches.
- **Evidence:** unit tests drive a real `TiledRenderer` to check the per-frame classification and counters; widget tests cover the kit and the pane in the real `PainterApp` (toggle, live numbers, pause, controls, overlays, report, no interference with drawing).

## Application controls and workspaces

- **Controls:** `lib/ui/painter_action_button.dart` supplies the shared labeled
  action style; `lib/help/contextual_help.dart` catalogs hover hints and F1
  articles. F1 chooses hovered help, then keyboard-focused help, then general
  help. These scopes wrap Navigator so modal routes inherit help and sizing.
  The workspace selector presents only the existing canvas and diagnostics
  arrangements.
- **Touch sizing:** `TouchTargetSettings` in
  `lib/ui/touch_target_settings.dart` provides app-wide 48-logical-pixel
  standard and 56-logical-pixel enlarged minimum heights. The in-session
  switch is in the AppBar.
- **Evidence and record:** widget tests cover workspace selection, F1 opening
  help for hovered canvas and modal-dialog controls, touch target sizing, and
  help-topic precedence. See [ADR 0008](decisions/0008-discoverable-controls-workspaces-and-touch-targets.md).

## Code Documentation

- All code in `lib/` and `test/` follows the [code commenting standard](decisions/0007-code-commenting-standard.md): a What/Why header per file, an overview in the primary file of each general system, doc comments on non-obvious functions, named coupling, and comments kept in step with the code.

## Decisions Not Yet Made

