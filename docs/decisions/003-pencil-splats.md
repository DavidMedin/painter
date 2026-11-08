# 003. Pencil Stroke Rendering as Gaussian Splats

Design for how a stroke becomes pencil-like marks. 
## Status
Status: accepted (supersedes: 005; superseded by: none)
Date: 2026-11-10
Relates to: 



## Context

Strokes were first painted as solid black round-capped segments joined by circles. The requested look is a pencil: from a distance it reads as a pencil line, but each mark is a tiny graphite speck. 

## Decision

- **PNT-A0004-01** The Canvas shall draw a stroke as a cloud of many small gaussian splats.
- **PNT-A0004-02** The Canvas shall rasterize one 32×32 black gaussian sprite, with alpha following `exp(-r²/2)`, once, and shall draw it thousands of times per stroke with a single `Canvas.drawRawAtlas` call, so that splats are GPU-instanced.
- **PNT-A0004-03** The Canvas shall derive splats at paint time from the stroke's points and weights and shall not store them.
- **PNT-A0004-04** The Painter shall leave the document model and the `painter-document` format unchanged, so that existing `.paint` files render as pencil without migration.
- **PNT-A0004-05** The `PencilSplats` (in `lib/canvas/pencil_splats.dart`) shall be pure Dart with no `dart:ui` dependency.
- **PNT-A0004-06** The `PencilSplats` shall walk each stroke every `0.5` document units, interpolating position and weight.
- **PNT-A0004-07** The `PencilSplats` shall emit up to 6 splats per sample, scaled by weight, placed uniformly over a disc of the local brush radius, with a size of 0.5–1.5×, a rotation, and an opacity (alpha 40–190) that are random-looking.
- **PNT-A0004-08** The `PencilSplats` shall derive randomness from a counter-based hash (SplitMix64-style) of `(stroke seed, sample index, splat index)`, so that the same stroke always renders the same specks and extending a stroke never moves earlier specks.
- **PNT-A0004-09** The Canvas shall use weight to control brush size only, scaling both the disc radius and the splat count so that thin strokes are not denser than thick ones.
- **PNT-A0004-13** The Canvas shall size the splat sprite at `1.6` document units at scale 1, with the brush diameter remaining the `8`-unit prototype value.
- **PNT-A0005-27** The `SplatStream` (in `lib/canvas/pencil_splats.dart`) shall append splats for only the new points, so that a pointer move costs time proportional to the new points rather than the stroke length.
- **PNT-A0005-28** `PencilSplats.build` shall be `SplatStream` run once, so that there is one generation path.
- **PNT-A0005-29** The Canvas shall give each stroke a seed equal to its 1-based index in the document (`CanvasStroke.seed`), assigned at commit or load.
- **PNT-A0005-30** The active stroke shall use `document.nextSeed`, so that its grain is identical before and after pointer-up.

Retired requirement IDs for this document are recorded in the.

## Consequences

- Stroke geometry stays vector, so zoom re-rasterizes the same splats at any scale. The sprite stays soft up to the `16×` zoom limit with no visible square edges (checked by rendering at 10×).
- Cost grows with stroke length: a full-weight stroke is about 13 splats per document unit (a roughly 634-unit wavy stroke produced 8,178).
- Seeds are stable within a document but not persisted. Opening a file assigns seeds by stroke order, which equals draw order, so a saved and reopened document re-derives the same specks. Deleting or reordering strokes, if ever added, would change seeds and needs a persisted seed or id.
- Tuning values (spacing, density, splat size, alpha range, sprite resolution) are first-pass choices judged on offscreen renders. They have not been reviewed by an artist or compared against real pencil on screen.
- Tests assert splat-generation invariants and pixel statistics of an offscreen render (grainy rather than solid, contained to the brush, pressure-dependent). They do not pin exact pixels.
- Not verified: physical stylus behavior.
