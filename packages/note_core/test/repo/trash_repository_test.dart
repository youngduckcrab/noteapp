// CORE T9 — DriftTrashRepository beyond the shared contract (6.8 '휴지통'): rows and
// outbox of a purge, restore outbox fields, cycle-safe restore, retention from the
// config and the automatic clean-up of openNoteStore (10 s, then every 6 h).
@TestOn('vm')
library;

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:drift/native.dart';
import 'package:fake_async/fake_async.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:note_core/src/storage/drift_trash_repository.dart';
import 'package:note_core/src/storage/outbox_writer.dart';
import 'package:note_core/testing.dart';
import 'package:test/test.dart';

import '../storage/storage_support.dart';

const _day = Duration(days: 1);

Future<void> _putRemote(DriftNoteStore store, List<SyncEntity> entities) {
  var ms = 1793750400000;
  return store.queue.run((tx) async {
    for (final e in entities) {
      await tx.putRemote(
        e,
        EntityFieldVersions(Hlc(ms++, 0, 'ffffffffffffffff')),
      );
    }
  }, origin: ChangeOrigin.remote);
}

void main() {
  late DriftNoteStore store;
  late LibraryRepository lib;
  late TrashRepository trash;
  setUp(() async {
    store = await openStore();
    lib = store.library;
    trash = store.trash;
  });
  tearDown(() => store.close());

  Future<List<OutboxEntry>> outbox() => readOutbox(store.db);
  Future<void> ack() => store.db.delete(store.db.outbox).go();

  test('purge: rows of the group with pages, strokes, recordings; one outbox '
      'purge per folder / note', () async {
    final f = await lib.createFolder(name: 'f');
    final sub = await lib.createFolder(name: 'sub', parentId: f.id);
    const pageId = '0193f1d2-7c40-7000-8000-0000000001a1';
    final n = await lib.createNote(
      title: 'n',
      folderId: sub.id,
      pages: [
        PageDraft(
          id: pageId,
          size: PageSize.a4Portrait,
          background: PdfBackground(assetId: 'c' * 64, pdfPageIndex: 0),
          strokes: [StrokeFixtures.synthetic(pageId: pageId, ids: store.ids)],
        ),
      ],
    );
    final other = await lib.createNote(title: 'other');
    await store.queue.run(
      (tx) => tx.putLocal(recording('rec-1', n.id), const {kAllFields}),
    );
    await store.queue.run(
      (tx) => tx.putLocal(
        Asset(
          id: 'c' * 64,
          ownerId: kLocalOwnerId,
          type: AssetType.pdf,
          mimeType: 'application/pdf',
          size: 3,
          createdAt: 1,
        ),
        const {kAllFields},
      ),
    );
    await lib.trashItems([FolderRef(f.id)]);
    // Pending entries: the group's upserts and the note's page / stroke / recording.
    final pendingBefore = await outbox();
    final folderSeq = pendingBefore.singleWhere((e) => e.entityId == f.id).seq;
    expect(
      pendingBefore.where((e) => e.kind == EntityKind.stroke),
      hasLength(1),
    );

    final batches = <ChangeBatch>[];
    final listen = store.changes.listen(batches.add);
    await trash.purge([FolderRef(f.id)]);
    await pumpEventQueue();
    await listen.cancel();

    expect(await lib.getFolder(f.id), isNull);
    expect(await lib.getFolder(sub.id), isNull);
    expect(await lib.getNote(n.id), isNull);
    final db = store.db;
    expect(await db.select(db.pages).get(), hasLength(1)); // other's page
    expect(await db.select(db.strokes).get(), isEmpty);
    expect(await db.select(db.recordings).get(), isEmpty);
    expect(
      await db.select(db.assets).get(),
      hasLength(1),
      reason: 'asset bytes and rows stay (GC later)',
    );

    final entries = await outbox();
    final byId = {for (final e in entries) e.entityId: e};
    for (final id in [f.id, sub.id, n.id]) {
      expect(byId[id]!.op, OutboxOp.purge, reason: id);
      expect(byId[id]!.changedFields, {kAllFields});
    }
    expect(byId[f.id]!.seq, folderSeq, reason: 'pending upsert became purge');
    expect(
      entries.where(
        (e) =>
            e.kind == EntityKind.page ||
            e.kind == EntityKind.stroke ||
            e.kind == EntityKind.recording,
      ),
      everyElement(
        isA<OutboxEntry>().having((e) => e.noteId, 'noteId', other.id),
      ),
      reason: 'children entries of purged notes are dropped',
    );
    expect(batches, hasLength(1));
    expect(
      batches.single.changes.map((c) => (c.kind, c.id, c.purged)),
      unorderedEquals([
        (EntityKind.folder, f.id, true),
        (EntityKind.folder, sub.id, true),
        (EntityKind.note, n.id, true),
      ]),
    );
  });

  test(
    'restore writes deletedAt / trashRootId (+ place of the representative)',
    () async {
      final f = await lib.createFolder(name: 'f');
      final n = await lib.createNote(title: 'n', folderId: f.id);
      final m = await lib.createNote(title: 'm', folderId: f.id);
      await lib.trashItems([NoteRef(n.id)]);
      await lib.trashItems([FolderRef(f.id)]);
      await ack();
      await trash.restore([FolderRef(f.id)]);
      final entries = {for (final e in await outbox()) e.entityId: e};
      expect(entries[f.id]!.changedFields, {'deletedAt', 'trashRootId'});
      expect(entries[m.id]!.changedFields, {'deletedAt', 'trashRootId'});
      expect(entries.containsKey(n.id), isFalse, reason: 'its own group');
      await ack();
      await lib.trashItems([FolderRef(f.id)]);
      await trash.purge([FolderRef(f.id)]);
      await lib.createNote(title: 'top'); // the restored note goes after it
      await ack();
      await trash.restore([NoteRef(n.id)]);
      final restored = (await outbox()).single;
      expect(restored.entityId, n.id);
      expect(restored.changedFields, {
        'deletedAt',
        'trashRootId',
        'folderId',
        'sortKey',
      });
    },
  );

  test(
    'restore walks through trashed folders with rows; a cycle ends at the top',
    () async {
      final a = await lib.createFolder(name: 'a');
      final b = await lib.createFolder(name: 'b', parentId: a.id);
      final c = await lib.createFolder(name: 'c', parentId: b.id);
      final n = await lib.createNote(title: 'n', folderId: c.id);
      await lib.trashItems([NoteRef(n.id)]);
      await lib.trashItems([FolderRef(c.id)]);
      await lib.trashItems([FolderRef(b.id)]);
      await trash.restore([NoteRef(n.id)]);
      expect((await lib.getNote(n.id))!.folderId, a.id);

      // A sync merge left a parent cycle among trashed folders.
      final x =
          folder(
            '0193f1d2-7c40-7000-8000-0000000001b1',
            parentId: '0193f1d2-7c40-7000-8000-0000000001b2',
          ).copyWith(
            deletedAt: 1,
            trashRootId: '0193f1d2-7c40-7000-8000-0000000001b1',
          );
      final y = folder('0193f1d2-7c40-7000-8000-0000000001b2', parentId: x.id)
          .copyWith(
            deletedAt: 1,
            trashRootId: '0193f1d2-7c40-7000-8000-0000000001b2',
          );
      final orphan = note('0193f1d2-7c40-7000-8000-0000000001b3').copyWith(
        folderId: x.id,
        deletedAt: 1,
        trashRootId: '0193f1d2-7c40-7000-8000-0000000001b3',
      );
      await _putRemote(store, [x, y, orphan]);
      await trash.restore([NoteRef(orphan.id)]);
      final back = (await lib.getNote(orphan.id))!;
      expect(back.isDeleted, isFalse);
      expect(back.folderId, isNull);
    },
  );

  test(
    'purge / restore of another owner\'s rows: not found or ignored',
    () async {
      final theirs = note('0193f1d2-7c40-7000-8000-0000000001c1').copyWith(
        ownerId: 'user-2',
        deletedAt: 1,
        trashRootId: '0193f1d2-7c40-7000-8000-0000000001c1',
      );
      await _putRemote(store, [theirs]);
      expect(await trash.watchTrash().first, isEmpty);
      await trash.purge([NoteRef(theirs.id)]);
      await trash.emptyTrash();
      expect(await store.db.select(store.db.notes).get(), hasLength(1));
      await expectLater(
        trash.restore([NoteRef(theirs.id)]),
        throwsA(isA<EntityNotFoundException>()),
      );
    },
  );

  test(
    'expiresAt and purgeExpired use NoteStoreConfig.trashRetention',
    () async {
      var now = DateTime.utc(2026, 11, 5);
      final s = await DriftNoteStore.open(
        executor: NativeDatabase.memory(),
        storageInfo: const StorageInfo(backend: StorageBackend.nativeMemory),
        config: NoteStoreConfig(
          inMemory: true,
          trashRetention: _day,
          clock: Clock(() => now),
          idGenerator: SequentialIdGenerator(),
        ),
      );
      addTearDown(s.close);
      final n = await s.library.createNote(title: 'n');
      await s.library.trashItems([NoteRef(n.id)]);
      final item = (await s.trash.watchTrash().first).single;
      expect(item.expiresAt, item.deletedAt + _day.inMilliseconds);
      now = now.add(const Duration(hours: 23));
      expect(await s.trash.purgeExpired(), 0);
      now = now.add(const Duration(hours: 1));
      expect(await s.trash.purgeExpired(), 1);
    },
  );

  test(
    'an open session of a note in a trashed folder turns read-only before the '
    'trash Future completes; restore makes it writable again (N-4)',
    () async {
      final f = await lib.createFolder(name: 'f');
      final n = await lib.createNote(title: 'n', folderId: f.id);
      final session = await store.openSession(n.id);
      addTearDown(session.close);
      final notes = <Note>[];
      final sub = session.noteStream.listen(notes.add);
      addTearDown(sub.cancel);
      expect(session.isReadOnly, isFalse);
      await lib.trashItems([FolderRef(f.id)]);
      expect(session.isReadOnly, isTrue);
      expect(notes.last.isDeleted, isTrue);
      expect(
        () => session.execute(const DeletePages(pageIds: [])),
        throwsA(isA<ReadOnlyNoteException>()),
      );
      await trash.restore([FolderRef(f.id)]);
      expect(session.isReadOnly, isFalse);
      expect(notes.last.isDeleted, isFalse);
      // Purged while open: stays read-only.
      await lib.trashItems([NoteRef(n.id)]);
      await trash.purge([NoteRef(n.id)]);
      expect(session.isReadOnly, isTrue);
    },
  );

  group('automatic clean-up (openNoteStore)', () {
    test('10 s after opening, then every 6 hours; close stops it', () {
      fakeAsync((async) {
        final clock = async.getClock(DateTime.utc(2026, 11, 5));
        late DriftNoteStore s;
        DriftNoteStore.open(
          executor: NativeDatabase.memory(),
          storageInfo: const StorageInfo(backend: StorageBackend.nativeMemory),
          config: NoteStoreConfig(
            inMemory: true,
            clock: clock,
            idGenerator: SequentialIdGenerator(),
          ),
          autoPurge: true,
        ).then((x) => s = x);
        async.flushMicrotasks();

        Note? old;
        Future<void> trashOld(String id) async {
          final t = clock.now().millisecondsSinceEpoch;
          await _putRemote(s, [
            note(id).copyWith(
              deletedAt: t - const Duration(days: 31).inMilliseconds,
              trashRootId: id,
            ),
          ]);
          old = await s.library.getNote(id);
        }

        unawaited(trashOld('old-1'));
        async.flushMicrotasks();
        expect(old, isNotNull);
        async.elapse(const Duration(seconds: 9));
        expect(_rowCount(async, s), 1);
        async.elapse(const Duration(seconds: 1));
        expect(_rowCount(async, s), 0, reason: 'first run at 10 s');

        unawaited(trashOld('old-2'));
        async.flushMicrotasks();
        async.elapse(kAutoPurgePeriod - const Duration(seconds: 1));
        expect(_rowCount(async, s), 1);
        async.elapse(const Duration(seconds: 1));
        expect(_rowCount(async, s), 0, reason: 'then every 6 hours');

        unawaited(s.close());
        async.flushMicrotasks();
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('openTestNoteStore starts no timer', () {
      fakeAsync((async) {
        late DriftNoteStore s;
        openStore().then((x) => s = x);
        async.flushMicrotasks();
        expect(async.pendingTimers, isEmpty);
        unawaited(s.close());
        async.flushMicrotasks();
      });
    });
  });
}

int _rowCount(FakeAsync async, DriftNoteStore s) {
  int? n;
  s.db.select(s.db.notes).get().then((rows) => n = rows.length);
  async.flushMicrotasks();
  return n!;
}
