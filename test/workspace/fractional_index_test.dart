// What: Unit tests for fractional-index order keys: keys between, before and
//   after neighbors, actor suffixes, and the cases with no room.
// Why: Sibling order in the Layout tree depends on these keys sorting by
//   plain String.compareTo and on concurrent inserts at one place getting
//   distinct keys (docs/decisions/010-pane-layout-tree.md, PNT-A0016-09).
// Covers: lib/workspace/fractional_index.dart.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:painter/workspace/fractional_index.dart';

void main() {
  test('a key lies strictly between its neighbors', () {
    final first = orderKeyBetween(null, null, 'aa')!;
    final last = orderKeyBetween(first, null, 'aa')!;
    final middle = orderKeyBetween(first, last, 'aa')!;
    final head = orderKeyBetween(null, first, 'aa')!;
    expect(first.compareTo(last), lessThan(0));
    expect(first.compareTo(middle), lessThan(0));
    expect(middle.compareTo(last), lessThan(0));
    expect(head.compareTo(first), lessThan(0));
  });

  test('two actors inserting at one place get distinct ordered keys', () {
    final low = orderKeyBetween(null, null, 'aa')!;
    final high = orderKeyBetween(low, null, 'aa')!;
    final fromA = orderKeyBetween(low, high, 'actor-a')!;
    final fromB = orderKeyBetween(low, high, 'actor-b')!;
    expect(fromA, isNot(fromB));
    for (final key in [fromA, fromB]) {
      expect(low.compareTo(key), lessThan(0));
      expect(key.compareTo(high), lessThan(0));
    }
  });

  test('repeated inserts at random places keep a sorted list', () {
    final random = Random(7);
    final keys = <String>[orderKeyBetween(null, null, 'aa')!];
    for (var i = 0; i < 500; i++) {
      final at = random.nextInt(keys.length + 1);
      final key = orderKeyBetween(
        at == 0 ? null : keys[at - 1],
        at == keys.length ? null : keys[at],
        'actor${random.nextInt(3)}',
      )!;
      keys.insert(at, key);
    }
    final sorted = [...keys]..sort();
    expect(keys, sorted);
    expect(keys.toSet(), hasLength(keys.length));
  });

  test('keys made one after another increase', () {
    final keys = orderKeysAfter(null, 100, 'aa');
    expect(keys, [...keys]..sort());
    expect(keys.toSet(), hasLength(100));
    final more = orderKeysAfter(keys.last, 2, 'bb');
    expect(keys.last.compareTo(more.first), lessThan(0));
  });

  test('is null when there is no room', () {
    expect(orderKeyBetween('b', 'a', 'aa'), isNull);
    expect(orderKeyBetween('a', 'a', 'aa'), isNull);
    expect(orderKeyBetween(null, '0', 'aa'), isNull);
    expect(orderKeyBetween('x', 'x00', 'aa'), isNull);
  });

  test('works between keys with characters outside its digits', () {
    final key = orderKeyBetween('a~', 'a~~', 'aa');
    expect(key, isNotNull);
    expect('a~'.compareTo(key!), lessThan(0));
    expect(key.compareTo('a~~'), lessThan(0));
  });
}
