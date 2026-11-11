# automerge_dart

A Dart binding for [Automerge](https://automerge.org) (Rust crate `automerge`
0.12.0), written for Painter
([docs/decisions/007-crdt-automerge.md](../../docs/decisions/007-crdt-automerge.md)).
It calls the vendored C API, [`third_party/automerge-c`](third_party/automerge-c/README.md),
through `ffigen`-generated bindings. A build hook compiles that crate with
`native_toolchain_rust`.

It covers documents of nested string-keyed maps whose leaves are null, bool,
int, double, String or bytes; save and load; merge and fork; and the Automerge
sync protocol. It has no list edits, text, counters, marks or cursors.

App code outside `lib/crdt/` does not import this package; it goes through the
app's CRDT port (PNT-A0013-03).

## Requirements

- macOS, the only target in
  [`rust-toolchain.toml`](third_party/automerge-c/rust-toolchain.toml)
  (`aarch64-apple-darwin`, `x86_64-apple-darwin`). Other platforms are future
  targets (see the repository's [README.md](../../README.md)).
- [rustup](https://rustup.rs). The first build installs the pinned toolchain
  (1.99.1) and its targets, which needs network access once.
- rustup's proxy directory on `PATH`. The build hook runs
  `rustup run 1.99.1 cargo build`, and Cargo then starts `rustc` by name, so
  `rustup` alone on `PATH` is not enough:
  - installed with `rustup-init`: `~/.cargo/bin` (the installer adds it);
  - installed with Homebrew (the `rustup` formula is keg-only): add
    `$(brew --prefix rustup)/bin`, e.g. `/opt/homebrew/opt/rustup/bin`.

  Without it, the build fails with
  `could not execute process rustc -vV (never executed)`.

The same applies to `dart run`, `dart test`, `flutter run` and
`flutter build` in this package or the app, which all run the build hook.

## Usage

```dart
import 'package:automerge_dart/automerge_dart.dart';

final doc = AutomergeDoc.create();
final strokes = doc.putMap(doc.root, 'strokes');
doc.put(strokes, 'seed', 7);
doc.commit(message: 'add stroke');

switch (doc.get(strokes, 'seed')) {
  case AutomergeInt(:final value):
    print(value);
  case _:
    break;
}

final bytes = doc.save();
final copy = AutomergeDoc.load(bytes);

// Sync: one SyncState per peer, exchange messages until both return null.
final stateForPeer = SyncState();
final message = doc.generateSyncMessage(stateForPeer); // send if non-null
```

### Memory

`AutomergeDoc`, `SyncState` and every `ObjId` except `ObjId.root` own native
memory. Call `dispose()` when done; a `NativeFinalizer` frees it if the object
is garbage collected first. Using a disposed object throws `StateError`. An
`ObjId` stays valid after the document it came from is disposed, and works
with that document's forks and merge partners.

### Errors

A failed Automerge operation throws `AutomergeException` with Automerge's
error text, for example when loading bytes that are not a document, reading a
map through an id of another document, or setting an actor id that is not
hexadecimal. `put` throws `ArgumentError` for a value of an unsupported Dart
type. `get` throws `AutomergeException` for values the binding does not model
(counters, timestamps, unsigned ints, text objects).

### Threading

Automerge documents are not thread-safe. Use a document, and the `ObjId`s and
`SyncState`s used with it, from one isolate only (the UI isolate in Painter,
PNT-A0013-06). All calls are synchronous.

## Development

From this directory, with the `PATH` set up as above:

- `dart test` runs the tests (the hook builds the library first).
- `dart run tool/generate_header.dart` regenerates
  `third_party/automerge-c/include/automerge-c/automerge.h`.
- `dart run tool/ffigen.dart` regenerates
  `lib/src/third_party/automerge.g.dart`. Add a C function to its list before
  calling it from `lib/src/`.

### Choices

- No link hook and no `recordUse`: the library is a Rust `cdylib` built by
  Cargo, which a link hook cannot re-link with fewer symbols, and ffigen's
  record-use mapping is experimental. The binding is instead limited to the
  functions listed in `tool/ffigen.dart`.
- The library is built in release mode in every build (the
  `native_toolchain_rust` default), so debug app builds take the Rust release
  build time on first build.

## Licenses

[LICENSE](LICENSE) holds Automerge's MIT license, which covers the vendored
crate and the generated bindings. The built library also contains crates.io
dependencies of `automerge`, all under permissive licenses (MIT, Apache-2.0,
Zlib, Unicode-3.0, mostly dual MIT/Apache-2.0). List them with
`cargo tree -e normal --prefix none --format '{p} {l}'` in
`third_party/automerge-c`. Their notices are not yet included in the app's
license page.
