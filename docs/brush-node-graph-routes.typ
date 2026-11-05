#set document(title: "Brush node graph: routes for every brush", author: "Painter — exploratory design research")
#set page(paper: "a4", margin: (x: 18mm, y: 17mm), numbering: "1")
#set text(size: 9.5pt)
#set par(justify: false, leading: 0.6em)
#set heading(numbering: "1.1")
#set table(stroke: 0.35pt + luma(205), inset: 5pt)

#align(center)[
  #text(size: 19pt, weight: "bold")[Brush node graph: routes for every brush]
  #v(5pt)
  #text(size: 11pt)[Architecture options and research notes for Painter]
  #v(5pt)
  _Exploratory advice, not an ADR, implementation plan, or product commitment._
]

= Executive assessment

Painter's eventual *brush graph* should specify how input becomes a mark, canvas-dependent operation, or material change. It is *not* the separately envisioned composition graph that connects canvas outputs for viewing and compositing. Today the macOS Flutter app saves immutable document-space stroke points and weights, derives seeded pencil splats, and incrementally rasterizes additive strokes into cached multi-resolution tiles. It has no brush graph, wet state, or saved brush definitions. The product brief explicitly aspires to all brushes being graph-defined and to resolution-independent authored marks; those aspirations need testing together, not treating the present tile images as authoritative paint state. See #link("design/brush-graph/behavior.md")[brush graph behavior] and #link("design/architecture-overview.md")[current architecture], also Graph systems [1–2].

*Recommendation to test, not a decision:* a staged hybrid: named, paint-ready family presets built from typed, inspectable subgraphs; a small stable primitive vocabulary beneath them; and explicit, separately scheduled canvas/state boundaries for clone, smudge, and wet media. First reproduce the existing pencil output with a pure graph and an ink/airbrush path; then test snapshot reads and wet-media state before claiming universal editable/vector behavior. A native brush-family node is a legitimate experiment, but if its behavior cannot be exposed as graph-owned composition it is an exception to the “all brushes graph-defined” ambition. Engine research [4, 9, 11]; Graph systems [6, 13, 20–21]; Paint research [3–6].

*What “all” could honestly mean:* every brush preset is authored as a versioned graph with a defined output contract, while implementations may use native field, mask, deposit, or bounded state primitives. It does *not* mean every stroke is merely a list of analytic vectors. A hard nib, seeded pencil splats and some local dry textures can remain reconstructible at arbitrary tile resolutions. Sampling already-composited pixels, wet transport, drying, or clone dependencies introduce raster-state resolution, ordering and replay choices; saving input points alone is insufficient. Do not promise Photoshop preset compatibility or equivalence to its Mixer Brush, Krita's Color Smudge, Procreate Wet Mix, or a physical fluid solver on the basis of similar-looking strokes. Engine research [1–12]; Paint research [1–7].

== How to read the evidence

The three included research sections distinguish documented precedent from proposals, and each has *its own locally numbered source list*: “Graph systems [6]”, “Brush engines [6]”, and “Paint media [6]” are three different references. Numbers in this synthesis are always prefixed by the research-section name; local project facts come from the linked brief/architecture. The concluding worked examples are proposals, not claims about current features or competitor internals. In particular, the available Our Paint evidence establishes a node-based brush engine and pigment canvas, *not* its private node classes, socket semantics, execution strategy, or persistence (Graph systems [9–10]).

= Architecture routes, side by side

