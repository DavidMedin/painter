# Plan

## 1. Implement NON-010.

## 2. Verify Sessions between two running app instances
Acceptance criteria:
- Two app instances (on one machine or two machines on one LAN) start and join a Session through the Session pane; strokes, undo, workspace joins, and Make host behave as multiplayer.md and workspace.md describe.
- Pulling one machine off the network drops it from the other's list after 10 seconds.
Covers: MPLY-3, MPLY-5, MPLY-11, MPLY-17, WKSP-32

## 3. Implement NON-012: log what logging.md requires
Acceptance criteria:
- Running the acceptance examples of logging.md produces exactly the records they describe, in the Log pane and in the Log file.
- Every `catch` in `lib/` meets PNT-A0020-05, and every new message id has a template that follows PNT-A0020-02.
- Tests in `test/` check each record's Severity and message id through `PainterLog.memory()` and cite the LOG IDs they verify, including the existing tests in `test/logging/`.
Covers: LOG-1, LOG-2, LOG-3, LOG-4, LOG-5, LOG-6, LOG-7, LOG-8, LOG-9, LOG-10, LOG-11, LOG-12, LOG-13, LOG-14, LOG-15, LOG-16, LOG-17, LOG-18, LOG-19, LOG-20, LOG-21, LOG-22, LOG-23, LOG-24
