import 'dart:math';

import 'package:note_core/note_core.dart';
import 'package:test/test.dart';

void main() {
  // Vectors generated with npm fractional-indexing 3.2.0 (CORE 6.6).
  const vectors = <(String?, String?, String)>[
    (null, null, 'a0'),
    (null, 'a0', 'Zz'),
    (null, 'Zz', 'Zy'),
    ('a0', null, 'a1'),
    ('a1', null, 'a2'),
    ('a0', 'a1', 'a0V'),
    ('a1', 'a2', 'a1V'),
    ('a0V', 'a1', 'a0l'),
    ('Zz', 'a0', 'ZzV'),
    ('Zz', 'a1', 'a0'),
    (null, 'Y00', 'Xzzz'),
    ('bzz', null, 'c000'),
    ('a0', 'a0V', 'a0G'),
    ('a0', 'a0G', 'a08'),
    ('b125', 'b129', 'b127'),
    ('a0', 'a1V', 'a1'),
    ('Zz', 'a01', 'a0'),
    (null, 'a0V', 'a0'),
    (null, 'b999', 'b99'),
    ('az', null, 'b00'),
  ];

  for (final (a, b, expected) in vectors) {
    test('between($a, $b) == $expected', () {
      expect(SortKeys.between(a, b), expected);
    });
  }

  test('errors', () {
    expect(
      () => SortKeys.between('a0', 'a00'),
      throwsArgumentError,
    ); // invalid key
    expect(() => SortKeys.between('a1', 'a0'), throwsArgumentError); // a >= b
    expect(
      () => SortKeys.between('a1', 'a1'),
      throwsArgumentError,
    ); // equal keys
    expect(
      () => SortKeys.between('0', '1'),
      throwsArgumentError,
    ); // invalid head
    expect(SortKeys.isValid('a0'), isTrue);
    expect(SortKeys.isValid('a00'), isFalse);
    expect(SortKeys.isValid(''), isFalse);
    expect(SortKeys.first, 'a0');
  });

  test('nBetween', () {
    expect(SortKeys.nBetween(null, null, 5), ['a0', 'a1', 'a2', 'a3', 'a4']);
    expect(SortKeys.nBetween('a0', 'a1', 3), ['a0G', 'a0V', 'a0l']);
    expect(SortKeys.nBetween(null, 'a0', 3), ['Zx', 'Zy', 'Zz']);
    expect(SortKeys.nBetween('a0', 'a1', 0), isEmpty);
  });

  test('appending 10 000 keys grows logarithmically', () {
    String? last;
    final keys = <String>[];
    for (var i = 0; i < 10000; i++) {
      last = SortKeys.between(last, null);
      keys.add(last);
    }
    expect(keys[61], 'az');
    expect(keys[62], 'b00');
    expect(keys[3905], 'bzz');
    expect(keys[9999], 'c1aH');
  });

  test('inserting 50 times before / after the same neighbour', () {
    var hi = 'a1';
    for (var i = 0; i < 50; i++) {
      hi = SortKeys.between('a0', hi);
    }
    expect(hi, 'a000000000G');
    var lo = 'a0';
    for (var i = 0; i < 50; i++) {
      lo = SortKeys.between(lo, 'a1');
    }
    expect(lo, 'a0zzzzzzzzzz');
  });

  test('10 000 random insertions keep the order', () {
    final r = Random(42);
    final keys = <String>[];
    for (var i = 0; i < 10000; i++) {
      final at = keys.isEmpty ? 0 : r.nextInt(keys.length + 1);
      final key = SortKeys.between(
        at == 0 ? null : keys[at - 1],
        at == keys.length ? null : keys[at],
      );
      keys.insert(at, key);
    }
    final sorted = [...keys]..sort();
    expect(keys, sorted);
    expect(keys.toSet().length, keys.length);
    expect(keys.every(SortKeys.isValid), isTrue);
  });

  test('compareSortKeyThenId', () {
    expect(compareSortKeyThenId('a0', 'b', 'a1', 'a'), lessThan(0));
    expect(compareSortKeyThenId('a1', 'a', 'a1', 'b'), lessThan(0));
    expect(compareSortKeyThenId('a1', 'b', 'a1', 'b'), 0);
  });
}
