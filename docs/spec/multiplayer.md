# Multiplayer
## Scope
How several users edit one document together over a network: starting, joining, and leaving a **Session**, the **Host** role, keeping the document the same for everyone, and saving.
Out of scope: how **Workspaces** are shared (see workspace.md); undo (see undo-redo.md); finding a **Session** without knowing a **Session address**; connecting across networks that block direct connections; authentication and encryption (see Open Questions).
## Definitions
- **Session**: One multiplayer editing session of one document.
- **Participant**: A user taking part in a **Session**, including the **Host**.
- **Host**: The **Participant** shown as the owner of the **Session**. At first, the user who started it. Outside a **Session**, the only user is the **Host**.
- **Session address**: A network address and port at which a **Participant** accepts other users into the **Session**.
- **Engine version**: The version of the rules that turn a document's stored strokes into pixels.
## Requirements

MPLY-1 - The system shall allow the user to start a **Session** for the active document, becoming its **Host**.
MPLY-2 - When the user starts a **Session**, the system shall show the **Session addresses** at which other users can join it.
MPLY-3 - The system shall allow the user to join a **Session** by entering the **Session address** of any of its **Participants**.
MPLY-4 - When a user joins a **Session**, the system shall make the **Session**'s document that user's active document.
MPLY-5 - The system shall connect every **Participant** of a **Session** directly to every other **Participant**, without a server.
MPLY-6 - When a **Participant** changes the document, the system shall apply the change for every other **Participant**.
MPLY-7 - When **Participants** have received the same changes, including changes made at the same time, the system shall show every one of them the same document content.
MPLY-8 - If a joining user's **Engine version** differs from the **Session**'s, then the system shall refuse the join and show the user both **Engine versions**.
MPLY-9 - The system shall show every **Participant** the name of each **Participant**, marking the **Host**.
MPLY-10 - When a user starts or joins a **Session**, the system shall ask for the name to show the other **Participants**, offering the user's account name.
MPLY-11 - When the **Host** promotes another **Participant**, the system shall make that **Participant** the **Host**.
MPLY-12 - When the **Host** leaves a **Session**, the system shall make the remaining **Participant** who joined earliest the **Host**.
MPLY-13 - The system shall allow every **Participant** to save the document to a file of their own.
MPLY-14 - When a user joins a **Session**, the system shall leave the joined document without an associated file.
MPLY-15 - The system shall allow a **Participant** to leave the **Session**.
MPLY-16 - When a **Participant** leaves a **Session**, the system shall keep that **Participant**'s document open with every change received until then.
MPLY-17 - If the system receives nothing from a **Participant** for 10 seconds, then the system shall treat that **Participant** as having left the **Session**.
MPLY-18 - When a **Participant** leaves a **Session**, the system shall keep the **Session** going for the remaining **Participants**.

## Acceptance Examples
- A opens a file and starts a **Session**; the **Session** pane lists A's addresses. B enters one of them and joins: B sees A's strokes, and both see A as **Host**.
- A and B draw at the same moment: each sees both strokes, stacked in the same order.
- C joins by entering B's address instead of A's: C is connected to both A and B.
- A promotes B and leaves: B is **Host**. Had A left without promoting, the earliest-joined remaining **Participant** would be **Host**.
- B saves: B is asked for a file path, and A's file is not touched.
- D's build renders strokes differently from A's: D's join is refused, naming both **Engine versions**.
- B's network cable is pulled: after 10 seconds A and C no longer list B, and B is left alone with the document as last received.

## Open Questions
- Who may join a **Session**? Anyone who can reach a **Session address** can join today; a password or invitation scheme is undecided.
- Should a **Participant** whose connection dropped be able to rejoin and merge the changes made on each side while apart?
- What should Open do during a **Session**: leave it, or open the file outside it? Open is disabled while in a **Session** until this is decided.
