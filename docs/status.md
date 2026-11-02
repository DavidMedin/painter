# Project Status

- **Current state:** a runnable macOS Flutter app with the first painting workflow and an in-house (non-native) Open/Save document flow implemented.
- **In progress:** T-005, saved-document behavior. Headless automated verification is complete; a live visual confirmation of the Open/Save UI in the built Release app is outstanding.
- **Last verified:** T-005 tests, analysis, and the macOS Release build passed. The Release app launches and stays running with no errors logged, but this agent's Accessibility permission was revoked mid-task, so the running window could not be reliably brought to a key/composited state for a trustworthy screenshot of the Open/Save UI; `screencapture` of the non-key window returned blank/black frames, not real content, while the process itself logged no exceptions.
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

## Apple Virtualization VM Exploration (not pursued further)

An earlier attempt used native file dialogs (`file_selector`) verified through a local Apple Virtualization macOS guest, so the native dialogs could be screenshotted outside the host's own file-dialog state. The guest built, signed, and had macOS installed successfully, but `VZVirtualMachine.start` never completed. Sampling both the VM host process and Apple's own `com.apple.Virtualization.VirtualMachine.xpc` helper mid-stall showed both completely idle (no hypervisor-execution threads), and the unified system log showed the host's Carbon Black Endpoint Security extension repeatedly erroring while intercepting Virtualization-framework file accesses for the entire stall window — a corporate EDR conflict with the VM host on this managed laptop, not a defect in the VM tooling. That exploration (VM scripts, ADR, and `file_selector`-based implementation) is preserved on the `vm-native-dialog-approach` bookmark rather than discarded, in case native-dialog verification is revisited later on unmanaged hardware or with an EDR exception. T-005 now uses the in-house picker described above instead, which needs no VM and is fully headlessly testable.
