# Commit bounded stroke chunks during long gestures

## Status

Accepted.

## Context

`TiledRenderer` draws the active stroke directly through an incremental `SplatStream`, while `TileCache` incrementally rasterizes strokes appended to `CanvasDocument`. A long pointer gesture previously stayed entirely live, so its active splat batch kept growing even though the cache could already process appended strokes. The app has no undo behavior, and the saved document stores an ordered list of strokes without gesture identity.

## Decision

- Keep only a bounded tail live: at most 64 document units of accumulated path length and at most 64 sampled points.
- Interpolate long pointer segments at the path-length limit. When either bound is reached, append the completed chunk to `CanvasDocument` with its next document seed and start a new active chunk at the shared endpoint.
- Leave the latest chunk live through `TiledRenderer`; let the existing `TileCache` process earlier chunks through its normal incremental append path. Commit the final chunk at pointer-up.
- Keep the saved-document format unchanged. Each committed chunk is an ordinary immutable `CanvasStroke`.

## Consequences

- The live splat batch is bounded for both long sparse segments and repeated zero-distance pointer events; previously completed trail can be rasterized asynchronously while the pointer remains down.
- One physical pointer gesture is represented as multiple document strokes. Chunk seeds are independent, so grain restarts at each boundary; the shared endpoint is present in both adjacent chunks and may receive overlapping splats. Undo, if added, will need gesture grouping or will otherwise operate per chunk.
- Tile construction remains asynchronous. This bounds live drawing work; it does not guarantee that every completed chunk is already visible in a tile before pointer-up.
- ADR 0005's decision that the entire active stroke is not tiled is superseded for completed chunks; only the current bounded chunk remains live and untiled.
