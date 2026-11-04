// What: Routes uncaught Flutter framework and platform errors to PainterLog.
// Why: Replacing debugPrint at individual call sites alone misses asynchronous
//   framework errors; these handlers keep those records in the same log history.
// Coupled to: painter_log.dart (structured error records) and main.dart
//   (installation before settings load and runApp).

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'painter_log.dart';

/// Installs application-wide handlers that record framework and async errors.
void installFlutterLogHandlers(PainterLog log) {
  FlutterError.onError = (details) {
    unawaited(
      log.error(
        'flutter.framework.error',
        arguments: {'error': details.exceptionAsString()},
        stackTrace: details.stack?.toString(),
      ),
    );
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    unawaited(
      log.error(
        'error.unhandled',
        arguments: {'error': error.toString()},
        stackTrace: stackTrace.toString(),
      ),
    );
    return true;
  };
}
