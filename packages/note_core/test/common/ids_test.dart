import 'package:clock/clock.dart';
import 'package:note_core/note_core.dart';
import 'package:test/test.dart';

void main() {
  final v7 = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  group('UuidV7IdGenerator', () {
    test('produces RFC 9562 v7 ids (36 chars, lowercase)', () {
      final g = UuidV7IdGenerator();
      for (var i = 0; i < 1000; i++) {
        final id = g.newId();
        expect(id, matches(v7));
        expect(id.length, 36);
        expect(isValidEntityId(id), isTrue);
      }
    });

    test('100 000 ids are unique', () {
      final g = UuidV7IdGenerator();
      final ids = {for (var i = 0; i < 100000; i++) g.newId()};
      expect(ids.length, 100000);
    });

    test('lexicographic order follows the clock (ms precision)', () {
      var ms = 1793750400000;
      final g = UuidV7IdGenerator(
        clock: Clock(
          () => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
        ),
      );
      final ids = <String>[];
      for (var i = 0; i < 500; i++) {
        ids.add(g.newId());
        ms += 1 + i % 3;
      }
      final sorted = [...ids]..sort();
      expect(sorted, ids);
    });

    test('the time prefix encodes the clock milliseconds', () {
      const ms = 1793750400000;
      final g = UuidV7IdGenerator(
        clock: Clock.fixed(
          DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
        ),
      );
      final hex = g.newId().replaceAll('-', '').substring(0, 12);
      expect(int.parse(hex, radix: 16), ms);
    });
  });

  test('SequentialIdGenerator is deterministic', () {
    final g = SequentialIdGenerator();
    expect([g.newId(), g.newId()], ['id-000001', 'id-000002']);
    final p = SequentialIdGenerator(prefix: 'page');
    expect(p.newId(), 'page-000001');
    expect(isValidEntityId(p.newId()), isTrue);
  });

  test('isValidEntityId', () {
    expect(isValidEntityId('a'), isTrue);
    expect(isValidEntityId('preset-default-ballpoint'), isTrue);
    expect(isValidEntityId('A_b-9'), isTrue);
    expect(isValidEntityId('x' * 64), isTrue);
    expect(isValidEntityId('x' * 65), isFalse);
    expect(isValidEntityId(''), isFalse);
    expect(isValidEntityId('a b'), isFalse);
    expect(isValidEntityId('a/b'), isFalse);
    expect(isValidEntityId('노트'), isFalse);
  });

  test('kLocalOwnerId', () => expect(kLocalOwnerId, 'local'));
}
