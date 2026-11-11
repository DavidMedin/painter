# 012. Undo replays inverse actions on the shared document, per Participant

Status: accepted   (supersedes: 001; superseded by: none)
Date: 2026-11-11
Relates to: UNDO-1, UNDO-2, UNDO-3, UNDO-4, UNDO-5, UNDO-7, UNDO-8, UNDO-9, EDIT-1

## Context
Decision 001 chose undo commands that store the pixels an edit changed. With several Participants drawing on a merged document, restoring pixels would also undo others' strokes over the same area (UNDO-8), and strokes are stored as data, not pixels. The owner requires action-based undo that reverts only one's own actions (UNDO-7). Automerge has no undo of its own.

## Decision
- **PNT-A0018-01** An edit shall be one pointer gesture, recorded as the ids of the strokes it added (one per committed chunk) and the gesture id.
- **PNT-A0018-02** Undo shall delete those stroke entries from the content document in one commit and keep their stroke maps in memory. Redo shall put the same entries back under the same ids, in one commit.
- **PNT-A0018-03** Only edits made by the local actor shall enter a Participant's history; changes received from peers never do.
- **PNT-A0018-04** The history shall keep the most recent 256 edits per document and drop the oldest first (UNDO-5).
- **PNT-A0018-05** A history shall be cleared when its document is replaced by Open or by joining a Session.

## Alternatives considered
- **Pixel diffs (decision 001).** Overwrites other Participants' work. Rejected.
- **Reverting Automerge changes by hash.** Not offered by the C API, and inverting a change in general can undo concurrent edits merged into the same keys. Rejected.

## Consequences
- An undo is an ordinary change: it syncs to peers and enters the change history (DOCF-1).
- A redone stroke reappears for everyone with its original id, seed and z order.
- When editing operations other than adding strokes arrive (EDIT-1), each needs an inverse here.
- Decision 001 is superseded; no pixel diffs are recorded.
