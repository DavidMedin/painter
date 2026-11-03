# Project Status

- **Current state:** a runnable macOS Flutter app with the first painting workflow and an in-house (non-native) Open/Save document flow implemented.
- **In progress:** T-005, saved-document behavior. Headless automated verification is complete; a live visual confirmation of the Open/Save UI in the built Release app is outstanding.
- **Last verified:** T-005 tests, analysis, and the macOS Release build passed. The Release app launches and stays running with no errors logged, but this agent's Accessibility permission was revoked mid-task, so the running window could not be reliably brought to a key/composited state for a trustworthy screenshot of the Open/Save UI; `screencapture` of the non-key window returned blank/black frames, not real content, while the process itself logged no exceptions. The later pencil splat stroke change (see its section below) also passes tests, analysis, and the Release build.
- **Next action:** Have a user (or an agent with Accessibility/window-focus access restored) click through Open and Save once in the Release build to visually confirm the in-house picker dialog, then mark T-005 done.
- **Blockers:** Live visual verification of T-005's user-visible path is blocked by this agent's Accessibility permission being revoked; see T-005 Verification below.

## T-002 Verification

- `flutter pub get` — succeeded; dependencies resolved (five packages have newer versions outside the current constraints).
- `flutter analyze` — passed: `No issues found!`.
- `flutter test` — passed: `All tests passed!`.
- `flutter build macos` — passed: built `build/macos/Build/Products/Release/painter.app` (37.8 MB).
- `open build/macos/Build/Products/Release/painter.app && sleep 2 && pgrep -fl 'painter.app|Runner'` — exited successfully; process output showed `.../painter.app/Contents/MacOS/painter` running.
- `flutter run -d macos --no-pub` — built the Debug app and emitted a VM service URL, but logged `Failed to foreground app; open returned 1`; the command timed out after 300 seconds. Directly opening the built Release app succeeded as recorded above.

## T-003 Verification

- `flutter test test/canvas/canvas_view_test.dart` — passed all three canvas interaction tests: mouse stroke document points and fixed weight, synthetic stylus pressure weight, and mouse pan/zoom/rotation.
- `flutter test` — passed all four widget tests, including launch directly to the blank canvas.
- `flutter analyze` — passed: `No issues found!`.
- `flutter build macos` — passed; built `build/macos/Build/Products/Release/painter.app` (37.9 MB). Xcode emitted stale-file warnings for build artifacts under `/Users/medindj1/small-projects/painter/build/`, outside this worktree; the build completed successfully.
- `open -n build/macos/Build/Products/Release/painter.app` — process output showed the Release executable running. A 1920×1080 desktop capture was written to `/tmp/painter-t003-final.png`.
- Widget tests verify document changes and input/viewport behavior, not raster pixel output or physical stylus hardware. See [ADR 0001](decisions/0001-vector-canvas-and-flutter-input.md) for the prototype's evidence limits and deferred choices.

## T-004 Verification

- `flutter pub get` — succeeded after removing `integration_test` and its integration-only transitive packages.
- `flutter test test/canvas/painting_workflow_test.dart` — passed the combined blank-canvas, mouse/stylus drawing, pan, zoom, and rotation workflow under the regular headless test binding.
- `flutter test` — passed all five widget tests.
- `flutter analyze` — passed: `No issues found!`.
- `flutter build macos` — passed; built `build/macos/Build/Products/Release/painter.app` (37.9 MB).
- `open -n build/macos/Build/Products/Release/painter.app && sleep 2 && pgrep -fl 'painter.app/Contents/MacOS/painter'` — exited successfully; the Release executable was running. A desktop capture showed the blank white canvas after launch.
- Pointer tests use synthetic mouse/stylus events. The 8-logical-pixel diameter and linear `0.05`–`1.0` pressure mapping remain prototype parameters, not artist-approved production choices; physical stylus hardware and raster output are not verified.

## T-005 Verification

