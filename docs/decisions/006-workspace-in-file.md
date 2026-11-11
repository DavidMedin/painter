# 006. A document file stores its workspace in a separate section written only by an explicit Flash

Status: accepted   (supersedes: 003; superseded by: none)
Date: 2026-11-11
Relates to: WKSP-1, WKSP-2, WKSP-3, WKSP-4, WKSP-22, WKSP-23, PANE-22

## Context
Work on a large project can leave a deeply personalized pane layout, and losing it on close costs the user real time. The document file is the natural owner of that layout. Three risks follow from putting it there:

- Layout changes are frequent and meaningless to a reader of the document. If every save rewrites the layout, version-control diffs are noisy.
- In a multiplayer session a layout belongs to one user. Sharing it by default would overwrite collaborators' layouts.
- The saved format today holds strokes only. A corrupt or unfamiliar layout must not stop a document from loading.

## Decision
Embed the workspace in the document file as a section separate from the document's content. Write that section only when the host performs an explicit Flash; saving the document leaves it untouched. In a multiplayer session each participant holds an ephemeral layout of their own, and shares layouts only by choosing to follow another participant.

## Alternatives considered
- **Sidecar file next to the document.** Keeps the document bytes clean, but the layout is lost when the file is moved or sent alone. Rejected on portability.
- **Write the workspace on every save.** The user never has to remember to Flash, but every save that follows a layout change changes the file. Rejected on version-control churn.
- **Store the workspace inside the document's content.** Simplest format, but it ties layout to content, so content diffs and multiplayer sync would carry layout. Rejected.
- **Keep the layout only in global user settings.** Avoids all file concerns, but one layout cannot suit every project. Rejected, since the point is per-file layouts.
- **One layout shared by the whole session when enabled.** Simple to explain, but two participants changing it at once would conflict. Rejected for following, where only the followed participant can change a layout.

## Consequences
- Explicit Flash means a user can lose layout changes they forgot to flash. The cost was accepted to avoid churn.
- Layout changes are not document modifications, so they neither mark the document modified nor enter undo history.
- Positions are stored as fractions of the workspace area, so a layout fits different window sizes and a participant's screen size never needs to be known by others. How a layout behaves in a window too small for the 100 px pane minimum is deferred (panes.md, Open Questions).
- A Canvas pane's view is per-mode state and is stored in the workspace section. This replaces decision 003's statements (PNT-A0012-04, PNT-A0012-05) that views are transient, reset on open, and not saved in the document format.
- Decision 003 is superseded entirely, as it already was by decision 005. Its requirements on stroke storage, pointer and trackpad input, and prototype parameters are no longer recorded in an accepted decision.
- Headless export ignores the workspace section.

## Revisit if
Users routinely lose layouts by forgetting to Flash, or the workspace section grows large enough to affect load time.
