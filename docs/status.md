# Project Status

- **Current state:** a runnable macOS Flutter app delivering the first painting workflow.
- **In progress:** none (current task: none).
- **Last verified:** T-004 first-workflow scenarios passed on the macOS target; see verification below.
- **Next action:** Start T-005, implement saved-document and export behavior.
- **Blockers:** none known.

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
