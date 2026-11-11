# Painter

A Flutter/Dart painting application.

This repository is an Oh My Pi LLM harness.

macOS is the current target. Linux, Windows, and Android are future targets; their rollout order is undecided.

## Building

Document content and workspaces are Automerge documents ([decision 007](docs/decisions/007-crdt-automerge.md)), reached through the binding in [`packages/automerge_dart`](packages/automerge_dart). Its build hook compiles Rust on every `flutter run`, `flutter test`, and `flutter build`, so `rustc` and `cargo` from [`rustup`](https://rustup.rs) must be on `PATH` (with Homebrew's keg-only `rustup`, add `/opt/homebrew/opt/rustup/bin`). The pinned toolchain is installed on the first build.

## Project context

- [Agent instructions](AGENTS.md)
- [EARS+ requirements skill](.agents/skills/ears-plus-requirements/SKILL.md)
- [Spec-driven development skill](.agents/skills/painter-spec-driven-development/SKILL.md)
- [Project brief](docs/project-brief.md)
- [Design documents](docs/design/README.md): one folder per system, each with a behavioral document in EARS+ and design decisions
- [Architecture overview](docs/design/architecture-overview.md)
- [Code commenting standard](docs/design/engineering/code-commenting.md)
- [Feature strategy report](docs/feature-strategy-report.typ)
- [Brush node-graph routes report](docs/brush-node-graph-routes.typ)
- [Current status](docs/status.md)
- [Testing](docs/testing.md)
- [Task backlog](tasks/README.md)
