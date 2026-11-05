# Agent Instructions

## Before editing

At the start of every session, read these files in order:

1. `README.md`
2. `docs/status.md`
3. `docs/project-brief.md`
4. `docs/design/README.md`, then `docs/design/architecture-overview.md`
5. The `behavior.md` and design documents of each system the task touches, under `docs/design/`
6. `tasks/README.md`
7. The selected task in `tasks/ROADMAP.md`

## Working rules

- Work on one roadmap task at a time. Respect its acceptance criteria and dependencies.
- When a task is complete, update its status in `tasks/ROADMAP.md`. Update `docs/status.md` only to remove the work it listed as open and to list anything still unverified; it records no completed work.
- Describe what a system does in its `behavior.md`, in EARS+. Record durable technical choices in a design document in the same system folder under `docs/design/`; do not treat proposals as decisions. Keep `docs/design/README.md` in step with the tree.
- Distinguish verified facts from assumptions. Do not invent product requirements or claim unsupported platform support.
- Follow the [code commenting standard](docs/design/engineering/code-commenting.md) for all code in `lib/` and `test/`. Other coding conventions and code architecture are not prescribed beyond what `docs/design/` records.
