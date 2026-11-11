// What: Public entry point of automerge_dart, a Dart binding for Automerge
//   (Rust crate automerge 0.12.0) through its C API, automerge-c.
// Why: docs/decisions/007-crdt-automerge.md (PNT-A0013-02) chose a binding
//   written in this repository; this file exports its API.
// Coupled to: lib/src/document.dart, lib/src/value.dart,
//   lib/src/exception.dart (exported), lib/src/native.dart (internal).
//
// ---------------------------------------------------------------------------
// automerge_dart overview
//
// What it is: documents of nested string-keyed maps whose leaves are null,
// bool, int, double, String or bytes (AutomergeDoc, ObjId, AutomergeValue),
// with save/load, merge, fork, and the Automerge sync protocol (SyncState).
// It covers what the app's CRDT port needs (PNT-A0013-03), not all of
// automerge-c: no list edits, text, counters, marks or cursors.
// Why: Automerge has no maintained Dart binding. The alternatives (yjs_dart,
// crdt_lf, Loro) were rejected in docs/decisions/007-crdt-automerge.md.
// How it works:
// - hook/build.dart compiles third_party/automerge-c (vendored, MIT) with the
//   toolchain pinned in its rust-toolchain.toml into a dynamic library, the
//   code asset `package:automerge_dart/src/third_party/automerge.g.dart`.
// - lib/src/third_party/automerge.g.dart holds the `@Native` bindings that
//   tool/ffigen.dart generates from the header tool/generate_header.dart
//   produces.
// - Every automerge-c call returns an AMresult that must be freed once.
//   Results that only carry an answer are freed before the call returns,
//   after copying values into Dart (lib/src/native.dart useResult). Results
//   that hold a document, an object id or a sync state are owned by the Dart
//   object wrapping them (NativeResult): freed by its dispose(), or by a
//   NativeFinalizer if it is collected undisposed. A failed result becomes
//   an AutomergeException carrying the C error text.
// - Threading: Automerge documents are not thread-safe. Use each document,
//   and the ObjIds and SyncStates used with it, from one isolate only (the
//   UI isolate in Painter, PNT-A0013-06). Calls are synchronous; load, save,
//   merge and sync run on the calling thread.
// ---------------------------------------------------------------------------

export 'src/document.dart' show AutomergeDoc, ObjId, SyncState;
export 'src/exception.dart' show AutomergeException;
export 'src/value.dart';
