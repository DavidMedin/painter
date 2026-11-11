// What: The message-id catalog and formatter used to render Painter log records.
// Why: Log records store stable ids and arguments rather than prose so wording
//   changes and future translations do not require rewriting the log history.
// Coupled to: painter_log.dart (record ids), log_widgets.dart (presentation),
//   docs/spec/logging.md, and docs/decisions/014-logging.md (id rules: an id
//   is never removed or given another meaning).

/// Templates for user-facing log messages, keyed by stable record id.
abstract final class LogMessages {
  static const Map<String, String> templates = {
    'app.started': 'Painter started.',
    'app.quit': 'Painter is quitting.',
    'settings.load.failed': 'Could not load settings: {error}',
    'settings.load.invalid':
        'Used a default in place of stored settings: '
        '{problem}.',
    'settings.persistence.failed': 'Could not save settings: {error}',
    'settings.change.succeeded': 'Changed setting {setting} to {value}.',
    'document.operation.failed':
        'Failed to {operation} Painter document: {error}',
    'document.open.succeeded': 'Opened {path}.',
    'document.open.cancelled': 'Open was cancelled.',
    'document.save.succeeded': 'Saved {path}.',
    'document.save.cancelled': 'Save was cancelled.',
    'document.flash.succeeded': 'Flashed the layout into {path}.',
    'document.strokes.unreadable':
        'Deleted {count} unreadable stroke(s) received from {source}.',
    'document.picker.list_failed': 'Could not list {path}: {error}',
    'document.stroke.finished': 'Finished a stroke of {chunks} chunk(s).',
    'document.undo.succeeded': 'Undid a stroke.',
    'document.redo.succeeded': 'Redid a stroke.',
    'workspace.stored.unusable':
        'Ignored the stored workspace of {source}: it cannot be read in full '
        'or names a pane mode or state this build does not have.',
    'workspace.pane.added': 'Added a {mode} pane.',
    'workspace.pane.joined': 'Joined two panes.',
    'workspace.pane.swapped': 'Swapped two panes.',
    'workspace.pane.opened': 'Showed a {mode} pane.',
    'workspace.mode.changed': 'Changed a pane to {mode}.',
    'workspace.splitter.moved': 'Moved a pane boundary.',
    'workspace.join.succeeded': 'Joined the workspace of {participant}.',
    'workspace.leave.succeeded': 'Left the joined workspace.',
    'splat.worker.failed': 'Could not generate canvas splats: {error}',
    'session.operation.failed': 'Could not {operation}: {error}',
    'session.start.succeeded': 'Started a session at {addresses}.',
    'session.start.cancelled': 'Start session was cancelled.',
    'session.join.succeeded': 'Joined the session at {address}.',
    'session.join.refused': 'Refused {participant} joining: {reason}.',
    'session.leave.succeeded': 'Left the session.',
    'session.promote.succeeded': 'Made {participant} the host.',
    'session.participant.joined': '{participant} joined the session.',
    'session.participant.left': '{participant} left the session.',
    'session.participant.timed_out':
        'Heard nothing from {participant} for {seconds} seconds; treating '
        'them as gone.',
    'session.host.changed': '{participant} is now the host.',
    'session.message.malformed':
        'Dropped the connection to {participant} after a malformed message: '
        '{error}',
    'session.connection.failed': 'Could not accept a connection: {error}',
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
