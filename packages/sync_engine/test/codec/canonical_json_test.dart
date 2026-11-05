import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/src/codec/canonical_json.dart';

void main() {
  test('sorts keys at every level and writes no whitespace', () {
    expect(
      canonicalJson({
        'b': 1,
        'a': {'z': true, 'y': null},
        'c': [
          {'q': 1, 'p': 2},
          'x',
        ],
      }),
      '{"a":{"y":null,"z":true},"b":1,"c":[{"p":2,"q":1},"x"]}',
    );
  });

  test('lists keep their order, scalars use jsonEncode', () {
    expect(canonicalJson([3, 1, 2]), '[3,1,2]');
    expect(canonicalJson('a"b\\c\n'), jsonEncode('a"b\\c\n'));
    expect(canonicalJson('강의 ✓'), '"강의 ✓"');
    expect(canonicalJson(0.55), '0.55');
    expect(canonicalJson(4279970411), '4279970411');
    expect(canonicalJson(null), 'null');
    expect(canonicalJson(<String, Object?>{}), '{}');
    expect(canonicalJson(<Object?>[]), '[]');
  });

  test('chunk golden headers (6.4.4)', () {
    const v0 = '001793750400000-0000-3f2a9c0d11e0b7a4';
    const v1 = '001793750460000-0001-3f2a9c0d11e0b7a4';
    final setting = canonicalJsonBytes({
      'k': 'setting',
      'id': 'editor.theme',
      'fv': {'b': v0},
      'e': {
        'version': v0,
        'valueJson': '"dark"',
        'updatedAt': 1793750400000,
        'key': 'editor.theme',
        'deletedAt': null,
      },
    });
    expect(setting, hasLength(229));
    expect(
      utf8.decode(setting),
      '{"e":{"deletedAt":null,"key":"editor.theme","updatedAt":1793750400000,'
      '"valueJson":"\\"dark\\"","version":"$v0"},"fv":{"b":"$v0"},'
      '"id":"editor.theme","k":"setting"}',
    );
    final purge = canonicalJsonBytes({'k': 'note', 'id': 'n9', 'h': v1});
    expect(purge, hasLength(66));
    expect(utf8.decode(purge), '{"h":"$v1","id":"n9","k":"note"}');
  });

  test('is stable for equal content in any insertion order', () {
    final a = {'x': 1, 'y': 2};
    final b = {'y': 2, 'x': 1};
    expect(canonicalJson(a), canonicalJson(b));
  });

  test('rejects values that are not JSON', () {
    expect(() => canonicalJson({1: 'a'}), throwsArgumentError);
    expect(() => canonicalJson(double.nan), throwsArgumentError);
    expect(() => canonicalJson(double.infinity), throwsArgumentError);
    expect(() => canonicalJson(DateTime(2026)), throwsArgumentError);
  });
}
