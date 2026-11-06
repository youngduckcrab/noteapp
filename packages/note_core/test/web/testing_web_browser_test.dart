// testing_web.dart (2nd-round contract 7.6, C2-39; m5-7/02-core 4.9, 6.18.1): the REAL web
// store under a test name — open → write → close → reopen (the data stays) →
// deleteWebTestNoteStore → an empty store; name validation.
@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:note_core/note_core.dart';
import 'package:note_core/testing_web.dart';
import 'package:test/test.dart';

void main() {
  final name = 'core_t23b_${DateTime.now().microsecondsSinceEpoch}';

  test('open → write → close → reopen → delete', () async {
    final store = await openWebTestNoteStore(name);
    expect(store.storageInfo.backend, isNot(StorageBackend.nativeMemory));
    final note = await store.library.createNote(title: '웹 시험');
    final asset = await store.assets.put(
      Uint8List.fromList([1, 2, 3, 4]),
      type: AssetType.image,
      mimeType: 'image/png',
    );
    await store.close();

    final again = await openWebTestNoteStore(name);
    expect((await again.library.getNote(note.id))?.title, '웹 시험');
    expect(await again.assets.readBytes(asset.id), [1, 2, 3, 4]);
    await again.close();

    await deleteWebTestNoteStore(name);
    final fresh = await openWebTestNoteStore(name);
    expect(await fresh.library.getNote(note.id), isNull);
    expect(await fresh.assets.getAsset(asset.id), isNull);
    await fresh.close();
    await deleteWebTestNoteStore(name);
  });

  test('the name must match ^[A-Za-z0-9_-]{1,40}\$', () async {
    for (final bad in ['', 'a b', 'x' * 41, 'ü', 'a/b']) {
      await expectLater(
        openWebTestNoteStore(bad),
        throwsArgumentError,
        reason: bad,
      );
      await expectLater(
        deleteWebTestNoteStore(bad),
        throwsArgumentError,
        reason: bad,
      );
    }
  });

  test(
    'deleteWebTestNoteStore while the store is open is a StateError',
    () async {
      final n = '${name}_open';
      final store = await openWebTestNoteStore(n);
      await expectLater(deleteWebTestNoteStore(n), throwsStateError);
      await store.close();
      await deleteWebTestNoteStore(n);
    },
  );
}
