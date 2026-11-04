// What: Structured log entries, severity levels, and the append-only log store.
// Why: Logging is a shared application service: calls retain message ids and
//   arguments, persist JSONL records, and can optionally render to stdout.
// Coupled to: log_messages.dart (message ids), flutter_log_handlers.dart (global
//   error routing), log_widgets.dart (observable history), and main.dart.
//
// ---------------------------------------------------------------------------
// Logging system overview
//
// Every record contains a UTC timestamp, severity, catalog message id,
// formatting arguments, and optional stack text. The catalog in
// log_messages.dart owns all prose; the JSONL file therefore remains structured
// and can be re-rendered after wording changes. The store loads existing rows
// before the app starts, then appends each new row in order. A serialized write
// tail prevents asynchronous file writes from reordering records. The in-memory
// list is updated synchronously and notifies the status bar and Log pane;
// callers that need durable completion await the returned Future. The
// --log-to-stdout flag adds a resolved human-readable line without replacing
// the file record. File-write failures use stderr as a last-resort diagnostic
// because the configured log file is unavailable.
// ---------------------------------------------------------------------------

import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'log_messages.dart';

enum PainterLogLevel { trace, debug, info, warn, error }

/// One structured log event; the message is resolved from its catalog id.
@immutable
class PainterLogEntry {
  PainterLogEntry({
    required this.timestamp,
    required this.level,
    required this.messageId,
    Map<String, Object?> arguments = const {},
    this.stackTrace,
  }) : arguments = Map.unmodifiable(arguments);

  final DateTime timestamp;
  final PainterLogLevel level;
  final String messageId;
  final Map<String, Object?> arguments;
  final String? stackTrace;

  /// Reconstructs a record read from the JSONL log file.
  factory PainterLogEntry.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Log record must be a JSON object.');
    }
    final rawTimestamp = value['timestamp'];
    final rawLevel = value['level'];
    final rawMessageId = value['messageId'];
    final rawArguments = value['arguments'];
    final rawStackTrace = value['stackTrace'];
    if (rawTimestamp is! String ||
        rawLevel is! String ||
        rawMessageId is! String ||
        rawArguments is! Map ||
        (rawStackTrace != null && rawStackTrace is! String)) {
      throw const FormatException('Log record fields are invalid.');
    }
    final timestamp = DateTime.tryParse(rawTimestamp);
    if (timestamp == null) {
      throw const FormatException('Log record timestamp is invalid.');
    }
    final level = PainterLogLevel.values.where((item) => item.name == rawLevel);
    if (level.isEmpty) {
      throw const FormatException('Log record severity is invalid.');
    }
    return PainterLogEntry(
      timestamp: timestamp.toUtc(),
      level: level.first,
      messageId: rawMessageId,
      arguments: Map<String, Object?>.from(rawArguments),
      stackTrace: rawStackTrace as String?,
    );
  }

  /// Serializes only structured fields; rendered message text is never stored.
  Map<String, Object?> toJson() => {
    'timestamp': timestamp.toUtc().toIso8601String(),
    'level': level.name,
    'messageId': messageId,
    'arguments': arguments,
    if (stackTrace != null) 'stackTrace': stackTrace,
  };

  /// Resolves this record through the current message catalog.
  String get message => LogMessages.format(messageId, arguments);

  /// Builds a plain-text line for the optional stdout stream.
  String toConsoleLine() =>
      '${timestamp.toLocal().toIso8601String()} ${level.name.toUpperCase()} '
      '$message${stackTrace == null ? '' : '\n$stackTrace'}';
}

/// Observable JSONL log history shared by app widgets and error handlers.
class PainterLog extends ChangeNotifier {
  PainterLog._({
    this._file,
    required this._pipeToStdout,
    void Function(String line)? stdoutWriter,
  }) : _stdoutWriter = stdoutWriter ?? stdout.writeln;

  final File? _file;
  final bool _pipeToStdout;
  final void Function(String line) _stdoutWriter;
  final List<PainterLogEntry> _entries = [];
  late final List<PainterLogEntry> entries = UnmodifiableListView(_entries);
  Future<void> _writeTail = Future<void>.value();

