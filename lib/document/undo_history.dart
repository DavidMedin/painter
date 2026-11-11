// What: EditHistory, the local Participant's undo and redo stacks for one
//   content document, and UndoEdit, one recorded pointer gesture.
// Why: docs/decisions/012-undo-per-participant.md: undo replays inverse
//   actions on the shared document and reverts only one's own gestures, so a
//   peer's strokes drawn over an undone one stay (UNDO-7, UNDO-8). Automerge
//   has no undo of its own (docs/decisions/007-crdt-automerge.md).
// Coupled to: ../canvas/canvas_controller.dart (onGestureCompleted,
//   strokeInProgress, removeStrokes, insertStrokes), content_document.dart
//   (ContentDocument.transact makes each undo or redo one commit; see its
//   overview), ../logging/painter_log.dart (a debug record per finished
//   gesture, undo and redo, docs/spec/logging.md LOG-19), and ../main.dart
//   (Undo and Redo buttons and shortcuts, one history per attached document).
//
// How it works: CanvasController reports each finished gesture with the
// strokes it added; they are kept as one UndoEdit, which holds the immutable
// strokes themselves, so redo puts back the same ids, seeds, z and points
// even when a peer has removed one meanwhile. Undo removes the edit's strokes
// from the canvas, and through ContentDocument's mirror deletes their entries
// in one commit; redo inserts the missing ones in one commit. Remote changes
// never reach this class (PNT-A0018-03). The one exception to "same z": when
// a joined document's root keys arrive, strokes drawn before then are given
// new `z` values (ContentDocument.onRestamped) and the stacks take them. A
// history belongs to one document: ../main.dart makes a new one when the
// document is replaced (PNT-A0018-05).

import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../canvas/canvas_controller.dart';
import '../logging/painter_log.dart';
import 'content_document.dart';

/// One local pointer gesture: the strokes it added, one per committed chunk
/// (PNT-A0018-01).
@immutable
class UndoEdit {
  const UndoEdit(this.strokes);

  final List<CanvasStroke> strokes;

  /// The gesture id the strokes share.
  String get gesture => strokes.first.gesture;
}

/// The undo and redo stacks of the local Participant for [content], fed by
/// [controller]'s finished gestures. See the header of this file.
///
/// Notifies when [canUndo] or [canRedo] may have changed through this
/// history; they also depend on `CanvasController.strokeInProgress`, so
/// widgets listen to [controller] as well.
class EditHistory extends ChangeNotifier {
  /// Starts recording [controller]'s gestures (it sets
  /// `CanvasController.onGestureCompleted`); [content] must be the document
  /// [controller] draws. [log] receives a debug record for each finished
  /// gesture, undo and redo (LOG-19); never one per pointer event (LOG-20).
  EditHistory({
    required this.controller,
    required this.content,
    this.capacity = defaultCapacity,
    this.log,
  }) {
    controller.onGestureCompleted = _record;
    content.onRestamped = _restamp;
  }

  /// Edits kept per document (PNT-A0018-04, UNDO-5).
  static const int defaultCapacity = 256;

  final CanvasController controller;
  final ContentDocument content;

  /// The most edits kept; the oldest is dropped beyond it.
  final int capacity;

  final PainterLog? log;

  final ListQueue<UndoEdit> _undo = ListQueue();
  final List<UndoEdit> _redo = [];

  /// Edits that can be undone, oldest first.
  List<UndoEdit> get undoStack => List.unmodifiable(_undo);

  /// Undone edits that can be redone, least recently undone first.
  List<UndoEdit> get redoStack => List.unmodifiable(_redo);

  /// Whether [undo] would change the document now (UNDO-2, UNDO-4).
  bool get canUndo => _undo.isNotEmpty && !controller.strokeInProgress;

  /// Whether [redo] would change the document now (UNDO-4).
  bool get canRedo => _redo.isNotEmpty && !controller.strokeInProgress;

  /// Reverts the most recent edit not undone and moves it to the redo stack
  /// (UNDO-1). Does nothing, without error, when there is none (UNDO-2) or a
  /// stroke is in progress (UNDO-4). Returns whether it undid an edit.
  bool undo() {
    if (!canUndo) return false;
    final edit = _undo.removeLast();
    content.transact(
      () => controller.removeStrokes([
        for (final stroke in edit.strokes) stroke.id,
      ]),
      message: 'Undo',
    );
    _redo.add(edit);
    notifyListeners();
    _logEdit('document.undo.succeeded');
    return true;
  }

  /// Reapplies the most recently undone edit with its original ids, seeds
  /// and z, and moves it back to the history (UNDO-9). Strokes already in
  /// the document are left as they are. Does nothing when the redo stack is
  /// empty or a stroke is in progress (UNDO-4). Returns whether it redid an
  /// edit.
  bool redo() {
    if (!canRedo) return false;
    final edit = _redo.removeLast();
    final document = controller.document;
    content.transact(
      () => controller.insertStrokes([
        for (final stroke in edit.strokes)
          if (document.strokeById(stroke.id) == null) stroke,
      ]),
      message: 'Redo',
    );
    _push(edit);
    notifyListeners();
    _logEdit('document.redo.succeeded');
    return true;
  }

  /// Stops recording [controller]'s gestures and [content]'s restamps.
  @override
  void dispose() {
    if (controller.onGestureCompleted == _record) {
      controller.onGestureCompleted = null;
    }
    if (content.onRestamped == _restamp) content.onRestamped = null;
    super.dispose();
  }

  /// Records a finished local gesture and discards the redo stack (UNDO-3).
  /// Each stroke is taken as the document now holds it: a joined document
  /// may have given a chunk a new `z` while the gesture went on
  /// (ContentDocument.onRestamped).
  void _record(List<CanvasStroke> strokes) {
    if (strokes.isEmpty) return;
    final document = controller.document;
    _push(
      UndoEdit([
        for (final stroke in strokes) document.strokeById(stroke.id) ?? stroke,
      ]),
    );
    _redo.clear();
    notifyListeners();
    _logEdit('document.stroke.finished', {'chunks': strokes.length});
  }

  void _logEdit(String messageId, [Map<String, Object?> arguments = const {}]) {
    final log = this.log;
    if (log != null) unawaited(log.debug(messageId, arguments: arguments));
  }

  /// Replaces strokes in both stacks by their [restamped] versions, so redo
  /// puts back the `z` they got when the root keys arrived.
  void _restamp(Map<String, CanvasStroke> restamped) {
    UndoEdit update(UndoEdit edit) => UndoEdit([
      for (final stroke in edit.strokes) restamped[stroke.id] ?? stroke,
    ]);
    final undo = [for (final edit in _undo) update(edit)];
    _undo
      ..clear()
      ..addAll(undo);
    for (var i = 0; i < _redo.length; i++) {
      _redo[i] = update(_redo[i]);
    }
  }

  void _push(UndoEdit edit) {
    _undo.addLast(edit);
    while (_undo.length > capacity) {
      _undo.removeFirst();
    }
  }
}
