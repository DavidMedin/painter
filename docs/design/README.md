# Design Documents

This tree describes how Painter is designed, one folder per system. It replaces the former linear list of architecture decision records (ADRs).

## Requirement Notation (EARS+)

Every normative statement in the design tree uses EARS (Easy Approach to Requirements Syntax) with these additions:

- **ID:** each requirement carries a unique, stable ID. IDs are never reused or renumbered, and a requirement keeps its ID when it moves between documents. The prefix names the area the requirement was first written for and is historical: `PNT-A<NNNN>-<NN>` came from the former ADR with that number.
- **Source:** each behavioral requirement has a `Source:` line naming the roadmap task, a design document, or direct owner direction.
- **Templates** (clause order is fixed: `WHILE`, then `WHEN`/`IF`, then `WHERE`):
  - Ubiquitous: `The <system> shall <response>.`
  - Event-driven: `WHEN <trigger>, the <system> shall <response>.`
  - State-driven: `WHILE <state>, the <system> shall <response>.`
  - Optional feature: `WHERE <feature is present>, the <system> shall <response>.`
  - Unwanted behavior: `IF <condition>, THEN the <system> shall <response>.`
  - Complex: a combination of the clauses above.
- **Systems named:** `Painter` (the whole application), `Canvas` (a Canvas pane and its view), `Pane System`, `Document Service` (open/save), `Settings`, `Logger`, `Help System`.
- Text outside a requirement (purpose, context, consequences, open questions) is non-normative and is labeled as such.

## Document Kinds

Each system folder holds two kinds of document:

| Kind | File | Contents |
| --- | --- | --- |
| Behavioral | `behavior.md` | What the system does as observed by the user or a caller, in EARS+. Contains no implementation names. |
| Design | any other `*.md` | One decision about how the system is built: `Status`, `Context`, `Decision` (EARS+, may name implementation symbols), `Consequences`. |

A design document records a decision that has actually been made. Do not record an undecided proposal as a decision; list it as an open question in the system's `behavior.md` instead. A design document that replaces another records the replaced document under `Supersedes` and links to it.

## Tree

```
docs/design/
  README.md                      this index
  architecture-overview.md       platform constraints, priorities, system map
  canvas/
    behavior.md                  drawing, viewport, paper, undo model
    vector-canvas.md             vector document, input mapping, trackpad
    pencil-splats.md             pencil rendering as gaussian splats
    tile-cache.md                tile cache and bounded active chunks
  document/
    behavior.md                  launch, open, save, file errors
    file-format-and-flow.md      saved format, in-app picker, save flow
  panes/
    behavior.md                  splits, selectors, borders, shortcuts
    pane-system.md               binary split tree and pane ownership
  diagnostics/
    behavior.md                  Diagnostics pane
    debug-pane.md                ImGui-style kit, counters, overlays
  settings/
    behavior.md                  theme modes, palettes, persistence
    theme-and-palettes.md        settings model, fixed canvas paper
  controls/
    behavior.md                  hints, F1 help, Manual pane, touch targets
    manual-pane.md               help catalog, docked Manual, touch sizing
  logging/
    behavior.md                  log, status bar, Log pane, fatal errors
    file-backed-logging.md       JSONL store and error routing
  brush-graph/
    behavior.md                  node graph brushes (product direction)
  composition/
    behavior.md                  node graph composition (product direction)
  engineering/
    code-commenting.md           commenting standard for lib/ and test/
```

## Retired Requirement IDs

An ID is retired when its fact is stated once elsewhere or the behavior it described was replaced. A retired ID is never reused.

| Retired | Replaced by | Reason |
| --- | --- | --- |
| PNT-A0004-10, -11, -12 | PNT-A0005-09, -12, -27 | Per-stroke batch cache and full per-move rebuild of the former `PencilRenderer` were replaced by the tile cache and `SplatStream`. |
| PNT-A0005-26 | PNT-A0009-03, -04 | Narrowed: completed chunks are tiled; only the current bounded chunk is live. |
| PNT-A0006-15 | PNT-A0010-15, -16, -17 | F3 toggle is specified once, in the pane system. |
| PNT-A0008-01, -02, -03 | PNT-A0010-06, -15, -16, -17; PNT-ARC-030 | Two-mode selector and F3 behavior superseded by the pane system. |
| PNT-A0013-06, -07, -08 | PNT-A0008-05, -06, -07 | F1 precedence is specified once. |
| PNT-ARC-001, -002, -003 | PNT-PLT-001, -002, -003 | Platform constraints moved to the architecture overview under the `PLT` area. |
| PNT-ARC-012, -013, -014, -016, -017, -019 | PNT-A0014-01 to -09 | Restatements of the logging decision. |
| PNT-ARC-020, -022, -023, -024, -026, -027, -028, -029 | PNT-A0011-01 to -03, -08 to -13 | Restatements of the theme decision. |
| PNT-ARC-031, -032, -033, -034 | PNT-A0013-05, -09, -10, -11 | Restatements of the Manual pane decision. |
| PNT-ARC-035 to -040 | PNT-A0010-03 to -05, -08 to -12 | Restatements of the pane chrome decision. |
| PNT-ARC-041, -042 | PNT-A0010-15, -16 | F3 behavior is specified once. |
| PNT-ARC-043 to -046 | PNT-A0010-18 to -20 | Restatements of renderer and viewport ownership. |
| PNT-ARC-048, -050, -051 | PNT-A0006-01, -04, -13 | Restatements of the debug pane decision. |
| PNT-ARC-053 | PNT-A0008-04 | Restatement of labeled controls. |
| PNT-ARC-055, -058, -059 | PNT-A0008-05, -06, -07 | F1 precedence is specified once. |
| PNT-ARC-057 | PNT-A0007-01 to -13 | Restatement of the commenting standard. |
| PNT-A0011-14 | PNT-A0012-06 | Same fact (fixed white paper), stated once. |
| PNT-CNV-001, -004 | PNT-A0005-01, -09 | Restatements of the tile cache decision. |
| PNT-CNV-002, -003 | PNT-A0004-05, -08; PNT-A0005-16 | Restatements of splat generation and the worker isolate. |
| PNT-CNV-005 | PNT-A0005-19; PNT-A0009-05 | Restatement of stale-tile and overlay behavior. |
| PNT-CNV-006, -007 | PNT-A0009-04, -03 | Restatements of the bounded chunk decision. |
| PNT-CNV-008, -009 | PNT-A0001-03; PNT-A0012-01 | Restatements of document ownership. |
| PNT-CNV-010, -011, -012 | PNT-A0012-02, -04, -05; PNT-A0001-14 | Restatements of viewport ownership. |
| PNT-CNV-013, -014, -015 | PNT-A0001-13, -11, -15 | Restatements of the prototype parameters. |

## Adding or Changing a Design

- Put a new system in its own folder with a `behavior.md` first.
- Update the behavioral document in the same change as any behavior it describes.
- Add a design document only when a decision has been made; cite its path in code comments rather than a number.
- Keep the tree and this index in step: a folder or document that is not listed here is incomplete.
