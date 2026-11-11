# 011. A canvas view is stored as a center, an extent across the pane's shorter side, and a rotation

Status: accepted   (supersedes: none; superseded by: none)
Date: 2026-11-11
Relates to: CNVS-6, CNVS-7, CNVS-8, CNVS-9, WKSP-7, WKSP-33

## Context
`CanvasViewportController` stored pan in screen pixels and zoom in pixels per document unit, rotating about the pane center, so one stored view showed different regions in panes of different sizes. Members of one workspace see it in windows of different sizes, and the owner chose views relative to the pane's shorter side.

## Decision
- **PNT-A0017-01** A view shall be `center` (the document point at the pane center), `extent` (document units across the pane's shorter side) and `rotation` (radians, clockwise on screen).
- **PNT-A0017-02** The pixel zoom used for drawing and input shall be the pane's shorter side in logical pixels divided by `extent`; screen point s maps to document point `center + R(-rotation)(s - paneCenter) / zoom`.
- **PNT-A0017-03** `extent` shall be clamped to 64..10240 document units (CNVS-9), which is the earlier zoom range 0.1..16 on a 1024-pixel shorter side.
- **PNT-A0017-04** The default view shall be `center` (512, 512), `extent` 1024 and `rotation` 0, so a document drawn under the earlier default view appears about where it did in a pane near 1024 pixels.
- **PNT-A0017-05** Pan, zoom about a point, and rotate about a point shall take the pane's size and keep the document point under the pointer fixed, as before.

## Alternatives considered
- **Relative center, absolute zoom.** A small window would show less of the canvas, and Members would frame different regions. Rejected by the owner.
- **Extent across the width, or the diagonal.** Width cuts off content in tall panes and the diagonal is hard to reason about. Rejected.

## Consequences
- Resizing a pane zooms its canvas (CNVS-8).
- The tile level of detail follows the effective pixel zoom and is still clamped by `TileGrid`'s levels, so a very large or small pane renders at the nearest available level.
- Views stored by decision 006's format are unusable (docs/decisions/009-shared-workspaces.md).
