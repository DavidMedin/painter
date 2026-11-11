# Panes
## Scope
Out of scope: Panes across multiple OS windows.
## Definitions
- **Application window**: The single OS window containing the whole user interface.
- **Workspace area**: The area of the **Application window** reserved for **Panes**.
- **Workspace**: The **Panes** of one open document, with their rectangles, **Pane Modes**, and **Per-mode state**. The **Panes** of a **Workspace** together fill the **Workspace area** while that document's tab is active.
- **Pane**: A rectangular region within the **Workspace area**.
- **Frame**: The border around a **Pane**'s toolbar and content area.
- **Frame edge**: One of the four sides of a **Frame**.
- **Neighbor**: The **Pane** whose **Frame edge** coincides exactly, along its whole length, with a given **Frame edge**. A **Frame edge** has at most one **Neighbor**. A **Frame edge** bordered by several **Panes**, or by none, has no **Neighbor**.
- **Splitter**: The area between a **Pane** and its other **Panes**.
- **Pane Mode**: The kind of content a **Pane** shows in its content area.
- **Per-mode state**: The state a **Pane** keeps for one **Pane Mode**, for example a canvas view.
## Requirements

PANE-1 - The system shall not allow **Panes** to overlap or to leave gaps in the **Workspace area**.
PANE-2 - The system shall draw a **Frame** around every **Pane**.
PANE-3 - When the handle at the center of a **Splitter** is dragged, the system shall resize the **Panes** it borders.
PANE-4 - The system shall give every **Pane** a toolbar over the whole top edge.
PANE-5 - Retired.
PANE-6 - The system shall keep each **Pane** in exactly one **Pane Mode** at a time.
PANE-7 - The system shall place on the far left of each **Pane** toolbar a dropdown that selects the **Pane**'s **Pane Mode**.
PANE-8 - The system shall show in each **Pane**'s content area the content of its **Pane Mode**.
PANE-9 - The system shall keep at least one **Pane** in the **Workspace**.
PANE-10 - The system shall place a frame toolbar along each **Frame edge** of every **Pane**.
PANE-11 - While a frame toolbar is on a left or right **Frame edge**, the system shall rotate it 90 degrees counter-clockwise or 90 degrees clockwise respectively.
PANE-12 - The system shall provide the buttons 'add', 'join', and 'swap' on every frame toolbar.
PANE-13 - When the 'add' button of **Frame edge** E of **Pane** P is activated, the system shall split P in two along a line parallel to E, give the half touching E to a new **Pane** in P's **Pane Mode** with a copy of P's **Per-mode state**, and keep the other half in P.
PANE-14 - If **Frame edge** E has no **Neighbor**, then the system shall disable the 'join' and 'swap' buttons on E's frame toolbar.
PANE-15 - When the 'join' button of **Frame edge** E of **Pane** P is activated, the system shall remove E's **Neighbor** and extend P over the space it occupied, keeping P's **Pane Mode**.
PANE-16 - When the 'swap' button of **Frame edge** E of **Pane** P is activated, the system shall exchange the **Pane Mode** and **Per-mode state** of P and E's **Neighbor**, leaving both rectangles unchanged.
PANE-17 - The system shall place a **Splitter** on every **Frame edge** that borders another **Pane**.
PANE-18 - If a **Splitter** drag would make a **Pane** smaller than 100 px in either dimension, then the system shall clamp that **Pane** to 100 px in that dimension.
PANE-19 - If P's extent perpendicular to **Frame edge** E is less than 200 px, then the system shall disable the 'add' button on E's frame toolbar.
PANE-20 - When a **Pane**'s **Pane Mode** is changed away from a mode and later changed back to it, the system shall restore the **Per-mode state** the **Pane** had for that mode.
PANE-21 - Retired.
PANE-22 - The system shall keep one **Workspace** for each open document.
PANE-23 - When the active tab changes, the system shall show the **Workspace** of the newly active tab's document in the **Workspace area**.

## Acceptance Examples

## Open Questions
- What happens when the **Application window** is too small for every **Pane** to be 100 px in both dimensions? Deferred: for now the system does not constrain the **Application window**, and a **Workspace** is not changed to fit it.
