// What: PaneKind, the Pane Modes a pane can be in, with display label and icon.
// Why: Both the workspace model (workspace.dart, which stores a mode per pane
//   and writes its name to a file) and the pane UI (../ui/pane_system.dart)
//   need the mode list; a separate file keeps them from importing each other.
// Coupled to: workspace.dart (serializes `name`), pane_system.dart (dropdown
//   labels and icons), and main.dart (chooses content per mode).
//   Behavior: docs/spec/panes.md (PANE-6 to PANE-8).

import 'package:flutter/material.dart';

/// The Pane Modes the app implements. [name] is written to workspace sections,
/// so renaming a value changes the stored format.
enum PaneKind {
  canvas('Canvas', Icons.brush_outlined),
  diagnostics('Diagnostics', Icons.analytics_outlined),
  settings('Settings', Icons.settings_outlined),
  manual('Manual', Icons.menu_book_outlined),
  log('Log', Icons.receipt_long_outlined);

  const PaneKind(this.label, this.icon);

  final String label;
  final IconData icon;
}
