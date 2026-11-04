# Architecture Decision Records

Use this directory for durable technical or product decisions that have actually been made.

## Convention

- Add one numbered Markdown file per decision, named `NNNN-kebab-case.md` (for example, `0001-example-decision.md`).
- Each record must include `Status`, `Context`, `Decision`, and `Consequences` sections.
- Link to the decision an ADR supersedes, when applicable.
- Never record undecided proposals as decisions. Do not create ADRs for choices that remain open in the project brief or architecture page.

## Records

- [ADR 0001 — Use a vector canvas with Flutter pointer input](0001-vector-canvas-and-flutter-input.md)
- [ADR 0002 — Saved-document format and file flow](0002-saved-document-format-and-flow.md)
- [ADR 0003 — Add macOS trackpad pan, zoom, and rotate controls](0003-trackpad-gesture-controls.md)
- [ADR 0004 — Render strokes as instanced gaussian pencil splats](0004-pencil-splat-stroke-rendering.md)
- [ADR 0005 — Cache the canvas as multi-resolution document-space tiles](0005-tiled-texture-cache.md)
- [ADR 0006 — An ImGui-style debug pane for the tile cache](0006-debug-pane.md)
- [ADR 0007 — Code commenting standard](0007-code-commenting-standard.md)
- [ADR 0008 — Discoverable controls, workspaces, and touch targets](0008-discoverable-controls-workspaces-and-touch-targets.md)
- [ADR 0009 — Commit bounded stroke chunks during long gestures](0009-bounded-active-stroke-chunks.md)
- [ADR 0010 — Docked pane system](0010-pane-system.md)

## Record template

```markdown
# <Decision title>

## Status

<Proposed, accepted, superseded, or another explicit state>

## Context

<Relevant facts and constraints>

## Decision

<The choice actually made>

## Consequences

<Important results and tradeoffs>

<If superseding another decision, link it here>
```
