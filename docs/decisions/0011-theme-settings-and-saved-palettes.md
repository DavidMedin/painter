# Theme settings and saved palettes

## Status

Accepted and implemented. The former canvas-paper palette role is superseded by
[ADR 0012](0012-pane-viewports-and-fixed-canvas-paper.md).

## Context

Painter's UI colors were fixed in the canvas and diagnostics UI. The app shell
now has selectable Canvas, Diagnostics, and Settings pane contents. Appearance
must be configurable without changing the saved painting or coupling theme
state to canvas/document state. macOS is the current target; future platform
support is not established by this change.

## Decision

- Store appearance as immutable `PainterSettings`, `PainterTheme`, and
  `PainterThemeColors` values in `lib/settings/painter_settings.dart`.
  `PainterTheme.themeData` maps editable UI roles into Material 3 `ColorScheme`
  plus the Painter-specific extension for semantic diagnostics colors.
- Support `ThemeMode.system`, `ThemeMode.light`, and `ThemeMode.dark`. Keep the
  selected light palette and selected dark palette independent so the system
  brightness can change without losing either choice. Default to Gruvbox Light
  and Gruvbox Dark respectively.
- Treat Gruvbox palettes as built-ins. Custom palettes have a stable generated
  ID, a name, and a fixed brightness; users can create and edit all theme color
  roles in the Settings pane.
- Persist mode, selected palette IDs, and custom palettes together as one JSON
  preference under `painter.settings.v1`, through
  `SharedPreferencesPainterSettingsStore`. Load before `runApp` and fall back to
  defaults for missing, malformed, or unavailable settings.
- Resolve application UI colors from the active `ThemeData`. `CanvasView` passes
  the active `ColorScheme` and semantic colors to canvas overlays; canvas paper
  is fixed white and is not a palette role. User-authored painting remains
  independent of UI theme selection.

## Consequences

- Theme selection updates the live app through `PainterSettingsController` and
  is saved through one injected persistence callback; settings do not belong to
  the document format or canvas controller.
- Adding a persisted settings field requires updating the versioned JSON mapping
  and its tests. A future incompatible representation needs an explicit storage
  migration rather than silently changing the current record.
- The Flutter `shared_preferences` plugin is a runtime dependency. When the
  plugin is unavailable or a stored record is malformed, Painter uses the
  default theme settings rather than blocking app startup.
- Headless tests cover settings/model behavior, custom palette interaction,
  persistence restoration, and both built-in tile-color maps. The macOS Release
  app builds. Its appearance has not been visually inspected; no GUI window was
  launched for this change.
