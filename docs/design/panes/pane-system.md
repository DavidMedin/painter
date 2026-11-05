# Docked Pane System

Design for the nested split-pane layout that hosts all Painter content. Observable behavior is in [behavior](behavior.md). Notation: [EARS+](../README.md#requirement-notation-ears).

## Status

Accepted and implemented. Combines the former ADR 0010 (pane system) and the pane parts of ADR 0008 (workspace selector). Supersedes the earlier floating-window diagnostics presentation and the workspace selector that replaced the Canvas.

## Context

Painter needs modular panes whose content is chosen from a control at each pane's top-left, with distinct borders. The earlier workspace selector replaced the Canvas with diagnostics drawn as a floating overlay, which did not provide multiple independently selected panes. Pane contents now are Canvas, Diagnostics, Settings, Manual, and Log.

## Decision

### Structure

- **PNT-A0010-01** The `PaneSystem` (in `lib/ui/pane_system.dart`) shall own pane identities, content kinds, a binary split tree, focus, and dividers.
- **PNT-ARC-030** The `PaneSystem` shall host the Canvas, Diagnostics, Settings, Manual, and Log pane modes in a nested binary split tree.
- **PNT-A0010-02** Each split shall choose side-by-side or top-and-bottom and keep independent child weights.
- **PNT-A0010-21** The Pane System shall keep pane layout state runtime-only and shall leave the document model and saved-document format unchanged.

### Dividers

- **PNT-A0010-03** Each split shall show a visibly marked 12-logical-pixel handle that resizes only that split's children.
- **PNT-A0010-04** WHILE the available extent is smaller than the handle, the handle shall clamp to the split extent.
- **PNT-A0010-05** WHEN the user right-clicks a handle, the Pane System shall offer split and close actions for the panes next to it.

### Pane chrome

- **PNT-A0010-06** Each pane shall have a visibly emphasized top-left content selector and a Split menu offering both directions.
- **PNT-A0010-07** WHILE another pane remains, each pane shall offer a Close action.
- **PNT-A0010-13** WHEN the user closes a leaf, the Pane System shall collapse the leaf's parent into the sibling.
- **PNT-A0010-08** The Pane System shall draw focused borders 2 logical pixels wide in the primary color and inactive borders in `outlineVariant`.
- **PNT-A0010-09** The Pane System shall draw pane content on the active theme surface, while Canvas paper remains fixed white.
- **PNT-A0010-10** WHILE a pane header is 180 logical pixels wide or wider, the header shall use labeled actions.
- **PNT-A0010-11** WHILE a pane header is from 48 to 180 logical pixels wide, the header shall use a compact action menu.
- **PNT-A0010-12** WHILE a pane header is narrower than 48 logical pixels, the header shall show no control.

### Diagnostics placement

- **PNT-A0010-14** The Diagnostics shall be ordinary content inside its pane and shall not be a floating window.
- **PNT-A0010-15** WHEN the user presses F3 and Diagnostics is absent, the Pane System shall add Diagnostics beside a Canvas pane using a side-by-side split.
- **PNT-A0010-16** WHEN the user presses F3 and Diagnostics is present, the Pane System shall remove it.
- **PNT-A0010-17** IF Diagnostics is the sole pane and the user presses F3, THEN the Pane System shall change it back to Canvas.

### Renderer and viewport ownership

- **PNT-A0010-18** The `PainterApp` shall own one `TiledRenderer` per pane and one `CanvasViewportController` per Canvas pane.
- **PNT-A0010-19** All Canvas panes shall share the same document controller.
- **PNT-A0010-20** The Diagnostics shall read the first Canvas pane's renderer and viewport, or, WHILE no Canvas is visible, its own retained renderer and viewport.

Retired requirement IDs for this document are recorded in the [retired ID registry](../README.md#retired-requirement-ids).

## Consequences

- Canvas and Diagnostics can be visible at the same time without overlapping, and users can resize or close a pane while at least one pane remains.
- Splits can be nested on either axis. Pane sizes and layout are not persisted.
- The pane layout does not change the document model or file workflow.
- Pane selectors, compact actions, split menus, divider menus, and dropdown
  entries use the shared target height policy; enlarged mode gives these
  controls a minimum height of 56 logical pixels.
- Verification uses headless widget tests covering pane-mode selection (including Settings and Log), both split axes, resizing, close, F3, themed surfaces, border and handle contrast, divider right-click actions, and a 14-logical-pixel pane without overflow.
- Not verified: macOS window appearance.
