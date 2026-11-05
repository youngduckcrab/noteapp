// CORE T6 — openTestNoteStore body (contract 7.6, CORE 4.10).
@TestOn('vm')
library;

import 'dart:io';

import 'package:clock/clock.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/testing_vm.dart';
import 'package:test/test.dart';

void main() {
  test(
    'storageInfo omitted → nativeMemory, not durable, notDurable banner',
    () async {
      final store = await openTestNoteStore();
      addTearDown(store.close);
      expect(store.storageInfo.backend, StorageBackend.nativeMemory);
      expect(store.storageInfo.isDurable, isFalse);
      expect(
        storageWarningOf(store.storageInfo, store.persistenceStatus),
        StorageWarning.notDurable,
      );
    },
  );

  test('NoteStoreConfig(inMemory: true) reports the same', () async {
    final store = await openNoteStore(const NoteStoreConfig(inMemory: true));
    addTearDown(store.close);
    expect(store.storageInfo.backend, StorageBackend.nativeMemory);
    expect(store.storageInfo.isDurable, isFalse);
    expect(
      storageWarningOf(store.storageInfo, store.persistenceStatus),
      StorageWarning.notDurable,
    );
  });

  test(
    'a given storageInfo is reported as is; no banner for nativeFile',
    () async {
      const info = StorageInfo(backend: StorageBackend.nativeFile);
      final store = await openTestNoteStore(storageInfo: info);
      addTearDown(store.close);
      expect(store.storageInfo, info);
      expect(await store.refreshStorageInfo(), info);
      expect(
        storageWarningOf(store.storageInfo, store.persistenceStatus),
        isNull,
      );

      const web = StorageInfo(backend: StorageBackend.webInMemory);
      final other = await openTestNoteStore(storageInfo: web);
      addTearDown(other.close);
      expect(other.storageInfo, web);
    },
  );

  test(
    'deviceNodeId fixes the HLC node; omitted → a random valid node',
    () async {
      final a = await openTestNoteStore(deviceNodeId: '00000000000000aa');
      final b = await openTestNoteStore(deviceNodeId: '00000000000000bb');
      final c = await openTestNoteStore();
      addTearDown(a.close);
      addTearDown(b.close);
      addTearDown(c.close);
      expect(a.sync.deviceNodeId, '00000000000000aa');
      expect(b.sync.deviceNodeId, '00000000000000bb');
      expect(c.sync.deviceNodeId, matches(RegExp(r'^[0-9a-f]{16}$')));
      expect(
        () => openTestNoteStore(deviceNodeId: 'not-a-node'),
        throwsArgumentError,
      );
    },
  );

  test('ownerId, ids and clock are the given ones', () async {
    final ids = SequentialIdGenerator(prefix: 't');
    final clock = Clock.fixed(DateTime.utc(2026, 11, 5));
    final store = await openTestNoteStore(
      ownerId: 'user-1',
      ids: ids,
      clock: clock,
    );
    addTearDown(store.close);
    expect(store.ownerId, 'user-1');
    expect(store.sync.ownerId, 'user-1');
    expect(store.ids, same(ids));
    expect(store.clock, same(clock));
  });

  test('a file database keeps its node and owner across reopen', () async {
    final dir = Directory.systemTemp.createTempSync('note_core_test_store_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/a.db';

    final first = await openTestNoteStore(filePath: path, ownerId: 'u1');
    expect(first.storageInfo.backend, StorageBackend.nativeFile);
    expect(first.storageInfo.isDurable, isTrue);
    final node = first.sync.deviceNodeId;
    await first.close();

    // A persisted owner wins over the argument (NoteStoreConfig.ownerId).
    final again = await openTestNoteStore(filePath: path, ownerId: 'u2');
    expect(again.sync.deviceNodeId, node);
    expect(again.ownerId, 'u1');
    await again.close();

    final fixed = await openTestNoteStore(
      filePath: path,
      deviceNodeId: '0000000000000abc',
    );
    expect(fixed.sync.deviceNodeId, '0000000000000abc');
    await fixed.close();
  });

  test(
    'persistenceStatusStream emits the current value once on listen',
    () async {
      final store = await openTestNoteStore();
      addTearDown(store.close);
      final first = await store.persistenceStatusStream.first;
      expect(first, store.persistenceStatus);
      expect(first.pendingOps, 0);
      expect(first.isWriting, isFalse);
    },
  );
}
