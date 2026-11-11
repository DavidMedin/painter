# Document file
## Scope
What a document file holds, and opening and saving it.
Out of scope: the **Workspace section** (see workspace.md); headless export (see headless.md).
## Definitions
Terms defined in multiplayer.md are used here with the same meaning: **Engine version**, **Session**.
Terms defined in workspace.md are used here with the same meaning: **Workspace section**.
- **Stroke**: A continuous input from an input device, such as a mouse or stylus, as stored in a document.
- **Change history**: Every change made to a document's content since it was created, including changes that were later undone.
- **Earlier format**: The JSON stroke-list format that documents were saved in before the **Change history** was stored.
## Requirements

DOCF-1 - The system shall save a document's content together with its **Change history**.
DOCF-2 - The system shall give every **Stroke** an identity that stays the same across saving, opening, and **Sessions**.
DOCF-3 - The system shall open files in the **Earlier format**, rendering their **Strokes** as that format rendered them.
DOCF-4 - When the user saves a document that was opened from a file in the **Earlier format**, the system shall write the current format.
DOCF-5 - The system shall record in each file the **Engine version** its **Strokes** are rendered with.
DOCF-6 - If a file records an **Engine version** the system does not have, then the system shall refuse to open it and show the file's and the system's **Engine versions**.
DOCF-7 - If a file's content cannot be read in full, then the system shall refuse to open it, show the reason, and leave the current document unchanged.
DOCF-8 - When the user saves a document, the system shall write to the file the document's associated path, asking for a path when none is associated.

## Acceptance Examples
- Open a file saved by the previous version of Painter: it looks as it did. Save it, reopen it: it still looks the same.
- Draw, undo, save, reopen: the undone **Stroke** is not shown, but the file still records that it was drawn and undone.
- Open a file from a build with a newer **Engine version**: an error names both versions and the current document stays open.

## Open Questions
- Should the user be able to merge two copies of a document that were edited apart, using their **Change histories**?