#table(
  columns: (22%, 37%, 41%),
  table.header([*Route*], [*Payoff / authoring surface*], [*Cost / failure mode to test*]),
  [*Macro graph* — named `Pencil`, `Ink`, `Spray`, `WetMixer` groups over typed internals.],
  [Artist paints immediately with size, pressure, grain and wetness controls; open internals or insert a node when needed. Shared building blocks stay inspectable.],
  [Versioning group ports/assets and preserving old strokes become real schema work. A “wet” macro must expose its image/state dependencies rather than hide them. Brush engines [1–3, 11]; Graph systems [7–8, 16].],
  [*Fine primitives* — one filter, emitter, mask, sensor map or deposit per node.],
  [Maximum reuse, observable intermediate values, custom combinations beyond canned Photoshop-style categories.],
  [Graph sprawl and confusing domain transitions; cycles, state, per-dab cost and unsupported device sensors cannot be left to accidental wiring. Start with presets and optional low-level editor. Brush engines [5, 9]; Graph systems [6–7].],
  [*Brush-family node* — `PixelBrush` / `SmudgeBrush` with one settings surface.],
  [A concise route to engine-specific behaviors; compare a native implementation against graph-assembled equivalents. Krita documents genuinely distinct engine families.],
  [Opaque algorithms resist recombination and inspection; if a family is a black box, the graph may just select engines. Require a declared input/output/state contract; decide explicitly whether native families satisfy “graph-defined.” Brush engines [4, 6–8].],
  [*Staged hybrid* — macros + pure primitives first, explicit stateful services later.],
  [Separates reproducible dry marks from costly read/feedback paths; can preserve an uncomplicated pencil/ink path while studying wet paint.],
  [Two execution/replay contracts, disciplined scheduling, version migration, and visible UI distinctions are required. Not a promise that every media family shares the same renderer. Graph systems [13–14, 20–21]; Paint media [3–7].],
)

A shader-like per-pixel field is an *implementation option inside* a mask or deposit, not automatically a fifth whole-brush architecture: pixel fields alone do not define stroke order, reservoir depletion, or source-image revision. A single node-editor widget need not imply a single kind of graph: Blender's shader, geometry, compositor and brush-texture contexts have distinct contracts; TouchDesigner uses explicit family boundaries and conversions. Graph systems [3–8, 11–12, 22]; Brush engines [11].

= Proposed graph contract: types, cadence, and ownership

*Notation:* `A -> B` means a typed output to a typed input, not an existing Dart API. `1` means exactly one value at that invocation; `0..1` means optional; `*` denotes an ordered stream or bounded collection, never an implicit arbitrary fan-in. A single output may feed many read-only consumers; a single input admits one connection unless it is explicitly a `Merge` / `Mix` / `Composite` node with an ordered multi-input contract. A multi-input value is *not* interchangeable with a stream of events. Controls may be constant or domain-indexed, but a per-stroke constant is not automatically a per-pixel field. The types, cardinalities and units below are design candidates, not currently supported sockets. Graph systems [6–7, 11–12, 19]; Brush engines [5, 9].

#table(
  columns: (30%, 31%, 39%),
  table.header([*Port / cardinality*], [*Lifetime / unit*], [*Valid use and crossing*]),
  [`StrokeSamples*`, `SampleStream*`], [Ordered stroke or sample; position in document-length units, optional event time in seconds, pressure normalized if present.], [Input observations and normalized samples are distinct. Input capabilities are explicit; historical weight cannot recover tilt or event time.],
  [`DabEventStream*`], [One ordered event per emitted dab; document position, tangent angle, index, optional time, stable seed.], [Arc-length and time emitters create different event sequences; preserve stroke order and bound each dab footprint.],
  [`Control<T, domain> 1`], [Typed length, angle, fraction, rate or color; per stroke/sample/dab/pixel as declared.], [Explicit `EvaluateAtDab` / `CaptureAtStroke` crosses cadence. Convert document length to screen pixels only at view/render boundaries.],
  [`TipShape 1`, `MaskField 1`], [Local tip coordinates; spatial support in document units; coverage in 0..1.], [Shape/mask is not paint. An anchored paper field, tip-local repeat and moving grain have distinct coordinate frames.],
  [`MarkStream*`, `OperationStream*`], [Ordered deposits in document space; footprint, color/coverage, blend or erase intent.], [Emitted geometry is distinct from composited pixels; operation order and alpha/flow law must be declared.],
  [`ImageRead 1`, `ImageResult 1`], [Immutable region at named document revision / pre-dab or pre-step phase; pixels with stated color space and resolution.], [No implicit read of a stale preview tile. `Rasterize` / `SampleImage` visibly crosses geometry-to-image and resolution boundaries.],
  [`MaterialState 0..1`, `StepState 1`], [Reservoir or canvas cells at one dab/stroke/solver tick; pigment mass, water amount, volume or height in stated units.], [Must declare initial/reset state and owning clock; `PreviousStep -> NextStep` is delayed feedback, not a combinational cycle.],
)

