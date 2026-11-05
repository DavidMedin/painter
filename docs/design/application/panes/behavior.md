# Panes: Behavior

Behavior of the docked pane layout, as observed by the user. Notation: [EARS+](../README.md#requirement-notation-ears). Implementation is in [pane-system](pane-system.md).

## Layout

- **PNT-PAN-001** The Pane System shall be a Binary Space Partition tiling of panes.
  Source: [pane-system](pane-system.md).
- **PNT-PAN-002** The Pane System shall provide a draggable divider for each split.
  Source: [pane-system](pane-system.md).
- **PNT-PAN-003** WHEN the user drags a divider, the Pane System shall resize only the two panes adjacent to that divider.
  Source: [pane-system](pane-system.md).
- **PNT-PAN-009** WHEN the user drags the corner between any panes, The Pane System shall resize all necessary panes accordingly.

## Content Selection

- **PNT-PAN-004** The Pane System shall visibly identify the selected content mode in each pane's content selector.
  Source: [pane-system](pane-system.md).
- **PNT-PAN-005** The Pane System shall let the user choose each pane's content from a selector at the pane's top-left, as in Blender.
  Source: project owner; [pane-system](pane-system.md).

## Appearance

- **PNT-PAN-006** The Pane System shall draw distinct borders around panes.
  Source: project owner; [pane-system](pane-system.md).

## Shortcuts

- **PNT-PAN-007** WHEN the user presses F3 and no Diagnostics pane exists, the Pane System shall add a Diagnostics pane.
  Source: [pane-system](pane-system.md); [debug-pane](../diagnostics/debug-pane.md).
- **PNT-PAN-008** WHEN the user presses F3 and a Diagnostics pane exists, the Pane System shall remove it.
  Source: [pane-system](pane-system.md); [debug-pane](../diagnostics/debug-pane.md).
