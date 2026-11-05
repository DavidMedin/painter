# Task Backlog

Notation: requirements use EARS+ as defined in [the design index](../docs/design/README.md#requirement-notation-ears). IDs are `PNT-TSK-<NNN>`; each has a `Source:` line.

## Backlog

- **PNT-TSK-001** The project shall keep every task record in [`ROADMAP.md`](ROADMAP.md) as the single canonical backlog.
  Source: project owner.
- **PNT-TSK-002** The project shall not create a parallel task list outside `ROADMAP.md`.
  Source: project owner.

## Required Task Fields

- **PNT-TSK-003** Every task entry shall include a unique ID and title.
  Source: project owner.
- **PNT-TSK-004** Every task entry shall include a priority of `P0` or `P1`.
  Source: project owner.
- **PNT-TSK-005** Every task entry shall include a status of `todo`, `in-progress`, `blocked`, or `done`.
  Source: project owner.
- **PNT-TSK-006** Every task entry shall include its dependencies as task IDs or `none`.
  Source: project owner.
- **PNT-TSK-007** Every task entry shall include an outcome.
  Source: project owner.
- **PNT-TSK-008** Every task entry shall include observable acceptance criteria, each written as an EARS+ requirement.
  Source: this conversion; project owner.

## Workflow

- **PNT-TSK-009** Each task's dependencies shall be `done` before that task starts.
  Source: project owner.
- **PNT-TSK-010** The project shall keep exactly one task `in-progress` at a time.
  Source: project owner.
- **PNT-TSK-011** IF a task's prerequisite is missing and concrete, THEN the project shall mark that task `blocked`.
  Source: project owner.
- **PNT-TSK-012** The project shall not mark a task `blocked` without naming the concrete missing prerequisite.
  Source: project owner.
- **PNT-TSK-013** WHEN every acceptance criterion of a task is verified, the project shall mark that task `done`.
  Source: project owner.
- **PNT-TSK-014** The project shall not mark a task `done` while any of its acceptance criteria is unverified.
  Source: project owner.
- **PNT-TSK-015** The project shall keep completed task records in the roadmap.
  Source: project owner.