Choose a reference color space and alpha/compositing convention for `Color`, separate RGB display color from spectral/latent pigment quantities, and make transforms into `ImageRead` explicit. A size control is document length; a flow fraction per dab is not the same thing as stroke opacity, dab density per document length, or rate per second. Spectral mixing changes optics, not by itself transport or drying. Brush engines [1, 9–12]; Paint media [1–3].

= Candidate node catalog

Every item here is a *possible Painter node*, not an already shipped feature. Signatures show essential ports; options are artist/graph choices, not claims of Photoshop-compatible formulas. For readability, `C` = `Control<T, domain>`, `E*` = `DabEventStream*`, `M*` = `MarkStream*`, and `O*` = `OperationStream*` as typed above. Other names retain their full type. A port with `?` is optional and requires a defined default, not an implicit invented device reading.

#table(
  columns: (19%, 43%, 38%),
  table.header([*Phase*], [*Nodes and typed signature*], [*Concrete options / constraints*]),
  [Input], [`PointerStroke: events* -> StrokeSamples*`; `StoredStroke: StrokeRecord -> StrokeSamples*`], [Mouse weight 1; stylus pressure only if present; absent tilt/time remains absent. Device and document coordinates cannot silently mix.],
  [Sampling], [`Stabilize: SampleStream* -> SampleStream*`; `ArcSpacing or TimedEmitter: SampleStream* + C<Length|Rate> -> E*`], [Distance versus per-second dabs; smoothing, stationary airbrush ticks, begin/end taper. A pen-up-dependent taper may require deferred finalization.],
  [Modulation], [`PressureCurve, TiltMap, DistanceFade, SeededNoise: samples/E* -> C<Length|Angle|Fraction, domain>`], [Radius, angle, opacity, flow and count are separate mappings; per-stroke vs per-dab random. Unavailable sensor = explicit fallback control, not invented tilt.],
  [Shape], [`Disk, Ellipse, TipImage, BristleBundle: settings -> TipShape`; `IntersectMasks: MaskField × MaskField -> MaskField`], [Hardness, nib angle, sampled-tip scale, secondary tip spacing/count; Photoshop tip intersection differs from combining two fully rendered brushes.],
  [Mark], [`Scatter: E* + C<Length|Angle> -> E*`; `PlaceTip: E* + TipShape + MaskField? -> M*`], [Seeded radial/angular distributions, mark rotation, stable index and footprint; spray is not just jitter in one large stamp.],
  [Materials], [`PaperGrain / MovingGrain: coordinates -> MaskField`; `ChooseColor / MixColor: Color × Color -> Color`; `LoadReservoir: preset -> MaterialState`], [Document-anchored vs stroke-moving grain; RGB, latent-pigment or spectral mixing must be named; reservoir charge/depletion is state, not a color picker.],
  [Canvas read], [`FreezeSource: document revision + region -> ImageRead`; `SampleImage: ImageRead + position -> Color|neighborhood`; `ReadMaterial: StepState + region -> MaterialState`], [Clone offset and source scope; pre-dab versus previous position for smudge; read wet material versus rendered RGB; never a live cache tile by default.],
  [Deposit], [`Deposit: M* + C<Color|Flow> + MaterialState? -> O* + MaterialState?`; `Erase: M* -> O*`; `Composite: ImageRead + O* -> ImageResult`], [Alpha/flow accumulation, erase semantics, ordered pickup/transfer; no assumed additive-tile optimization for canvas-dependent output.],
  [Time simulation], [`PreviousDab, TransferPigment, ApplyFlux, Absorb, Dry, NextStep: StepState + operations -> StepState`], [Named dab or solver-tick clock, init/reset, cell size and timestep; neighbor flux/halo and dry/rewet are separate from one-stroke marks.],
  [Display], [`Rasterize: M* + resolution -> ImageResult`; `Shade: StepState -> ImageResult`; `PreviewTap: typed value -> UI preview`], [Rendered image is not persistent stroke truth; preview may request work and must not change saved results or run every intermediate at each dab.],
)

