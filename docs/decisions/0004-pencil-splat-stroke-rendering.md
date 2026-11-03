# Render strokes as instanced gaussian pencil splats

## Status

Accepted. Supersedes the solid round-stroke rendering in [ADR 0001](0001-vector-canvas-and-flutter-input.md); the rest of ADR 0001 (vector document, pointer input, viewport controls) still applies. Amended by [ADR 0005](0005-tiled-texture-cache.md): strokes are no longer replayed every frame, `PencilRenderer` and its per-stroke batch cache are replaced by a tile cache, and seeds are the stroke's document index rather than paint-order.

## Context

Strokes were painted as solid black round-capped line segments joined by circles. The requested look is a pencil: seen from a distance it should read as a pencil line, but each mark is a tiny graphite speck. The saved-document format ([ADR 0002](0002-saved-document-format-and-flow.md)) stores only document-space points and weights.

## Decision

- A stroke is drawn as a cloud of many small gaussian splats. One soft gaussian sprite (32×32, black, alpha following `exp(-r²/2)`) is rasterized once and drawn thousands of times per stroke with a single `Canvas.drawRawAtlas` call, so the splats are GPU-instanced rather than individual draw calls.
- Splats are **derived at paint time** from the stroke's points and weights, not stored. The document model and the `painter-document` format are unchanged, and existing `.paint` files render as pencil without migration.
- Generation (`PencilSplats` in `lib/canvas/pencil_splats.dart`) is pure Dart with no `dart:ui` dependency. It walks each stroke every `0.5` document units, interpolating position and weight, and emits up to 6 splats per sample (scaled by weight) placed uniformly over a disc of the local brush radius, with random-looking size (0.5–1.5×), rotation, and opacity (alpha 40–190).
- Randomness is a counter-based hash (SplitMix64-style) of `(stroke seed, sample index, splat index)`. The same stroke always renders the same specks, extending a stroke never moves earlier specks, and generation is unit-testable without a GPU.
- Weight still controls brush size only: it scales the disc radius and splat count so thin strokes are not denser than thick ones.
- `PencilRenderer` (`lib/canvas/pencil_renderer.dart`) owns the sprite and caches one `SplatBatch` per completed stroke, keyed by stroke identity. It is owned by `CanvasView`'s state and disposed with it. The in-progress stroke is rebuilt on every pointer move.
- Splat sprite size is `1.6` document units at scale 1, and brush diameter remains the `8`-unit prototype value.

## Consequences

- Stroke geometry stays vector, so zoom re-rasterizes the same splats at any scale; the sprite is magnified up to the `16×` zoom limit and stays soft with no visible square edges (checked by rendering at 10× during development).
- Cost grows with stroke length: a full-weight stroke is about 13 splats per document unit (a roughly 634-unit wavy stroke produced 8,178). Completed strokes are cached, but the active stroke is regenerated in full on every point, which is O(stroke length) per move. Long-document and long-single-stroke performance has not been measured.
- The in-progress stroke is rendered with the seed the next committed stroke will receive, so its grain does not change on pointer-up. This relies on seeds being assigned sequentially in paint order and on at most one stroke being committed between paints.
- Per-stroke seeds are assigned in paint order at first paint and are not persisted, so reopening a document can assign different seeds than the original session. Splat patterns are deterministic within a session but not guaranteed identical across sessions.
- Tuning values (spacing, density, splat size, alpha range, sprite resolution) are first-pass choices judged on offscreen renders; they have not been reviewed by an artist or compared against real pencil on screen.
- Tests assert splat-generation invariants and pixel statistics of an offscreen render (grainy rather than solid, contained to the brush, pressure-dependent). They do not pin exact pixels, and physical stylus behavior is still unverified.
