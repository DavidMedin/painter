// What: Helpers shared by the content document and undo tests: in-process
//   sync of two CRDT replicas, a replica pair with its controllers, and a
//   one-call pointer gesture.
// Why: content_document_test.dart and undo_history_test.dart both model two
//   Participants syncing in one process; keeping the loop in one place keeps
//   them exchanging messages the same way test/crdt/
//   automerge_crdt_document_test.dart does.
// Covers: nothing by itself; used with lib/document/content_document.dart,
//   lib/document/undo_history.dart and lib/canvas/canvas_controller.dart.


import 'package:flutter_test/flutter_test.dart';
import 'package:painter/canvas/canvas_controller.dart';
import 'package:painter/crdt/automerge_crdt_document.dart';
import 'package:painter/crdt/crdt_document.dart';
import 'package:painter/document/content_document.dart';

const CrdtBackend testBackend = AutomergeBackend();

/// Exchanges sync messages between [a] and [b] until neither has any.
void syncReplicas(CrdtDocument a, CrdtDocument b) {
  final ab = a.createSyncPeer();
  final ba = b.createSyncPeer();
  try {
    for (var round = 0; round < 20; round++) {
      final toB = a.generateSyncMessage(ab);
      if (toB != null) b.receiveSyncMessage(ba, toB);
      final toA = b.generateSyncMessage(ba);
      if (toA != null) a.receiveSyncMessage(ab, toA);
      if (toB == null && toA == null) return;
    }
    fail('sync did not settle');
  } finally {
    ab.dispose();
    ba.dispose();
  }
}

/// One Participant: a content document drawn by its own controller.
class Replica {
  Replica(this.content) : controller = CanvasController() {
    content.attach(controller);
    addTearDown(() {
      content.dispose();
      controller.dispose();
    });
  }

  /// A new document's creator.
  factory Replica.create() => Replica(ContentDocument.create(testBackend));

  /// A second Participant that starts from [other]'s saved content.
  factory Replica.copyOf(Replica other) =>
      Replica(ContentDocument.load(testBackend, other.content.save()));

  final ContentDocument content;
  final CanvasController controller;

  CanvasDocument get canvas => controller.document;

  /// The drawn stroke ids, bottom first.
  List<String> get ids => [for (final stroke in canvas.strokes) stroke.id];

  /// Draws one gesture from [start] to [start] + [delta] and returns the id
  /// of its last stroke.
  String draw(Offset start, {Offset delta = const Offset(10, 4)}) {
    controller
      ..beginStroke(start, 0.5)
      ..extendStroke(start + delta, 0.8)
      ..endStroke();
    return canvas.strokes.last.id;
  }

  void syncWith(Replica other) =>
      syncReplicas(content.crdt, other.content.crdt);
}
