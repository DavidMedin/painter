// What: The message-id catalog and formatter used to render Painter log records.
// Why: Log records store stable ids and arguments rather than prose so wording
//   changes and future translations do not require rewriting the log history.
// Coupled to: painter_log.dart (record ids), log_widgets.dart (presentation),
//   and docs/decisions/0014-file-backed-logging.md.

/// Templates for user-facing log messages, keyed by stable record id.
abstract final class LogMessages {
  static const Map<String, String> templates = {
    'app.started': 'Painter started.',
    'settings.load.failed': 'Could not load settings: {error}',
    'document.operation.failed':
        'Failed to {operation} Painter document: {error}',
    'flutter.framework.error': 'Flutter framework error: {error}',
    'error.unhandled': 'Unhandled application error: {error}',
    'log.file.invalid_entries':
        'Skipped {count} malformed log record(s) while loading.',
  };

  /// Resolves placeholders from [arguments], leaving unknown ids visible.
  static String format(String messageId, Map<String, Object?> arguments) {
    final template = templates[messageId];
    if (template == null) return '[$messageId]';
    return template.replaceAllMapped(RegExp(r'\{([^{}]+)\}'), (match) {
      final key = match[1]!;
      return arguments.containsKey(key) ? '${arguments[key]}' : match[0]!;
    });
  }
}
