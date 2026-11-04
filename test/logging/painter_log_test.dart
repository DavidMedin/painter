// What: Unit tests for structured log persistence, catalog rendering, and stdout.
// Why: App and widget consumers depend on ordered, durable records with
//   message ids and arguments; stdout is an optional mirror, not the store.
// Covers: lib/logging/painter_log.dart and log_messages.dart.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:painter/logging/log_messages.dart';
import 'package:painter/logging/painter_log.dart';

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

  test('persists structured records and reloads them in write order', () async {
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

  test('skips malformed rows and records how many were rejected', () async {
    final file = File('${directory.path}${Platform.pathSeparator}painter.log');
    await file.writeAsString('{broken record}\n');

    final restored = await PainterLog.open(directory: directory);
    try {
      expect(restored.entries, hasLength(1));
      expect(restored.entries.single.messageId, 'log.file.invalid_entries');
      expect(restored.entries.single.arguments['count'], 1);
    } finally {
      await restored.flush();
      restored.dispose();
    }
  });

  test('stdout mirrors readable records only when enabled', () async {
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
