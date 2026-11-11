# 014. Every Operation, edit, and handled failure is logged through the one PainterLog, with catalog message ids

Status: accepted   (supersedes: none; superseded by: none)
Date: 2026-11-11
Relates to: LOG-1, LOG-2, LOG-3, LOG-4, LOG-5, LOG-6, LOG-7, LOG-8, LOG-9, LOG-10, LOG-11, LOG-12, LOG-13, LOG-14, LOG-15, LOG-16, LOG-17, LOG-18, LOG-19, LOG-20, LOG-21, LOG-22, LOG-23, LOG-24

## Context
Painter has a structured, file-backed log (`lib/logging/`) with a Log pane and a status bar, but no spec or decision said what to record, so code added since recorded nothing. The app logs its start, unhandled errors, and the failures of Open, Save, Flash, Session commands, settings, and splat generation. Successful Operations, Session membership changes, and edits are not logged. Several `catch` blocks fall back without a trace: unreadable settings (`lib/settings/settings_store.dart`), an invalid custom theme (`lib/settings/painter_settings.dart`), an unreadable workspace section (`lib/document/document_file_format.dart`, `lib/main.dart`), and a malformed message from a peer (`lib/session/session_network.dart`). Comments in `lib/logging/log_messages.dart` and `lib/canvas/tile_cache.dart` cited a design document that never existed in this tree.

## Decision
- **PNT-A0020-01** Every Log record shall be made through the app's one `PainterLog` (`lib/logging/painter_log.dart`). Code in `lib/` shall not use `print`, `debugPrint`, `stdout`, `stderr`, or `dart:developer`'s `log` for diagnostics; `PainterLog`'s own fallback for a failed file write (LOG-5) is the only exception.
- **PNT-A0020-02** Every message id shall have a template in `LogMessages.templates` (`lib/logging/log_messages.dart`), added in the same change as the call that uses it. A new id shall be lowercase and dotted, `<area>.<subject>.<event>`, where `<area>` names the system the record is about (`app`, `document`, `workspace`, `session`, `settings`), not the file that makes it, for example `document.open.succeeded` or `session.participant.timed_out`. An id shall never be removed or given another meaning, because records already in the Log file name it.
- **PNT-A0020-03** Values shall be passed as `arguments`, never formatted into the id: `error` is `error.toString()`, `path` is the absolute file path, and `participant` is the Participant's shown name. A record caused by a caught exception shall carry its `stackTrace`.
- **PNT-A0020-04** Code that has no `PainterLog` shall receive one as a constructor parameter, or report through a callback to code that has one, as `TileCache.onSplatWorkerError` does. There shall be no global logger.
- **PNT-A0020-05** Every `catch` in `lib/` shall rethrow, throw another exception, or make a Log record (LOG-11, LOG-13). A `catch` that does none of these is allowed only where the caught case is normal control flow, such as falling back from port 47800 (PNT-A0019-01), and shall then carry a `//` comment saying so.
- **PNT-A0020-06** A change that adds or changes an Operation, an edit listed in LOG-19, or a `catch` shall add its Log record in the same change, with a test that reads `PainterLog.entries` from a `PainterLog.memory()` and checks the record's Severity and message id.
- **PNT-A0020-07** Records of every Severity shall go to the Log file and to every Log pane's list; only a Log pane's lowest Severity (LOG-22) hides records, and only in that pane.
- **PNT-A0020-08** A Log pane's Per-mode state shall be `{"lowest": <Severity name>}`, held in the session document and the workspace section beside the Canvas and Manual states of PNT-A0015-07.

## Alternatives considered
- **Leave logging to each author's judgment.** This is what the code did, and it recorded almost nothing beyond the start. Rejected.
- **`package:logging` or `dart:developer`'s `log`.** Familiar, but their records reach neither the Log file nor the Log pane without an adapter, leaving two ways to log. Rejected.
- **A global logger.** Saves constructor parameters, but tests would share one log across cases, and `PainterApp` already takes its `PainterLog` as a parameter for tests. Rejected.
- **Record every UI event at `trace`.** Pointer events and frames would flood the Log file (LOG-20). Rejected.

## Consequences
- Session, document, and settings code that has no `PainterLog` today gains a parameter or a callback.
- The message catalog grows with every Operation and edit, and its ids become a lasting format: wording may change, but an id may not be reused.
- The Log file grows faster, and nothing limits its size yet (logging.md, Open Questions).
- Nothing checks this mechanically. Review searches the changed files for `catch` and for new Operations; a search of `lib/` for `print(` and `debugPrint` finds violations of PNT-A0020-01.

## Revisit if
- The owner decides how to limit the Log file's size (logging.md, Open Questions).
