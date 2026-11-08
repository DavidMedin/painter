# 001. Undo is implemented as a command history, not document snapshots

Status: accepted   (supersedes: none; superseded by: none)
Date: 2026-11-07
Relates to: UNDO-1, UNDO-5

## Context
Undo must retain 100+ edits (UNDO-5) on documents that can reach
8192×8192 px with multiple layers. Edits are mostly small strokes.
We need undo to be fast and memory use to stay bounded.

## Decision
Record each edit as a reversible command that stores only the pixels
it changed (a tile-level diff), and keep commands in a bounded list.

## Alternatives considered
- **Full snapshot per edit.** Simplest, but 100 snapshots of a large
  document is gigabytes. Rejected on memory.
- **Replay all edits from the start.** Small storage, but undo time grows
  with document age and edits must be deterministic. Rejected on speed.
- **Snapshot every N edits plus replay.** Middle ground, but adds
  complexity we don't need until diffs prove too large. Revisit if so.

## Consequences
- Memory scales with edit size, not document size.
- Every new tool must produce a reversible command, or undo breaks.
- Operations that touch the whole canvas (for example, a resize) will
  store large diffs, so they may need a special case.

## Revisit if
Typical tile diffs exceed ~50 MB per edit, or command bookkeeping
becomes a source of bugs.
