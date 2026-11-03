// What: A small widget kit that imitates Dear ImGui's look: ImTheme, ImWindow,
//   ImSection, ImValue, ImText, ImSeparator, ImCheckbox, ImButton,
//   ImSliderInt, ImPlot, ImStackedBar (with ImSegment), ImLegend, and imCopy.
//   This file is also where the kit's system overview lives (below).
// Why: The debug pane (canvas_debug_pane.dart) wants a dense, flat,
//   monospace "immediate-mode look" (ADR 0006). The ADR chose to write it
//   as plain Flutter widgets with no new dependency, in a file that knows
//   nothing about the painter. Keeping the kit apart from the pane keeps the
//   pane file about *what* is shown and this file about *how* it looks.
//   Only canvas_debug_pane.dart and tile_overlay.dart (for colors) import it.
//
// ---------------------------------------------------------------------------
// OVERVIEW: the ImGui-style widget kit
// ---------------------------------------------------------------------------
// What it is: a set of ordinary retained Flutter widgets that look like Dear
//   ImGui: a flat, monospace, dark, dense UI. It has a floating window
//   (ImWindow) with a title bar that drags, collapses, and optionally closes;
//   tree-style collapsible sections (ImSection); one-line widgets (ImValue
//   label/value rows, ImText, ImSeparator, ImCheckbox, ImButton, ImSliderInt);
//   and small visualisations (ImPlot line plot, ImStackedBar + ImLegend).
//
// Why it exists: ADR 0006 wanted the tile cache's internals visible in the
//   running app in an "immediate-mode look". The ADR states the kit is NOT an
//   immediate-mode engine and takes no dependency: it is written with
//   ordinary Flutter widgets, which rebuild normally. The ADR does not record
//   why an existing package or stock Material widgets were not used.
//
// How it works:
//   - Retained, not immediate: the caller builds a normal widget tree every
//     time its state changes. The kit keeps only UI state (window offset and
//     collapsed flag, section open flag, hover flags). Values, checkbox
//     states, and slider positions are owned by the caller and passed in; a
//     widget reports changes through onChanged / onPressed.
//   - Windows: ImWindow fills its parent Stack to measure it, then places a
//     fixed-width panel at a stored offset. Dragging the title bar updates the
//     offset, always clamped so the whole title bar (and close button) stays
//     inside the container, even after the container is resized. Content is a
//     SingleChildScrollView limited by maxHeight.
//   - Sections: ImSection keeps its open flag in State, so it survives parent
//     rebuilds (the pane rebuilds every refresh).
//   - Plots: ImPlot paints the samples with a CustomPainter, scaled to the
//     largest sample unless scaleMax is given, and prints min/avg/max under
//     it. ImStackedBar normalises its segments' weights into flex widths.
//   - Accessibility: each widget wraps itself in Semantics with a text label
//     (windows, buttons, checkbox, slider increase/decrease, plot summary), so
//     widget tests can find controls by label.
//   - Painter-agnostic: nothing here imports the canvas or painter code. The
//     only coupling is by callers: canvas_debug_pane.dart composes these
//     widgets, and tile_overlay.dart borrows ImTheme colors so overlay tints
//     match the pane's legend.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../help/contextual_help.dart';
import '../ui/painter_action_button.dart';
import '../ui/touch_target_settings.dart';

/// Colors, metrics, and the shared monospace [TextStyle] of the kit. Every
/// widget in this file reads its look from here, so restyling the kit means
/// editing only this class. [good], [warn], and [bad] are also used by callers
/// for value coloring (canvas_debug_pane.dart) and by `tileDrawColor` in
/// tile_overlay.dart.
class ImTheme {
  const ImTheme._();

