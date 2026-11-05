# Controls and Help: Behavior

Behavior of discoverable controls, in-app help, and touch sizing, as observed by the user. Accessibility is a core requirement. Notation: [EARS+](../README.md#requirement-notation-ears). Implementation is in [manual-pane](manual-pane.md).

## Accessibility Gaps

- **PNT-UX-001** The Painter project shall document every temporary accessibility gap.
  Source: project owner.

## Controls

- **PNT-UX-002** The Help System shall give every button a text label, a leading action icon, and visible pressed feedback.
  Source: project owner; [manual-pane](manual-pane.md).
- **PNT-UX-003** WHILE the pointer hovers an interactive element, the Painter
  shall show a concise hint that adds to, rather than repeats, its label.
  Source: project owner; [manual-pane](manual-pane.md).

## Help

- **PNT-UX-004** The Help System shall make in-app help available for every interactive element.
  Source: project owner.
- **PNT-UX-017** WHEN a Manual navigation or Log record control is hovered or
  focused, THEN it shall show a concise catalog hint and resolve its
  contextual help topic.
  Source: T-010; [manual-pane](manual-pane.md);
  [logging behavior](../logging/behavior.md).
- **PNT-UX-005** WHEN the user presses F1 and a control is hovered, the Help System shall open help for the hovered control.
  Source: project owner; [manual-pane](manual-pane.md).
- **PNT-UX-011** WHEN the user presses F1 and no control is hovered and a control has keyboard focus, the Help System shall open help for the focused control.
  Source: [manual-pane](manual-pane.md).
- **PNT-UX-012** WHEN the user presses F1 and no control is hovered or focused, the Help System shall open general help.
  Source: [manual-pane](manual-pane.md).
- **PNT-UX-013** WHEN help opens and a Manual pane exists, the Help System shall navigate and focus that pane.
  Source: [manual-pane](manual-pane.md).
- **PNT-UX-014** WHEN help opens and no Manual pane exists, the Help System shall open the article in a new Manual pane beside the pane with the greatest width.
  Source: [manual-pane](manual-pane.md).
- **PNT-UX-015** WHEN the user selects an article in the Manual navigation tree, the Manual pane shall show that article.
  Source: [manual-pane](manual-pane.md).
- **PNT-UX-016** The Help System shall keep the Painter's workspace visible while help is shown and shall not use a modal or floating help window.
  Source: [manual-pane](manual-pane.md).

## Touch Targets

- **PNT-UI-001** The Painter shall keep the UI compact, useful, and configurable for touch.
  Source: project owner; [manual-pane](manual-pane.md).
- **PNT-UI-002** The Painter shall use Blender as the visual reference for the UI.
  Source: project owner.
- **PNT-UX-006** The Painter shall provide an app-wide touch-size switch with a standard and an enlarged setting.
  Source: [manual-pane](manual-pane.md).
- **PNT-UX-007** WHILE the touch-size setting is standard, every interactive target shall be at least 48 logical pixels high.
  Source: [manual-pane](manual-pane.md).
- **PNT-UX-008** WHILE the touch-size setting is enlarged, every interactive target shall be at least 56 logical pixels high.
  Source: [manual-pane](manual-pane.md).
- **PNT-UX-009** WHEN the Painter starts, the touch-size setting shall be standard.
  Source: [manual-pane](manual-pane.md).
- **PNT-UX-010** The Painter shall hold the touch-size choice for the current app session only.
  Source: [manual-pane](manual-pane.md).
