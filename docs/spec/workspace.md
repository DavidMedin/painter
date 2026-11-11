# Workspace persistence and sharing
## Scope
How a document file stores its **Workspace**, when it is written and applied, and how **Participants** of a **Session** share **Workspaces**.
Out of scope: what a **Workspace** contains and how its **Panes** behave (see panes.md); the document's content; open dialogs, which are never stored; handling a **Workspace** that does not fit a small window (see panes.md, Open Questions); starting, joining, and leaving a **Session** (see multiplayer.md).
## Definitions
Terms defined in panes.md are used here with the same meaning: **Workspace**, **Workspace area**, **Pane**, **Pane Mode**, **Per-mode state**, **Layout tree**.
Terms defined in canvas.md are used here with the same meaning: **Canvas Pane**, **View of a canvas**.
Terms defined in multiplayer.md are used here with the same meaning: **Session**, **Host**, **Participant**.
- **Workspace section**: A part of a document file, separate from the document's content, that holds at most one **Stored workspace**.
- **Stored workspace**: A **Workspace** as recorded in a **Workspace section**.
- **Flash**: The explicit user action that writes the user's current **Workspace** into the **Workspace section** of the document's file.
- **Default workspace**: A **Workspace** with one **Pane** in Canvas mode and default **Per-mode state**.
- **Unusable**: Describes a **Stored workspace** that cannot be read in full or that names a **Pane Mode** the system does not have.
- **Member**: A **Participant** shown a given **Workspace**. Every **Participant** is a **Member** of exactly one **Workspace** of the shared document.
- **Joining a workspace**: A **Participant** becoming a **Member** of the **Workspace** of another **Participant**.
## Requirements

WKSP-1 - The system shall record a **Stored workspace** only in the **Workspace section** of a document file, and never in the document's content.
WKSP-2 - When a **Participant** performs **Flash**, the system shall write the **Workspace** that **Participant** is a **Member** of to the **Workspace section** of the file that **Participant** saves the document to, replacing any previous **Stored workspace**.
WKSP-3 - The system shall write a **Workspace section** only when a **Participant** performs **Flash** or when the user saves a document to a new file (WKSP-20).
WKSP-4 - When the user saves a document, the system shall preserve the **Workspace section** of the document's file.
WKSP-5 - The system shall not treat a change to a **Workspace** as a modification of the document.
WKSP-6 - The system shall not record a change to a **Workspace** in the document's undo history.
WKSP-7 - The system shall record a **Workspace** as a **Layout tree** of fractions of the **Workspace area**, with each **View of a canvas** in the form of CNVS-7, and never as sizes in pixels.
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
WKSP-21 - When no **Participant** in the **Session** is a **Member** of a **Workspace** or would return to it on leaving a joined **Workspace** (WKSP-37), the system shall discard that **Workspace**.
WKSP-22 - Retired.
WKSP-23 - Retired.
WKSP-24 - Retired.
WKSP-25 - Retired.
WKSP-26 - Retired.
WKSP-27 - Retired.
WKSP-28 - Retired.
WKSP-29 - When a **Participant** performs **Flash**, the system shall leave every **Workspace** of the **Session** unchanged.
WKSP-30 - Retired.
WKSP-31 - When a user starts or joins a **Session**, the system shall make that user the only **Member** of a new **Workspace** whose content WKSP-9 and WKSP-11 determine.
WKSP-32 - The system shall allow a **Participant** to join the **Workspace** of any other **Participant** of the same **Session**.
WKSP-33 - When a **Member** changes a **Workspace**, including any **View of a canvas** in it, the system shall apply the change for every other **Member** of that **Workspace**.
WKSP-34 - While a **Member** is changing a **Workspace**, the system shall send the change to the other **Members** at least every 100 ms.
WKSP-35 - When **Members** of a **Workspace** have received the same changes, including changes made at the same time, the system shall show every one of them the same **Layout tree**, **Pane Modes**, and **Per-mode state**.
WKSP-36 - The system shall allow a **Participant** who joined a **Workspace** to leave it.
WKSP-37 - When a **Participant** leaves a joined **Workspace**, the system shall make that **Participant** a **Member** of the **Workspace** they were a **Member** of before joining if it still exists, or else the only **Member** of a new copy of the **Workspace** they left.
WKSP-38 - When a **Participant** leaves the **Session**, the system shall end that **Participant**'s membership of their **Workspace**.

## Acceptance Examples
- Rearrange panes, save, close, reopen: the layout is the one from before the rearranging. Rearrange panes, **Flash**, close, reopen: the rearranged layout returns.
- **Flash**, then change the layout and save: reopening gives the flashed layout.
- Corrupt the **Workspace section** by hand, reopen: the strokes load and the layout is the active one.
- Save to a new file after a **Flash**: the new file opens with the flashed layout.
- Participant B joins participant A's **Workspace**. A splits a pane and B pans a canvas: both see the split and the pan, each scaled to their own window. B leaves the **Workspace**: B's earlier layout returns, and A's **Workspace** keeps the split and the pan.
- A and B are **Members** of one **Workspace**. At the same moment A joins pane P into its neighbor Q and B joins Q into P: after both changes arrive, A and B see the same single **Pane** where P and Q were.
- A starts a **Session**, B joins A's **Workspace**, A leaves the **Session**: B keeps the **Workspace**. B leaves the **Session** too: the **Workspace** is discarded.
- B, who is not the **Host**, performs **Flash** after saving to a file of their own: their file stores B's **Workspace**, and nobody's **Workspace** changes.

## Open Questions
None.
