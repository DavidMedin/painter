// What: Stable help identifiers and the complete article/section catalog for
//   the in-app manual.
// Why: F1 targets must resolve to the same centrally maintained article that
//   the manual pane displays, rather than duplicating help text at call sites.
// Coupled to: contextual_help.dart (hover/focus ids), manual_pane.dart (tree
//   and article rendering), and controls that assign HelpId values, among
//   them the Undo, Redo and Session buttons in ../main.dart and the Session
//   pane and dialogs in ../session/session_pane.dart.

/// Stable identifiers assigned to interactive controls and manual articles.
enum HelpId {
  general,
  manualNavigation,
  canvas,
  openDocument,
  saveDocument,
  undo,
  redo,
  paneMode,
  themeMode,
  themePalette,
  createTheme,
  editTheme,
  themeColor,
  paneBoundary,
  logEntryDetails,
  loadStoredWorkspaces,
  flashWorkspace,
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
  openSession,
  startSession,
  joinSession,
  leaveSession,
  sessionName,
  sessionAddress,
  sessionAddresses,
  sessionParticipant,
  joinWorkspace,
  leaveWorkspace,
  makeHost,
  dialogCancel,
}

/// Names the ids assigned by controls; article text stays in [ManualCatalog].
abstract final class HelpIds {
  static const general = HelpId.general;
  static const manualNavigation = HelpId.manualNavigation;
  static const canvas = HelpId.canvas;
  static const openDocument = HelpId.openDocument;
  static const themeMode = HelpId.themeMode;
  static const themePalette = HelpId.themePalette;
  static const saveDocument = HelpId.saveDocument;
  static const undo = HelpId.undo;
  static const redo = HelpId.redo;
  static const paneType = HelpId.paneMode;
  static const createTheme = HelpId.createTheme;
  static const paneBoundary = HelpId.paneBoundary;
  static const editTheme = HelpId.editTheme;
  static const themeColor = HelpId.themeColor;
  static const loadStoredWorkspaces = HelpId.loadStoredWorkspaces;
  static const flashWorkspace = HelpId.flashWorkspace;
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
  static const logEntryDetails = HelpId.logEntryDetails;
  static const openSession = HelpId.openSession;
  static const startSession = HelpId.startSession;
  static const joinSession = HelpId.joinSession;
  static const leaveSession = HelpId.leaveSession;
  static const sessionName = HelpId.sessionName;
  static const sessionAddress = HelpId.sessionAddress;
  static const sessionAddresses = HelpId.sessionAddresses;
  static const sessionParticipant = HelpId.sessionParticipant;
  static const joinWorkspace = HelpId.joinWorkspace;
  static const leaveWorkspace = HelpId.leaveWorkspace;
  static const makeHost = HelpId.makeHost;
  static const dialogCancel = HelpId.dialogCancel;
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
          'Manual, Log, or Session. Hover a control and press F1 to open its '
          'manual page. '
          'The manual navigation tree stays beside the article so you can '
          'browse related topics.',
    ),
    HelpId.manualNavigation: ManualArticle(
      id: HelpId.manualNavigation,
      title: 'Manual navigation',
      tooltip: 'Expand or collapse this article group',
      section: 'Getting started',
      content:
          'Expand a group to browse its articles. Selecting an article shows '
          'it beside the navigation tree.',
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
          'current document and starts a new undo history. Files saved by '
          'earlier versions of Painter open as they looked. A file made '
          'with a different stroke engine version is refused, and the error '
          'names both versions. A failed open leaves the current document '
          'unchanged. Open is unavailable while you are in a session; leave '
          'the session first.',
    ),
    HelpId.saveDocument: ManualArticle(
      id: HelpId.saveDocument,
      title: 'Save document',
      tooltip: 'Write the current painting to a document',
      section: 'Documents',
      content:
          'Choose a destination the first time you save. Later saves write to '
          'the associated file. Saving writes the current file format, which '
          'keeps every change made to the document, including undone '
          'strokes. The pane layout stored in the file is kept as it was.',
    ),
    HelpId.undo: ManualArticle(
      id: HelpId.undo,
      title: 'Undo',
      tooltip: 'Remove your most recent stroke (Command+Z)',
      section: 'Painting',
      content:
          'Undo removes the most recent stroke you drew and keeps it for '
          'Redo. Press it again to go further back, up to your last 256 '
          'strokes. In a shared session it only removes your own strokes; '
          'strokes others drew, even over yours, stay. Undo does nothing '
          'while you are drawing. Opening a document starts a new history.',
    ),
    HelpId.redo: ManualArticle(
      id: HelpId.redo,
      title: 'Redo',
      tooltip: 'Bring back the stroke you last undid (Command+Shift+Z)',
      section: 'Painting',
      content:
          'Redo brings back the most recently undone stroke exactly as it '
          'was drawn. Drawing a new stroke discards the strokes you could '
          'redo. Redo does nothing while you are drawing.',
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
          'Settings for appearance, Manual for this guide, Log for the '
          'message history, or Session to start, join, or manage a shared '
          'editing session. Each pane has its own mode selector.',
    ),
    HelpId.paneBoundary: ManualArticle(
      id: HelpId.paneBoundary,
      title: 'Pane layout',
      tooltip: 'Add, join, swap, or resize panes',
      section: 'Workspace',
      content:
          'Each pane edge has a toolbar. Add splits the pane and puts a copy '
          'of it against that edge; it needs the pane to span at least a '
          'fifth of the workspace across that edge. Join removes the pane '
          'across the edge and extends this pane over it. Swap exchanges the '
          'modes of the two panes. Join and swap need exactly one pane '
          'sharing the whole edge, and join is also unavailable when the '
          'result could not be cut into side-by-side parts. Drag a splitter '
          'to resize the panes it separates; a pane cannot be made smaller '
          'than a tenth of the workspace, whatever the window size.',
    ),
    HelpId.flashWorkspace: ManualArticle(
      id: HelpId.flashWorkspace,
      title: 'Flash layout',
      tooltip: 'Write the current pane layout into the document file',
      section: 'Workspace',
      content:
          'Saving never changes the layout stored in a file. Flash writes the '
          'current pane layout, including each canvas view, into the opened '
          'document file without touching its strokes. Open and Save first '
          'so the document has a file. In a session, Flash writes the layout '
          'of the workspace you are a member of into your own file and '
          'changes nobody’s layout.',
    ),
    HelpId.logEntryDetails: ManualArticle(
      id: HelpId.logEntryDetails,
      title: 'Log entry details',
      tooltip: 'Expand this record to inspect its details',
      section: 'Logging',
      content:
          'Expand a log record to inspect its structured arguments and stack '
          'trace when they are available.',
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
    HelpId.editTheme: ManualArticle(
      id: HelpId.editTheme,
      title: 'Edit theme',
      tooltip: 'Edit the selected custom color palette',
      section: 'Appearance',
      content:
          'Change the selected custom palette’s name or colors. Saving '
          'updates that palette in place without changing its identity.',
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
    HelpId.loadStoredWorkspaces: ManualArticle(
      id: HelpId.loadStoredWorkspaces,
      title: 'Load stored workspaces',
      tooltip: 'Apply the pane layout saved in a file when opening it',
      section: 'Appearance',
      content:
          'When on, opening a document, or joining a session, applies the '
          'pane layout stored in its file. When off, the file’s stored layout '
          'is ignored and the current layout stays; the stored layout is kept '
          'in the file.',
    ),
    HelpId.dialogClose: ManualArticle(
      id: HelpId.dialogClose,
      title: 'Close dialog',
      tooltip: 'Dismiss this dialog',
      section: 'Dialogs',
      content: 'Close the current dialog and return to the app.',
    ),
    HelpId.dialogCancel: ManualArticle(
      id: HelpId.dialogCancel,
      title: 'Cancel dialog',
      tooltip: 'Close this dialog without doing anything',
      section: 'Dialogs',
      content: 'Close the current dialog without making any change.',
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
    HelpId.openSession: ManualArticle(
      id: HelpId.openSession,
      title: 'Session pane',
      tooltip: 'Show the Session pane',
      section: 'Session',
      content:
          'Shows the Session pane, adding one beside the widest pane when no '
          'pane is in Session mode. A session lets several people edit one '
          'document over the network, each on their own computer, without a '
          'server. Every participant must be able to reach the others '
          'directly, for example on one local network.',
    ),
    HelpId.startSession: ManualArticle(
      id: HelpId.startSession,
      title: 'Start session',
      tooltip: 'Let others join this document',
      section: 'Session',
      content:
          'Starts a session for the open document and makes you its host. '
          'You are asked for the name the other participants see, offered '
          'your account name. The Session pane then lists the addresses at '
          'which others can join. If the document’s file stores a layout, '
          'joiners who load stored workspaces start with it.',
    ),
    HelpId.joinSession: ManualArticle(
      id: HelpId.joinSession,
      title: 'Join session',
      tooltip: 'Join a session by its address',
      section: 'Session',
      content:
          'Joins a session by the address of any of its participants, in the '
          'form host:port, under the name you give. The session’s document '
          'replaces the open one and has no file until you save it. Your '
          'layout is the session’s stored layout when there is one and '
          '‘Load stored workspaces’ is on, otherwise a copy of the layout you '
          'had. A join is refused when the other painter renders strokes '
          'with another engine version; both versions are shown. Nothing '
          'changes when a join is refused or cannot connect.',
    ),
    HelpId.leaveSession: ManualArticle(
      id: HelpId.leaveSession,
      title: 'Leave session',
      tooltip: 'Leave the session and keep the document',
      section: 'Session',
      content:
          'Leaves the session. You keep the document with every change '
          'received so far, and your current layout; the session goes on for '
          'the others. When the host leaves, the participant who joined '
          'earliest becomes host.',
    ),
    HelpId.sessionName: ManualArticle(
      id: HelpId.sessionName,
      title: 'Your name',
      tooltip: 'The name other participants see',
      section: 'Session',
      content:
          'The name shown to the other participants of the session. It starts '
          'as your account name.',
    ),
    HelpId.sessionAddress: ManualArticle(
      id: HelpId.sessionAddress,
      title: 'Session address',
      tooltip: 'host:port of a participant',
      section: 'Session',
      content:
          'The address of any participant of the session you want to join, '
          'as shown in their Session pane, for example 192.168.1.20:47800.',
    ),
    HelpId.sessionAddresses: ManualArticle(
      id: HelpId.sessionAddresses,
      title: 'Your session addresses',
      tooltip: 'Addresses others can join at',
      section: 'Session',
      content:
          'The addresses at which other people can join this session through '
          'you. Give one of them to whoever should join; any participant’s '
          'address works.',
    ),
    HelpId.sessionParticipant: ManualArticle(
      id: HelpId.sessionParticipant,
      title: 'Participants',
      tooltip: 'A participant of this session',
      section: 'Session',
      content:
          'Each participant is listed by name. The host is marked Host, you '
          'are marked (you), and a participant you are not connected to is '
          'marked away. A participant you hear nothing from for 10 seconds '
          'is treated as having left.',
    ),
    HelpId.joinWorkspace: ManualArticle(
      id: HelpId.joinWorkspace,
      title: 'Join workspace',
      tooltip: 'Share this participant’s pane layout',
      section: 'Session',
      content:
          'Makes you a member of this participant’s workspace: you both see '
          'and edit the same panes, modes, and canvas views. Your own layout '
          'is kept for you to return to.',
    ),
    HelpId.leaveWorkspace: ManualArticle(
      id: HelpId.leaveWorkspace,
      title: 'Leave workspace',
      tooltip: 'Return to your own pane layout',
      section: 'Session',
      content:
          'Leaves the workspace you joined. Your earlier layout returns if it '
          'still exists; otherwise you keep a copy of the layout you leave.',
    ),
    HelpId.makeHost: ManualArticle(
      id: HelpId.makeHost,
      title: 'Make host',
      tooltip: 'Make this participant the host',
      section: 'Session',
      content:
          'Only the host sees this. It makes the participant the host of the '
          'session; the host is a label and grants no extra rights besides '
          'passing the label on.',
    ),
  };

  static const sections = <ManualSection>[
    ManualSection(
      title: 'Getting started',
      articles: [HelpId.general, HelpId.manualNavigation],
    ),
    ManualSection(
      title: 'Painting',
      articles: [HelpId.canvas, HelpId.undo, HelpId.redo],
    ),
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
      articles: [HelpId.paneMode, HelpId.paneBoundary, HelpId.flashWorkspace],
    ),
    ManualSection(
      title: 'Session',
      articles: [
        HelpId.openSession,
        HelpId.startSession,
        HelpId.joinSession,
        HelpId.leaveSession,
        HelpId.sessionName,
        HelpId.sessionAddress,
        HelpId.sessionAddresses,
        HelpId.sessionParticipant,
        HelpId.joinWorkspace,
        HelpId.leaveWorkspace,
        HelpId.makeHost,
      ],
    ),
    ManualSection(
      title: 'Appearance',
      articles: [
        HelpId.themeMode,
        HelpId.themePalette,
        HelpId.createTheme,
        HelpId.editTheme,
        HelpId.themeColor,
        HelpId.loadStoredWorkspaces,
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
    ManualSection(title: 'Logging', articles: [HelpId.logEntryDetails]),
    ManualSection(
      title: 'Dialogs',
      articles: [HelpId.dialogClose, HelpId.dialogCancel, HelpId.dialogDetails],
    ),
  ];

  /// Returns the article mapped to a control's stable help identifier.
  static ManualArticle article(HelpId id) => articles[id]!;

  /// Finds the navigation group that contains [id].
  static String sectionFor(HelpId id) => article(id).section;
}
