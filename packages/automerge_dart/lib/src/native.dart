// What: Internal helpers between the Dart API and the generated automerge-c
//   bindings: ownership of AMresult pointers, status checking, and copying
//   strings and bytes across the boundary.
// Why: every automerge-c call returns an AMresult that must be freed exactly
//   once; keeping that rule and the AMbyteSpan conversions in one place keeps
//   lib/src/document.dart free of memory bookkeeping.
// Coupled to: lib/src/third_party/automerge.g.dart (bindings),
//   lib/src/document.dart (only caller), lib/src/exception.dart.
//   See lib/automerge_dart.dart for the system overview.

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'exception.dart';
import 'third_party/automerge.g.dart';

/// Frees an AMresult when the Dart object owning it is garbage collected
/// without having been disposed.
final _resultFinalizer = NativeFinalizer(addresses.AMresultFree.cast());

/// Owns one AMresult and frees it on [dispose], or through
/// [_resultFinalizer] if [dispose] is never called.
///
/// Pointers into the result (an AMdoc, AMobjId or AMsyncState) are valid
/// only while it is not disposed. Public classes holding a [NativeResult]
/// implement [Finalizable] themselves, so the VM keeps them, and so this
/// object, alive until each of their methods returns.
final class NativeResult implements Finalizable {
  /// Takes ownership of [pointer], which must have status AM_STATUS_OK
  /// (see [checkResult]).
  NativeResult(Pointer<AMresult> pointer) : _pointer = pointer {
    _resultFinalizer.attach(this, pointer.cast(), detach: this);
  }

  Pointer<AMresult> _pointer;

  /// Whether [dispose] has run.
  bool get isDisposed => _pointer == nullptr;

  /// The owned result.
  ///
  /// Throws [StateError] after [dispose], naming [owner] in the message.
  Pointer<AMresult> pointer(String owner) {
    if (_pointer == nullptr) throw StateError('$owner was disposed.');
    return _pointer;
  }

  /// Frees the result now. Later calls do nothing.
  void dispose() {
    if (_pointer == nullptr) return;
    _resultFinalizer.detach(this);
    AMresultFree(_pointer);
    _pointer = nullptr;
  }
}

/// Returns [result] if its status is AM_STATUS_OK; otherwise frees it and
/// throws an [AutomergeException] carrying its error text.
Pointer<AMresult> checkResult(Pointer<AMresult> result) {
  if (result == nullptr) {
    throw const AutomergeException('automerge-c returned no result.');
  }
  if (AMresultStatus(result) == AMstatus.AM_STATUS_OK) return result;
  final message = spanToString(AMresultError(result));
  AMresultFree(result);
  throw AutomergeException(message);
}

/// Checks [result], passes it to [body], and frees it afterwards, also when
/// [body] throws. [body] must copy out anything it needs from the result.
T useResult<T>(Pointer<AMresult> result, T Function(Pointer<AMresult>) body) {
  final checked = checkResult(result);
  try {
    return body(checked);
  } finally {
    AMresultFree(checked);
  }
}

/// Calls [visit] for each item of [result], in order.
void forEachItem(
  Pointer<AMresult> result,
  void Function(Pointer<AMitem>) visit,
) {
  using((arena) {
    // AMitemsNext advances an iterator in place, so it needs the by-value
    // AMitems struct copied into native memory.
    final items = arena<AMitems>()..ref = AMresultItems(result);
    for (
      var item = AMitemsNext(items, 1);
      item != nullptr;
      item = AMitemsNext(items, 1)
    ) {
      visit(item);
    }
  });
}

/// Copies [bytes] into memory from [arena] and returns a span over it.
///
/// Always allocates at least one byte: automerge-c turns the span into a
/// Rust slice, which must not start at a null pointer even when empty.
AMbyteSpan bytesToSpan(Uint8List bytes, Arena arena) {
  final src = arena<Uint8>(bytes.isEmpty ? 1 : bytes.length);
  src.asTypedList(bytes.length).setAll(0, bytes);
  final span = arena<AMbyteSpan>();
  span.ref
    ..src = src
    ..count = bytes.length;
  return span.ref;
}

/// UTF-8 encodes [text] into memory from [arena] (see [bytesToSpan]).
AMbyteSpan stringToSpan(String text, Arena arena) =>
    bytesToSpan(utf8.encode(text), arena);

/// A span with a null pointer, which automerge-c reads as "absent".
AMbyteSpan nullSpan(Arena arena) {
  final span = arena<AMbyteSpan>();
  span.ref
    ..src = nullptr
    ..count = 0;
  return span.ref;
}

/// Copies the bytes a span points at into Dart memory.
Uint8List spanToBytes(AMbyteSpan span) => span.count == 0
    ? Uint8List(0)
    : Uint8List.fromList(span.src.asTypedList(span.count));

/// Decodes the UTF-8 text a span points at.
String spanToString(AMbyteSpan span) =>
    span.count == 0 ? '' : utf8.decode(span.src.asTypedList(span.count));

/// Lowercase hexadecimal form of [bytes], as used for change hashes.
String toHex(Uint8List bytes) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}
