# Workspace persistence
## Scope
How a document file stores its **Workspace**, when it is written and applied, and how **Participants** of a multiplayer **Session** share layouts.
Out of scope: what a **Workspace** contains and how it behaves (see panes.md); the document's content; open dialogs, which are never stored; handling a **Workspace** that does not fit a small window (see panes.md, Open Questions).
## Definitions
Terms defined in panes.md are used here with the same meaning: **Workspace**, **Workspace area**, **Pane**, **Pane Mode**, **Per-mode state**.
Terms defined in canvas.md are used here with the same meaning: **Canvas Pane**, **View of a canvas**.
- **Workspace section**: A part of a document file, separate from the document's content, that holds at most one **Stored workspace**.
- **Stored workspace**: A **Workspace** as recorded in a **Workspace section**.
- **Flash**: The explicit user action that writes a document's current **Workspace** into the **Workspace section** of the document's file.
- **Default workspace**: A **Workspace** with one **Pane** in Canvas mode and default **Per-mode state**.
- **Unusable**: Describes a **Stored workspace** that cannot be read in full or that names a **Pane Mode** the system does not have.
- **Session**: One multiplayer editing session of one document.
- **Host**: The user who owns the shared file. Only the **Host** may save it, for now. Outside a **Session**, the only user is the **Host**.
- **Participant**: A user taking part in a **Session**, including the **Host**.
- **Own layout**: The **Workspace** a **Participant** holds for the shared document while following no one. It is never sent to the file except by **Flash**, and it exists only while the **Participant** is in the **Session**.
- **Following**: A **Participant** keeping their **Workspace** synchronized with that of another **Participant**.
## Requirements

WKSP-1 - The system shall record a **Stored workspace** only in the **Workspace section** of a document file, and never in the document's content.
WKSP-2 - When the **Host** performs **Flash**, the system shall write the **Workspace** the **Host** currently has for the document to the **Workspace section** of its file, replacing any previous **Stored workspace**.
WKSP-3 - The system shall write a **Workspace section** only when the **Host** performs **Flash** or when the user saves a document to a new file (WKSP-20).
WKSP-4 - When the user saves a document, the system shall preserve the **Workspace section** of the document's file.
WKSP-5 - The system shall not treat a change to a **Workspace** as a modification of the document.
WKSP-6 - The system shall not record a change to a **Workspace** in the document's undo history.
WKSP-7 - The system shall record each **Pane**'s rectangle as a fraction of the **Workspace area**, not as a size in pixels.
WKSP-8 - The system shall provide a user setting 'load stored workspaces', on by default.
WKSP-9 - While 'load stored workspaces' is on, when a document is opened, including by joining a **Session**, from a file with a usable **Stored workspace**, the system shall apply it as that document's **Workspace**.
WKSP-10 - While 'load stored workspaces' is off, the system shall ignore the **Workspace section** of every file it opens or joins.
WKSP-11 - If a document is opened, including by joining a **Session**, and the system does not apply a **Stored workspace** (the file has none, the **Stored workspace** is **Unusable**, or the setting is off), then the system shall give the document a copy of the **Workspace** that was active when it was opened, or the **Default workspace** when none was.
WKSP-12 - If a **Stored workspace** is **Unusable**, then the system shall load the document's content as if the file had no **Workspace section**.
WKSP-13 - Retired.
WKSP-14 - Retired.
WKSP-15 - Retired.
WKSP-16 - Retired.
WKSP-17 - Retired.
WKSP-18 - Retired.
WKSP-19 - Retired.
WKSP-20 - When the user saves a document to a new file, the system shall include in the new file the **Workspace section** of the source file, if it has one.
WKSP-21 - When a **Participant** leaves a **Session**, the system shall discard that **Participant**'s **Own layout** for the shared document.
WKSP-22 - The system shall allow a **Participant** to choose one other **Participant** to follow, and to stop following.
WKSP-23 - While a **Participant** is **Following** another, the system shall keep the follower's **Workspace** identical to the followed **Participant**'s **Workspace**, including the **View of a canvas** in every **Canvas Pane**.
WKSP-24 - While a **Participant** is **Following** another, the system shall not allow that **Participant** to change their **Workspace**.
WKSP-25 - When a **Participant** stops **Following**, the system shall restore the **Own layout** that **Participant** had when they began **Following**.
WKSP-26 - If a **Participant** chooses to follow someone who is, directly or through others, following them, then the system shall refuse the choice.
WKSP-27 - When the **Participant** being followed leaves the **Session**, the system shall make each of that **Participant**'s followers stop **Following**.
WKSP-28 - The system shall allow only the **Host** to perform **Flash**.
WKSP-29 - When the **Host** performs **Flash**, the system shall leave every other **Participant**'s **Workspace** unchanged.
WKSP-30 - While a **Participant** is **Following** another, the system shall scale the followed **Workspace** to the follower's **Workspace area**, keeping each **Pane**'s rectangle the same fraction of it.

## Acceptance Examples
- Rearrange panes, save, close, reopen: the layout is the one from before the rearranging. Rearrange panes, **Flash**, close, reopen: the rearranged layout returns.
- **Flash**, then change the layout and save: reopening gives the flashed layout.
- Corrupt the **Workspace section** by hand, reopen: the strokes load and the layout is the active one.
- Save to a new file after a **Flash**: the new file opens with the flashed layout.
- Participant B follows participant A. A splits a pane and pans a canvas: B's panes and canvas view change the same way, in proportion to B's window. B stops following: B's earlier layout returns.
- B follows A and the **Host** performs **Flash**: B's layout does not change.

## Open Questions
- While the **Host** is **Following** another **Participant**, does **Flash** write the layout the **Host** sees (the followed one, as WKSP-2 reads) or the **Host**'s **Own layout**?
- Multiplayer itself has no spec yet; the **Session**, **Host**, and **Participant** definitions and the rule that only the **Host** may save belong there once it exists.
