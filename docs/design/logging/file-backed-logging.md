# File-Backed Structured Application Logging

Design for the shared logger, its JSONL store, error routing, and presentation. Observable behavior is in [behavior](behavior.md). Notation: [EARS+](../README.md#requirement-notation-ears).

## Status

Accepted and implemented. Formerly ADR 0014, merged with the logging notes of the former architecture page.

## Context

The app used `debugPrint` for settings-load and document-operation failures. It had no shared log history, message catalog, or handlers for Flutter framework and platform-dispatched errors. The macOS app needs persistent records while keeping the status bar, the selectable Log pane, and optional stdout output consistent.

## Decision

### Store

- **PNT-A0014-01** The Painter shall use one shared `PainterLog` service (in `lib/logging/`).
- **PNT-A0014-02** On macOS, the `PainterLog` shall append JSON Lines to `~/Library/Logs/Painter/painter.log`.
- **PNT-A0014-03** WHEN the app starts, the `PainterLog` shall load valid prior records.
- **PNT-A0014-04** The `PainterLog` shall store a UTC timestamp, a severity, a stable message-catalog ID, formatting arguments, and an optional stack trace in each record.
- **PNT-A0014-05** The `LogMessages` shall resolve human-readable prose at display or output time, and the `PainterLog` shall not persist rendered prose.
- **PNT-A0014-06** WHERE `--log-to-stdout` is present, the `PainterLog` shall mirror readable output to stdout and shall not disable file persistence.

### Routing

- **PNT-ARC-015** WHEN the app starts, the `main.dart` shall open one shared logger before loading settings.
- **PNT-A0014-07** The Painter shall route settings-load and
  settings-persistence failures, document-operation failures, splat-worker
  failures, Flutter framework errors, and platform-dispatched unhandled errors
  to the same history. Handlers installed by `main.dart` shall capture Flutter
  framework errors and platform-dispatched unhandled errors.

### Presentation

- **PNT-A0014-08** The `LogStatusBar` shall show the latest record.
- **PNT-A0014-09** The `LogPane` shall show records in append order, with the newest at the scroll bottom.
- **PNT-ARC-018** The `LogStatusBar` and the selectable `LogPane` shall observe the same history.

Fatal-error classification and termination policy remain open in [behavior](behavior.md#open-questions-non-normative); this document does not define a fatal category or shutdown rule.

Retired requirement IDs for this document are recorded in the [retired ID registry](../README.md#retired-requirement-ids).

## Consequences

- The UI, file, and optional stdout share one ordered record source, and later message wording changes do not rewrite stored history.
- The in-house JSONL store has no rotation or retention policy. Records append indefinitely until an external action removes the file.
- The default location is macOS-specific. Future platform targets need a platform-appropriate directory before support is claimed.
- Tests can inject a temporary directory, an in-memory store, and a stdout writer without opening a GUI window or writing to a user's log directory.
