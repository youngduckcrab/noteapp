// CORE T17 — the providers on the SQLite store (6.16, 7.2.14): the shared provider
// cases of T5, refreshStorageInfo + ref.invalidate(storageInfoProvider) (7.2.12 v1.1),
// a remote change refreshing pageContentProvider (N-7), and the first
// persistenceStatusProvider value arriving without any write.
@TestOn('vm')
library;

import 'package:drift/native.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:note_core/src/storage/web_storage/storage_query.dart';
import 'package:note_core/testing.dart';
import 'package:note_core/testing_vm.dart';
import 'package:riverpod/riverpod.dart';
import 'package:test/test.dart';

import '../shared/providers_contract.dart';
import '../sync/support/sync_support.dart';

/// navigator.storage as a test double (the VM has none).
final class _Storage implements StorageQuery {
  bool granted = false;
  int usage = 100;

  @override
  Future<bool> persisted() async => granted;

  @override
  Future<bool> persist() async => granted;

  @override
  Future<StorageEstimateBytes?> estimate() async =>
      (usage: usage, quota: 1 << 30);
}

ProviderContainer _containerOf(NoteStore store) {
  final container = ProviderContainer.test(
    overrides: [noteStoreProvider.overrideWithValue(store)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('shared provider cases', () {
    defineProviderContractTests(openTestNoteStore);
  });

  test('storageInfoProvider: the new value after refreshStorageInfo + '
      'invalidate, not before', () async {
    final storage = _Storage();
    const opened = StorageInfo(
      backend: StorageBackend.webSharedIndexedDb,
      persistGranted: false,
      usageBytes: 100,
      quotaBytes: 1 << 30,
    );
    final store = await DriftNoteStore.open(
      executor: NativeDatabase.memory(),
      storageInfo: opened,
      config: const NoteStoreConfig(inMemory: true),
      storageQuery: storage,
    );
    addTearDown(store.close);
    final container = _containerOf(store);
    expect(container.read(storageInfoProvider), opened);

    storage
      ..granted = true
      ..usage = 4096;
    final refreshed = await store.refreshStorageInfo();
    expect(refreshed.persistGranted, isTrue);
    expect(refreshed.usageBytes, 4096);
    expect(refreshed.backend, opened.backend);
    expect(store.storageInfo, refreshed);
    // A plain Provider: unchanged until whoever refreshed invalidates it.
    expect(container.read(storageInfoProvider), opened);
    container.invalidate(storageInfoProvider);
    expect(container.read(storageInfoProvider), refreshed);
    expect(
      storageWarningOf(
        container.read(storageInfoProvider),
        store.persistenceStatus,
      ),
      isNull,
    );
  });

  test('a remote stroke on an open page refreshes pageContentProvider; the '
      'history is unchanged', () async {
    final store = await openTestNoteStore() as DriftNoteStore;
    addTearDown(store.close);
    final container = _containerOf(store);
    final note = await store.library.createNote(title: 'n');
    final sessionSub = container.listen(
      noteSessionProvider(note.id),
      (_, _) {},
    );
    addTearDown(sessionSub.close);
    final session = await readWhileListening(
      container,
      noteSessionProvider(note.id).future,
    );
    final pageId = session.pages.single.id;
    final contents = <PageContent>[];
    final sub = container.listen(
      pageContentProvider((noteId: note.id, pageId: pageId)),
      (_, next) {
        if (next case AsyncData(:final value)) contents.add(value);
      },
    );
    addTearDown(sub.close);
    await pumpEventQueue();
    expect(contents.single.strokeCount, 0);

    final stroke = StrokeFixtures.synthetic(pageId: pageId, ids: store.ids);
    await store.sync.applyRemote([
      upsert(stroke, remoteAfter(store)),
    ], policy: newerVersionWinsPolicy);
    await pumpEventQueue();
    expect(contents.last.strokeCount, 1);
    expect(contents.last.strokes.single.id, stroke.id);
    expect(session.history, HistoryState.empty);
    expect(
      await readWhileListening(container, historyStateProvider(note.id).future),
      HistoryState.empty,
    );
  });

  test('persistenceStatusProvider: the first value arrives on a newly opened '
      'in-memory store with no write', () async {
    final store = await openTestNoteStore(seedDefaultPenPresets: false);
    addTearDown(store.close);
    final container = _containerOf(store);
    final first = await readWhileListening(
      container,
      persistenceStatusProvider.future,
    );
    expect(first.pendingOps, 0);
    expect(first.isWriting, isFalse);
    expect(first.lastCommittedAt, isNull);
    expect(first.consecutiveFailures, 0);
    expect(await store.sync.pendingChanges(), isEmpty, reason: 'no write');
    // The in-memory store reports its banner condition (7.2.12 v1.1).
    expect(
      storageWarningOf(container.read(storageInfoProvider), first),
      StorageWarning.notDurable,
    );
  });
}