  static const Color windowBg = Color(0xF0151518);
  static const Color titleBg = Color(0xFF0A0A0C);
  static const Color titleActive = Color(0xFF29477A);
  static const Color border = Color(0xFF6E6E80);
  static const Color header = Color(0xFF2F4F80);
  static const Color headerHover = Color(0xFF3D6CB3);
  static const Color frameBg = Color(0xFF29292E);
  static const Color frameHover = Color(0xFF3B5E96);
  static const Color accent = Color(0xFF4296FA);
  static const Color text = Color(0xFFF2F2F2);
  static const Color textDim = Color(0xFF8A8A92);
  static const Color good = Color(0xFF6BD66B);
  static const Color warn = Color(0xFFF2C14E);
  static const Color bad = Color(0xFFF26B5E);
  static const Color plot = Color(0xFF9C7BE8);

  static const double rowHeight = 20;
  static const double padding = 6;
  static const String fontFamily = 'Menlo';
  static const List<String> fontFallback = [
    'Monaco',
    'Courier New',
    'monospace',
  ];

  static const TextStyle style = TextStyle(
    color: text,
    fontSize: 12,
    height: 1.2,
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallback,
    decoration: TextDecoration.none,
    fontWeight: FontWeight.normal,
  );

  static TextStyle get dim => style.copyWith(color: textDim);
}

/// A floating, draggable, collapsible tool window of fixed [width].
///
/// Place it inside a [Stack]; it positions itself with its own offset and moves
/// when its title bar is dragged, staying inside the Stack's bounds. Collapse
/// by tapping the arrow or double-tapping the title text. The title bar's
/// gesture layout (and why the double-tap recognizer is on the text only) is
/// explained in [_ImWindowState._titleBar].
class ImWindow extends StatefulWidget {
  const ImWindow({
    super.key,
    required this.title,
    required this.children,
    this.initialOffset = const Offset(12, 12),
    this.width = 320,
    this.maxHeight,
    this.onClose,
  });

  final String title;
  final List<Widget> children;
  final Offset initialOffset;
  final double width;

  /// Content scrolls beyond this height. When null the window uses the room
  /// left in its container below the window's top edge (at least 80 logical
  /// pixels), so a tall pane scrolls instead of running off screen.
  final double? maxHeight;

  /// When non-null a close button is shown in the title bar and calls this.
  /// The window does not hide itself; the owner removes it from the tree
  /// (see CanvasDebugPane.onClose, wired to the Diagnostics workspace and F3
  /// shortcut in lib/main.dart).
  final VoidCallback? onClose;

  @override
  State<ImWindow> createState() => _ImWindowState();
}

class _ImWindowState extends State<ImWindow> {
  late Offset _offset = widget.initialOffset;
  bool _collapsed = false;

  // Size of the area the window floats in, from the latest layout. Dragging
  // clamps against it so the stored offset never drifts off screen. Starts
  // infinite (no clamping) until the first layout measures the container.
  Size _bounds = Size.infinite;

  /// Keeps the whole title bar (and its close button) inside [bounds], even
  /// after the window or its container is resized. A window wider than its
  /// container is pinned to the left edge.
  Offset _clamped(Offset offset, Size bounds, double titleBarHeight) {
    final maxX = bounds.width.isFinite
        ? math.max(0.0, bounds.width - widget.width)
        : double.infinity;
    final maxY = bounds.height.isFinite
        ? math.max(0.0, bounds.height - titleBarHeight)
        : double.infinity;
    return Offset(
      offset.dx.clamp(0.0, maxX).toDouble(),
      offset.dy.clamp(0.0, maxY).toDouble(),
    );
  }

