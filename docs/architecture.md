# Architecture

## Current Constraints

- The application is intended to use Flutter and Dart.
- macOS is the current target; Linux, Windows, and Android are future targets with no rollout order decided.

## Architectural Priorities

- Prefer cohesive components with clear responsibilities and narrow interfaces. Minimize unnecessary dependencies and cross-component knowledge so changes can be developed, tested, and revised with limited impact on unrelated parts.
- Make component ownership, public contracts, and permitted dependencies clear when planning work, especially when work may be implemented independently.
- Treat modularity as a priority, not as a requirement to use a particular architecture or split code into packages. Choose concrete boundaries and mechanisms based on the product requirements and runnable evidence.

## Canvas Architecture (T-003/T-004)

- **Rendering:** `CanvasView` draws a white canvas and round vector strokes with Flutter `CustomPainter`.
- **Document:** `CanvasDocument` stores immutable strokes made of document-space points and per-point brush weights. Viewport pan, zoom, rotation, and the active stroke are separate controller state.
- **State:** `CanvasController` owns document and viewport changes and extends Flutter `ChangeNotifier`; no state-management package is required.
- **Input:** `CanvasView` consumes Flutter pointer events on macOS without a native input/rendering plugin. Primary mouse drag draws at weight `1.0`; secondary drag pans; middle drag rotates; vertical mouse-wheel movement zooms about the pointer. Trackpad two-finger gestures (`PointerPanZoom*` events, `PointerDeviceKind.trackpad`) drive the same viewport: two-finger scroll pans, pinch zooms about the gesture's focal point, and two-finger rotate rotates about that same point. Stylus pressure controls weight only.
- **Prototype parameters:** an 8-logical-pixel brush diameter, linear normalized pressure-to-weight range `0.05`–`1.0`, and zoom limits `0.1`–`16` make the focused prototype runnable. The brush diameter and exact pressure mapping remain open production choices.
- **Evidence and record:** widget tests cover isolated pointer behavior and the combined painting/viewport workflow; `flutter test` runs them headlessly. The Release app builds and launches. Automated tests assert model behavior rather than raster pixels. See [ADR 0001](decisions/0001-vector-canvas-and-flutter-input.md) for tradeoffs and limitations.

## Document and File Architecture (T-005)

- **Format:** `CanvasDocument.toJson`/`.fromJson` serialize ordered strokes of document-space points and weights to UTF-8 JSON with a `painter-document` format identifier and integer version. See [ADR 0002](decisions/0002-saved-document-format-and-flow.md).
- **Picking:** `DocumentFileService` (in `lib/document/`) separates file I/O from path picking. The production implementation, `InAppDocumentFileService`, shows `InAppFilePicker`, an in-app dialog built from ordinary Flutter widgets (directory listing, navigation, a filename field) instead of a native file dialog or a platform plugin.
- **Wiring:** `PainterApp` in `lib/main.dart` owns the current document path and in-flight file-operation state, and shows a details-expandable error dialog on failure without replacing the current document or crashing.
- **Evidence and record:** because picking is ordinary Flutter UI, `flutter test` drives and verifies the full open/save flow headlessly, including the picker dialog itself (navigate, type a name, confirm, cancel); no native dialog, VM, or file-picker plugin dependency is required.

## Decisions Not Yet Made

