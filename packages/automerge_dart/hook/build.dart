// What: Build hook that compiles the vendored automerge-c crate into a
//   dynamic library and registers it as this package's native code asset.
// Why: docs/decisions/007-crdt-automerge.md (PNT-A0013-02) builds the binding
//   from source with a Dart build hook using package:native_toolchain_rust,
//   so `dart test`, `flutter run` and `flutter build` compile and bundle it.
// Coupled to: third_party/automerge-c/Cargo.toml (crate-type must include
//   staticlib and cdylib), third_party/automerge-c/rust-toolchain.toml
//   (pinned channel and supported targets), tool/ffigen.dart (its asset id
//   is `package:automerge_dart/` + the asset name below).

import 'package:hooks/hooks.dart';
import 'package:native_toolchain_rust/native_toolchain_rust.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    await const RustBuilder(
      assetName: 'src/third_party/automerge.g.dart',
      cratePath: 'third_party/automerge-c',
    ).run(input: input, output: output);
  });
}
