# File-backed structured application logging

## Status

Accepted.

## Context

The app used `debugPrint` for settings-load and document-operation failures. It had no shared log history, message catalog, or handlers for Flutter framework and platform-dispatched errors. The macOS app needs persistent records while keeping the status bar, selectable Log pane, and optional stdout output consistent.

## Decision

- Use one shared `PainterLog` service. On macOS it appends JSON Lines to `~/Library/Logs/Painter/painter.log` and loads valid prior records when the app starts.
- Store UTC timestamp, severity, stable message-catalog ID, formatting arguments, and an optional stack trace. Resolve human-readable prose from `LogMessages` at display/output time; do not persist rendered prose.
- Make `--log-to-stdout` an optional readable mirror. It never disables file persistence.
- Route settings-load and document-operation failures, Flutter framework errors, and platform-dispatched unhandled errors to the same history.
- Have `LogStatusBar` show the latest record and `LogPane` show records in append order, with the newest at the scroll bottom.

Fatal-error classification and termination policy remain open in the project brief; this decision does not invent a fatal category or shutdown rule.

## Consequences

- The UI, file, and optional stdout share one ordered record source, and later message wording changes do not rewrite stored history.
- The in-house JSONL store has no rotation or retention policy; records append indefinitely until an external action removes the file.
- The default location is macOS-specific. Future platform targets need a platform-appropriate directory before support is claimed.
- Tests can inject a temporary directory, in-memory store, and stdout writer without opening a GUI window or writing to a user's log directory.
