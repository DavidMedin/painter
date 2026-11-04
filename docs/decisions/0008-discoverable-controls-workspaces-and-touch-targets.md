# Discoverable controls, workspaces, and touch targets

## Status

Accepted. Labeled controls, contextual help, and touch sizing remain in force. Pane selection and layout are superseded by [ADR 0010](0010-pane-system.md).

## Context

The UX requirements in [project-brief.md](../project-brief.md) require labeled,
icon-bearing buttons with concise hover hints and pressed feedback; pane content
chosen from a top-left selector; contextual help reachable from any interactive
control using F1; and configurable targets for touch use. The app already has a
painting canvas, an in-app document picker, and tile-cache diagnostics. New
modes or brush settings without implemented behavior would be misleading.

## Decision

- Each pane selects **Canvas** or **Diagnostics** from its top-left control. The Canvas and diagnostics may be shown side by side; **F3** toggles docked Diagnostics, returning a sole Diagnostics pane to Canvas. See [ADR 0010](0010-pane-system.md).
- Shared controls provide labeled actions, leading icons, concise tooltips,
pressed-state feedback, and help topics. F1 opens the hovered control's article,
then the focused control's article, then general help when neither is active.
- The touch-size switch uses an app-wide setting: standard targets are at least
48 logical pixels high and enlarged targets are at least 56 logical pixels high.
The default is standard; the choice is held for the current app session.

## Consequences

- Pane content is limited to implemented Canvas and Diagnostics content; no placeholder workspace or brush settings are offered. The pane layout does not change the document model or file workflow.
- One shared size setting keeps the app bar, picker, pane controls, and help dialog aligned when the user enlarges targets.
- Help descriptions and tooltips must be updated when their controls' behavior
changes. The target sizes are implementation choices, not artist-tested
production accessibility measurements.
