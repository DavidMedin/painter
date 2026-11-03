// What: Inherited app-wide selection for standard and enlarged hit targets.
// Why: docs/project-brief.md requires control sizes configurable for touch use;
//   shared controls read one setting instead of keeping independent sizes.
// Coupled to: PainterApp (owns the selection), PainterActionButton, diagnostic
//   controls, picker rows, and the contextual help dialog.

import 'package:flutter/widgets.dart';

/// App-level setting for the minimum interactive-target height.
class TouchTargetSettings extends InheritedWidget {
  const TouchTargetSettings({
    super.key,
    required this.enlarged,
    required super.child,
  });

  final bool enlarged;

  /// The selected minimum height, or 48 logical pixels outside the app shell.
  static double height(BuildContext context) =>
      context
              .dependOnInheritedWidgetOfExactType<TouchTargetSettings>()
              ?.enlarged ==
          true
      ? 56
      : 48;

  @override
  bool updateShouldNotify(TouchTargetSettings oldWidget) =>
      enlarged != oldWidget.enlarged;
}