  /// Fills the parent [Stack] (Positioned.fill + LayoutBuilder) purely to
  /// learn its size, then places the window inside it at the clamped offset.
  /// The measured size is kept in [_bounds] so drag updates clamp against the
  /// same area that was last laid out.
  @override
  Widget build(BuildContext context) {
    // Fill the parent Stack so we can measure it, then place the window inside.
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, box) {
          _bounds = box.biggest;
          final titleBarHeight = TouchTargetSettings.height(context) + 2;
          final position = _clamped(_offset, _bounds, titleBarHeight);
          final maxHeight =
              widget.maxHeight ??
              math.max(80.0, _bounds.height - position.dy - titleBarHeight);
          return Stack(
            children: [
              Positioned(
                left: position.dx,
                top: position.dy,
                width: widget.width,
                child: _window(maxHeight),
              ),
            ],
          );
        },
      ),
    );
  }

  /// The visible panel: border, title bar, and (unless collapsed) a scrollable
  /// content column capped at [maxHeight]. When collapsed the children are not
  /// built at all, which discards the State of widgets inside (see
  /// [ImSection]).
  Widget _window(double maxHeight) {
    return Semantics(
      label: 'Debug window ${widget.title}',
      container: true,
      child: Container(
        decoration: BoxDecoration(
          color: ImTheme.windowBg,
          border: Border.all(color: ImTheme.border.withValues(alpha: 0.5)),
        ),
        child: DefaultTextStyle(
          style: ImTheme.style,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _titleBar(),
              if (!_collapsed)
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxHeight),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(ImTheme.padding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: widget.children,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Title bar: shared action buttons, a drag handle, and a double-tap title.
  ///
  /// Dragging uses the whole bar (onPanUpdate, clamped by [_clamped]). The
  /// collapse and close actions use [PainterActionButton]; double-tap is
  /// attached only to the title text so single taps on the actions are not
  /// delayed by the gesture recognizer (ADR 0006, Consequences).
  Widget _titleBar() {
    final targetHeight = TouchTargetSettings.height(context);
    final titleBarHeight = targetHeight + 2;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (d) => setState(
        () => _offset = _clamped(_offset + d.delta, _bounds, titleBarHeight),
      ),
      child: Container(
        height: titleBarHeight,
        color: _collapsed ? ImTheme.titleBg : ImTheme.titleActive,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            PainterActionButton(
              icon: _collapsed ? Icons.expand_more : Icons.expand_less,
              label: _collapsed ? 'Expand' : 'Collapse',
              topic: HelpTopics.windowCollapse,
              background: ImTheme.titleBg,
              foreground: ImTheme.text,
              minimumHeight: targetHeight,
              onPressed: () => setState(() => _collapsed = !_collapsed),
            ),
            Expanded(
              child: HelpTarget(
                topic: HelpTopics.diagnostics,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onDoubleTap: () => setState(() => _collapsed = !_collapsed),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(widget.title, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ),
            ),
            if (widget.onClose != null)
              PainterActionButton(
                icon: Icons.close,
                label: 'Close',
                topic: HelpTopics.windowClose,
                background: ImTheme.titleBg,
                foreground: ImTheme.text,
                minimumHeight: targetHeight,
                onPressed: widget.onClose,
              ),
          ],
        ),
      ),
    );
  }
}

/// A collapsible `CollapsingHeader` / `TreeNode`. State survives rebuilds.
///
/// The open flag lives in this widget's State, so the pane's periodic
/// rebuilds (canvas_debug_pane.dart) do not reset it. It does NOT survive
/// the enclosing [ImWindow] being collapsed: a collapsed window drops its
/// content subtree, so sections inside restart at [initiallyOpen] when the
/// window is expanded again.
class ImSection extends StatefulWidget {
  const ImSection({
    super.key,
    required this.title,
    required this.children,
    this.initiallyOpen = true,
  });

  final String title;
  final List<Widget> children;
  final bool initiallyOpen;

  @override
  State<ImSection> createState() => _ImSectionState();
}

class _ImSectionState extends State<ImSection> {
  late bool _open = widget.initiallyOpen;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HelpTarget(
          topic: HelpTopics.debugSection,
          child: Semantics(
            button: true,
            expanded: _open,
            label: widget.title,
            onTap: () => setState(() => _open = !_open),
            excludeSemantics: true,
            child: MouseRegion(
              onEnter: (_) => setState(() => _hover = true),
              onExit: (_) => setState(() => _hover = false),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => setState(() => _open = !_open),
                  child: Container(
                    height: TouchTargetSettings.height(context),
                    margin: const EdgeInsets.only(top: 3),
                    color: _hover ? ImTheme.headerHover : ImTheme.header,
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Row(
                      children: [
                        Icon(
                          _open ? Icons.arrow_drop_down : Icons.arrow_right,
                          size: 16,
                          color: ImTheme.text,
                        ),
                        Expanded(
                          child: Text(
                            widget.title,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 2, bottom: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: widget.children,
            ),
          ),
      ],
    );
  }
}

/// `LabelText`: dim label on the left, value on the right. [color] tints only
/// the value (the pane uses it for threshold coloring, e.g. `_budget`).
class ImValue extends StatelessWidget {
  const ImValue(this.label, this.value, {super.key, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: SizedBox(
        height: ImTheme.rowHeight - 2,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: ImTheme.dim,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(value, style: ImTheme.style.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}

/// A plain text line (`Text` / `TextDisabled` / `TextColored`).
class ImText extends StatelessWidget {
  const ImText(this.text, {super.key, this.color, this.dim = false});

  final String text;
  final Color? color;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final base = dim ? ImTheme.dim : ImTheme.style;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Text(
        text,
        style: color == null ? base : base.copyWith(color: color),
      ),
    );
  }
}

/// A thin horizontal rule (`Separator`).
class ImSeparator extends StatelessWidget {
  const ImSeparator({super.key});

  @override
  Widget build(BuildContext context) => Container(
    height: 1,
    margin: const EdgeInsets.symmetric(vertical: 4),
    color: ImTheme.border.withValues(alpha: 0.4),
  );
}

/// `Checkbox`. Stateless about its value: shows [value] and reports the
/// toggled value through [onChanged]; the caller stores it (the pane stores
/// overlay switches in `CanvasDebugOptions`).
class ImCheckbox extends StatefulWidget {
  const ImCheckbox({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  State<ImCheckbox> createState() => _ImCheckboxState();
}

class _ImCheckboxState extends State<ImCheckbox> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return HelpTarget(
      topic: HelpTopics.debugCheckbox,
      child: Semantics(
        label: widget.label,
        checked: widget.value,
        onTap: () => widget.onChanged(!widget.value),
        excludeSemantics: true,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => widget.onChanged(!widget.value),
              child: SizedBox(
                height: TouchTargetSettings.height(context),
                child: Row(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      margin: const EdgeInsets.only(right: 8),
                      color: _hover ? ImTheme.frameHover : ImTheme.frameBg,
                      child: widget.value
                          ? const Icon(
                              Icons.check,
                              size: 16,
                              color: ImTheme.accent,
                            )
                          : null,
                    ),
                    Expanded(
                      child: Text(
                        widget.label,
                        overflow: TextOverflow.ellipsis,
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

/// A labelled action with the shared help, focus, and touch-target behavior.
class ImButton extends StatelessWidget {
  const ImButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.play_arrow,
    this.topic = HelpTopics.debugAction,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData icon;
  final HelpTopic topic;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: PainterActionButton(
      icon: icon,
      label: label,
      topic: topic,
      background: ImTheme.header,
      foreground: ImTheme.text,
      onPressed: onPressed,
    ),
  );
}

/// A labelled, draggable integer slider. Tapping or dragging reports the
/// value at the pointer through [onChanged]; [value] is clamped to [min] and
/// [max] for display. Arrow keys and semantic increase/decrease actions step
/// by one, and callers feed changes back through [value].
class ImSliderInt extends StatefulWidget {
  const ImSliderInt({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  State<ImSliderInt> createState() => _ImSliderIntState();
}

class _ImSliderIntState extends State<ImSliderInt> {
  bool _hover = false;
  bool _focused = false;
  final FocusNode _focusNode = FocusNode(debugLabel: 'Diagnostic slider');

  /// Maps a pointer x offset within a track [width] pixels wide to a value in
  /// `[min, max]`: position as a fraction, clamped, then rounded to an int.
  int _at(double dx, double width) {
    final t = (dx / width).clamp(0.0, 1.0);
    return (widget.min + t * (widget.max - widget.min)).round();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value.clamp(widget.min, widget.max);
    final span = math.max(1, widget.max - widget.min);
    final targetHeight = TouchTargetSettings.height(context);
    return HelpTarget(
      topic: HelpTopics.debugSlider,
      child: Focus(
        focusNode: _focusNode,
        onFocusChange: (focused) => setState(() => _focused = focused),
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
            return KeyEventResult.ignored;
          }
          final delta = switch (event.logicalKey) {
            LogicalKeyboardKey.arrowLeft || LogicalKeyboardKey.arrowDown => -1,
            LogicalKeyboardKey.arrowRight || LogicalKeyboardKey.arrowUp => 1,
            _ => 0,
          };
          if (delta == 0) return KeyEventResult.ignored;
          widget.onChanged((value + delta).clamp(widget.min, widget.max));
          return KeyEventResult.handled;
        },
        child: Semantics(
          label: widget.label,
          value: '$value',
          slider: true,
          increasedValue: '${math.min(widget.max, value + 1)}',
          decreasedValue: '${math.max(widget.min, value - 1)}',
          onIncrease: value < widget.max
              ? () => widget.onChanged(value + 1)
              : null,
          onDecrease: value > widget.min
              ? () => widget.onChanged(value - 1)
              : null,
          excludeSemantics: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: SizedBox(
              height: targetHeight,
              child: Row(
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, box) {
                        return MouseRegion(
                          onEnter: (_) => setState(() => _hover = true),
                          onExit: (_) => setState(() => _hover = false),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapDown: (d) {
                              _focusNode.requestFocus();
                              widget.onChanged(
                                _at(d.localPosition.dx, box.maxWidth),
                              );
                            },
                            onHorizontalDragUpdate: (d) => widget.onChanged(
                              _at(d.localPosition.dx, box.maxWidth),
                            ),
                            child: Container(
                              height: targetHeight,
                              color: _hover || _focused
                                  ? ImTheme.frameHover
                                  : ImTheme.frameBg,
                              child: Stack(
                                children: [
                                  Positioned(
                                    left: 0,
                                    top: 0,
                                    bottom: 0,
                                    width:
                                        box.maxWidth *
                                        (value - widget.min) /
                                        span,
                                    child: const ColoredBox(
                                      color: ImTheme.header,
                                    ),
                                  ),
                                  Center(child: Text('$value')),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 110,
                    child: Text(widget.label, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `PlotLines`: a sparkline of recent samples with min/avg/max readout.
///
/// The y axis always starts at 0 and ends at [scaleMax], or at the largest
/// sample when [scaleMax] is null (floored at 1e-6 to avoid dividing by
/// zero). Samples are copied out of [samples] on each build, so a live queue
/// such as `TiledRenderer.recordHistory` would be safe to pass, but the pane
/// passes frozen copies (see `_Reading` in canvas_debug_pane.dart).
class ImPlot extends StatelessWidget {
  const ImPlot({
    super.key,
    required this.label,
    required this.samples,
    this.unit = '',
    this.height = 44,
    this.scaleMax,
  });

  final String label;
  final Iterable<double> samples;
  final String unit;
  final double height;

  /// Fixed upper bound of the y axis; defaults to the largest sample.
  final double? scaleMax;

  @override
  Widget build(BuildContext context) {
    final data = samples.toList(growable: false);
    var min = 0.0, max = 0.0, sum = 0.0;
    if (data.isNotEmpty) {
      min = data.reduce(math.min);
      max = data.reduce(math.max);
      sum = data.fold(0.0, (a, b) => a + b);
    }
    final avg = data.isEmpty ? 0.0 : sum / data.length;
    String f(double v) => '${v.toStringAsFixed(v < 10 ? 2 : 1)}$unit';
    return Semantics(
      label: label,
      value: data.isEmpty
          ? 'no samples'
          : 'min ${f(min)}, avg ${f(avg)}, max ${f(max)}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: height,
              color: ImTheme.frameBg,
              child: CustomPaint(
                painter: _PlotPainter(data, scaleMax ?? math.max(max, 1e-6)),
              ),
            ),
            Text(
              data.isEmpty
                  ? '$label  (no samples)'
                  : '$label  min ${f(min)}  avg ${f(avg)}  max ${f(max)}',
              style: ImTheme.dim,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// Paints [ImPlot]'s line: [data] spread evenly across the width, y scaled so
/// [top] sits near the top edge and 0 at the bottom (2 px margin each side).
/// Values above [top] are clamped to the top. Draws nothing for fewer than two
/// samples, since a line needs two points.
class _PlotPainter extends CustomPainter {
  _PlotPainter(this.data, this.top);

  final List<double> data;
  final double top;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;
    final path = Path();
    for (var i = 0; i < data.length; i++) {
      final x = size.width * i / (data.length - 1);
      final y =
          size.height - 2 - (size.height - 4) * (data[i] / top).clamp(0.0, 1.0);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = ImTheme.plot,
    );
  }

  // Always repaints: every ImPlot build creates a new painter over a fresh
  // sample list, and no content comparison is done.
  @override
  bool shouldRepaint(_PlotPainter old) => true;
}

/// A single-line horizontal stacked bar (`ProgressBar` with segments). The
/// weights of [segments] are normalised, so they need not sum to 1.
///
/// Each positive-weight segment becomes an [Expanded] with flex proportional
/// to its share (scaled by 1000 and rounded, at least 1, so a nonzero segment
/// never gets zero width). Zero-weight segments are skipped and an all-zero
/// bar is an empty frame. Labels are exposed through Semantics only; pair the
/// bar with an [ImLegend] or [ImValue] rows to show them (the pane's "Visible
/// tiles" section uses [ImValue] rows).
class ImStackedBar extends StatelessWidget {
  const ImStackedBar({super.key, required this.segments, this.height = 12});

  final List<ImSegment> segments;
  final double height;

  @override
  Widget build(BuildContext context) {
    final total = segments.fold<double>(0, (a, s) => a + s.weight);
    return Semantics(
      label: segments.map((s) => '${s.label} ${s.weight.round()}').join(', '),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Container(
          height: height,
          color: ImTheme.frameBg,
          child: total <= 0
              ? null
              : Row(
                  children: [
                    for (final s in segments)
                      if (s.weight > 0)
                        Expanded(
                          flex: math.max(1, (s.weight / total * 1000).round()),
                          child: ColoredBox(color: s.color),
                        ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// One slice of an [ImStackedBar]: [weight] is a relative size (any positive
/// scale; the bar normalises), [color] fills the slice, and [label] is used
/// only for the bar's accessibility description, not drawn.
class ImSegment {
  const ImSegment(this.weight, this.color, this.label);

  final double weight;
  final Color color;
  final String label;
}

/// A color swatch + label, for legends.
class ImLegend extends StatelessWidget {
  const ImLegend(this.entries, {super.key});

  final List<(Color, String)> entries;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 2,
      children: [
        for (final (color, label) in entries)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 8, height: 8, color: color),
              const SizedBox(width: 4),
              Text(label, style: ImTheme.dim),
            ],
          ),
      ],
    );
  }
}

/// Copies [text] to the system clipboard. Its only caller is the pane's
/// "Copy report" button (`_CanvasDebugPaneState._copyReport`).
Future<void> imCopy(String text) =>
    Clipboard.setData(ClipboardData(text: text));
