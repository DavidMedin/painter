// What: Stable help identifiers and the complete article/section catalog for
//   the in-app manual.
// Why: F1 targets must resolve to the same centrally maintained article that
//   the manual pane displays, rather than duplicating help text at call sites.
// Coupled to: contextual_help.dart (hover/focus ids), manual_pane.dart (tree and
//   article rendering), and controls that assign HelpId values.

/// Stable identifiers assigned to interactive controls and manual articles.
enum HelpId {
  general,
  canvas,
  openDocument,
  saveDocument,
  paneMode,
  themeMode,
  themePalette,
  createTheme,
  themeColor,
  paneBoundary,
  touchTargets,
  pickerUp,
  pickerDirectory,
  pickerFile,
  pickerSaveFile,
  pickerFileName,
  pickerSave,
  pickerCancel,
  dialogClose,
  dialogDetails,
  debugSection,
  debugCheckbox,
  debugSlider,
  debugAction,
  resetView,
  rebuildTiles,
  copyReport,
}

/// Names the ids assigned by controls; article text stays in [ManualCatalog].
abstract final class HelpIds {
  static const general = HelpId.general;
  static const canvas = HelpId.canvas;
  static const openDocument = HelpId.openDocument;
  static const saveDocument = HelpId.saveDocument;
  static const paneType = HelpId.paneMode;
  static const themeMode = HelpId.themeMode;
  static const themePalette = HelpId.themePalette;
  static const createTheme = HelpId.createTheme;
  static const themeColor = HelpId.themeColor;
  static const paneBoundary = HelpId.paneBoundary;
  static const touchTargets = HelpId.touchTargets;
  static const pickerUp = HelpId.pickerUp;
  static const pickerDirectory = HelpId.pickerDirectory;
  static const pickerFile = HelpId.pickerFile;
  static const pickerSaveFile = HelpId.pickerSaveFile;
  static const pickerFileName = HelpId.pickerFileName;
  static const pickerSave = HelpId.pickerSave;
  static const pickerCancel = HelpId.pickerCancel;
  static const dialogClose = HelpId.dialogClose;
  static const dialogDetails = HelpId.dialogDetails;
  static const debugSection = HelpId.debugSection;
  static const debugCheckbox = HelpId.debugCheckbox;
  static const debugSlider = HelpId.debugSlider;
  static const debugAction = HelpId.debugAction;
  static const resetView = HelpId.resetView;
  static const rebuildTiles = HelpId.rebuildTiles;
  static const copyReport = HelpId.copyReport;
}

/// The user-facing text and navigation group for one manual page.
class ManualArticle {
  const ManualArticle({
    required this.id,
    required this.title,
    required this.tooltip,
    required this.content,
    required this.section,
  });

  final HelpId id;
  final String title;
  final String tooltip;
  final String content;
  final String section;
}

/// A top-level expandable group in the manual navigation tree.
class ManualSection {
  const ManualSection({required this.title, required this.articles});

  final String title;
  final List<HelpId> articles;
}

/// One canonical mapping from control help ids to manual pages and tree nodes.
class ManualCatalog {
  const ManualCatalog._();

