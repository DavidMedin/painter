# Project Status

This file lists only work that is not done or not verified. Completed work is recorded in [the roadmap](../tasks/ROADMAP.md) and in the [design documents](design/README.md).

- **Current state:** A runnable macOS painting application. Very WIP; pre-alpha.
- **Current roadmap work:** T-005 is blocked; T-006 is todo.
- **Next action:** complete T-005's live Open/Save and pane visual confirmation
  when Accessibility and window-focus access is available.

## Blocked

### T-005: live visual confirmation

- **Missing prerequisite:** a window the agent can reliably activate and foreground. The agent's Accessibility permission was revoked partway through the task, and `screencapture` of the non-key Metal-backed window returned blank white or solid black frames rather than real content. This is a known compositing artifact, not an application error.
- **Remaining acceptance step:** a user manually clicking through Open and Save in the Release build, and confirming the pane behavior.
- **Evidence so far:** the built Release executable started, stayed running, and logged no exceptions or Flutter framework errors. No GUI window has been opened or visually inspected during later work.

## Not Started

- **T-006:** assess cross-platform readiness and recommend a rollout order. See [the roadmap](../tasks/ROADMAP.md#t-006--assess-cross-platform-readiness).

## Not Verified

None of the following has been exercised in a running macOS window, because [testing](testing.md) requires explicit permission for windowed runs. Verification so far used synthetic Flutter input and offscreen rendering.

- Appearance and interaction of the pane controls, viewport interactions, Settings pane, Manual pane, Log pane, status bar, and Diagnostics pane in a running window.
- Drawing performance in a running window: raster-thread and GPU time, texture memory, and the overhead of the always-on diagnostics counters.
- Physical stylus pressure and latency, and physical trackpad pan, zoom, and rotate, including whether the rotation sign feels natural.
- Whether the pencil density, grain, and splat size suit an artist's idea of pencil, and how the scaled-fallback transition looks.
- Very large documents and extreme zoom or extents.
- The Menlo font in the Diagnostics pane (test renders use Ahem).

## Open Findings

Found while commenting the code; each remaining finding was re-checked against
the current code.

- `TileCache.isCachedCurrent` has no caller in `lib/` or `test/`.
- `describeTiles()` is read only by a test, not by the Diagnostics pane.
- `TileCache._rectsFor` and `TiledRenderer._rectsFor` are near-duplicates that
  must be kept in sync by hand.

## Open Questions for the Owner

The repository does not record the reason for these choices, so the code describes behavior without a rationale.

- Why the ImGui kit is hand-written rather than a package or stock Material widgets.
- The origin of the pane's 2 ms and 8 ms record-time color thresholds and of the Controls slider ranges.
- The origin of the rotation (`dx / 100`) and wheel-zoom (`exp(-dy / 500)`) constants.
- Why touch input is ignored.
- Why the file picker lists directories with `listSync`.
- Whether the missing overwrite confirmation on save is intentional.
