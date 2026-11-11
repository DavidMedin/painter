// What: Unit tests for structured log persistence, catalog rendering, stdout,
//   a file that cannot be written, the global error handlers, and the start
//   record.
// Why: App and widget consumers depend on ordered, durable records with
//   message ids and arguments (docs/spec/logging.md LOG-1, LOG-2, LOG-4);
//   malformed rows are skipped and counted (LOG-3); a failed write loses no
//   record (LOG-5); stdout is an optional mirror, not the store (LOG-6);
//   starting is recorded (LOG-9); uncaught errors become error records
//   (LOG-14).
// Covers: lib/logging/painter_log.dart, log_messages.dart,
//   flutter_log_handlers.dart, and startLogging in lib/main.dart.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart' show FlutterError, FlutterErrorDetails;
import 'package:flutter_test/flutter_test.dart';
import 'package:painter/logging/flutter_log_handlers.dart';
import 'package:painter/logging/log_messages.dart';
import 'package:painter/logging/painter_log.dart';
import 'package:painter/main.dart' show startLogging;

void main() {
  late Directory directory;
  late PainterLog log;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('painter-log-test-');
    log = await PainterLog.open(directory: directory);
  });

  tearDown(() async {
    await log.flush();
    log.dispose();
    await directory.delete(recursive: true);
  });

  test('persists structured records and reloads them in write order '
      '(LOG-1, LOG-2, LOG-4)', () async {
    await Future.wait([
      log.info('app.started'),
      log.error(
        'document.operation.failed',
        arguments: {'operation': 'save', 'error': 'disk full'},
        stackTrace: 'save stack',
      ),
    ]);

    final file = File('${directory.path}${Platform.pathSeparator}painter.log');
    final lines = await file.readAsLines();
    expect(lines, hasLength(2));
    final firstRecord = jsonDecode(lines.first) as Map<String, dynamic>;
    final secondRecord = jsonDecode(lines.last) as Map<String, dynamic>;
    expect(firstRecord['messageId'], 'app.started');
    expect(firstRecord['level'], 'info');
    expect(DateTime.parse(firstRecord['timestamp'] as String).isUtc, isTrue);
    expect(firstRecord, isNot(contains('message')));
    expect(secondRecord['level'], 'error');
    expect(secondRecord['arguments'], {
      'operation': 'save',
      'error': 'disk full',
    });
    expect(secondRecord['stackTrace'], 'save stack');

    final restored = await PainterLog.open(directory: directory);
    try {
      expect(restored.entries.map((entry) => entry.messageId), [
        'app.started',
        'document.operation.failed',
      ]);
      expect(
        restored.entries.last.message,
        'Failed to save Painter document: disk full',
      );
      expect(restored.entries.last.stackTrace, 'save stack');
    } finally {
      await restored.flush();
      restored.dispose();
    }
  });

  test(
    'skips malformed rows and records how many were rejected (LOG-3)',
    () async {
      final file = File(
        '${directory.path}${Platform.pathSeparator}painter.log',
      );
      await file.writeAsString('{broken record}\n');

      final restored = await PainterLog.open(directory: directory);
      try {
        expect(restored.entries, hasLength(1));
        expect(restored.entries.single.messageId, 'log.file.invalid_entries');
        expect(restored.entries.single.level, PainterLogLevel.warn);
        expect(restored.entries.single.arguments['count'], 1);
      } finally {
        await restored.flush();
        restored.dispose();
      }
    },
  );

  test('stdout mirrors readable records only when enabled (LOG-6)', () async {
    final output = <String>[];
    final piped = await PainterLog.open(
      directory: directory,
      pipeToStdout: true,
      stdoutWriter: output.add,
    );
    try {
      await piped.warn(
        'settings.load.failed',
        arguments: {'error': 'unavailable'},
      );
      expect(output, hasLength(1));
      expect(
        output.single,
        contains('WARN Could not load settings: unavailable'),
      );
      final file = File(
        '${directory.path}${Platform.pathSeparator}painter.log',
      );
      final record =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      expect(record['messageId'], 'settings.load.failed');
    } finally {
      await piped.flush();
      piped.dispose();
    }

    final silentOutput = <String>[];
    final silent = PainterLog.memory(stdoutWriter: silentOutput.add);
    await silent.info('app.started');
    expect(silentOutput, isEmpty);
    silent.dispose();
  });

  test('keeps a record it cannot write to the file (LOG-5)', () async {
    final blocked = await Directory.systemTemp.createTemp('painter-log-block-');
    addTearDown(() => blocked.delete(recursive: true));
    // A directory where the file should be makes every append fail.
    await Directory('${blocked.path}${Platform.pathSeparator}painter.log')
        .create();
    final unwritable = await PainterLog.open(directory: blocked);
    addTearDown(unwritable.dispose);

    await unwritable.info('app.started');

    expect(unwritable.entries.single.messageId, 'app.started');
  });

  test('uncaught framework and platform errors become error records '
      '(LOG-14)', () {
    final memory = PainterLog.memory();
    addTearDown(memory.dispose);
    final previousFramework = FlutterError.onError;
    final previousPlatform = PlatformDispatcher.instance.onError;
    try {
      installFlutterLogHandlers(memory);
      FlutterError.onError!(
        FlutterErrorDetails(
          exception: StateError('framework'),
          stack: StackTrace.current,
        ),
      );
      expect(
        PlatformDispatcher.instance.onError!(
          StateError('async'),
          StackTrace.current,
        ),
        isTrue,
      );
    } finally {
      FlutterError.onError = previousFramework;
      PlatformDispatcher.instance.onError = previousPlatform;
    }

    expect(
      [for (final entry in memory.entries) entry.messageId],
      ['flutter.framework.error', 'error.unhandled'],
    );
    for (final entry in memory.entries) {
      expect(entry.level, PainterLogLevel.error);
      expect(entry.stackTrace, isNotEmpty);
    }
  });

  test('starting Painter records it in the log file (LOG-9)', () async {
    final previousFramework = FlutterError.onError;
    final previousPlatform = PlatformDispatcher.instance.onError;
    final PainterLog started;
    try {
      started = await startLogging(const [], directory: directory);
    } finally {
      FlutterError.onError = previousFramework;
      PlatformDispatcher.instance.onError = previousPlatform;
    }
    await started.flush();
    started.dispose();

    expect(started.entries.last.messageId, 'app.started');
    expect(started.entries.last.level, PainterLogLevel.info);
    final file = File('${directory.path}${Platform.pathSeparator}painter.log');
    expect(await file.readAsString(), contains('"messageId":"app.started"'));
  });

  test('message catalog handles stable ids, arguments, and unknown ids', () {
    expect(
      LogMessages.format('document.operation.failed', {
        'operation': 'open',
        'error': 'bad format',
      }),
      'Failed to open Painter document: bad format',
    );
    expect(LogMessages.format('future.message', const {}), '[future.message]');
  });
}
