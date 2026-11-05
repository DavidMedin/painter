# Code commenting standard

## Status

Accepted. Directed by the project owner.

## Context

The code base has several non-trivial systems (tile cache, pencil splats, isolate worker, debug widget kit, open/save flow) whose files are tightly coupled to each other. The reason a file exists, or why two functions must change together, is not visible from the code alone, and several pre-existing comments had drifted from the code.

## Decision

Requirements use EARS+ ([notation](../README.md#requirement-notation-ears)); IDs are `PNT-A<NNNN>-<NN>`.

All Dart code in `lib/` and `test/` follows this standard. It applies to new code and to changes to existing code.

- **PNT-A0007-01** Every file shall start with a `//` block (not `///`, because it is not attached to a declaration) containing `What:` (what the file contains) and `Why:` (why the file exists and why it is separate), and shall name the other files it is coupled to.
- **PNT-A0007-02** WHERE a file is a test file, its header shall also state what behavior it verifies, why, and which `lib/` code it covers.
- **PNT-A0007-03** WHERE a set of files implements a general system, the primary file shall carry a block comment of roughly 15-40 lines covering what the system is, why it exists (the problem and the rejected alternative, citing the design document), and how it works (data flow, threading and isolate boundaries, invariants).
- **PNT-A0007-04** The other files in a system shall point to the system overview instead of repeating it.
- **PNT-A0007-05** Every function, class, or method that is not obvious from its name and body shall carry a `///` doc comment stating what it does and, if non-obvious, why.
- **PNT-A0007-06** A comment shall not narrate code line by line; short `//` step comments shall appear only where the logic is subtle (math, ordering, concurrency, invariants).
- **PNT-A0007-07** WHERE a function is heavily coupled to others (it calls them, shares an invariant with them, or changes together with them), its comment shall name them.
- **PNT-A0007-08** Every named symbol in a comment shall exist, checked when the comment is written and when a symbol is renamed.
- **PNT-A0007-09** A comment's rationale shall come from the code, a design document, or the status document.
- **PNT-A0007-10** IF the reason for code is not recorded anywhere, THEN the author shall describe what the code does and ask the owner, and shall not invent a reason.
- **PNT-A0007-11** WHEN a change makes a comment wrong, the same change shall fix the comment.
- **PNT-A0007-12** Comments shall wrap at 80 columns.
- **PNT-A0007-13** WHEN a comment cites a design decision, the comment shall cite the design document by its path under `docs/design/` and shall not cite it by a number.


## Consequences

- Reviewing a change includes checking that its comments still match the code, and that renamed symbols are updated in comments that name them.
- Comments that cite function names are a maintenance cost: renames must also update them. This was accepted because the owner wants coupling visible.
- Nothing mechanical enforces this today; `flutter analyze` does not check comment content. Compliance is by review.
