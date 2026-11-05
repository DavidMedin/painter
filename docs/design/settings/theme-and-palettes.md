# Theme Settings, Saved Palettes, and Fixed Canvas Paper

Design for appearance settings and how they reach the UI, and for keeping canvas paper independent of the theme. Observable behavior is in [behavior](behavior.md). Notation: [EARS+](../README.md#requirement-notation-ears).

## Status

Accepted and implemented. Combines the former ADR 0011 (theme settings) and the paper half of ADR 0012. The former canvas-paper palette role is superseded by fixed white paper.

## Context

Painter's UI colors were fixed in the canvas and diagnostics UI. Appearance must be configurable without changing the saved painting or coupling theme state to canvas or document state. macOS is the current target, and future platform support is not established by this change.

Canvas paper tied to the app palette changes the painting surface with the UI theme. Stored custom palettes may already contain the old `canvasBackground` key.

## Decision

### Model

- **PNT-A0011-01** The Settings shall store appearance as immutable `PainterSettings`, `PainterTheme`, and `PainterThemeColors` values in `lib/settings/painter_settings.dart`.
- **PNT-A0011-02** The `PainterTheme.themeData` shall map editable UI roles into a Material 3 `ColorScheme` plus the Painter-specific extension for semantic diagnostics colors.
- **PNT-A0011-03** The Settings shall support `ThemeMode.system`, `ThemeMode.light`, and `ThemeMode.dark`.
- **PNT-A0011-04** The Settings shall keep the selected light palette and the selected dark palette independent, so that a system brightness change loses neither choice.
- **PNT-A0011-05** WHEN the app starts with no stored selection, the Settings shall default to Gruvbox Light and Gruvbox Dark respectively.
- **PNT-A0011-06** The Settings shall treat the Gruvbox palettes as built-ins.
- **PNT-A0011-07** Each custom palette shall have a stable generated ID, a name, and a fixed brightness.
- **PNT-A0011-08** The Settings pane (`ThemeSettingsPane`) shall let the user
  create custom palettes and edit all theme color roles, and shall expose the
  mode, independent light and dark selectors, and palette swatches. Built-in
  palettes remain create-only; editing a custom palette preserves its ID.
- **PNT-ARC-021** The `PainterSettingsController` shall own the live immutable settings value and shall invoke its persistence callback after each change.

### Persistence

- **PNT-A0011-09** The Settings shall persist the mode, the selected palette IDs, and the custom palettes together as one versioned JSON preference under `painter.settings.v1`, through `SharedPreferencesPainterSettingsStore`.
- **PNT-A0011-10** The Painter shall load the settings before `runApp`.
- **PNT-A0011-11** IF the stored settings are missing, malformed, or unavailable, THEN the Painter shall fall back to defaults.
- **PNT-ARC-025** The `main.dart` shall supply both brightness themes and the `ThemeMode` to `MaterialApp`.

### Color resolution

- **PNT-A0011-12** The Painter shall resolve application UI colors from the active `ThemeData`, including tile overlays, diagnostics, and `lib/debug/imgui.dart`.
- **PNT-A0011-13** The `CanvasView` shall pass the active `ColorScheme` and semantic colors to canvas overlays.
- **PNT-A0011-15** The Painter shall keep user-authored painting independent of UI theme selection.

### Canvas paper

- **PNT-A0012-06** The `CanvasView` shall paint paper with the fixed white `CanvasView.paperColor`, regardless of app theme.
- **PNT-A0012-07** The `canvasBackground` shall not be a `PainterTheme` or `PainterThemeColors` role, and the semantic diagnostic colors shall remain theme-driven.
- **PNT-A0012-08** WHEN loading a custom palette, the Settings shall ignore the legacy extra `canvasBackground` JSON key.
- **PNT-A0012-09** The Settings shall omit `canvasBackground` from newly serialized palettes.

Retired requirement IDs for this document are recorded in the [retired ID registry](../README.md#retired-requirement-ids).

## Consequences

- Theme selection updates the live app through `PainterSettingsController` and is saved through one injected persistence callback. Settings do not belong to the document format or canvas controller.
- Adding a persisted settings field requires updating the versioned JSON mapping and its tests. A future incompatible representation needs an explicit storage migration rather than silently changing the current record.
- The Flutter `shared_preferences` plugin is a runtime dependency. When the plugin is unavailable or a stored record is malformed, Painter uses default theme settings rather than blocking startup.
- Light, dark, and custom UI palettes do not recolor canvas paper, and existing palette records remain loadable without a migration.
- The custom-palette editor uses shared icon-bearing actions for Cancel and
  Save, preserving the controls behavior in
  `docs/design/controls/behavior.md`.
- Headless tests cover settings and model behavior, custom palette interaction, persistence restoration, legacy palette loading, both built-in tile-color maps, and a dark-theme pixel sample of the white canvas.
- Not verified: the appearance of the macOS window.

## Regression Notes

- Palette selectors expand within their available width and truncate long custom theme names instead of overflowing. The narrow-pane regression failed before the fix: its selected custom-theme label measured 1065.9 logical pixels against a 55-pixel selector. It checks that the label fits and that layout reports no rendering exception.
