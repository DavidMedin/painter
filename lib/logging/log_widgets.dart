// What: The selectable Log pane, with its lowest-Severity filter, and the
//   always-visible latest-entry status bar.
// Why: The log model is kept independent from Flutter presentation while both
//   views observe the same ordered history from painter_log.dart. The filter
//   only hides rows in one pane; the history and the file keep every record
//   (docs/spec/logging.md LOG-8, LOG-22; docs/decisions/014-logging.md
//   PNT-A0020-07).
// Coupled to: painter_log.dart (records and notifications), pane_system.dart
//   (Log Pane Mode), ../workspace/workspace.dart (stores each pane's lowest
//   Severity), main.dart (application bottom bar), and contextual help.

import 'dart:convert';

import 'package:flutter/material.dart';

import '../help/contextual_help.dart';
import '../ui/touch_target.dart';

import 'painter_log.dart';

/// Shows the newest structured record in the application's bottom bar.
class LogStatusBar extends StatelessWidget {
  const LogStatusBar({super.key, required this.log});

  final PainterLog log;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: log,
    builder: (context, _) {
      final latest = log.entries.isEmpty ? null : log.entries.last;
      final theme = Theme.of(context);
      return Container(
        height: 32,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          border: Border(top: BorderSide(color: theme.colorScheme.outline)),
        ),
        child: Row(
          children: [
            Text(
              latest?.level.name.toUpperCase() ?? 'LOG',
              style: theme.textTheme.labelSmall?.copyWith(
                color: _levelColor(theme.colorScheme, latest?.level),
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Tooltip(
                message: latest?.message ?? '',
                child: Text(
                  latest?.message ?? 'No log entries',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
            if (latest != null) ...[
              const SizedBox(width: 10),
              Text(
                latest.timestamp.toLocal().toIso8601String(),
                style: theme.textTheme.labelSmall,
              ),
            ],
          ],
        ),
      );
    },
  );
}

/// Displays the records at or above [lowest] in file order, with the latest
/// item at the scroll bottom, under a control that selects [lowest].
class LogPane extends StatefulWidget {
  const LogPane({
    super.key,
    required this.log,
    this.lowest = PainterLogLevel.trace,
    this.onLowestChanged,
  });

  final PainterLog log;

  /// The lowest Severity listed (LOG-22); `trace` lists every record.
  final PainterLogLevel lowest;

  /// Called with the Severity the user selects; null disables the control.
  final ValueChanged<PainterLogLevel>? onLowestChanged;

  @override
  State<LogPane> createState() => _LogPaneState();
}

class _LogPaneState extends State<LogPane> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.log.addListener(_onLogChanged);
    _scrollToLatest();
  }

  @override
  void didUpdateWidget(covariant LogPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lowest != widget.lowest) _scrollToLatest();
    if (oldWidget.log == widget.log) return;
    oldWidget.log.removeListener(_onLogChanged);
    widget.log.addListener(_onLogChanged);
    _scrollToLatest();
  }

  @override
  void dispose() {
    widget.log.removeListener(_onLogChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onLogChanged() {
    setState(() {});
    _scrollToLatest();
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final lowest = widget.lowest;
    final entries = widget.log.entries;
    // Indices into the whole history, so a row keeps its key when the
    // filter changes.
    final shown = [
      for (var index = 0; index < entries.length; index++)
        if (entries[index].level.index >= lowest.index) index,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: HelpTarget(
            topic: HelpIds.logSeverity,
            child: Row(
              children: [
                const Flexible(
                  child: Text(
                    'Lowest severity',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<PainterLogLevel>(
                  key: const ValueKey('log-lowest-severity'),
                  value: lowest,
                  itemHeight: touchTargetHeight,
                  items: [
                    for (final level in PainterLogLevel.values)
                      DropdownMenuItem(
                        value: level,
                        child: Text(level.name.toUpperCase()),
                      ),
                  ],
                  onChanged: widget.onLowestChanged == null
                      ? null
                      : (level) {
                          if (level != null) widget.onLowestChanged!(level);
                        },
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: shown.isEmpty
              ? const Center(child: Text('No log entries'))
              : ListView.separated(
                  controller: _scrollController,
                  itemCount: shown.length,
                  itemBuilder: (context, row) =>
                      _entryTile(context, entries[shown[row]], shown[row]),
                  separatorBuilder: (context, row) => const Divider(height: 1),
                ),
        ),
      ],
    );
  }

  /// One expandable record row; [index] is its position in the history.
  Widget _entryTile(BuildContext context, PainterLogEntry entry, int index) {
    final color = _levelColor(Theme.of(context).colorScheme, entry.level);
    return HelpTarget(
      topic: HelpIds.logEntryDetails,
      child: ExpansionTile(
        key: ValueKey('log-entry-${entry.timestamp}-$index'),
        minTileHeight: touchTargetHeight,
        leading: Icon(Icons.circle, size: 10, color: color),
        title: Text(entry.message),
        subtitle: Text(
          '${entry.timestamp.toLocal().toIso8601String()} · '
          '${entry.level.name.toUpperCase()}',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          if (entry.arguments.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: SelectableText(
                'Arguments: ${jsonEncode(entry.arguments)}',
              ),
            ),
          if (entry.stackTrace != null)
            Align(
              alignment: Alignment.centerLeft,
              child: SelectableText(entry.stackTrace!),
            ),
        ],
      ),
    );
  }
}

Color _levelColor(ColorScheme colors, PainterLogLevel? level) =>
    switch (level) {
      PainterLogLevel.trace || PainterLogLevel.debug => colors.onSurfaceVariant,
      PainterLogLevel.info || null => colors.primary,
      PainterLogLevel.warn => colors.tertiary,
      PainterLogLevel.error => colors.error,
    };
