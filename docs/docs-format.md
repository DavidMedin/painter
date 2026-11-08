# Documentation structure and validation rules

Purpose: define the documentation layout and formats so a reader or agent can
verify them mechanically. A rule marked **[check]** can be verified by script
or grep. A rule marked **[review]** needs judgment.

## 1. Layout

```
intent.md
spec/<capability>.md          # one file per capability, kebab-case name
decisions/NNN-<slug>.md       # NNN = zero-padded 3-digit sequence number
decisions/README.md           # index of all decisions
plan.md
open-questions.md
AGENTS.md
```

- **[check]** Every file above exists. No other `.md` files exist under
  `spec/` or `decisions/`.
- **[check]** File names in `spec/` and `decisions/` match `^[a-z0-9-]+\.md$`;
  decision files match `^\d{3}-[a-z0-9-]+\.md$`.
- **[check]** Decision numbers are unique, start at `001`, and have no gaps.

## 2. `intent.md`

- **[check]** Contains the headings `Purpose`, `Users`, `Non-goals`, `Constraints`.
- **[check]** Is no longer than 100 lines.
- **[review]** Contains no requirements, status, or implementation detail.

## 3. Behavior specs (`spec/*.md`)

Required headings, in order: `Scope`, `Definitions`, `Requirements`,
`Acceptance examples`, `Open questions`. A heading may hold the single line
`None.`

Requirement format:

- **[check]** Each requirement is one entry that starts with an ID matching
  `^[A-Z]{2,6}-\d+$`. The prefix is unique to the file and the numbers
  ascend.
- **[check]** IDs are unique across `spec/`. A removed ID is never reused;
  retire it with the line `<ID> Retired.`
- **[check]** The body of each requirement matches one EARS template:
  - `The system shall …`
  - `When <trigger>, the system shall …`
  - `While <state>, the system shall …`
  - `If <condition>, then the system shall …`
  - Templates may be combined, for example `While … , when … , the system shall …`.
- **[check]** Each requirement contains exactly one `shall`.
- **[check]** Every capitalized term in a requirement that appears under
  `Definitions` is defined there. Defined terms are bolded.
- **[check]** No requirement contains status words (`done`, `implemented`,
  `TODO`, `WIP`, `planned`) or version markers.
- **[review]** Each requirement is observable from outside the system and
  can be tested without knowing the implementation.
- **[review]** Requirements state numbers and failure behavior explicitly.

## 4. Decisions (`decisions/NNN-<slug>.md`)

- **[check]** The first line is `# NNN. <statement>`, and `NNN` matches the
  file name.
- **[check]** A `Status:` line holds one of `proposed`, `accepted`, `rejected`,
  `superseded`.
- **[check]** Contains the headings `Context`, `Decision`, `Alternatives
  considered`, `Consequences`. `Revisit if` is optional.
- **[check]** `Alternatives considered` has at least one entry unless
  `Status` is `proposed`.
- **[check]** Supersession is symmetric: a decision with `superseded by: M`
  exists only if decision `M` lists `supersedes: N`, and `M` is `accepted`.
- **[check]** Every `Relates to:` ID exists in `spec/` and is not retired.
- **[check]** `decisions/README.md` lists every decision with its number,
  title, and status, and those match the files.
- **[review]** The `Decision` section is one decision, stated directly.
  Substantive edits to an `accepted` decision are not allowed; use a new one.

## 5. Plan (`plan.md`)

- **[check]** Each item has a title, `Acceptance criteria`, and `Covers:`
  followed by one or more requirement IDs.
- **[check]** Every `Covers:` ID exists in `spec/`.
- **[check]** Items are ordered and contain no completed work. Finished items
  are deleted.
- **[review]** Each criterion can be verified by running the system.

## 6. Open questions (`open-questions.md`)

- **[check]** Each entry has an ID matching `^Q-\d+$`, a question, and an
  `Affects:` line naming spec or decision IDs that exist.
- **[check]** A question that appears in a spec's `Open questions` section
  also has a `Q-` entry here.

## 7. Cross-document rules

- **[check]** Every requirement ID in `spec/` is cited by at least one
  test, or appears in a `plan.md` item. An uncited ID is reported.
- **[check]** Every ID cited in a test or in `plan.md` exists in `spec/`.
- **[check]** Every relative link in any `.md` file resolves.
- **[check]** A fact is stated in one place. Another file refers to it by ID
  or link and never restates it. (Detect duplicated requirement text with a
  string match.)
- **[review]** Text outside `decisions/` never explains why a choice was made.
  Text outside `spec/` never defines required behavior.

## 8. Agent check procedure

1. Run all **[check]** rules and report each failure as
   `<file>:<line> <rule section> <message>`.
2. For files changed in the current work, apply the **[review]** rules and
   list any concerns separately from the mechanical failures.
3. Do not edit a requirement, decision, or plan to make a check pass without
   saying so. If a check fails because the rule is wrong, report that rather
   than working around it.
4. The structure is valid when there are no **[check]** failures and no
   unaddressed **[review]** concerns.
