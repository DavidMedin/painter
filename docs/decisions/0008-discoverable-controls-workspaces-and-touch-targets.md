# Discoverable controls, workspaces, and touch targets

## Status

Accepted and implemented at the project owner's request.

## Context

The UX requirements in [project-brief.md](../project-brief.md) require labeled,
icon-bearing buttons with concise hover hints and pressed feedback; a top-left
workspace selector backed by real content; contextual help reachable from any
interactive control using F1; and configurable targets for touch use. The app
already has a painting canvas, an in-app document picker, and a tile-diagnostics
pane. New modes or brush settings without implemented behavior would be
misleading.

## Decision

- The top-left selector offers only **Canvas** and **Diagnostics**. These show
the existing canvas and the existing diagnostics pane over the canvas;
**F3** remains a keyboard shortcut for the same switch.
- Shared controls provide labeled actions, leading icons, concise tooltips,
pressed-state feedback, and help topics. F1 opens the hovered control's article,
then the focused control's article, then general help when neither is active.
- The touch-size switch uses an app-wide setting: standard targets are at least
48 logical pixels high and enlarged targets are at least 56 logical pixels high.
The default is standard; the choice is held for the current app session.

## Consequences

- The selector presents only implemented content; it adds no placeholder
workspace or brush settings and does not change the document model or file
workflow.
- One shared size setting keeps the app bar, picker, diagnostics controls,
workspace selector, and help dialog aligned when the user enlarges targets.
- Help descriptions and tooltips must be updated when their controls' behavior
changes. The target sizes are implementation choices, not artist-tested
production accessibility measurements.
