// CORE T16 — deleteLocalNoteData on the web (6.18): the SQLite database (whatever web
// storage drift chose) and the blob IndexedDB are deleted; openNoteStore with the same
// config then starts an empty database. Refused while the store is open; a deletion
// blocked by another connection (another tab) ends in a TimeoutException.
@TestOn('browser')
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:idb_shim/idb_browser.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/connect/connect_browser.dart';
import 'package:test/test.dart';

import 'web_store_support.dart';

final _bytes = Uint8List.fromList([for (var i = 0; i < 3000; i++) i % 199]);

void main() {
  test('after deleting, the same config opens an empty database', () async {
    final config = freshWebConfig('reset');
    dropAfterTest(config);
    var store = await openNoteStore(config);
    final note = await store.library.createNote(title: '지울 노트');
    final asset = await store.assets.put(
      _bytes,
      type: AssetType.image,
      mimeType: 'image/png',
    );
    final node = store.sync.deviceNodeId;
    await store.close();

    await deleteLocalNoteData(config);

    store = await openNoteStore(config);
    addTearDown(store.close);
    expect(await store.library.getNote(note.id), isNull);
    final listing = await store.library
        .watchListing(const LibraryQuery())
        .first;
    expect(listing.notes, isEmpty);
    expect(listing.folders, isEmpty);
    expect(await store.assets.getAsset(asset.id), isNull);
    expect(await store.assets.readBytes(asset.id), isNull);
    expect(await store.assets.hasBytes(asset.id), isFalse);
    // A new database: new random device node, the default presets again.
    expect(store.sync.deviceNodeId, isNot(node));
    expect(await store.penPresets.getPresets(), hasLength(5));
    expect(await store.sync.pendingChanges(), hasLength(5));
  });

  test(
    'refused while a store of that database is open; nothing deleted',
    () async {
      final config = freshWebConfig('open');
      dropAfterTest(config);
      final store = await openNoteStore(config);
      addTearDown(store.close);
      final note = await store.library.createNote(title: 'kept');
      await expectLater(deleteLocalNoteData(config), throwsStateError);
      expect((await store.library.getNote(note.id))?.title, 'kept');
    },
  );

  test('a database that was never created: nothing to do', () async {
    await deleteLocalNoteData(freshWebConfig('never'));
  });

  test('blocked by another open connection: TimeoutException, then it goes '
      'through once that connection closes', () async {
    final config = freshWebConfig('blocked');
    dropAfterTest(config);
    final store = await openNoteStore(config);
    await store.assets.put(
      _bytes,
      type: AssetType.image,
      mimeType: 'image/png',
    );
    await store.close();

    // "Another tab": a connection to the blob database that ignores
    // versionchange (the store's own connection closes on it, 6.13).
    final other = await idbFactoryBrowser.open(config.web.blobDatabaseName);
    var otherOpen = true;
    addTearDown(() {
      if (otherOpen) other.close();
    });
    await expectLater(
      deleteLocalData(config, timeout: const Duration(milliseconds: 300)),
      throwsA(isA<TimeoutException>()),
    );
    other.close();
    otherOpen = false;
    await deleteLocalNoteData(config);

    final reopened = await openNoteStore(config);
    addTearDown(reopened.close);
    expect(await reopened.assets.listAssets(), isEmpty);
  });

  test('the default limit of a blocked web deletion is 10 s (6.18)', () {
    expect(deleteBlockedTimeout, const Duration(seconds: 10));
  });
}
