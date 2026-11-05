// What: PainterActionButton, the shared rendering for labeled, icon-bearing
//   actions.
// Why: docs/design/controls/behavior.md requires visible button affordance,
//   concise hover hints, and touch-configurable sizing. One component keeps
//   those behaviors
//   consistent across the app shell, file picker, and developer controls.
// Coupled to: contextual_help.dart (tooltip and help topic),
//   touch_target_settings.dart (minimum hit-target height), and callers in
//   lib/debug/ and lib/document/.

import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../help/contextual_help.dart';
import 'touch_target_settings.dart';

/// A tactile action with a leading icon, visible label, hover hint, and help.
class PainterActionButton extends StatefulWidget {
  const PainterActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.topic,
    required this.onPressed,
    this.background,
    this.foreground,
    this.minimumHeight,
  });

  final IconData icon;
  final String label;
  final HelpId topic;
  final VoidCallback? onPressed;
  final Color? background;
  final Color? foreground;
  final double? minimumHeight;

  @override
  State<PainterActionButton> createState() => _PainterActionButtonState();
}

class _PainterActionButtonState extends State<PainterActionButton> {
  bool _highlighted = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final background =
        widget.background ?? Theme.of(context).colorScheme.primary;
    final foreground =
        widget.foreground ?? Theme.of(context).colorScheme.onPrimary;
    final height = widget.minimumHeight ?? TouchTargetSettings.height(context);
    final radius = BorderRadius.circular(4);

    return HelpTarget(
      topic: widget.topic,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: widget.label,
        onTap: widget.onPressed,
        excludeSemantics: true,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: height),
          child: Material(
            color: enabled ? background : Theme.of(context).disabledColor,
            elevation: enabled && !_highlighted ? 2 : 0,
            borderRadius: radius,
            child: InkWell(
              borderRadius: radius,
              onTap: widget.onPressed,
              onHighlightChanged: (highlighted) {
                if (_highlighted != highlighted) {
                  setState(() => _highlighted = highlighted);
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(widget.icon, size: 18, color: foreground),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        widget.label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: foreground),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Displays the shared action style inside the Flutter widget previewer.
@Preview(name: 'Painter action button', group: 'Painter controls')
Widget painterActionButtonPreview() => MaterialApp(
  home: Scaffold(
    body: Center(
      child: Builder(
        builder: (context) => PainterActionButton(
          icon: Icons.save,
          label: 'Save',
          topic: HelpIds.saveDocument,
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Preview action selected')),
          ),
        ),
      ),
    ),
  ),
);
