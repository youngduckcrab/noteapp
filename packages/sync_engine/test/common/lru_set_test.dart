import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/src/common/lru_set.dart';

void main() {
  test('add reports new elements and keeps at most capacity', () {
    final s = LruSet<String>(3);
    expect(s.add('a'), isTrue);
    expect(s.add('b'), isTrue);
    expect(s.add('a'), isFalse);
    expect(s.add('c'), isTrue);
    expect(s.add('d'), isTrue);
    expect(s.length, 3);
    // 'b' was the least recent ('a' was re-added after it).
    expect(s.contains('b'), isFalse);
    expect(s.toList(), ['a', 'c', 'd']);
  });

  test('contains does not refresh, add does', () {
    final s = LruSet<int>(2)
      ..add(1)
      ..add(2);
    expect(s.contains(1), isTrue);
    s.add(3);
    expect(s.contains(1), isFalse);
    s
      ..add(2)
      ..add(4);
    expect(s.toList(), [2, 4]);
  });

  test('remove and clear', () {
    final s = LruSet<int>(4)
      ..add(1)
      ..add(2);
    expect(s.remove(1), isTrue);
    expect(s.remove(1), isFalse);
    s.clear();
    expect(s.length, 0);
  });

  test('capacity must be positive', () {
    expect(() => LruSet<int>(0), throwsArgumentError);
  });
}