  static const articles = <HelpId, ManualArticle>{
    HelpId.general: ManualArticle(
      id: HelpId.general,
      title: 'Painter manual',
      tooltip: 'Open help for the current control',
      section: 'Getting started',
      content:
          'Use the pane mode selector to choose Canvas, Diagnostics, Settings, '
          'or Manual. Hover a control and press F1 to open its manual page. '
          'The manual navigation tree stays beside the article so you can '
          'browse related topics.',
    ),
    HelpId.canvas: ManualArticle(
      id: HelpId.canvas,
      title: 'Canvas',
      tooltip: 'Draw and navigate the painting surface',
      section: 'Painting',
      content:
          'Drag with the primary mouse button or a stylus to draw. Use the '
          'secondary mouse button to pan, the middle button to rotate, and '
          'the wheel to zoom. Trackpad gestures pan, zoom, and rotate. '
          'Stylus pressure changes brush weight.',
    ),
    HelpId.openDocument: ManualArticle(
      id: HelpId.openDocument,
      title: 'Open document',
      tooltip: 'Choose a saved Painter document',
      section: 'Documents',
      content:
          'Choose a .paint file in the in-app picker. Opening replaces the '
          'current document. A failed open leaves the current document '
          'unchanged.',
    ),
    HelpId.saveDocument: ManualArticle(
      id: HelpId.saveDocument,
      title: 'Save document',
      tooltip: 'Write the current painting to a document',
      section: 'Documents',
      content:
          'Choose a destination the first time you save. Later saves write to '
          'the associated file.',
    ),
    HelpId.pickerUp: ManualArticle(
      id: HelpId.pickerUp,
      title: 'Parent directory',
      tooltip: 'Browse the containing folder',
      section: 'Documents',
      content: 'Move to the current folder’s parent directory.',
    ),
    HelpId.pickerDirectory: ManualArticle(
      id: HelpId.pickerDirectory,
      title: 'Folder',
      tooltip: 'Browse this folder',
      section: 'Documents',
      content: 'Open this folder to see its contents.',
    ),
    HelpId.pickerFile: ManualArticle(
      id: HelpId.pickerFile,
      title: 'Document file',
      tooltip: 'Choose this document',
      section: 'Documents',
      content: 'Open this .paint document.',
    ),
    HelpId.pickerSaveFile: ManualArticle(
      id: HelpId.pickerSaveFile,
      title: 'Existing document name',
      tooltip: 'Use this document name',
      section: 'Documents',
      content:
          'Copy this file name into the save field. Confirming writes to that '
          'path.',
    ),
    HelpId.pickerFileName: ManualArticle(
      id: HelpId.pickerFileName,
      title: 'Document file name',
      tooltip: 'Enter a name for the saved document',
      section: 'Documents',
      content:
          'Type a file name. The .paint extension is added if it is missing.',
    ),
    HelpId.pickerSave: ManualArticle(
      id: HelpId.pickerSave,
      title: 'Confirm save',
      tooltip: 'Save using the selected name',
      section: 'Documents',
      content: 'Confirm the file name and save the document.',
    ),
    HelpId.pickerCancel: ManualArticle(
      id: HelpId.pickerCancel,
      title: 'Cancel file selection',
      tooltip: 'Return without opening or saving',
      section: 'Documents',
      content: 'Close the picker without performing a file operation.',
    ),
    HelpId.paneMode: ManualArticle(
      id: HelpId.paneMode,
      title: 'Pane mode',
      tooltip: 'Choose this pane’s content',
      section: 'Workspace',
      content:
          'Choose Canvas for painting, Diagnostics for tile-cache readouts, '
          'Settings for appearance, or Manual for this guide. Each pane has '
          'its own mode selector.',
    ),
    HelpId.paneBoundary: ManualArticle(
      id: HelpId.paneBoundary,
      title: 'Pane layout',
      tooltip: 'Split, resize, or close panes',
      section: 'Workspace',
      content:
          'Use Split to divide a pane side-by-side or top-and-bottom. Drag a '
          'divider to resize its two child panes. Close removes a pane; the '
          'final pane cannot be closed.',
    ),
    HelpId.themeMode: ManualArticle(
      id: HelpId.themeMode,
      title: 'Theme mode',
      tooltip: 'Choose light, dark, or system theme mode',
      section: 'Appearance',
      content:
          'System follows the operating system appearance. Light and Dark '
          'force the corresponding theme; each brightness has its own '
          'selected palette.',
    ),
    HelpId.themePalette: ManualArticle(
      id: HelpId.themePalette,
      title: 'Theme palette',
      tooltip: 'Select the palette used for this brightness',
      section: 'Appearance',
      content:
          'Choose a built-in Gruvbox palette or one of your saved custom '
          'themes for light or dark appearance.',
    ),
    HelpId.createTheme: ManualArticle(
      id: HelpId.createTheme,
      title: 'Create theme',
      tooltip: 'Create and save a custom color palette',
      section: 'Appearance',
      content:
          'Name a new palette, edit each UI color role, and save it for this '
          'brightness. The new theme is selected immediately.',
    ),
    HelpId.themeColor: ManualArticle(
      id: HelpId.themeColor,
      title: 'Theme color',
      tooltip: 'Set a six-digit hexadecimal color',
      section: 'Appearance',
      content:
          'Enter an opaque RGB color as six hexadecimal digits, with or '
          'without a leading #. The preview updates to the parsed color.',
    ),
    HelpId.touchTargets: ManualArticle(
      id: HelpId.touchTargets,
      title: 'Touch target size',
      tooltip: 'Increase control size for touch use',
      section: 'Appearance',
      content:
          'Switch between standard 48-pixel and enlarged 56-pixel '
          'interactive targets. The setting changes control hit areas '
          'without changing the document or painting.',
    ),
    HelpId.dialogClose: ManualArticle(
      id: HelpId.dialogClose,
      title: 'Close dialog',
      tooltip: 'Dismiss this dialog',
      section: 'Dialogs',
      content: 'Close the current dialog and return to the app.',
    ),
    HelpId.dialogDetails: ManualArticle(
      id: HelpId.dialogDetails,
      title: 'Error details',
      tooltip: 'Show or hide the error details',
      section: 'Dialogs',
      content: 'Expand the error details to inspect the operation failure.',
    ),
    HelpId.debugSection: ManualArticle(
      id: HelpId.debugSection,
      title: 'Diagnostic section',
      tooltip: 'Expand or collapse this section',
      section: 'Diagnostics',
      content: 'Show or hide the readouts and controls in this section.',
    ),
    HelpId.debugCheckbox: ManualArticle(
      id: HelpId.debugCheckbox,
      title: 'Diagnostic option',
      tooltip: 'Change this diagnostic option',
      section: 'Diagnostics',
      content:
          'Toggle this diagnostic setting. It affects the debug pane or '
          'canvas overlay, not the saved document.',
    ),
    HelpId.debugSlider: ManualArticle(
      id: HelpId.debugSlider,
      title: 'Diagnostic limit',
      tooltip: 'Adjust this cache limit',
      section: 'Diagnostics',
      content:
          'Drag the track or use accessible increase/decrease actions to '
          'change the diagnostic cache limit.',
    ),
    HelpId.debugAction: ManualArticle(
      id: HelpId.debugAction,
      title: 'Diagnostics action',
      tooltip: 'Run this diagnostic action',
      section: 'Diagnostics',
      content:
          'Run the selected diagnostic action without changing the document.',
    ),
    HelpId.resetView: ManualArticle(
      id: HelpId.resetView,
      title: 'Reset canvas view',
      tooltip: 'Return to the default canvas view',
      section: 'Diagnostics',
      content: 'Reset pan, zoom, and rotation without changing the painting.',
    ),
    HelpId.rebuildTiles: ManualArticle(
      id: HelpId.rebuildTiles,
      title: 'Rebuild cached tiles',
      tooltip: 'Discard cached images and rebuild them',
      section: 'Diagnostics',
      content:
          'Invalidate cached tile images. The canvas document remains intact.',
    ),
    HelpId.copyReport: ManualArticle(
      id: HelpId.copyReport,
      title: 'Copy diagnostics report',
      tooltip: 'Copy the current diagnostic snapshot',
      section: 'Diagnostics',
      content: 'Copy the current tile-cache report to the clipboard.',
    ),
  };

