# Canvas: Behavior

Behavior of drawing, the viewport, and canvas paper, as observed by the user. Notation: [EARS+](../README.md#requirement-notation-ears). Implementation is in [vector-canvas](vector-canvas.md), [pencil-splats](pencil-splats.md), and [tile-cache](tile-cache.md).

## Drawing

- **PNT-PNT-001** WHEN the user draws with a mouse, the Canvas shall add a stroke to the document using a pencil-like brush at weight `1.0`.
  Source: T-004.
- **PNT-PNT-002** WHEN the user draws with a stylus, the Canvas shall add a stroke to the document using a pencil-like brush whose weight is relative to stylus pressure.
  Source: T-004.
- **PNT-PNT-003** The Canvas shall use weight to control brush size only.
  Source: T-004.
- **PNT-PNT-004** The Painter shall provide no brush settings other than weight in the MVP.
  Source: T-004.
- **PNT-PNT-005** The Canvas shall render each stroke as many small gaussian splats (specks) so that the stroke reads as a pencil line from a distance.
  Source: [pencil-splats](pencil-splats.md).

## Viewport

- **PNT-PNT-006** WHEN the user pans, zooms, or rotates with the mouse, the Canvas shall change its view accordingly.
  Source: T-004.
- **PNT-VWP-001** WHILE more than one Canvas pane is visible, the Canvas panes shall show the same document.
  Source: [vector-canvas](vector-canvas.md).
- **PNT-VWP-002** The Canvas shall keep pan, zoom, and rotation independent for each Canvas pane.
  Source: [vector-canvas](vector-canvas.md).
- **PNT-VWP-003** WHEN a document is opened, the Painter shall reset the view of every Canvas pane.
  Source: [vector-canvas](vector-canvas.md).

## Paper and Marks

- **PNT-THM-006** The Canvas shall draw its paper as fixed white regardless of the active theme.
  Source: [theme-and-palettes](../settings/theme-and-palettes.md).
- **PNT-THM-007** The Painter shall treat canvas marks as painting content, not as UI theme colors.
  Source: [theme-and-palettes](../settings/theme-and-palettes.md).

## Vector Model and Undo (product direction)

These requirements are targets; the append-only store and editable history are not implemented.

- **PNT-KIL-008** The Painter shall create brush output as mathematical marks, such as gaussian splats or tiny textures.
  Source: project owner.
- **PNT-KIL-009** The Canvas Cache shall render marks lazily.
  Source: project owner; [tile-cache](tile-cache.md).
- **PNT-KIL-010** The Painter shall support arbitrary resolution and the editing or undoing of past strokes.
  Source: project owner.
- **PNT-KIL-011** The Painter shall store strokes, including eraser strokes, in an append-only database that overlays existing content to preserve vector editability.
  Source: project owner.
- **PNT-KIL-012** The Painter shall not discard old append-only data unless that data is no longer relevant.
  Source: project owner.

## Open Questions (non-normative)

- What is the default brush size, and what exact pressure-to-size mapping should the stylus use?
- Which mouse gestures or controls perform pan, zoom, and rotation?
