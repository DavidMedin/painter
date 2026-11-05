# Document: Behavior

Behavior of launch, opening, saving, and file errors, as observed by the user. Notation: [EARS+](../README.md#requirement-notation-ears). Implementation is in [file-format-and-flow](file-format-and-flow.md).

## Launch

- **PNT-LCH-001** WHEN the Painter is launched without a file, the Painter shall open directly to a blank canvas ready for painting.
  Source: T-001.
- **PNT-LCH-002** WHEN the Painter is launched without a file, the Painter shall not display a splash screen.
  Source: T-001.
- **PNT-LCH-003** WHEN the Painter is launched without a file, the Painter shall create a blank, unsaved document.
  Source: T-001.

## Open and Save

- **PNT-DOC-001** The Document Service shall support opening and saving documents.
  Source: T-005.
- **PNT-DOC-002** The Painter shall not support export in the MVP.
  Source: T-005.
- **PNT-DOC-003** The Painter shall provide a UI element for opening a document and a UI element for saving a document.
  Source: T-005.
- **PNT-DOC-004** WHEN the user opens a file, the Document Service shall replace the current canvas and document with the opened content.
  Source: T-005.
- **PNT-DOC-005** WHEN the user saves a document, the Document Service shall persist the current document.
  Source: T-005.
- **PNT-DOC-006** WHEN a document is saved and then reopened, the Document Service shall preserve its content.
  Source: T-005.

## File Errors

- **PNT-ERR-001** IF a file operation fails, THEN the Painter shall display a popup explaining the error, with an expandable area for more detailed information.
  Source: T-001; [file-format-and-flow](file-format-and-flow.md).
- **PNT-ERR-002** IF a file operation fails, THEN the Painter shall keep the current document unchanged.
  Source: [file-format-and-flow](file-format-and-flow.md).
- **PNT-ERR-003** IF a file operation fails, THEN the Logger shall record the
  failure in the persistent application log even when the initiating UI context
  is unmounted.
  Source: T-001; T-010; [file-backed-logging](../logging/file-backed-logging.md).

## Open Questions (non-normative)

- What should happen when opening another file would discard unsaved changes? The current behavior replaces the document without a prompt (see [file-format-and-flow](file-format-and-flow.md)), but whether that is intended is undecided.
- What should happen when saving a document that has no associated file? The current behavior asks for a location (see [file-format-and-flow](file-format-and-flow.md)); the product requirement was never specified.
