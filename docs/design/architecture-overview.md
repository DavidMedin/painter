# Architecture Overview

Cross-cutting constraints, priorities, and the map from systems to design documents. System-specific design lives in each system's folder; see the [design index](README.md). Notation: [EARS+](README.md#requirement-notation-ears).

## Platform and Technology

- **PNT-PLT-001** The Painter shall be implemented with Flutter and Dart.
  Source: project owner.
- **PNT-PLT-002** The Painter shall target macOS.
  Source: project owner.
- **PNT-PLT-003** IF a platform other than macOS is proposed as a target, THEN the Painter project shall not claim support for it until a roadmap task has verified that support.
  Source: [AGENTS.md](../../AGENTS.md); T-006.

Linux, Windows, and Android are future targets; their rollout order is undecided (see Open Questions).

## Architectural Priorities

- **PNT-ARC-004** The Painter shall keep components cohesive, with narrow interfaces, clear ownership and contracts, and few dependencies.
  Source: project owner.
- **PNT-ARC-005** The project shall choose component boundaries from product needs and runnable evidence.
  Source: project owner.
- **PNT-ARC-006** The project shall not require a specific architecture or separate packages in order to count a design as modular.
  Source: project owner.

## System Map

Each system maps to a source directory and to its behavioral and design documents.

| System | Source | Behavior | Design |
| --- | --- | --- | --- |
| Canvas | `lib/canvas/` | [behavior](canvas/behavior.md) | [vector-canvas](canvas/vector-canvas.md), [pencil-splats](canvas/pencil-splats.md), [tile-cache](canvas/tile-cache.md) |
| Document | `lib/document/` | [behavior](document/behavior.md) | [file-format-and-flow](document/file-format-and-flow.md) |
| Panes | `lib/ui/pane_system.dart` | [behavior](panes/behavior.md) | [pane-system](panes/pane-system.md) |
| Diagnostics | `lib/debug/` | [behavior](diagnostics/behavior.md) | [debug-pane](diagnostics/debug-pane.md) |
| Settings | `lib/settings/` | [behavior](settings/behavior.md) | [theme-and-palettes](settings/theme-and-palettes.md) |
| Controls and help | `lib/ui/`, `lib/help/` | [behavior](controls/behavior.md) | [manual-pane](controls/manual-pane.md) |
| Logging | `lib/logging/` | [behavior](logging/behavior.md) | [file-backed-logging](logging/file-backed-logging.md) |
| Brush graph | not implemented | [behavior](brush-graph/behavior.md) | none |
| Composition | not implemented | [behavior](composition/behavior.md) | none |
| Engineering | `lib/`, `test/` | none | [code-commenting](engineering/code-commenting.md) |

## Dependencies Between Systems

- **PNT-ARC-060** The Canvas, Diagnostics, Settings, Manual, and Log systems shall each be hosted as a pane kind by the Panes system.
  Source: [pane-system](panes/pane-system.md).
- **PNT-ARC-061** The core Canvas rendering (`TileCache`, `TiledRenderer`, `lib/canvas/tile_stats.dart`) shall not depend on the Diagnostics system.
  Source: [debug-pane](diagnostics/debug-pane.md).
- **PNT-ARC-062** The Document and Settings systems shall not depend on each other, and the saved document shall not contain Settings or viewport state.
  Source: [file-format-and-flow](document/file-format-and-flow.md); [theme-and-palettes](settings/theme-and-palettes.md).

## Open Questions (non-normative)

- In what order will Linux, Windows, and Android be targeted? Roadmap task T-006 assesses this.
