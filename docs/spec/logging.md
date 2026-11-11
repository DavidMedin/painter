# Logging
## Scope
What the system records about its own activity, where it keeps that record, and how the user reads it.
Out of scope: sending logs off the machine; the **Log** of another **Participant**, which that **Participant**'s system keeps; limiting the size of the **Log file** (see Open Questions).
## Definitions
Terms defined in multiplayer.md are used here with the same meaning: **Session**, **Participant**, **Host**, **Session address**, **Engine version**.
Terms defined in panes.md are used here with the same meaning: **Application window**, **Pane**, **Pane Mode**, **Per-mode state**, **Splitter**.
Terms defined in workspace.md are used here with the same meaning: **Flash**, **Stored workspace**, **Unusable**, **Workspace**.
Terms defined in canvas.md are used here with the same meaning: **View of a canvas**.
Terms defined in document-file.md are used here with the same meaning: **Stroke**.
- **Log**: The ordered list of **Log records** of one user account on one machine, kept across runs of the system.
- **Log file**: The file `~/Library/Logs/Painter/painter.log`, which holds the **Log**.
- **Log record**: One entry of the **Log**: a UTC time, a **Severity**, a message id, the values its message names, and optionally a stack trace.
- **Severity**: The weight of a **Log record**, one of:
  - `error`: an **Operation** failed, or a failure reached no handler.
  - `warn`: the system met a problem and continued with less, for example by skipping data, using a default, or dropping a **Participant**.
  - `info`: an **Operation** succeeded, or the system, the open document, or the **Session** changed state.
  - `debug`: the user made one edit of the document or of a **Workspace**, or cancelled an **Operation**.
  - `trace`: one step inside an **Operation**, recorded to diagnose it.
- **Operation**: A user command that the system completes or fails as a whole: opening a file, saving, **Flash**, starting, joining, or leaving a **Session**, promoting a **Participant**, joining or leaving a **Workspace**, and changing a setting.

## Requirements

LOG-1 - The system shall append each **Log record** to the **Log file** as one line of JSON, in the order the **Log records** were made.
LOG-2 - When the system starts, the system shall load the **Log records** already in the **Log file** before making new ones.
LOG-3 - If a line of the **Log file** is not a valid **Log record**, then the system shall skip that line and make one `warn` **Log record** stating how many lines were skipped.
LOG-4 - The system shall store each **Log record** in the **Log file** as its message id and values, never as rendered message text.
LOG-5 - If writing a **Log record** to the **Log file** fails, then the system shall keep that **Log record** in the **Log** it shows and write the reason to standard error.
LOG-6 - While the system was started with the argument `--log-to-stdout`, the system shall also write each new **Log record** to standard output as one readable line.
LOG-7 - The system shall show the newest **Log record** in a status bar along the bottom of the **Application window**.
LOG-8 - The system shall provide a Log **Pane Mode** that lists the **Log records** at or above the lowest **Severity** selected for that **Pane** (LOG-22), oldest first, scrolled to the newest.
LOG-9 - When the system starts, the system shall make an `info` **Log record**.
LOG-10 - When an **Operation** succeeds, the system shall make an `info` **Log record** naming the **Operation** and what it acted on, such as the file path, the **Session address**, the **Participant**, or the setting and its new value.
LOG-11 - If an **Operation** fails, then the system shall make an `error` **Log record** naming the **Operation**, the reason, and the stack trace.
LOG-12 - When the user cancels an **Operation** before it changes anything, such as by closing a file dialog, the system shall make a `debug` **Log record** naming the **Operation**.
LOG-13 - If the system continues past a problem without failing an **Operation**, such as by skipping unreadable data or using a default in its place, then the system shall make a `warn` **Log record** naming what was affected and the reason.
LOG-14 - If a failure reaches no handler, then the system shall make an `error` **Log record** with the reason and the stack trace.
LOG-15 - When another **Participant** joins or leaves the **Session**, the system shall make an `info` **Log record** naming that **Participant**.
LOG-16 - When the system treats a **Participant** as having left under MPLY-17, the system shall make a `warn` **Log record** naming that **Participant**.
LOG-17 - When the system refuses a user's request to join the **Session**, the system shall make a `warn` **Log record** stating the reason.
LOG-18 - When the **Host** changes, the system shall make an `info` **Log record** naming the new **Host**.
LOG-19 - When the user finishes a **Stroke**, an undo, a redo, a **Pane** add, join, or swap, a **Pane Mode** change, or a **Splitter** drag, the system shall make one `debug` **Log record** naming that edit.
LOG-20 - The system shall not make a **Log record** for each pointer event, each drawn frame, each network message, or each change to a **View of a canvas**.
LOG-21 - The system shall not write the points of a **Stroke** to the **Log**.
LOG-22 - The system shall give each **Pane** in the Log **Pane Mode** a control that selects the lowest **Severity** that **Pane** lists, kept as the **Pane**'s **Per-mode state**.
LOG-23 - When a **Pane** enters the Log **Pane Mode** with no lowest **Severity** selected, the system shall select `trace`.
LOG-24 - When the user quits the system, the system shall make an `info` **Log record** and finish writing it to the **Log file** before the system exits.

## Acceptance Examples
- Start Painter, open `a.paint`, draw one **Stroke**, and save: the Log pane ends with `info` started, `info` opened `a.paint`, `debug` **Stroke** finished, and `info` saved `a.paint`.
- Open a file whose **Stored workspace** is **Unusable**: an `info` record names the opened file and a `warn` record says its **Stored workspace** was ignored and why.
- Open Save, then close the file dialog: one `debug` record says Save was cancelled, and no `info` or `error` record follows.
- Open a file from a build with a newer **Engine version**: an `error` record names the file and both **Engine versions**, with a stack trace.
- A, B, and C share a **Session**, and B's network cable is pulled: after 10 seconds, A's and C's **Logs** each hold a `warn` record naming B.
- Pan and zoom a canvas for 5 seconds: the **Log** gains no records.
- Append the line `{broken` to the **Log file** and start Painter: one `warn` record says 1 line was skipped.
- Start Painter with `--log-to-stdout` and save: the save record is also printed to the terminal.
- Set one Log pane's lowest **Severity** to `warn`: that pane lists only `warn` and `error` records, a second Log pane still lists every record, and the **Log file** still holds every record.
- Quit Painter and start it again: the record of quitting comes just before the new start record.

## Open Questions
- Should the **Log file** be limited in size, by rotating or trimming it? Today it grows without limit.
