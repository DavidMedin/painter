# Code commenting standard

## Status

Accepted. Directed by the project owner.

## Context

The code base has several non-trivial systems (tile cache, pencil splats, isolate worker, debug widget kit, open/save flow) whose files are tightly coupled to each other. The reason a file exists, or why two functions must change together, is not visible from the code alone, and several pre-existing comments had drifted from the code (see "Code Comments Verification" in [status.md](../status.md)).

## Decision

All Dart code in `lib/` and `test/` follows this standard. It applies to new code and to changes to existing code.

1. **File header.** Every file starts with a `//` block (not `///`, because it is not attached to a declaration) with `What:` (what the file contains) and `Why:` (why the file exists and why it is separate). Name the other files it is coupled to. Test files also say what behavior they verify, why, and which `lib/` code they cover.
2. **System overview.** Where a set of files implements a general system, the primary file carries a semi-large block comment (roughly 15-40 lines) covering what it is, why it exists (the problem and the rejected alternative, citing the ADR), and how it works (data flow, threading and isolate boundaries, invariants). Other files in the system point to it instead of repeating it.
3. **Functions.** A `///` doc comment on every function, class, or method that is not obvious from its name and body: what it does and, if non-obvious, why. No line-by-line narration. Short `//` step comments only where the logic is subtle (math, ordering, concurrency, invariants).
4. **Coupling.** If a function is heavily coupled to others (calls them, shares an invariant, must change with them), the comment names them. Every named symbol must exist; check it when writing and when renaming.
5. **Truthful justification.** A rationale must come from the code, an ADR, or the status docs. If the reason is not recorded anywhere, describe what the code does and ask the owner; do not invent a reason.
6. **Keep comments current.** A change that makes a comment wrong must fix the comment in the same change. A wrong comment is worse than none.
7. Wrap comments at 80 columns, matching the existing code.

## Consequences

- Reviewing a change includes checking that its comments still match the code, and that renamed symbols are updated in comments that name them.
- Comments that cite function names are a maintenance cost: renames must also update them. This was accepted because the owner wants coupling visible.
- Nothing mechanical enforces this today; `flutter analyze` does not check comment content. Compliance is by review.
