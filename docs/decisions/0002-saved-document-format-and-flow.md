# Saved-document format and file flow

## Status

Accepted

## Context

T-005 requires opening and saving vector canvas documents. The MVP explicitly excludes image export. The initial brief leaves the file format and first-save behavior unspecified.

An earlier attempt used the platform's native file dialogs (`file_selector`) and verified them in a local Apple Virtualization macOS guest, so the native UI could be screenshotted outside the host's own file-dialog state. The guest could be built, signed, and have macOS installed, but `VZVirtualMachine.start` never completed: sampling both the VM host process and Apple's own `com.apple.Virtualization.VirtualMachine.xpc` helper mid-stall showed both completely idle, and the unified system log showed the host's Carbon Black Endpoint Security extension repeatedly erroring while intercepting file accesses the Virtualization framework made during startup, for the entire stall. That is a corporate EDR/managed-hardware conflict with the VM host, not a defect in the VM or dialog code, but it blocks automated verification on this machine.

## Decision

- Store documents as UTF-8 JSON files with the `.paint` extension, format identifier `painter-document`, and integer format version `1`.
- Persist ordered strokes as document-space points with their brush weights. Viewport pan, zoom, and rotation are not document content.
- Open and save use an in-app file picker (`InAppFilePicker`) built from ordinary Flutter widgets instead of the platform's native file dialogs. It lists directories and `.paint` files starting from the user's home directory, lets the user navigate and pick a file to open, or type a name and confirm to save.
- Saving an unsaved document asks for a location; after the first successful save, Save writes to that associated path. Opening a file replaces the current document without an unsaved-changes prompt and resets the viewport.
- File-operation failures are logged with their stack trace and shown in a dialog with expandable details. They do not replace the current document or terminate the app.

## Consequences

- The format is inspectable and straightforward to test, but JSON is not optimized for large paintings.
- The explicit identifier and version allow incompatible formats to be rejected rather than misread.
- Because picking is ordinary Flutter UI, `flutter test` can drive and verify the full open/save flow headlessly (navigate, type a name, confirm, cancel) with no native dialog, no VM, and no platform file-picker plugin dependency.
- The picker is custom-built and does not inherit native behavior (recents, search, iCloud locations, keyboard shortcuts). Those remain open UX gaps versus a native picker.
- Open/save behavior is implemented for the current macOS target. No export format or export control is part of the MVP.
- Opening another document can discard unsaved changes; adding dirty-state prompts remains a separate product decision.
- The Apple Virtualization VM exploration (build/sign/create/install tooling, and the EDR-interference evidence) is preserved on the `vm-native-dialog-approach` branch/bookmark rather than discarded, in case native-dialog verification is revisited later on unmanaged hardware or with an EDR exception.