  static const sections = <ManualSection>[
    ManualSection(title: 'Getting started', articles: [HelpId.general]),
    ManualSection(title: 'Painting', articles: [HelpId.canvas]),
    ManualSection(
      title: 'Documents',
      articles: [
        HelpId.openDocument,
        HelpId.saveDocument,
        HelpId.pickerUp,
        HelpId.pickerDirectory,
        HelpId.pickerFile,
        HelpId.pickerSaveFile,
        HelpId.pickerFileName,
        HelpId.pickerSave,
        HelpId.pickerCancel,
      ],
    ),
    ManualSection(
      title: 'Workspace',
      articles: [HelpId.paneMode, HelpId.paneBoundary],
    ),
    ManualSection(
      title: 'Appearance',
      articles: [
        HelpId.themeMode,
        HelpId.themePalette,
        HelpId.createTheme,
        HelpId.themeColor,
        HelpId.touchTargets,
      ],
    ),
    ManualSection(
      title: 'Diagnostics',
      articles: [
        HelpId.debugSection,
        HelpId.debugCheckbox,
        HelpId.debugSlider,
        HelpId.debugAction,
        HelpId.resetView,
        HelpId.rebuildTiles,
        HelpId.copyReport,
      ],
    ),
    ManualSection(
      title: 'Dialogs',
      articles: [HelpId.dialogClose, HelpId.dialogDetails],
    ),
  ];

  /// Returns the article mapped to a control's stable help identifier.
  static ManualArticle article(HelpId id) => articles[id]!;

  /// Finds the navigation group that contains [id].
  static String sectionFor(HelpId id) => article(id).section;
}
