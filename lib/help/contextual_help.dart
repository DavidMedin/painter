// What: HelpTopic content, the app-scoped HelpState, HelpTarget wrappers, and
//   the in-app help dialog opened by F1.
// Why: docs/project-brief.md requires help to be reachable from every
//   interactive element and keyed to the element under the pointer. Keeping
//   topics and tracking in one small presentation system lets controls expose
//   help without coupling their behavior to the app shell.
// Coupled to: lib/main.dart (owns HelpState and handles F1),
//   lib/ui/painter_action_button.dart, lib/debug/imgui.dart, and
//   lib/document/file_picker_dialog.dart (mark interactive surfaces).
//
// ---------------------------------------------------------------------------
// Contextual help overview
// ---------------------------------------------------------------------------
// HelpTarget reports pointer hover and keyboard focus to one HelpState. F1
// selects the hovered target first, then the focused target, then general
// help. Each target also displays its concise Tooltip. The HelpTopic catalog
// is the in-app manual: adding a new interactive control requires assigning a
// topic whose description explains the control's effect.
// ---------------------------------------------------------------------------

import 'package:flutter/material.dart';

import '../ui/touch_target_settings.dart';

/// A help article used by hover hints and the F1 manual.
class HelpTopic {
  const HelpTopic({
    required this.title,
    required this.tooltip,
    required this.description,
  });

  final String title;
  final String tooltip;
  final String description;
}

/// The in-app manual entries for the currently implemented interactions.
class HelpTopics {
  const HelpTopics._();

  static const general = HelpTopic(
    title: 'Painter help',
    tooltip: 'Open help for the current control',
    description:
        'Choose a workspace, draw and navigate the canvas, or open and save '
        'Painter documents. Hover a control and press F1 for its help.',
  );
  static const canvas = HelpTopic(
    title: 'Canvas',
    tooltip: 'Draw and navigate the painting surface',
    description:
        'Drag with the primary mouse button or a stylus to draw. Use the '
        'secondary mouse button to pan, the middle button to rotate, and the '
        'wheel to zoom. Trackpad gestures pan, zoom, and rotate.',
  );
  static const openDocument = HelpTopic(
    title: 'Open document',
    tooltip: 'Choose a saved Painter document',
    description:
        'Browse to a .paint file and select it. Opening replaces the current '
        'document; a failed open leaves the current document unchanged.',
  );
  static const saveDocument = HelpTopic(
    title: 'Save document',
    tooltip: 'Write the current painting to a document',
    description:
        'Choose a destination the first time you save. Later saves write to '
        'the associated file.',
  );
  static const workspace = HelpTopic(
    title: 'Workspace selector',
    tooltip: 'Choose which workspace content is visible',
    description:
        'Canvas shows the painting surface. Canvas + tile diagnostics adds '
        'the developer diagnostics window over the canvas.',
  );
  static const touchTargets = HelpTopic(
    title: 'Touch target size',
    tooltip: 'Increase control size for touch use',
    description:
        'Switch between standard 48-pixel and enlarged 56-pixel interactive '
        'targets. The setting changes control hit areas without changing the '
        'document or painting.',
  );
  static const pickerUp = HelpTopic(
    title: 'Parent directory',
    tooltip: 'Browse the containing folder',
    description: 'Move to the current folder’s parent directory.',
  );
  static const pickerDirectory = HelpTopic(
    title: 'Folder',
    tooltip: 'Browse this folder',
    description: 'Open this folder to see its contents.',
  );
  static const pickerFile = HelpTopic(
    title: 'Document file',
    tooltip: 'Choose this document',
    description: 'Open this .paint document.',
  );
  static const pickerSaveFile = HelpTopic(
    title: 'Existing document name',
    tooltip: 'Use this document name',
    description:
        'Copy this file name into the save field. Confirming writes to that '
        'path.',
  );
  static const pickerFileName = HelpTopic(
    title: 'Document file name',
    tooltip: 'Enter a name for the saved document',
    description:
        'Type a file name. The .paint extension is added if it is missing.',
  );
  static const pickerSave = HelpTopic(
    title: 'Confirm save',
    tooltip: 'Save using the selected name',
    description: 'Confirm the file name and save the document.',
  );
  static const pickerCancel = HelpTopic(
    title: 'Cancel file selection',
    tooltip: 'Return without opening or saving',
    description: 'Close the picker without performing a file operation.',
  );
  static const dialogClose = HelpTopic(
    title: 'Close dialog',
    tooltip: 'Dismiss this dialog',
    description: 'Close the current dialog and return to the app.',
  );
  static const dialogDetails = HelpTopic(
    title: 'Error details',
    tooltip: 'Show or hide the error details',
    description: 'Expand the error details to inspect the operation failure.',
  );
  static const diagnostics = HelpTopic(
    title: 'Tile diagnostics',
    tooltip: 'Show tile-cache diagnostics',
    description:
        'Show or hide the diagnostics window for tile rendering and cache '
        'behavior. F3 toggles this workspace content.',
  );
  static const windowCollapse = HelpTopic(
    title: 'Collapse diagnostics window',
    tooltip: 'Hide or show diagnostic controls',
    description: 'Collapse the window contents or expand them again.',
  );
  static const windowClose = HelpTopic(
    title: 'Close diagnostics window',
    tooltip: 'Hide the diagnostics window',
    description: 'Hide the developer diagnostics without changing the canvas.',
  );
  static const debugSection = HelpTopic(
    title: 'Diagnostic section',
    tooltip: 'Expand or collapse this section',
    description: 'Show or hide the readouts and controls in this section.',
  );
  static const debugCheckbox = HelpTopic(
    title: 'Diagnostic option',
    tooltip: 'Change this diagnostic option',
    description:
        'Toggle this diagnostic setting. It affects the debug pane or canvas '
        'overlay, not the saved document.',
  );
  static const debugSlider = HelpTopic(
    title: 'Diagnostic limit',
    tooltip: 'Adjust this cache limit',
    description:
        'Drag the track or use accessible increase/decrease actions to change '
        'the diagnostic cache limit.',
  );
  static const debugAction = HelpTopic(
    title: 'Diagnostics action',
    tooltip: 'Run this diagnostic action',
    description:
        'Run the selected diagnostic action without changing the document.',
  );
  static const resetView = HelpTopic(
    title: 'Reset canvas view',
    tooltip: 'Return to the default canvas view',
    description: 'Reset pan, zoom, and rotation without changing the painting.',
  );
  static const rebuildTiles = HelpTopic(
    title: 'Rebuild cached tiles',
    tooltip: 'Discard cached images and rebuild them',
    description:
        'Invalidate cached tile images. The canvas document remains intact.',
  );
  static const copyReport = HelpTopic(
    title: 'Copy diagnostics report',
    tooltip: 'Copy the current diagnostic snapshot',
    description: 'Copy the current tile-cache report to the clipboard.',
  );
}

