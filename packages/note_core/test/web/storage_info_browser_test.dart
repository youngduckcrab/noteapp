// CORE T16 — navigator.storage in the browser (6.12 ①②): openNoteStore asks persist()
// (answered or cut off at the 1 s limit) and estimate(); refreshStorageInfo reads them
// again. A persist() that never answers does not hold the open up.
@TestOn('browser')
library;

import 'dart:async';

import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/web_storage/persistence.dart';
import 'package:note_core/src/storage/web_storage/storage_query.dart';
import 'package:note_core/testing.dart';
import 'package:test/test.dart';

import 'web_store_support.dart';

/// The browser's StorageQuery with a persist() that never answers.
final class _HangingPersist implements StorageQuery {
  _HangingPersist(this._real);
  final StorageQuery _real;
  var persistCalls = 0;

  @override
  Future<bool> persisted() => _real.persisted();

  @override
  Future<bool> persist() {
    persistCalls++;
    return Completer<bool>().future;
  }

  @override
  Future<StorageEstimateBytes?> estimate() => _real.estimate();
}

void main() {
  test('the browser has navigator.storage with persisted / estimate', () async {
    final query = platformStorageQuery();
    expect(query, isNotNull);
    expect(await query!.persisted(), isA<bool>());
    final estimate = await query.estimate();
    expect(estimate, isNotNull, reason: 'Chrome has estimate()');
    expect(estimate!.quota, greaterThan(0));
    expect(estimate.usage, greaterThanOrEqualTo(0));
  });

  test('openNoteStore with requestPersistentStorage: persistGranted and '
      'usage / quota are filled', () async {
    final config = freshWebConfig('persist', requestPersistentStorage: true);
    dropAfterTest(config);
    final store = await openNoteStore(config);
    addTearDown(store.close);
    final info = store.storageInfo;
    printOnFailure('$info');
    expect(info.persistGranted, isNotNull);
    expect(info.quotaBytes, isNotNull);
    expect(info.usageBytes, isNotNull);
    expect(info.isDurable, isTrue);
  });

  test('a persist() that never answers is cut off at the limit with the '
      'persisted() value', () async {
    final real = platformStorageQuery()!;
    final persisted = await real.persisted();
    final query = _HangingPersist(real);
    const base = StorageInfo(backend: StorageBackend.webSharedIndexedDb);
    final info = await storageInfoAtOpen(base, query, requestPersist: true);
    // Chrome may already persist this origin; persist() is only asked if not.
    expect(query.persistCalls, persisted ? 0 : 1);
    expect(info.persistGranted, persisted);
    expect(info.quotaBytes, isNotNull);
  });

  test('refreshStorageInfo re-reads persisted() / estimate() and becomes '
      'storageInfo', () async {
    final config = freshWebConfig('refresh');
    dropAfterTest(config);
    final store = await openNoteStore(config);
    addTearDown(store.close);
    final before = store.storageInfo;
    final note = await store.library.createNote(title: 'usage');
    final session = await store.openSession(note.id);
    await session.openPage(session.pages.first.id);
    session.execute(
      AddStrokes(
        pageId: session.pages.first.id,
        strokes: [
          for (var i = 0; i < 50; i++)
            StrokeFixtures.synthetic(
              pageId: session.pages.first.id,
              ids: store.ids,
              seed: i,
            ),
        ],
      ),
    );
    await session.close();
    await store.flush();

    final after = await store.refreshStorageInfo();
    printOnFailure('before $before, after $after');
    expect(store.storageInfo, after);
    expect(after.backend, before.backend);
    expect(after.missingBrowserFeatures, before.missingBrowserFeatures);
    expect(after.persistGranted, await platformStorageQuery()!.persisted());
    expect(after.usageBytes, isNotNull);
    expect(after.quotaBytes, isNotNull);
  });
}
