// What: Regenerates third_party/automerge-c/include/automerge-c/automerge.h,
//   the C header of the vendored automerge-c crate, with cbindgen.
// Why: upstream produces the header through CMake (CMakeLists.txt), which this
//   package does not vendor or use. This script runs the crate's build.rs the
//   same way and repeats the header post-processing CMake applies, so ffigen
//   (tool/ffigen.dart) reads the same header a CMake build would install.
// Coupled to: third_party/automerge-c/build.rs (writes automerge.h when
//   CBINDGEN_TARGET_DIR is set), third_party/automerge-c/rust-toolchain.toml
//   (pinned channel), tool/ffigen.dart (consumes the header).
//
// Usage, from the package root: dart run tool/generate_header.dart
// Needs rustup with its proxy directory on PATH (see README.md).

import 'dart:io';

/// Pointer size, in bytes, of every target listed in rust-toolchain.toml.
///
/// cbindgen cannot evaluate `size_of::<usize>()`, so automerge-c names the
/// constant `USIZE_USIZE_USIZE_` (src/items.rs) and CMake replaces each
/// `USIZE_` with `+<pointer size>`. All current targets are 64-bit.
const _pointerSize = 8;

Future<void> main() async {
  final packageRoot = Platform.script.resolve('../');
  final crateDir = packageRoot.resolve('third_party/automerge-c/');
  final headerFile = File.fromUri(
    crateDir.resolve('include/automerge-c/automerge.h'),
  );

  final toolchain = File.fromUri(
    crateDir.resolve('rust-toolchain.toml'),
  ).readAsStringSync();
  final channel = RegExp(
    r'^channel\s*=\s*"([^"]+)"',
    multiLine: true,
  ).firstMatch(toolchain)?.group(1);
  if (channel == null) {
    stderr.writeln('No channel found in rust-toolchain.toml.');
    exit(1);
  }

  // A fresh target directory forces build.rs to run; Cargo would otherwise
  // reuse a cached build script output and write no header.
  final scratch = Directory.systemTemp.createTempSync('automerge_header');
  try {
    final result = await Process.run(
      'rustup',
      [
        'run',
        channel,
        'cargo',
        'check',
        '--locked',
        '--manifest-path',
        crateDir.resolve('Cargo.toml').toFilePath(),
        '--target-dir',
        '${scratch.path}/target',
      ],
      environment: {'CBINDGEN_TARGET_DIR': scratch.path},
    );
    if (result.exitCode != 0) {
      stderr
        ..writeln('cargo check failed (exit ${result.exitCode}):')
        ..writeln(result.stderr);
      exit(result.exitCode);
    }

    final raw = File('${scratch.path}/automerge.h').readAsStringSync();
    // The two substitutions CMakeLists.txt applies after Cargo runs:
    // cbindgen renders the `AM` prefix of enum tags as `A_M`, and it leaves
    // the symbolic `USIZE_` size constant unevaluated.
    final header = raw
        .replaceAllMapped(RegExp(r'A_M([^_]+)_'), (match) => 'AM_${match[1]}_')
        .replaceAll('USIZE_', '+$_pointerSize');

    headerFile
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(header);
    stdout.writeln('Wrote ${headerFile.path}');
  } finally {
    scratch.deleteSync(recursive: true);
  }
}
