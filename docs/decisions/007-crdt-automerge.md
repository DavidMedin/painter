# 007. Shared state is held in Automerge documents, reached through a narrow CRDT port and our own FFI binding

Status: accepted   (supersedes: none; superseded by: none)
Date: 2026-11-11
Relates to: MPLY-5, MPLY-6, MPLY-7, WKSP-33, WKSP-35, DOCF-1

## Context
Several users edit one document and share workspaces peer to peer, with no server to order changes (MPLY-5). Every peer must end up with the same content and the same workspaces after receiving the same changes (MPLY-7, WKSP-35). The owner chose CRDTs for both, and Automerge in particular, with a binding written in this repository. Automerge's core is Rust; it offers a C API (`automerge-c`) but no maintained Dart binding.

## Decision
- **PNT-A0013-01** The Painter shall hold the document content and the session state in Automerge documents (Rust crate `automerge` 0.12.0).
- **PNT-A0013-02** The binding shall be the Dart package `packages/automerge_dart`, a path dependency of the app. It vendors the `automerge-c` crate source under `third_party/automerge-c` (MIT), builds it as a dynamic library with a Dart build hook using `native_toolchain_rust` and a pinned `rust-toolchain.toml`, and calls it through `ffigen`-generated bindings. Hand-written `dart:ffi` lookups are not used.
- **PNT-A0013-03** App code outside `lib/crdt/` shall not import `automerge_dart`. It uses the port in `lib/crdt/crdt_document.dart`: nested string-keyed maps whose leaves are null, bool, int, double, String or bytes; put, get, delete, keys and map creation by path; commit; save and load; the actor id; per-peer sync states that generate and receive sync messages; and a listener called after each local commit or applied remote change, saying which.
- **PNT-A0013-04** A map that more than one peer could create at the same key shall be created only by the peer that creates the document, before it is shared. Every other entry is keyed by an id that embeds the creating actor, `<actorHex>:<counter>`, so concurrent creations never collide.
- **PNT-A0013-05** Because the C API reports no diffs, a consumer shall re-read the parts of a document it shows when its listener reports a remote change.
- **PNT-A0013-06** All calls on one Automerge document shall happen on the UI isolate; documents are not thread-safe.

## Alternatives considered
- **`yjs_dart` (pure Dart port of Yjs).** No native build and a built-in undo manager, but one maintainer and little use. Rejected in favour of the owner's choice of Automerge; the port keeps it possible as a second backend.
- **`crdt_lf` (pure Dart).** Active and has sync and undo, but its format is its own and it is less proven. Rejected for the same reason.
- **Loro through `loro_crdt`.** Strong core with a movable tree, but the binding is a 0.1.0 third-party package. Rejected for the owner's choice.
- **A log ordered by the Host.** Simpler than a CRDT, but needs a peer to order every change and fails over badly when the Host leaves (MPLY-12). Rejected.
- **No port; call Automerge from the app directly.** Less code, but every system would depend on FFI types and memory rules. Rejected.

## Consequences
- Building the app needs `rustup`; the build hook installs the pinned toolchain on first build, which needs network access once.
- Automerge has no undo; Painter writes its own (docs/decisions/012-undo-per-participant.md).
- Automerge keeps every change, so documents grow with their history (docs/decisions/008-document-file-format.md).
- A second backend can implement the port, but saved files are Automerge documents, so it could not open them.

## Revisit if
The FFI binding becomes a recurring source of crashes or leaks, or a maintained Dart Automerge binding appears.
