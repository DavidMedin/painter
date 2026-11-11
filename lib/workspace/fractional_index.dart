// What: Fractional-index order keys: strings that sort with plain
//   String.compareTo and can always be generated between two neighbors, each
//   ending in characters derived from the generating actor.
// Why: Parts of a stored split are ordered by an `order` key so that inserting
//   one part writes only the new node, never its siblings, and two peers
//   inserting at the same place at once still get distinct keys
//   (docs/decisions/010-pane-layout-tree.md, PNT-A0016-09). It is separate
//   from the layout tree because it is a general string algorithm.
// Coupled to: layout_tree.dart (sorts children by these keys) and
//   layout_ops.dart and layout_flash.dart (generate keys for new nodes).

/// Digits that generated keys are made of, in ascending code-unit order, so
/// that String.compareTo orders them like the digits of a base-62 fraction.
const String _digits =
    '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';

/// Number of actor-derived characters ending every generated key.
const int _suffixLength = 5;

/// A key strictly between [before] and [after] in String.compareTo order,
/// ending in characters derived from [actor].
///
/// A null [before] means "before every key" and a null [after] "after every
/// key". Returns null when no such key exists: when [before] is not less
/// than [after], or when [after] is [before] followed only by the smallest
/// digit '0' (for example "" and "0"); the caller then renumbers the siblings
/// with [orderKeysAfter]. Generated keys never end in '0', so keys made only
/// by this file always leave room before them.
String? orderKeyBetween(String? before, String? after, String actor) {
  final low = before ?? '';
  if (after != null && low.compareTo(after) >= 0) return null;
  final prefix = _prefixBetween(low, after);
  if (prefix == null) return null;
  return '$prefix${_actorSuffix(actor)}';
}

/// [count] increasing keys, all after [previous] (or from the start when it is
/// null), each ending in [actor]'s suffix. Used to number a whole sibling list
/// at once, for new splits and when [orderKeyBetween] finds no room.
List<String> orderKeysAfter(String? previous, int count, String actor) {
  final keys = <String>[];
  var last = previous;
  for (var i = 0; i < count; i++) {
    // After any key there is always room, so the result is never null.
    final key = orderKeyBetween(last, null, actor)!;
    keys.add(key);
    last = key;
  }
  return keys;
}

/// The shortest string m with [low] < m < [high] (no upper bound when [high]
/// is null) that is not a prefix of [high], so that m followed by any suffix
/// stays below [high]. Null when none exists.
String? _prefixBetween(String low, String? high) {
  final prefix = StringBuffer();
  // While tied with low's prefix, m must not drop below low; while tied with
  // high's prefix, m must not reach high. Once m differs from one of them it
  // is free on that side.
  var tiedLow = true;
  var tiedHigh = high != null;
  final limit = low.length + (high?.length ?? 0) + 2;
  for (var i = 0; i < limit; i++) {
    final lo = tiedLow && i < low.length ? low.codeUnitAt(i) : -1;
    if (tiedHigh && i >= high!.length) return null;
    final hi = tiedHigh ? high!.codeUnitAt(i) : 0x10000;
    final digit = _digitBetween(lo, hi);
    if (digit != null) {
      prefix.writeCharCode(digit);
      return prefix.toString();
    }
    if (lo == -1) {
      // low is exhausted (any continuation is above it) and no digit fits
      // below hi: follow high and look further.
      prefix.writeCharCode(hi);
    } else {
      prefix.writeCharCode(lo);
      if (lo < hi) tiedHigh = false;
      if (lo > hi) return null;
    }
    if (lo == -1) tiedLow = false;
  }
  return null;
}

/// The middle digit of [_digits] whose code unit is strictly between [lo] and
/// [hi], or null when there is none.
int? _digitBetween(int lo, int hi) {
  var first = -1;
  var last = -1;
  for (var i = 0; i < _digits.length; i++) {
    final unit = _digits.codeUnitAt(i);
    if (unit > lo && unit < hi) {
      if (first == -1) first = i;
      last = i;
    }
  }
  if (first == -1) return null;
  return _digits.codeUnitAt((first + last + 1) ~/ 2);
}

/// [_suffixLength] digits from an FNV-1a hash of [actor], the last never '0'.
/// Different actors get different suffixes except for rare hash collisions,
/// after which sorting falls back to node ids and stays deterministic.
String _actorSuffix(String actor) {
  var hash = 0x811c9dc5;
  for (final unit in actor.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  final out = StringBuffer();
  for (var i = 0; i < _suffixLength - 1; i++) {
    out.write(_digits[hash % _digits.length]);
    hash ~/= _digits.length;
  }
  out.write(_digits[1 + hash % (_digits.length - 1)]);
  return out.toString();
}
