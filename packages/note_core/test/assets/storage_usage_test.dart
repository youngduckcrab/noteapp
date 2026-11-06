// AssetStorageUsage.bytesByType (2nd-round contract 7.2.6, m5-7/02-core 6.15.1): the same rows
// as totalBytes, per type — Σ bytesByType == totalBytes — on the fake and the real store.
@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';
import 'package:note_core/testing_vm.dart';
import 'package:test/test.dart';

Uint8List _bytes(int length, int seed) => Uint8List.fromList([
  for (var i = 0; i < length; i++) (i * 13 + seed) % 256,
]);

void _cases(String name, Future<NoteStore> Function() open) {
  test(
    '$name: Σ bytesByType == totalBytes; absent types are not keys',
    () async {
      final store = await open();
      addTearDown(store.close);
      expect((await store.assets.usage()).bytesByType, isEmpty);
      await store.assets.put(
        _bytes(100, 1),
        type: AssetType.pdf,
        mimeType: 'application/pdf',
      );
      await store.assets.put(
        _bytes(40, 2),
        type: AssetType.image,
        mimeType: 'image/png',
      );
      await store.assets.put(
        _bytes(30, 3),
        type: AssetType.image,
        mimeType: 'image/jpeg',
      );
      final usage = await store.assets.usage();
      expect(usage.bytesByType, {AssetType.pdf: 100, AssetType.image: 70});
      expect(usage.bytesByType.containsKey(AssetType.audio), isFalse);
      expect(
        usage.bytesByType.values.fold<int>(0, (a, b) => a + b),
        usage.totalBytes,
      );
      expect(
        () => usage.bytesByType[AssetType.audio] = 1,
        throwsUnsupportedError,
      );
    },
  );
}

void main() {
  _cases('fake', () async => createFakeNoteStore());
  _cases('real', openTestNoteStore);
}
