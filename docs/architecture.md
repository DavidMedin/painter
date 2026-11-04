# Architecture

## Current Constraints

- The application is intended to use Flutter and Dart.
- macOS is the current target; Linux, Windows, and Android are future targets with no rollout order decided.

## Architectural Priorities

- Keep components cohesive, with narrow interfaces, clear ownership and contracts, and few dependencies.
- Choose boundaries from product needs and runnable evidence; modularity does not require a specific architecture or separate packages.

## Canvas Architecture (T-003/T-004)

- **Rendering:** `CanvasView` composes the document from cached tiles. Pure-Dart `PencilSplats`/`SplatStream` deterministically derive instanced splats from stroke points, weights, and seed; `SplatWorker` generates them in an isolate. `TileCache` asynchronously rasterizes 512×512 document-space tiles at power-of-two resolutions and draws only new strokes. Stale tiles stay visible with ready splats overlaid where their images lag; `TiledRenderer` draws visible tiles and the current bounded chunk live. Completed chunks enter the cache during long gestures. See [ADR 0004](decisions/0004-pencil-splat-stroke-rendering.md), [ADR 0005](decisions/0005-tiled-texture-cache.md), and [ADR 0009](decisions/0009-bounded-active-stroke-chunks.md).
- **Document and viewport:** `CanvasDocument` stores immutable strokes made of
  document-space points and per-point brush weights. `CanvasController` owns the
  shared document and active stroke chunk. Every Canvas pane receives a distinct
  `CanvasViewportController` for pan, zoom, rotation, and coordinate mapping.
  Opening a document resets each current Canvas viewport; document format and
  painting remain independent of view transforms. See
  [ADR 0012](decisions/0012-pane-viewports-and-fixed-canvas-paper.md).
- **Prototype parameters:** an 8-logical-pixel brush diameter, linear normalized pressure-to-weight range `0.05`–`1.0`, and zoom limits `0.1`–`16` make the focused prototype runnable. The brush diameter and exact pressure mapping remain open production choices.
- **Evidence and record:** headless widget tests cover pointer input and the painting workflow; unit and renderer tests cover splat generation, tile geometry, output fidelity, updates, fallbacks, eviction, and long-gesture chunk caching. The Release app builds. See [ADR 0001](decisions/0001-vector-canvas-and-flutter-input.md), [ADR 0004](decisions/0004-pencil-splat-stroke-rendering.md), [ADR 0005](decisions/0005-tiled-texture-cache.md), and [ADR 0009](decisions/0009-bounded-active-stroke-chunks.md) for details and limitations.

## Document and File Architecture (T-005)

- **Format:** `CanvasDocument.toJson`/`.fromJson` serialize ordered strokes of document-space points and weights to UTF-8 JSON with a `painter-document` format identifier and integer version. See [ADR 0002](decisions/0002-saved-document-format-and-flow.md).
- **Picking:** `DocumentFileService` (in `lib/document/`) separates file I/O from path picking. The production implementation, `InAppDocumentFileService`, shows `InAppFilePicker`, an in-app dialog built from ordinary Flutter widgets (directory listing, navigation, a filename field) instead of a native file dialog or a platform plugin.
- **Wiring:** `PainterApp` in `lib/main.dart` owns the current document path and in-flight file-operation state, and shows a details-expandable error dialog on failure without replacing the current document or crashing.
- **Evidence and record:** because picking is ordinary Flutter UI, `flutter test` drives and verifies the full open/save flow headlessly, including the picker dialog itself (navigate, type a name, confirm, cancel); no native dialog, VM, or file-picker plugin dependency is required.

## App settings and theming

- `PainterSettings` and `PainterTheme` in `lib/settings/` define System/Light/Dark
  mode, separate brightness-specific selections, built-in Gruvbox palettes, and
  saved custom palettes. `PainterSettingsController` owns the live immutable
  settings value and invokes its persistence callback after changes.
- `SharedPreferencesPainterSettingsStore` stores the complete versioned record
  under `painter.settings.v1`. `main.dart` loads it before `runApp`, uses defaults
  if the record is malformed or unavailable, and supplies both brightness
  themes plus `ThemeMode` to `MaterialApp`.