- `flutter pub get` — succeeded; no new dependency was added (the in-house picker uses only `dart:io` and Flutter widgets, no `file_selector` or other file-picker plugin).
- `flutter test test/document/document_file_workflow_test.dart` — passed both lifecycle tests: first save, repeated save to the associated path, open/replacement round-trip of stroke coordinates and weights with a viewport reset, and open/save failures showing the expandable-details error dialog while preserving the current document.
- `flutter test test/document/file_picker_dialog_test.dart` — passed all five tests of the in-house `InAppFilePicker` dialog itself: listing directories and `.paint` files while hiding other extensions, confirming an open by tapping a file, navigating into a subdirectory, typing a name and confirming a save (appending `.paint`), and cancel returning `null`. This is the part that replaces the native file dialog and is exactly what could not be driven headlessly before.
- `flutter test` — passed all 12 tests, including the pre-existing canvas/widget tests, after fixing `test/canvas/painting_workflow_test.dart` to compute pointer positions relative to the canvas's actual on-screen offset (previously assumed the canvas started at the window origin, which broke once the Open/Save `AppBar` was added above it).
- `flutter analyze` — passed: `No issues found!`.
- `flutter build macos` — passed; built `build/macos/Build/Products/Release/painter.app` (37.9 MB).
- Running the built Release executable directly (`.../painter.app/Contents/MacOS/painter`) with stdout/stderr captured: the process started, logged only the expected Impeller/Metal backend notice, stayed running for the duration of the check, and logged no exceptions or Flutter framework errors. This agent's Accessibility permission was revoked partway through the task (by user instruction), so the window could not be reliably activated/foregrounded for a trustworthy screenshot: `screencapture` of the resulting non-key window returned blank white or solid black frames rather than real content, which is a known compositing artifact for non-key Metal-backed windows, not an application error. A user manually clicking through Open and Save in the Release build is the remaining acceptance-criteria step; see Next Action above.

## Trackpad Gesture Controls Verification (canvas, out-of-roadmap enhancement)

- Direct user request: expand `CanvasView`'s canvas controls to support macOS trackpad two-finger pan, pinch zoom, and two-finger rotate, in addition to the existing T-003/T-004 mouse controls. See [ADR 0003](decisions/0003-trackpad-gesture-controls.md).
- `flutter analyze` — passed: `No issues found!`.
- `flutter test` — passed all 12 pre-existing tests unchanged.
- A throwaway widget test drove `TestPointer.panZoomStart/panZoomUpdate/panZoomEnd` (synthetic `PointerDeviceKind.trackpad` events) through `CanvasView` with incremental pan, then pinch (`scale: 1.5`), then rotate (`rotation: 0.3`); asserted and printed `CanvasController.pan`, `.zoom`, and `.rotation` all changed as expected (`pan=Offset(50.7, 39.2) zoom=1.5 rotation=0.3`), then was deleted.
- `flutter build macos` — passed; built `build/macos/Build/Products/Release/painter.app` (42.0 MB).
- Not verified: physical trackpad hardware behavior and whether the OS-reported rotation sign feels natural to an artist; only Flutter-side synthetic pan/zoom/rotate events were exercised.

## Pencil Splat Stroke Verification (canvas, out-of-roadmap enhancement)

- Direct user request, developed on branch `pencil-splat-stroke` in a separate git worktree (`../painter-pencil-splat`): replace the solid round stroke with many instanced gaussian splats so a stroke reads as a pencil line from a distance and each splat is a speck. See [ADR 0004](decisions/0004-pencil-splat-stroke-rendering.md). The saved-document format is unchanged.
- `flutter analyze` — passed: `No issues found!`.
- `flutter test` — passed all 25 tests: the 12 pre-existing tests unchanged, plus new `pencil_splats_test.dart` (generation invariants) and `pencil_renderer_test.dart` (offscreen pixel statistics). One full-suite run reported `file_picker_dialog_test.dart` as failing to load while the new test files still had analyzer errors; that file passed alone and in the next full run after the errors were fixed, and the cause was not isolated further.
- Throwaway tests (deleted) rasterized strokes offscreen to PNG and were inspected: a roughly 634-unit full-weight wavy stroke produced 8,178 splats and showed a grainy graphite look; a pressure ramp narrowed and thinned toward low weight; at 10× zoom each splat was a soft gaussian blob with no square sprite edges.
- `flutter build macos` — passed; built `build/macos/Build/Products/Release/painter.app` (42.0 MB).
- Not verified: the stroke in the running macOS window. No app window was opened because [testing.md](testing.md) requires explicit permission for windowed runs; verification used offscreen rasterization only. Also not verified: drawing performance with the active stroke regenerated per pointer move on long strokes, physical stylus behavior, and whether the density, grain, and splat size suit an artist's idea of pencil.