  /// Opens persistent history in [directory], creating the file if necessary.
  static Future<PainterLog> open({
    Directory? directory,
    bool pipeToStdout = false,
    void Function(String line)? stdoutWriter,
  }) async {
    final logDirectory = directory ?? _defaultDirectory();
    await logDirectory.create(recursive: true);
    final file = File(
      '${logDirectory.path}${Platform.pathSeparator}painter.log',
    );
    final log = PainterLog._(
      file: file,
      pipeToStdout: pipeToStdout,
      stdoutWriter: stdoutWriter,
    );
    var invalidEntries = 0;
    if (await file.exists()) {
      for (final line in await file.readAsLines()) {
        if (line.isEmpty) continue;
        try {
          log._entries.add(PainterLogEntry.fromJson(jsonDecode(line)));
        } on FormatException {
          invalidEntries++;
        } on TypeError {
          invalidEntries++;
        }
      }
    }
    if (invalidEntries > 0) {
      await log.warn(
        'log.file.invalid_entries',
        arguments: {'count': invalidEntries},
      );
    }
    return log;
  }

  /// Creates a non-persistent store for isolated widget and unit tests.
  factory PainterLog.memory({
    bool pipeToStdout = false,
    void Function(String line)? stdoutWriter,
  }) => PainterLog._(pipeToStdout: pipeToStdout, stdoutWriter: stdoutWriter);

  /// Returns the current macOS user's application log directory.
  static Directory _defaultDirectory() {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      throw StateError('HOME is unavailable; Painter cannot locate its log.');
    }
    return Directory(
      '$home${Platform.pathSeparator}Library${Platform.pathSeparator}'
      'Logs${Platform.pathSeparator}Painter',
    );
  }

  /// Appends a trace-level event identified by [messageId].
  Future<void> trace(
    String messageId, {
    Map<String, Object?> arguments = const {},
    String? stackTrace,
  }) => _record(PainterLogLevel.trace, messageId, arguments, stackTrace);

  /// Appends a debug-level event identified by [messageId].
  Future<void> debug(
    String messageId, {
    Map<String, Object?> arguments = const {},
    String? stackTrace,
  }) => _record(PainterLogLevel.debug, messageId, arguments, stackTrace);

  /// Appends an informational event identified by [messageId].
  Future<void> info(
    String messageId, {
    Map<String, Object?> arguments = const {},
    String? stackTrace,
  }) => _record(PainterLogLevel.info, messageId, arguments, stackTrace);

  /// Appends a warning event identified by [messageId].
  Future<void> warn(
    String messageId, {
    Map<String, Object?> arguments = const {},
    String? stackTrace,
  }) => _record(PainterLogLevel.warn, messageId, arguments, stackTrace);

  /// Appends an error event identified by [messageId].
  Future<void> error(
    String messageId, {
    Map<String, Object?> arguments = const {},
    String? stackTrace,
  }) => _record(PainterLogLevel.error, messageId, arguments, stackTrace);

  /// Waits until all queued file appends have completed.
  Future<void> flush() => _writeTail;

  /// Adds to memory immediately, then writes the same structured record.
  Future<void> _record(
    PainterLogLevel level,
    String messageId,
    Map<String, Object?> arguments,
    String? stackTrace,
  ) {
    final entry = PainterLogEntry(
      timestamp: DateTime.now().toUtc(),
      level: level,
      messageId: messageId,
      arguments: arguments,
      stackTrace: stackTrace,
    );
    _entries.add(entry);
    notifyListeners();
    if (_pipeToStdout) _stdoutWriter(entry.toConsoleLine());
    final file = _file;
    if (file == null) return Future<void>.value();
    final line = '${jsonEncode(entry.toJson())}\n';
    _writeTail = _writeTail.then((_) async {
      try {
        await file.writeAsString(line, mode: FileMode.append, flush: true);
      } catch (error) {
        stderr.writeln('Painter log file write failed: $error');
      }
    });
    return _writeTail;
  }
}
