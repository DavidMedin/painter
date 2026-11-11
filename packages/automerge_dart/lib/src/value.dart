// What: AutomergeValue, the sealed set of values AutomergeDoc.get returns,
//   and AutomergeObjectType.
// Why: callers switch exhaustively over the kinds the binding models (the
//   leaves and containers of docs/decisions/007-crdt-automerge.md
//   PNT-A0013-03) instead of inspecting dynamic values.
// Coupled to: lib/src/document.dart (AutomergeDoc.get builds these values
//   from automerge-c items; ObjId is defined there).
//   See lib/automerge_dart.dart for the system overview.

import 'dart:typed_data';

import 'document.dart';

/// The kind of an Automerge object.
enum AutomergeObjectType {
  /// A string-keyed map.
  map,

  /// A list.
  list,

  /// A text object (a list of Unicode graphemes).
  text,
}

/// A value stored at a map key: a scalar copied out of the document, or a
/// reference to a nested map or list.
///
/// Scalars own no native memory. [AutomergeMap] and [AutomergeList] hold an
/// [ObjId], which does.
sealed class AutomergeValue {
  const AutomergeValue();
}

/// An explicit `null` stored in the document (unlike an absent key, for
/// which AutomergeDoc.get returns Dart `null`).
final class AutomergeNull extends AutomergeValue {
  /// The null value.
  const AutomergeNull();

  @override
  bool operator ==(Object other) => other is AutomergeNull;

  @override
  int get hashCode => (AutomergeNull).hashCode;

  @override
  String toString() => 'AutomergeNull()';
}

/// A boolean.
final class AutomergeBool extends AutomergeValue {
  /// Wraps [value].
  const AutomergeBool(this.value);

  /// The stored value.
  final bool value;

  @override
  bool operator ==(Object other) =>
      other is AutomergeBool && other.value == value;

  @override
  int get hashCode => Object.hash(AutomergeBool, value);

  @override
  String toString() => 'AutomergeBool($value)';
}

/// A signed 64-bit integer.
final class AutomergeInt extends AutomergeValue {
  /// Wraps [value].
  const AutomergeInt(this.value);

  /// The stored value.
  final int value;

  @override
  bool operator ==(Object other) =>
      other is AutomergeInt && other.value == value;

  @override
  int get hashCode => Object.hash(AutomergeInt, value);

  @override
  String toString() => 'AutomergeInt($value)';
}

/// A 64-bit float.
final class AutomergeDouble extends AutomergeValue {
  /// Wraps [value].
  const AutomergeDouble(this.value);

  /// The stored value.
  final double value;

  /// Equal when [value]s are identical, so a stored NaN equals itself.
  @override
  bool operator ==(Object other) =>
      other is AutomergeDouble && identical(other.value, value);

  @override
  int get hashCode => Object.hash(AutomergeDouble, value);

  @override
  String toString() => 'AutomergeDouble($value)';
}

/// A UTF-8 string.
final class AutomergeString extends AutomergeValue {
  /// Wraps [value].
  const AutomergeString(this.value);

  /// The stored value.
  final String value;

  @override
  bool operator ==(Object other) =>
      other is AutomergeString && other.value == value;

  @override
  int get hashCode => Object.hash(AutomergeString, value);

  @override
  String toString() => 'AutomergeString($value)';
}

/// A byte array, copied out of the document.
final class AutomergeBytes extends AutomergeValue {
  /// Wraps [value].
  const AutomergeBytes(this.value);

  /// The stored bytes.
  final Uint8List value;

  /// Equal when the bytes are equal.
  @override
  bool operator ==(Object other) {
    if (other is! AutomergeBytes) return false;
    final theirs = other.value;
    if (theirs.length != value.length) return false;
    for (var i = 0; i < value.length; i++) {
      if (theirs[i] != value[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(AutomergeBytes, Object.hashAll(value));

  @override
  String toString() => 'AutomergeBytes(${value.length} bytes)';
}

/// A nested map; pass [id] to AutomergeDoc's per-object methods.
final class AutomergeMap extends AutomergeValue {
  /// Refers to the map [id].
  const AutomergeMap(this.id);

  /// The map's object id.
  final ObjId id;

  @override
  bool operator ==(Object other) => other is AutomergeMap && other.id == id;

  @override
  int get hashCode => Object.hash(AutomergeMap, id);

  @override
  String toString() => 'AutomergeMap($id)';
}

/// A nested list; pass [id] to AutomergeDoc.objectType. The binding has no
/// list operations yet.
final class AutomergeList extends AutomergeValue {
  /// Refers to the list [id].
  const AutomergeList(this.id);

  /// The list's object id.
  final ObjId id;

  @override
  bool operator ==(Object other) => other is AutomergeList && other.id == id;

  @override
  int get hashCode => Object.hash(AutomergeList, id);

  @override
  String toString() => 'AutomergeList($id)';
}