Brush engines [1–12] motivates distinct dynamics, scattering, dual-tip, texture, airbrush, clone and wet-mixer controls; Graph systems [6–8, 13, 16, 18–21] motivates domain-aware ports, visible conversions, grouped presets, preview discipline and explicit delays; Paint media [1–7] motivates separating optical mixture, material transfer, time stepping and display. The names and signatures above are proposals, not reverse-engineered competitor nodes.

= One stroke, three execution paths

*Common front end:* pointer observations -> document-space stroke samples -> filtering/resampling -> initialized per-stroke seed and graph/preset version -> ordered dab events. On pen-up, finalize anything needing stroke end (e.g. a distance-normalized fade); save authored input plus sufficient graph/asset/version metadata for the chosen replay policy. Preview uses provisional results, not a hidden extra source of truth. A graph with no required time or tilt input can still paint with the present mouse/stylus data. Current format saves points and weights only; these additional fields are proposed, not backward-compatible assumptions. Brush engines [5, 9]; Graph systems [1–2, 6, 13].

- *Local dry marks:* events -> size/color maps -> mask/texture -> bounded ordered marks -> rasterize visible tiles. This can preserve a resolution-independent authored stroke/mark description; a seeded pencil reference and hard ink are the first equivalence checks. Repaint at a new zoom from authored data rather than scaling the old image forever. No canvas read; additive tiles may still overlay only new strokes when the compositing contract allows it.
- *Read-dependent clone/smudge:* freeze source scope and document revision before a dab (or explicitly read the previous completed dab) -> sample image -> deposit -> commit next ordered dab. A selected source paint node, fixed prior projection, and full composition are different artist-visible read scopes. If an earlier stroke changes, the dependent operation and later readers must be invalidated/replayed; local marks alone are no longer a complete record. Brush engines [3, 6–7]; Paint media [6].
- *Wet/material:* deposit pigment/water and transfer brush load -> freeze previous material step -> compute next step and neighbor fluxes -> shade pixels; drying can continue after pen-up on an explicit clock. State includes its cell resolution and boundary conditions. Document-resolution-independent *commands* can coexist with resolution-dependent simulation results, but fine export may disagree with a coarse preview unless one committed simulation resolution or a disclosed re-solve rule is chosen. Paint media [3–5, 7].

A feedback edge must cross `PreviousDab`, `PreviousStroke` or `PreviousStep` with a clock, initial value, reset, and replay rule; reject bare instantaneous cycles. A renderer's stale, scaled cache tile can be displayed while a replacement is prepared, but it is not an authoritative `ReadCanvas` input. Pure subgraphs may be scheduled per stroke/sample/dab/tile and planned or compiled if measured; stateful reads require ordered dependencies. Benchmark an interpreter before claiming graph compilation, GPU execution, or cached fields improve latency. Graph systems [6, 13–14, 20–21]; Paint media [3–7].

= Effects on the present document and tile cache

*Today:* `CanvasDocument` JSON stores ordered immutable strokes of points and weights. `PencilSplats` derives seeded geometry; `SplatWorker` generates it; `TileCache` holds multi-resolution raster images and incrementally overlays newly added additive strokes. `CanvasController` tracks document/viewport separately. These are facts about the existing baseline, not interfaces the proposed graph already implements. See #link("design/architecture-overview.md")[architecture overview], #link("design/canvas/vector-canvas.md")[vector canvas], and #link("design/document/file-format-and-flow.md")[document format].

