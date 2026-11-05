# Node Graph Brushes: Behavior

Product direction for brushes defined as node graphs. This system is a target and is not implemented; no design decision has been made, so there is no design document. Notation: [EARS+](../README.md#requirement-notation-ears). Related research (advisory, not a decision): [brush node-graph routes report](../../brush-node-graph-routes.typ).

## Brushes

- **PNT-KIL-001** The Painter shall define every brush, from hard digital to oil and pencil, as a node graph.
  Source: project owner.
- **PNT-KIL-002** The Painter shall use node graphs only for brushes initially.
  Source: project owner.
- **PNT-KIL-003** The Painter shall start with the simplest runnable graph evaluator.
  Source: project owner.

## Open Questions (non-normative)

- Graphs may need compilation to sustain thousands of evaluations per second. Which technology compiles or evaluates them is undecided.
- Do magic wand and lasso behavior use graphs? Undecided.
