# Decisions

| No. | Title | Status |
| --- | --- | --- |
| [001](001-undo-redo.md) | Undo is implemented as a command history, not document snapshots | superseded |
| [002](002-code-commenting.md) | Code commenting standard | accepted |
| [003](003-vector-canvas.md) | Vector Canvas, Input, and Viewports | superseded |
| [004](004-tile-cache.md) | Tile Cache and Bounded Active Chunks | accepted |
| [005](005-pencil-splats.md) | Pencil Stroke Rendering as Gaussian Splats | accepted |
| [006](006-workspace-in-file.md) | A document file stores its workspace in a separate section written only by an explicit Flash | superseded |
| [007](007-crdt-automerge.md) | Shared state is held in Automerge documents, reached through a narrow CRDT port and our own FFI binding | accepted |
| [008](008-document-file-format.md) | A document file is a binary container holding the Automerge content document and the workspace section | accepted |
| [009](009-shared-workspaces.md) | Workspaces live in an in-memory session document that Participants share by joining; a file stores one only through Flash | accepted |
| [010](010-pane-layout-tree.md) | A workspace's layout is a table of tree nodes in the session document, shown through a deterministic projection | accepted |
| [011](011-relative-canvas-view.md) | A canvas view is stored as a center, an extent across the pane's shorter side, and a rotation | accepted |
| [012](012-undo-per-participant.md) | Undo replays inverse actions on the shared document, per Participant | accepted |
| [013](013-session-networking.md) | Participants connect in a full mesh of WebSockets and run Automerge sync on each connection | accepted |
