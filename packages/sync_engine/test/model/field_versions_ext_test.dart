import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/src/model/field_versions_ext.dart';

Hlc h(int millis, [int counter = 0]) =>
    Hlc(millis, counter, '3f2a9c0d11e0b7a4');

EntityFieldVersions roundTrip(EntityFieldVersions v) =>
    EntityFieldVersions.fromJson(v.toJson());

void main() {
  group('ofUnit', () {
    final v = EntityFieldVersions(h(10), {'title': h(30), 'sortKey': h(20)});

    test('is the max over the unit fields', () {
      expect(v.ofUnit(['folderId', 'sortKey']), h(20));
      expect(v.ofUnit(['title', 'sortKey']), h(30));
    });

    test('fields without an override carry base', () {
      expect(v.ofUnit(['name']), h(10));
      expect(v.ofUnit(const []), h(10));
    });
  });

  group('stamped', () {
    final v = EntityFieldVersions(h(10), {'title': h(30)});

    test("'*' resets every field to the new version", () {
      final s = v.stamped(['title', kAllFields], h(40));
      expect(s.base, h(40));
      expect(s.overrides, isEmpty);
      expect(s.max, h(40));
    });

    test('listed fields get the new version, base and others are kept', () {
      final s = v.stamped(['name', 'color'], h(40));
      expect(s.base, h(10));
      expect(s.of('title'), h(30));
      expect(s.of('name'), h(40));
      expect(s.of('color'), h(40));
      expect(s.of('icon'), h(10));
      expect(s.max, h(40));
      expect(roundTrip(s).toJson(), s.toJson());
    });

    test('result is in normal form (overrides only > base)', () {
      final s = v.stamped(['title'], h(5));
      expect(s.overrides.containsKey('title'), isFalse);
      expect(s.toJson(), roundTrip(s).toJson());
    });
  });

  group('normalizedFieldVersions', () {
    test('base = min, overrides = fields newer than base', () {
      final n = normalizedFieldVersions({
        'title': h(30),
        'name': h(10),
        'sortKey': h(10),
        'color': h(20, 3),
      });
      expect(n.base, h(10));
      expect(n.overrides, {'color': h(20, 3), 'title': h(30)});
      expect(n.overrides.keys, ['color', 'title']);
    });

    test('equals EntityFieldVersions.fromJson(toJson()) form', () {
      final n = normalizedFieldVersions({'a': h(1), 'b': h(2), 'c': h(2)});
      final r = roundTrip(n);
      expect(n, r);
      expect(n.toJson(), r.toJson());
      expect(n.overrides, r.overrides);
      expect(n.toJson(), {
        'b': h(1).toString(),
        'o': {'b': h(2).toString(), 'c': h(2).toString()},
      });
    });

    test('all equal → no overrides', () {
      final n = normalizedFieldVersions({'a': h(7), 'b': h(7)});
      expect(n.overrides, isEmpty);
      expect(n.toJson(), {'b': h(7).toString()});
    });

    test('is unmodifiable and rejects an empty map', () {
      final n = normalizedFieldVersions({'a': h(1), 'b': h(2)});
      expect(() => n.overrides['x'] = h(3), throwsUnsupportedError);
      expect(() => normalizedFieldVersions(const {}), throwsArgumentError);
    });
  });
}