- A `PainterTheme` maps its UI roles to Material 3 `ColorScheme` and
  `PainterThemeColors`, whose extension contains semantic diagnostic colors.
  Canvas paper is fixed white in `CanvasView`, not a palette role; painting
  marks remain document content. Tile overlays, diagnostics, and
  `lib/debug/imgui.dart` resolve UI colors from the active `ThemeData`.
- `ThemeSettingsPane` exposes mode, independent light/dark selectors, palette
  swatches, and custom palette creation/editing. See
  [ADR 0011](decisions/0011-theme-settings-and-saved-palettes.md).
- **Evidence:** headless tests cover mode updates, custom palette editing and
  selection, serialization, malformed records, persistence, and distinct tile
  state colors in both built-in palettes. The macOS Release build succeeds;
  window appearance has not been visually checked.

## Docked pane system and diagnostics

- **Pane layout:** `lib/ui/pane_system.dart` owns stable pane ids and Canvas,
  Diagnostics, Settings, and Manual modes in a binary split tree. Each split is
  side-by-side or top-and-bottom; axes can be nested, and each draggable divider
  resizes only its two children. A Manual pane stores its selected `HelpId`; F1
  reuses and focuses an existing Manual pane, or opens the article beside the
  widest leaf with a horizontal split. Each pane has an emphasized content
  selector, a Split menu, and a Close action when another pane remains. F3 adds
  Diagnostics beside Canvas and removes it on the next press; a sole Diagnostics
  pane becomes Canvas. See [ADR 0010](decisions/0010-pane-system.md) for pane
  mechanics and [ADR 0013](decisions/0013-docked-manual-pane.md) for Manual.
- **Content ownership:** `PainterApp` shares one document controller across Canvas panes and owns one `TiledRenderer` per pane plus one `CanvasViewportController` per Canvas pane. Diagnostics reads the first visible Canvas pane's renderer and viewport; when no Canvas is visible, it uses its own retained renderer and viewport. `CanvasDebugPane` remains scrollable pane content, not a floating window.
- **Diagnostics:** `lib/debug/imgui.dart` is a reusable, painter-agnostic widget
  kit in the style of Dear ImGui (collapsible sections, rows, checkbox, button,
  integer slider, plot, stacked bar). `lib/debug/tile_overlay.dart` paints
  canvas overlays; `CanvasDebugOptions` carries the overlay switches.
- **Boundary:** the core (`TileCache`, `TiledRenderer`, `lib/canvas/tile_stats.dart`)
  only records counters and per-frame tile classification and never imports
  debug UI. The pane reads one frozen snapshot per refresh and writes only
  `maxInFlight`, `maxTiles`, `invalidateAll()`, the selected Canvas viewport's
  `resetViewport()`, and overlay switches. ADR 0006 defines the diagnostics data
  and controls; ADR 0010 supersedes its former floating-window placement.
- **Controls and touch sizing:** `lib/ui/painter_action_button.dart` supplies
  labeled actions; `lib/help/contextual_help.dart` catalogs hover hints and F1
  articles. F1 prefers hovered help, then keyboard focus, then general help.
  `TouchTargetSettings` provides app-wide 48-logical-pixel standard and
  56-logical-pixel enlarged minimum heights.
- **Evidence:** headless tests cover Pane Mode selection, the app's Settings
  route, both split axes, resizing, close, F3 behavior, widest-leaf Manual
  placement and pane reuse, article navigation, live diagnostics, pause,
  controls, overlays, reports, and continued drawing. Canvas tests verify shared
  documents with independent viewports and fixed-white paper under a dark theme.
  The app-level document workflow draws through two Canvas panes, verifies
  opening resets both viewport transforms, and routes file-error Details help to
  Manual. macOS window appearance is not verified.

## Code Documentation

- All code in `lib/` and `test/` follows the [code commenting standard](decisions/0007-code-commenting-standard.md): a What/Why header per file, an overview in the primary file of each general system, doc comments on non-obvious functions, named coupling, and comments kept in step with the code.

## Decisions Not Yet Made

