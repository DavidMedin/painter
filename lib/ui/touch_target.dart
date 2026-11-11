// What: The single minimum interactive-control height used across the app.
// Why: Shared controls read one constant instead of keeping separate sizes, so
//   every control is equally finger-sized.
// Coupled to: PainterActionButton, the diagnostics kit in debug/imgui.dart,
//   the file picker rows, log rows, the manual pane, the settings pane, and the
//   pane system.

/// Minimum height, in logical pixels, of every interactive control.
const double touchTargetHeight = 48;
