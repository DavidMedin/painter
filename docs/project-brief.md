# Project Brief

## Purpose

Create painting software using Flutter and Dart. The initial user is an artist. Painter is a macOS painting application today; Linux, Windows, and Android are future targets and their rollout order is undecided.

## Scope

What Painter does is specified in the behavioral documents of the [design tree](design/README.md), one per system, in [EARS+](design/README.md#requirement-notation-ears). This brief does not restate it.

| Behavior | Document |
| --- | --- |
| Drawing, viewport, paper, vector model, undo | [canvas](design/canvas/behavior.md) |
| Launch, open, save, file errors | [document](design/document/behavior.md) |
| Splits, content selection, borders, shortcuts | [panes](design/panes/behavior.md) |
| Diagnostics pane | [diagnostics](design/diagnostics/behavior.md) |
| Theme modes, palettes, persistence | [settings](design/settings/behavior.md) |
| Hints, F1 help, Manual pane, touch targets | [controls](design/controls/behavior.md) |
| Log, status bar, Log pane, fatal errors | [logging](design/logging/behavior.md) |
| Node graph brushes (product direction) | [brush-graph](design/brush-graph/behavior.md) |
| Node graph composition (product direction) | [composition](design/composition/behavior.md) |

Platform constraints and architectural priorities are in the [architecture overview](design/architecture-overview.md). How the project verifies behavior is in [testing](testing.md).

## Product Differentiators

These distinguish Painter and require deliberate design. They are specified as behavior in the documents above.

- **Node graph brushes:** every brush, from hard digital to oil and pencil, is defined by a node graph. See [brush-graph](design/brush-graph/behavior.md).
- **Node graph composition:** there are no conventional layers. See [composition](design/composition/behavior.md).
- **Everything is a vector:** brushes create mathematical marks that the canvas cache renders lazily, supporting arbitrary resolution and editing or undoing past strokes. See [canvas](design/canvas/behavior.md#vector-model-and-undo-product-direction).
- **Undo undo undo:** strokes, including eraser strokes, go into an append-only store. See [canvas](design/canvas/behavior.md#vector-model-and-undo-product-direction).

## Open Questions

Each question is recorded in the behavioral document of the system it affects; none is decided.

- Default brush size and the stylus pressure-to-size mapping, and which mouse gestures pan, zoom, and rotate: [canvas](design/canvas/behavior.md#open-questions-non-normative).
- What opening or saving does when there are unsaved changes or no associated file: [document](design/document/behavior.md#open-questions-non-normative).
- Which errors are fatal: [logging](design/logging/behavior.md#open-questions-non-normative).
- How brush graphs are compiled or evaluated, and whether magic wand and lasso use graphs: [brush-graph](design/brush-graph/behavior.md#open-questions-non-normative).
- The rollout order of Linux, Windows, and Android: [architecture overview](design/architecture-overview.md#open-questions-non-normative).
