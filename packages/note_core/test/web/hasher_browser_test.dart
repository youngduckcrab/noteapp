// CORE T13 — the web content hasher (6.13 ①): SubtleCrypto SHA-256 gives the same
// lowercase hex as package:crypto (the VM / fallback path).
@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:note_core/src/assets/content_hasher.dart';
import 'package:note_core/src/assets/content_hasher_browser.dart' as browser;
import 'package:test/test.dart';

Uint8List _bytes(int length, int seed) =>
    Uint8List.fromList([for (var i = 0; i < length; i++) (i * 7 + seed) % 256]);

void main() {
  test('SubtleCrypto is available in the test page', () {
    expect(browser.subtleCrypto(), isNotNull);
  });

  test('known value: SHA-256 of "abc"', () async {
    expect(
      await sha256Hex(Uint8List.fromList('abc'.codeUnits)),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
  });

  for (final length in [0, 1, 55, 64, 1000, 4 * 1024 * 1024 + 3]) {
    test('$length bytes: SubtleCrypto = package:crypto', () async {
      final bytes = _bytes(length, length % 17);
      final hex = await sha256Hex(bytes);
      expect(hex, sha256.convert(bytes).toString());
      expect(hex, matches(RegExp(r'^[0-9a-f]{64}$')));
    });
  }

  test('hexOf pads every byte to two digits', () {
    expect(
      browser.hexOf(Uint8List.fromList([0, 1, 15, 16, 255])),
      '00010f10ff',
    );
  });
}