## Tiled Texture Cache Verification (canvas, out-of-roadmap enhancement)

- Direct user request: rendering slowed as strokes accumulated because every frame replayed every stroke's splats. Cache the canvas as multi-resolution document-space tiles, update a tile by drawing new strokes over it, show scaled lower-resolution tiles until better ones land, and build everything lazily and asynchronously. Developed in the git worktree on branch `wt/20261102-200832`. See [ADR 0005](decisions/0005-tiled-texture-cache.md). The saved-document format is unchanged.
- `flutter analyze` — passed: `No issues found!`.
- `flutter test` — passed all 43 tests. `pencil_renderer_test.dart` was replaced by `tiled_renderer_test.dart` (the same four pixel-statistics assertions, now through the tile pipeline, plus: tiled output matches the same splats drawn directly; no seam across a tile edge; adding a stroke keeps earlier strokes and updates the tile; a stale tile keeps its old content until the update lands; a 4× zoom shows the scaled level-0 tile at once and later the level-2 tile; replacing the document discards tiles; tiles in the working set are not evicted when it exceeds `maxTiles`) and new `tile_grid_test.dart`. The eviction test was confirmed to fail (2 of 6 tiles survive) with the protection disabled and pass with it.
- Bugs found and fixed while testing: `SynchronousFuture` inside `Future.wait` returned an empty list, so a tile whose strokes were already generated (the first zoom after drawing) was recorded blank; and a constant `maxTiles` smaller than the working set (up to about 270 tiles when zoomed out and rotated) would have evicted on-screen tiles every frame.
- Benchmark (throwaway test, deleted; `flutter test` debug binding, 1920×1080 view, strokes of 40 points). UI-thread display-list recording per frame, before → after, at 100 / 500 / 2000 strokes: 4.3 / 22 / 79 ms → 0.03 / 0.01 / 0.006 ms. Worst pan frame after: 0.2 / 0.02 / 0.008 ms. Active-stroke pointer move on a 300-point stroke: 0.06–0.08 ms median, 0.12–0.20 ms p99 (not measured before; the old code regenerated the whole stroke per move). Background warm-up of all tiles at 2000 strokes: about 1.5 s.
- A throwaway widget test (deleted) drove `CanvasView` with a mouse stroke: after commit the UI was idle (no frame scheduled), and when a tile finished building a frame was scheduled with no further input, so a landing tile repaints the canvas.
- `flutter build macos` — passed; built `build/macos/Build/Products/Release/painter.app` (42.1 MB).
- Not verified: behavior in the running macOS window (no windowed run was permitted by [testing.md](testing.md)); raster-thread and GPU time of drawing about 40 tile images per frame, and texture memory, on real hardware (the benchmark measures only UI-thread recording in the test binding); how the scaled-fallback transition looks to an artist; physical stylus latency; very large documents or extreme extents.

## Apple Virtualization VM Exploration (not pursued further)

An earlier attempt used native file dialogs (`file_selector`) verified through a local Apple Virtualization macOS guest, so the native dialogs could be screenshotted outside the host's own file-dialog state. The guest built, signed, and had macOS installed successfully, but `VZVirtualMachine.start` never completed. Sampling both the VM host process and Apple's own `com.apple.Virtualization.VirtualMachine.xpc` helper mid-stall showed both completely idle (no hypervisor-execution threads), and the unified system log showed the host's Carbon Black Endpoint Security extension repeatedly erroring while intercepting Virtualization-framework file accesses for the entire stall window — a corporate EDR conflict with the VM host on this managed laptop, not a defect in the VM tooling. That exploration (VM scripts, ADR, and `file_selector`-based implementation) is preserved on the `vm-native-dialog-approach` bookmark rather than discarded, in case native-dialog verification is revisited later on unmanaged hardware or with an EDR exception. T-005 now uses the in-house picker described above instead, which needs no VM and is fully headlessly testable.
