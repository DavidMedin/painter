# Architecture Decision Records

Use this directory for durable technical or product decisions that have actually been made.

## Convention

- Add one numbered Markdown file per decision, named `NNNN-kebab-case.md` (for example, `0001-example-decision.md`).
- Each record must include `Status`, `Context`, `Decision`, and `Consequences` sections.
- Link to the decision an ADR supersedes, when applicable.
- Never record undecided proposals as decisions. Do not create ADRs for choices that remain open in the project brief or architecture page.

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
