import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A small widget kit that imitates the look and feel of Dear ImGui: a dense,
/// flat, monospace UI made of draggable windows, collapsible tree headers, and
/// one-line widgets (label/value rows, checkboxes, sliders, buttons, plots).
///
/// Nothing here knows about the painter; it is reusable by any debug tool.
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

/// A floating, draggable, collapsible, resizable-width tool window.
///
/// Place it inside a [Stack]; it positions itself with its own offset and moves
/// when its title bar is dragged. Collapse by tapping the arrow or
/// double-tapping the title bar.
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

  /// Content scrolls beyond this height; null fits the content to the screen.
  final double? maxHeight;
  final VoidCallback? onClose;

  @override
  State<ImWindow> createState() => _ImWindowState();
}

class _ImWindowState extends State<ImWindow> {
  late Offset _offset = widget.initialOffset;
  bool _collapsed = false;

  // Size of the area the window floats in, from the latest layout. Dragging
  // clamps against it so the stored offset never drifts off screen.
  Size _bounds = Size.infinite;

  /// Keeps the whole title bar (and its close button) inside [bounds], even
  /// after the window or its container is resized. A window wider than its
  /// container is pinned to the left edge.
  Offset _clamped(Offset offset, Size bounds) {
    final maxX = bounds.width.isFinite
        ? math.max(0.0, bounds.width - widget.width)
        : double.infinity;
    final maxY = bounds.height.isFinite
        ? math.max(0.0, bounds.height - (ImTheme.rowHeight + 2))
        : double.infinity;
    return Offset(
      offset.dx.clamp(0.0, maxX).toDouble(),
      offset.dy.clamp(0.0, maxY).toDouble(),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Fill the parent Stack so we can measure it, then place the window inside.
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, box) {
          _bounds = box.biggest;
          final position = _clamped(_offset, _bounds);
          final maxHeight =
              widget.maxHeight ??
              math.max(80.0, _bounds.height - position.dy - ImTheme.rowHeight);
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

  Widget _titleBar() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (d) =>
          setState(() => _offset = _clamped(_offset + d.delta, _bounds)),
      child: Container(
        height: ImTheme.rowHeight + 2,
        color: _collapsed ? ImTheme.titleBg : ImTheme.titleActive,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            InkWell(
              onTap: () => setState(() => _collapsed = !_collapsed),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  _collapsed ? Icons.arrow_right : Icons.arrow_drop_down,
                  size: 16,
                  color: ImTheme.text,
                  semanticLabel: _collapsed
                      ? 'Expand window'
                      : 'Collapse window',
                ),
              ),
            ),
            Expanded(
              // Double-tap lives here only: a recognizer on the whole bar would
              // delay the arrow's and close button's single taps.
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTap: () => setState(() => _collapsed = !_collapsed),
                child: Text(widget.title, overflow: TextOverflow.ellipsis),
              ),
            ),
            if (widget.onClose != null)
              InkWell(
                onTap: widget.onClose,
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(
                    Icons.close,
                    size: 14,
                    color: ImTheme.text,
                    semanticLabel: 'Close window',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A collapsible `CollapsingHeader` / `TreeNode`. State survives rebuilds.
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
        MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _open = !_open),
            child: Semantics(
              button: true,
              expanded: _open,
              label: widget.title,
              excludeSemantics: true,
              child: Container(
                height: ImTheme.rowHeight,
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

/// `LabelText`: dim label on the left, value on the right.
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

/// `Checkbox`.
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
    return Semantics(
      label: widget.label,
      checked: widget.value,
      onTap: () => widget.onChanged(!widget.value),
      excludeSemantics: true,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onChanged(!widget.value),
          child: SizedBox(
            height: ImTheme.rowHeight,
            child: Row(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  margin: const EdgeInsets.only(right: 6),
                  color: _hover ? ImTheme.frameHover : ImTheme.frameBg,
                  child: widget.value
                      ? const Icon(Icons.check, size: 12, color: ImTheme.accent)
                      : null,
                ),
                Expanded(
                  child: Text(widget.label, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `Button`.
class ImButton extends StatefulWidget {
  const ImButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  State<ImButton> createState() => _ImButtonState();
}

class _ImButtonState extends State<ImButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Semantics(
        button: true,
        enabled: enabled,
        label: widget.label,
        onTap: widget.onPressed,
        excludeSemantics: true,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            child: Container(
              height: ImTheme.rowHeight,
              alignment: Alignment.center,
              color: !enabled
                  ? ImTheme.frameBg
                  : _hover
                  ? ImTheme.headerHover
                  : ImTheme.header,
              child: Text(
                widget.label,
                style: enabled ? ImTheme.style : ImTheme.dim,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `SliderInt`: a labelled, draggable integer slider that also responds to
/// arrow keys when focused. [value] is clamped to `[min, max]`.
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

  int _at(double dx, double width) {
    final t = (dx / width).clamp(0.0, 1.0);
    return (widget.min + t * (widget.max - widget.min)).round();
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value.clamp(widget.min, widget.max);
    final span = math.max(1, widget.max - widget.min);
    return Semantics(
      label: widget.label,
      value: '$value',
      slider: true,
      increasedValue: '${math.min(widget.max, value + 1)}',
      decreasedValue: '${math.max(widget.min, value - 1)}',
      onIncrease: value < widget.max ? () => widget.onChanged(value + 1) : null,
      onDecrease: value > widget.min ? () => widget.onChanged(value - 1) : null,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
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
                      onTapDown: (d) => widget.onChanged(
                        _at(d.localPosition.dx, box.maxWidth),
                      ),
                      onHorizontalDragUpdate: (d) => widget.onChanged(
                        _at(d.localPosition.dx, box.maxWidth),
                      ),
                      child: Container(
                        height: ImTheme.rowHeight - 2,
                        color: _hover ? ImTheme.frameHover : ImTheme.frameBg,
                        child: Stack(
                          children: [
                            Positioned(
                              left: 0,
                              top: 0,
                              bottom: 0,
                              width: box.maxWidth * (value - widget.min) / span,
                              child: const ColoredBox(color: ImTheme.header),
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
    );
  }
}

/// `PlotLines`: a sparkline of recent samples with min/avg/max readout.
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

  @override
  bool shouldRepaint(_PlotPainter old) => true;
}

/// A single-line horizontal stacked bar (`ProgressBar` with segments); each
/// segment is `(fraction weight, color, label)` and the bar is normalised.
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

/// Copies [text] to the system clipboard (used by "Copy report" buttons).
Future<void> imCopy(String text) =>
    Clipboard.setData(ClipboardData(text: text));
