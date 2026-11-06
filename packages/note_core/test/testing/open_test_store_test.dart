// CORE T6 — openTestNoteStore body (contract 7.6, CORE 4.10). (v2.0) The B2-α state of the
// real store (m5-7/02-core 8.1 'B2 상태', column 'B2-α 끝').
@TestOn('vm')
library;

import 'dart:io';

import 'package:clock/clock.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:note_core/testing_vm.dart';
import 'package:test/test.dart';

import '../shared/b2_alpha_store_cases.dart';

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

  // SYNC's S-20 integration tests (sync_engine test/integration, CoreTestStore.failCommits)
  // make real CORE fail its commits by moving the open file away; that needs the rollback
  // journal (with WAL the commits go on).
  test('a file database keeps the rollback journal: moving the open file away '
      'fails its commits (retried, the write pending, reads go on) until it is '
      'back', () async {
    final dir = Directory.systemTemp.createTempSync('note_core_test_store_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/a.db';
    final moved = File('$path.moved');
    final store = await openTestNoteStore(filePath: path);
    addTearDown(store.close);
    // Runs before close, which waits for the queued writes (6.9).
    addTearDown(() {
      if (moved.existsSync()) moved.renameSync(path);
    });

    final journal = await (store as DriftNoteStore).db
        .customSelect('PRAGMA journal_mode')
        .getSingle();
    expect(journal.read<String>('journal_mode'), 'delete');

    final note = await store.library.createNote(title: 'before');
    File(path).renameSync(moved.path);
    var renamed = false;
    final write = store.library
        .renameNote(note.id, 'after')
        .then((_) => renamed = true);
    // A failed commit, or the write committing anyway (then the checks below fail).
    final failing = await Future.any([
      store.persistenceStatusStream.firstWhere(
        (s) => s.consecutiveFailures >= 1,
      ),
      write.then((_) => store.persistenceStatus),
    ]);
    expect(renamed, isFalse, reason: 'the write is retried, not completed');
    expect(failing.consecutiveFailures, greaterThanOrEqualTo(1));
    expect(failing.lastError, isNotNull);
    expect(failing.pendingOps, greaterThan(0));
    expect((await store.library.getNote(note.id))!.title, 'before');

    moved.renameSync(path);
    await write;
    expect((await store.library.getNote(note.id))!.title, 'after');
    expect(store.persistenceStatus.consecutiveFailures, 0);
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

  group('B2-α state (m5-7/02-core 8.1)', () {
    defineB2AlphaStoreTests(
      openTestNoteStore,
      tasks: (
        recordings:
            null, // works since CORE T30 (test/shared/recording_contract.dart)
        drafts: 'T31',
        handwriting: 'T32',
        search: 'T33a',
        v1Copy: null, // works since CORE T24 (an in-memory store has no copy)
        objects: 'T27',
      ),
      hasV1CopyApi: true,
    );

    test(
      'a new store has no row of the new kinds (DB v2; written since T26)',
      () async {
        final store = await openTestNoteStore();
        addTearDown(store.close);
        final refs = [
          const EntityRef(EntityKind.pageObject, 'o1'),
          EntityRef(EntityKind.handwriting, HandwritingText.idFor('p1')),
        ];
        expect(await store.sync.readVersioned(refs), [null, null]);
        expect(kDatabaseSchemaVersion, 2);
      },
    );
  });
}