*Possible dry cutover:* a saved stroke refers to a versioned brush graph/preset and assets plus deterministic seed, retaining immutable input points and an explicit source-data schema. Old files either retain a legacy pencil interpretation/version or undergo a tested migration; never reinterpret old weights under an unversioned new preset. Replace the hardwired splat derivation with a pure graph execution path that emits equivalent bounded marks, without treating display tiles as saved strokes. Incremental updates remain valid only for operations whose deposition law is local, ordered and composable over the old tile image. The exact file migration and graph snapshot/reference policy are decisions, not currently implemented.

*Possible canvas-dependent cutover:* a stroke is still an immutable authored command but may read a named prior document/material revision and generate raster-dependent effects. Choose between full ordered replay, checkpoints plus dependent replay, and persistent material fields; specify whether checkpoint/state cells are cache or file truth, how source edits/undo invalidate descendants, how wet extents cross tile edges, and how idle ticks are recorded. A read of the current composite would link the brush system to composition outputs; make that dependency/version explicit rather than silently combining the two graphs. No generic "update only this stroke's tiles" promise survives smudge, transport or post-stroke drying. Paint media [3–7]; Brush engines [3, 6–7].

= Suggested experiments and unresolved decisions

#enum(
  [*Dry reference:* run existing pencil stroke fixtures through the current generator and a candidate graph on identical points, weights and seed; compare mark order/geometry, pixel output over tile seams, prefix stability, save/reopen and zoom re-render. Add hard round and dry paper texture with a document-anchored grain test. Track input-to-preview latency, per-dab work, persisted bytes and tile redraw separately. Graph systems [6, 13]; Brush engines [5, 9, 11].],
  [*Artist controls:* paint with named ink, pencil, airbrush, spray and textured/dual-tip presets; compare macro, primitive and family-node editing of the same strokes. Check that size/pressure/flow/opacity/density are not conflated, stationary emission is intentional, node previews identify missing sensors and costly reads, and the graph need not be opened to draw. Brush engines [1–2, 4–5, 8–12]; Graph systems [7–8, 13, 16, 18].],
  [*Feedback fixture:* compare fixed-source clone, previous-position smearing, and under-dab dulling on an image that later changes. Record exact read revision, dab order, brush reservoir reset, dependency invalidation, undo/replay cost and result after save/reopen. Call these RGB approximations unless pigment accounting is present. Brush engines [3, 6–7]; Paint media [6].],
  [*Optics then wet state:* compare RGB, Mixbox-like latent and a small measured spectral palette on specified swatches; then a fixed-resolution wet sandbox with water/mobile/fixed pigment and conservative exchange across tile seams. Compare diffusion, transport and pinning; log quantities, fronts, step cost and preview/export divergence, including idle drying and undo. Do not label blur physical watercolor or RGB pigment transfer conservation. Paint media [1–7].],
)

*Open choices, intentionally not resolved here:* Are graph versions embedded per stroke, referenced immutably, or migrated? Is the authoritative output an analytic mark stream, raster operation stream, material state, or a declared union of these? Which canvas/paint node revision can a brush read, and can it read the composition graph's output? What is the exact per-dab color/alpha law and coordinate/color-space contract? How are missing time/tilt handled in old strokes? Does wetness advance in wall time, explicit document ticks, or only while painting? Which simulation resolution persists, and what does high-resolution export promise? What is artist-visible when editing a preset retroactively, undoing an earlier source stroke, or opening a file with unavailable brush assets? These are design questions, not solved by adding more sockets. See Brush engines [3–12], Graph systems [6–8, 13–14, 20–21], Paint media [1–7].

= Research dossiers and sources

The following three sections retain their own local citation numbering. Their proposals are research options, not accepted design. The worked examples conclude the document and use the contracts above as illustrative routes.

#include "brush-graph-systems-fragment.typ"
#include "brush-engines-fragment.typ"
#include "brush-paint-fragment.typ"
#include "brush-graph-examples.typ"
