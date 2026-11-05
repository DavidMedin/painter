# Logging and Errors: Behavior

Behavior of the application log, status bar, Log pane, and error handling, as observed by the user. Notation: [EARS+](../README.md#requirement-notation-ears). Implementation is in [file-backed-logging](file-backed-logging.md). File-operation errors are specified in [document behavior](../document/behavior.md#file-errors).

## Persistence

- **PNT-ERR-004** IF an internal error or exception occurs, including a
  settings-persistence or splat-worker failure, THEN the Logger shall record it
  in the persistent application log even if its UI context is unmounted, and
  the Painter shall continue running.
  Source: T-008; T-010; [file-backed-logging](file-backed-logging.md).
- **PNT-ERR-005** The Logger shall store each record as JSONL with message-catalog IDs and formatting arguments, not rendered prose.
  Source: T-008; [file-backed-logging](file-backed-logging.md).
- **PNT-ERR-006** WHERE the `--log-to-stdout` option is present, the Logger shall mirror readable lines to stdout in addition to persisting them.
  Source: T-008; [file-backed-logging](file-backed-logging.md).

## Presentation

- **PNT-ERR-007** WHEN a record is logged, the Painter shall show the latest record in the bottom status bar.
  Source: T-008; [file-backed-logging](file-backed-logging.md).
- **PNT-ERR-008** The Log pane shall show records chronologically with the
  newest at the bottom. Each record shall expand to show its structured
  arguments and optional stack trace; hovering or focusing a record shall
  provide its catalog-backed contextual help.
  Source: T-008; T-010; [file-backed-logging](file-backed-logging.md).

## Fatal Errors

- **PNT-ERR-009** IF a fatal error occurs, THEN the Painter shall terminate only after the error, its stack trace, and other relevant information have been successfully logged.
  Source: project owner.

## Open Questions (non-normative)

- Which errors are classified as fatal? Fatal classification and termination policy are undecided; [file-backed-logging](file-backed-logging.md) does not define a fatal category or shutdown rule.
