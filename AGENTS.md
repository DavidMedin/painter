# Agent Instructions

## Before editing

At the start of every session, read these files in order:

1. `README.md`
2. `docs/docs-format.md`
3. `docs/intent.md`
4. The specs in `docs/spec/` and the decisions in `docs/decisions/` of each capability the task touches
5. `docs/plan.md` and `docs/non-compliance.md`

## Working rules

- Work on one `docs/plan.md` item at a time. Respect its acceptance criteria.
- When a plan item is complete, delete it from `docs/plan.md`.
- Describe required behavior in `docs/spec/` and record decisions in `docs/decisions/`, in the formats `docs/docs-format.md` sets; do not treat proposals as decisions. Keep `docs/decisions/README.md` in step with the decisions.
- Distinguish verified facts from assumptions. Do not invent product requirements or claim unsupported platform support.
- Follow the [code commenting standard](docs/decisions/002-code-commenting.md) for all code in `lib/` and `test/`. Other coding conventions and code architecture are not prescribed beyond what `docs/decisions/` records.
- Log as [the logging spec](docs/spec/logging.md) and [decision 014](docs/decisions/014-logging.md) require. A change that adds or changes an Operation, a user edit, or a `catch` block adds its Log record and catalog message in the same change.
