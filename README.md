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
- [Project brief](docs/intent.md)
- [Documentation format](docs/docs-format.md)
- [Specs](docs/spec/): one EARS behavior spec per capability
- [Decisions](docs/decisions/README.md)
- [Code commenting standard](docs/decisions/002-code-commenting.md)
- [Plan](docs/plan.md)
- [Non-compliance](docs/non-compliance.md)
