// What: HelpState and HelpTarget expose stable manual ids to controls and F1.
// Why: docs/design/controls/behavior.md requires help to follow the hovered
//   interactive control. Article text and navigation live centrally in
//   manual_catalog.dart.
// Coupled to: manual_catalog.dart (ids and tooltips), manual_pane.dart (pages),
//   and lib/main.dart (owns state and routes F1 to the pane system).
//
// ---------------------------------------------------------------------------
// Contextual help overview
// ---------------------------------------------------------------------------
// HelpTarget reports pointer hover and keyboard focus to one HelpState. F1
// selects the hovered id first, then the focused id, then general help. Each
// target gets its tooltip from the central manual catalog.
// ---------------------------------------------------------------------------

import 'package:flutter/material.dart';

import 'manual_catalog.dart';
export 'manual_catalog.dart' show HelpId, HelpIds;

class HelpState extends ChangeNotifier {
  HelpId? _hovered;
  HelpId? _focused;

  /// The hovered control takes precedence over the focused control.
  HelpId get activeTopic => _hovered ?? _focused ?? HelpId.general;

  /// Current pointer target, exposed for the F1 action and tests.
  HelpId? get hoveredTopic => _hovered;

  /// Updates the target under the pointer.
  void setHovered(HelpId? topic) {
    if (_hovered == topic) return;
    _hovered = topic;
    notifyListeners();
  }

  /// Updates the target receiving keyboard focus.
  void setFocused(HelpId? topic) {
    if (_focused == topic) return;
    _focused = topic;
    notifyListeners();
  }
}

/// Adds a catalog tooltip and registers hover and keyboard focus for [topic].
class HelpTarget extends StatefulWidget {
  const HelpTarget({super.key, required this.topic, required this.child});

  final HelpId topic;
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
      message: ManualCatalog.article(widget.topic).tooltip,
      child: Focus(
        onFocusChange: (focused) =>
            _help?.setFocused(focused ? widget.topic : null),
        child: MouseRegion(
          onEnter: (_) => _help?.setHovered(widget.topic),
          onExit: (_) {
            if (_help?.hoveredTopic == widget.topic) {
              _help?.setHovered(null);
            }
          },
          child: widget.child,
        ),
      ),
    );
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
