# 010. A workspace's layout is a table of tree nodes in the session document, shown through a deterministic projection

Status: accepted   (supersedes: none; superseded by: none)
Date: 2026-11-11
Relates to: PANE-1, PANE-3, PANE-9, PANE-13, PANE-15, PANE-16, PANE-24, PANE-25, PANE-26, PANE-27, WKSP-7, WKSP-35

## Context
The layout was a set of unit-square rectangles (`lib/workspace/pane_layout.dart`), which kept PANE-1 only because one user edited it at a time. Merged per key under concurrency, two edits can leave rectangles overlapping or apart. The owner chose a tree, which has no gaps by construction, and chose to allow joins of aligned non-sibling panes by reshaping the tree when the result is still a tree. A CRDT merges values, not invariants, so whatever the merge produces must still display as a valid tree, identically on every peer.

## Decision
- **PNT-A0016-01** A workspace's `nodes` map shall map node ids to node maps holding `parent` (absent for the root), `kind` (`"split"` or `"pane"`), `order` (a fractional-index string), `share` (positive number), and for splits `axis` (`"row"` places parts left to right, `"column"` top to bottom), and for panes `mode` (a Pane Mode name), `state` (map from mode name to that mode's state map) and `deleted` (bool). The root is the split with id `root`.
- **PNT-A0016-02** The shown layout shall be the projection of `nodes`, computed the same way by every peer: walk down from `root`; a node's children are the nodes naming it as `parent` that are not deleted panes, sorted by `order` then id; a node reached twice is skipped (so cycles from concurrent moves end); a split with no shown children is dropped; a split with one is replaced by that child, which takes the split's share; a split child with its parent's axis is flattened into the parent, its parts' shares scaled to its share; shares in each split are normalized to sum to 1, a non-positive or non-finite share counting as the mean of the valid ones.
- **PNT-A0016-03** IF the projection shows no pane, THEN the Painter shall show the pane node with the smallest id, deleted or not, as the only pane (PANE-9).
- **PNT-A0016-04** Each shown node shall remember its anchor, the outermost stored node whose position in the tree it occupies after collapsing; edits write position and share to anchors.
- **PNT-A0016-05** Add (PANE-13) shall insert a new pane beside the anchor when the anchor's parent split runs along the edge's normal, halving the anchor's share between them; otherwise it shall create a split in the anchor's place, holding the anchor and the new pane at share 1 each. The new pane copies the pane's mode and states.
- **PNT-A0016-06** Join (PANE-15) of adjacent parts of one split shall mark the neighbor deleted and add its share to the pane's anchor. A join of aligned non-siblings shall compute the joined rectangles, rebuild them as a tree by recursive guillotine cuts, write that tree with new split nodes, and mark the neighbor deleted. If no guillotine cut sequence exists, join is disabled (PANE-25).
- **PNT-A0016-07** Swap (PANE-16) shall write copies of each pane's `mode` and `state` to the other; panes never hold references to shared content.
- **PNT-A0016-08** Splitter drags shall write the shares of the two anchors beside the splitter, clamped so that every pane stays at least 10% of the workspace area in the drag's direction (PANE-26). Add is disabled when the pane is under 20% across the edge (PANE-27).
- **PNT-A0016-09** Order keys shall be generated between neighbors' keys and end with characters derived from the actor id, so two peers inserting at the same place at once get different keys.

## Alternatives considered
- **Rectangles with each pane's rectangle merged as one value.** Concurrent edits can overlap or leave gaps (PANE-1). Rejected.
- **Restrict join to siblings.** Simpler, but the owner wants aligned panes joinable. Rejected.
- **Loro's movable tree.** A ready tree CRDT, but the owner chose Automerge (docs/decisions/007-crdt-automerge.md). Rejected.
- **Repair the stored tree after every merge.** Repairs written by several peers at once race each other. Rejected in favour of a read-time projection that never writes.

## Consequences
- Concurrent edits always converge to a valid layout, but not always the one either user intended: a pane can vanish, or shares can look uneven.
- Stored nodes that no longer show (empty splits, deleted panes) stay in the session document until the workspace is discarded.
- Pane ids are strings `<actorHex>:<counter>`, no longer ints.

## Revisit if
Users in a Session routinely lose panes to concurrent edits.