/// Tracks the currently hovered and keyboard-focused help topics.
class HelpState extends ChangeNotifier {
  HelpTopic? _hovered;
  HelpTopic? _focused;

  /// The hovered control takes precedence over the focused control.
  HelpTopic get activeTopic => _hovered ?? _focused ?? HelpTopics.general;

  /// Current pointer target, exposed for the F1 action and tests.
  HelpTopic? get hoveredTopic => _hovered;

  /// Updates the target under the pointer.
  void setHovered(HelpTopic? topic) {
    if (_hovered == topic) return;
    _hovered = topic;
    notifyListeners();
  }

  /// Updates the target receiving keyboard focus.
  void setFocused(HelpTopic? topic) {
    if (_focused == topic) return;
    _focused = topic;
    notifyListeners();
  }
}

/// Makes one [HelpState] available to controls in the app subtree.
class HelpScope extends InheritedNotifier<HelpState> {
  const HelpScope({
    super.key,
    required HelpState helpState,
    required super.child,
  }) : super(notifier: helpState);

  /// Returns the nearest help state, or null in standalone widget tests.
  static HelpState? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HelpScope>()?.notifier;
}

/// Adds a tooltip and registers pointer hover / keyboard focus for [topic].
class HelpTarget extends StatefulWidget {
  const HelpTarget({super.key, required this.topic, required this.child});

  final HelpTopic topic;
  final Widget child;

  @override
  State<HelpTarget> createState() => _HelpTargetState();
}

class _HelpTargetState extends State<HelpTarget> {
  HelpState? _help;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _help = HelpScope.maybeOf(context);
  }

  @override
  void didUpdateWidget(covariant HelpTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.topic != widget.topic) {
      if (_help?.hoveredTopic == oldWidget.topic) _help?.setHovered(null);
      _help?.setFocused(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.topic.tooltip,
      child: Focus(
        onFocusChange: (focused) =>
            _help?.setFocused(focused ? widget.topic : null),
        child: MouseRegion(
          onEnter: (_) => _help?.setHovered(widget.topic),
          onExit: (_) {
            if (_help?.hoveredTopic == widget.topic) _help?.setHovered(null);
          },
          child: widget.child,
        ),
      ),
    );
  }
}

/// Opens the in-app manual entry for [topic].
Future<void> showContextHelp(BuildContext context, HelpTopic topic) =>
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(topic.title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Text(topic.description),
        ),
        actions: [
          HelpTarget(
            topic: HelpTopics.dialogClose,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                minimumSize: Size(0, TouchTargetSettings.height(context)),
              ),
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close),
              label: const Text('Close'),
            ),
          ),
        ],
      ),
    );
