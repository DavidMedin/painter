# 008. A document file is a binary container holding the Automerge content document and the workspace section

Status: accepted   (supersedes: none; superseded by: none)
Date: 2026-11-11
Relates to: DOCF-1, DOCF-2, DOCF-3, DOCF-4, DOCF-5, DOCF-6, DOCF-7, WKSP-1, WKSP-4

## Context
The owner chose to store the Automerge document itself, keeping the full change history and making diverged copies mergeable, at the cost of a binary file. The workspace section must stay separate from the content (WKSP-1) and survive Save untouched (WKSP-4). Strokes need identities that survive saving and sessions (DOCF-2), and a stroke's grain must not change when strokes from another peer are interleaved; today the seed is the stroke's index.

## Decision
- **PNT-A0014-01** A version 2 file shall be: the 8 bytes `89 50 4E 54 52 0D 0A 1A` (`\x89PNTR\r\n\x1a`), a little-endian u32 container version `2`, then sections to the end of the file, each a little-endian u32 kind, a little-endian u32 length, and that many bytes.
- **PNT-A0014-02** Section kind 1 shall hold the bytes of the content document's Automerge save. Kind 2 shall hold the workspace section as UTF-8 JSON. Sections of other kinds shall be kept and written back unchanged by Save.
- **PNT-A0014-03** The content document's root map shall hold `format` = `"painter-document"`, `version` = 2, `engine` = the Engine version, and `strokes`, a map from stroke id to a stroke map.
- **PNT-A0014-04** A stroke map shall hold `points` (bytes: little-endian float64 triples x, y, weight), `seed` (int), `z` (int) and `gesture` (string id of the pointer gesture it belongs to).
- **PNT-A0014-05** Strokes shall be ordered bottom to top by `z`, then by stroke id. A new stroke's `z` is one more than the largest `z` in the document.
- **PNT-A0014-06** A new stroke's seed shall be the 32-bit FNV-1a hash of its id with the top bit cleared, and stored, so it never depends on position.
- **PNT-A0014-07** The Engine version shall be the constant `strokeEngineVersion` in `lib/canvas/pencil_splats.dart`, currently 1. Any change to how stroke data turns into splats shall increment it. A file or Session with another value shall be refused (DOCF-6, MPLY-8).
- **PNT-A0014-08** A file that does not start with the magic bytes shall be read as the earlier JSON format and imported into a new content document in one change, the stroke at index i getting `seed` = `z` = i + 1, which reproduces its old grain (DOCF-3).
- **PNT-A0014-09** Each process shall give a document it opens or creates a new random Automerge actor id.
- **PNT-A0014-10** A stroke entry the Painter cannot read (a field missing or of the wrong type, `z` outside 0..2^53-1, `seed` outside 0..2^31-1, or `points` not a whole number of triples with finite coordinates and weights in range) shall be deleted, in one commit, by the peer that reads it, whether it arrived by sync or in a file. It is never shown, and it never makes a file unopenable; DOCF-7 refers to the root keys and the container.

## Alternatives considered
- **Keep JSON and use the CRDT only during a Session.** Readable diffs, but loses history and the ability to merge diverged copies. Rejected by the owner.
- **JSON with the Automerge bytes in base64.** Keeps a JSON wrapper, but inflates the content by a third and still is not diffable. Rejected.
- **Store the workspace inside the Automerge document.** One blob, but Flash would become a content change with history, against WKSP-1 and WKSP-5. Rejected.

## Consequences
- Files grow with every change ever made, including undone strokes (DOCF-1). Automerge 3 stores history compressed.
- Text diffs of `.paint` files are no longer meaningful. Decision 006's concern about layout churn in diffs now applies to binary diffs only.
- Decision 004's PNT-A0009-07 (saved format unchanged) no longer holds. Its PNT-A0005-08 and PNT-A0005-09 (a tile counts applied strokes and only draws appended ones) hold only for strokes added on top: a tile now records the topmost stroke it has drawn, and an insert below the top or a removal rebuilds the tiles the changed stroke touches, showing the old image until the rebuild lands (PNT-A0005-19).
- Decision 005's PNT-A0005-29 and PNT-A0005-30 (a seed is the stroke's 1-based index, and the active stroke borrows the next one) no longer hold: a stroke's seed comes from its id (PNT-A0014-06), and the live chunk already has the id and seed it keeps after commit.
- Headless export must read this container too.
