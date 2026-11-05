# Saved-Document Format and File Flow

Design for how documents are stored and how the app opens and saves them. Observable behavior is in [behavior](behavior.md). Notation: [EARS+](../README.md#requirement-notation-ears).

## Status

Accepted and implemented. Formerly ADR 0002, merged with the document-architecture notes of the former architecture page.

## Context

T-005 requires opening and saving vector canvas documents. The MVP excludes image export, and the initial brief left the file format and first-save behavior unspecified.

Native dialogs were first tested in an Apple Virtualization macOS guest. macOS installed, but `VZVirtualMachine.start` stalled while Carbon Black repeatedly logged file-access interception errors, and both VM processes were idle. This points to EDR interference on managed hardware, not a dialog defect, and prevents automated native-dialog checks here.

## Decision

### Format

- **PNT-A0002-01** The Document Service shall store documents as UTF-8 JSON files with the `.paint` extension, the format identifier `painter-document`, and the integer format version `1`.
- **PNT-A0002-02** The Document Service shall persist ordered strokes as document-space points with their brush weights.
- **PNT-A0002-03** The Document Service shall not persist viewport pan, zoom, or rotation as document content.
- **PNT-ARC-007** The `CanvasDocument` shall serialize its ordered strokes of document-space points and weights, through `toJson` and `fromJson`, to UTF-8 JSON containing a `painter-document` format identifier and an integer version.

### Picking

- **PNT-ARC-008** The `DocumentFileService` (in `lib/document/`) shall separate file I/O from path picking.
- **PNT-A0002-04** The Document Service shall open and save through the in-app file picker `InAppFilePicker`, built from ordinary Flutter widgets, and shall not use the platform's native file dialogs.
- **PNT-ARC-009** The production `InAppDocumentFileService` shall pick paths with `InAppFilePicker`, an in-app dialog built from ordinary Flutter widgets (directory listing, navigation, a filename field), and shall not use a native file dialog or a platform plugin.
- **PNT-A0002-05** The `InAppFilePicker` shall list directories and `.paint` files, starting from the user's home directory.
- **PNT-A0002-06** WHEN opening, the `InAppFilePicker` shall let the user navigate and pick a file.
- **PNT-A0002-07** WHEN saving, the `InAppFilePicker` shall let the user type a name and confirm.

### Flow

- **PNT-ARC-010** The `PainterApp` in `lib/main.dart` shall own the current document path and the in-flight file-operation state.
- **PNT-A0002-08** WHEN the user saves an unsaved document, the Document Service shall ask for a location.
- **PNT-A0002-09** WHEN the user saves a document after its first successful save, the Document Service shall write to the associated path.
- **PNT-A0002-10** WHEN the user opens a file, the Document Service shall replace the current document without an unsaved-changes prompt and shall reset the viewport.
- **PNT-A0002-11** IF a file operation fails, THEN the Painter shall log the failure with its stack trace and show a dialog with expandable details.
- **PNT-A0002-12** IF a file operation fails, THEN the Painter shall keep the current document and continue running.
- **PNT-ARC-011** IF a file operation fails, THEN the `PainterApp` shall show an error dialog with expandable details, keep the current document, and continue running.

## Consequences

- The format is inspectable and straightforward to test, but JSON is not optimized for large paintings.
- The explicit identifier and version let incompatible formats be rejected rather than misread.
- Because picking is ordinary Flutter UI, `flutter test` drives and verifies the full open/save flow headlessly (navigate, type a name, confirm, cancel) with no native dialog, VM, or file-picker plugin dependency.
- The picker is custom-built and does not inherit native behavior (recents, search, iCloud locations, keyboard shortcuts). Those remain open UX gaps versus a native picker.
- Open and save are implemented for the current macOS target. No export format or control is part of the MVP.
- Opening another document can discard unsaved changes. Adding dirty-state prompts is a separate product decision.
- The Apple Virtualization VM exploration (build, sign, create, install tooling, and the EDR-interference evidence) is preserved on the `vm-native-dialog-approach` branch or bookmark in case native-dialog verification is revisited on unmanaged hardware or with an EDR exception.
- Not verified: the live Open/Save UI in a running macOS window (see [status](../../status.md)).
