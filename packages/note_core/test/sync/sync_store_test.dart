// CORE T14 — the sync window of the SQLite store (contract 7.2.10 v1.3, CORE 4.6, 6.10):
// outbox reads and acks, readVersioned, applyRemote decisions, device-local fields
// (CORE-2-1), pendingLocalFields (CORE-2-9 / CORE-3-3), origins (CORE-2-8), validation,
// rollback and the write-Future rule.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/src/assets/blob_store.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:note_core/testing.dart';
import 'package:test/test.dart';

import '../storage/storage_support.dart';
import 'support/sync_support.dart';

void main() {
  late DriftNoteStore store;
  late List<ChangeBatch> batches;
  late StreamSubscription<ChangeBatch> sub;

  setUp(() async {
    store = await openStore();
    batches = [];
    sub = store.changes.listen(batches.add);
  });
  tearDown(() async {
    await sub.cancel();
    await store.close();
  });

  SyncStore sync() => store.sync;

  Future<OutboxEntry?> entryOf(EntityKind kind, String id) async {
    final all = await store.sync.pendingChanges(limit: 100000);
    return all.where((e) => e.kind == kind && e.entityId == id).firstOrNull;
  }

  Future<VersionedEntity?> read(EntityKind kind, String id) async =>
      (await store.sync.readVersioned([EntityRef(kind, id)])).single;

  Future<int> outboxCount() async =>
      (await store.sync.pendingChanges(limit: 100000)).length;

  group('outbox reads', () {
    test('pendingChanges: seq order, afterSeq, limit', () async {
      await store.library.createFolder(name: 'a');
      await store.library.createFolder(name: 'b');
      await store.library.createFolder(name: 'c');
      final all = await sync().pendingChanges();
      expect(all, hasLength(3));
      expect([
        for (final e in all) e.seq,
      ], orderedEquals([...all.map((e) => e.seq)]..sort()));
      final after = await sync().pendingChanges(afterSeq: all.first.seq);
      expect([for (final e in after) e.seq], [all[1].seq, all[2].seq]);
      final limited = await sync().pendingChanges(limit: 2);
      expect([for (final e in limited) e.seq], [all[0].seq, all[1].seq]);
      await expectLater(
        sync().pendingChanges(limit: 0),
        throwsA(isA<ArgumentError>()),
      );
    });

    test(
      'acknowledge deletes matching (seq, rev); a re-edited entry stays',
      () async {
        final note = await store.library.createNote(title: 'n');
        final first = (await entryOf(EntityKind.note, note.id))!;
        await store.library.renameNote(note.id, 'renamed');
        final second = (await entryOf(EntityKind.note, note.id))!;
        expect(second.seq, first.seq);
        expect(second.rev, first.rev + 1);
        await sync().acknowledge([first.ack]);
        expect((await entryOf(EntityKind.note, note.id))!.rev, second.rev);
        await sync().acknowledge([second.ack]);
        expect(await entryOf(EntityKind.note, note.id), isNull);
      },
    );

    test('watchPendingCount follows writes and acks', () async {
      final counts = <int>[];
      final s = sync().watchPendingCount().listen(counts.add);
      await pumpEventQueue();
      expect(counts, [0]);
      await store.library.createFolder(name: 'a');
      expect(counts.last, 1);
      final e = await sync().pendingChanges();
      await sync().acknowledge([e.single.ack]);
      expect(counts.last, 0);
      await s.cancel();
    });
  });

  group('readVersioned', () {
    test(
      'tombstones included, purged / unknown null, field versions kept',
      () async {
        final a = await store.library.createNote(title: 'a');
        final b = await store.library.createNote(title: 'b');
        await store.library.renameNote(a.id, 'a2');
        await store.library.trashItems([NoteRef(b.id)]);
        final c = await store.library.createNote(title: 'c');
        await store.library.trashItems([NoteRef(c.id)]);
        await store.trash.purge([NoteRef(c.id)]);
        final got = await sync().readVersioned([
          EntityRef(EntityKind.note, a.id),
          EntityRef(EntityKind.note, b.id),
          EntityRef(EntityKind.note, c.id),
          const EntityRef(EntityKind.folder, 'unknown'),
          EntityRef(EntityKind.note, a.id),
        ]);
        expect(got, hasLength(5));
        final va = got[0]!;
        expect((va.entity as Note).title, 'a2');
        expect(va.versions.overrides.keys, contains('title'));
        expect(va.entity.version, va.versions.max);
        expect(va.versions.of('title'), va.versions.max);
        expect(va.versions.of('isFavorite'), va.versions.base);
        expect(got[1]!.entity.isDeleted, isTrue);
        expect(got[2], isNull);
        expect(got[3], isNull);
        expect(got[4]!.entity, va.entity);
      },
    );
  });

  group('applyRemote decisions', () {
    test('KeepLocal: row and pending entry unchanged', () async {
      final n = await store.library.createNote(title: 'local');
      final before = (await entryOf(EntityKind.note, n.id))!;
      final row = await read(EntityKind.note, n.id);
      final report = await sync().applyRemote([
        upsert(n.copyWith(title: 'remote'), remoteAfter(store)),
      ], policy: (_, _, _) => const KeepLocal());
      expect(report.kept, 1);
      expect(report.taken + report.merged + report.purged, 0);
      expect((await read(EntityKind.note, n.id))!.entity, row!.entity);
      final after = (await entryOf(EntityKind.note, n.id))!;
      expect(after, before, reason: 'OutboxEntry value equality');
    });

    test(
      'TakeRemote stores the remote versions as given and drops the entry',
      () async {
        final n = await store.library.createNote(title: 'local');
        final v = remoteAfter(store, 10);
        final t = Hlc(v.millis + 5, 0, kRemoteNode);
        final change = upsert(n.copyWith(title: 'remote'), v, {'title': t});
        final report = await sync().applyRemote([
          change,
        ], policy: (_, _, _) => const TakeRemote());
        expect(report.taken, 1);
        final got = (await read(EntityKind.note, n.id))!;
        expect((got.entity as Note).title, 'remote');
        expect(got.versions.toJson(), change.versions.toJson());
        expect(got.entity.version, t);
        expect(await entryOf(EntityKind.note, n.id), isNull);
      },
    );

    test(
      'TakeRemote(dropPendingLocal: false) keeps the pending entry',
      () async {
        final n = await store.library.createNote(title: 'local');
        final before = (await entryOf(EntityKind.note, n.id))!;
        await sync().applyRemote([
          upsert(n.copyWith(title: 'remote'), remoteAfter(store)),
        ], policy: (_, _, _) => const TakeRemote(dropPendingLocal: false));
        final after = (await entryOf(EntityKind.note, n.id))!;
        expect((after.seq, after.rev), (before.seq, before.rev));
      },
    );

    test('WriteMerged sets the entry fields exactly', () async {
      final n = await store.library.createNote(title: 'local');
      await store.library.setFavorite([n.id], true);
      final before = (await entryOf(EntityKind.note, n.id))!;
      final v = remoteAfter(store);
      final merged = decoded(
        n.copyWith(title: 'merged'),
        EntityFieldVersions(v),
      );
      await sync().applyRemote(
        [upsert(n, v)],
        policy: (_, _, _) => WriteMerged(
          merged,
          EntityFieldVersions(v),
          fieldsToUpload: const {'title'},
        ),
      );
      final after = (await entryOf(EntityKind.note, n.id))!;
      expect(after.seq, before.seq);
      expect(after.rev, before.rev + 1);
      expect(after.changedFields, {'title'});
      expect(after.op, OutboxOp.upsert);
      expect(after.hlc, v);
      expect(
        ((await read(EntityKind.note, n.id))!.entity as Note).title,
        'merged',
      );

      // Empty set → entry deleted.
      final v2 = remoteAfter(store);
      await sync().applyRemote(
        [upsert(n, v2)],
        policy: (_, _, _) => WriteMerged(
          decoded(n, EntityFieldVersions(v2)),
          EntityFieldVersions(v2),
          fieldsToUpload: const {},
        ),
      );
      expect(await entryOf(EntityKind.note, n.id), isNull);

      // No entry and a non-empty set → a new entry with a new seq.
      final other = await store.library.createFolder(name: 'later');
      final otherSeq = (await entryOf(EntityKind.folder, other.id))!.seq;
      final v3 = remoteAfter(store);
      await sync().applyRemote(
        [upsert(n, v3)],
        policy: (_, _, _) => WriteMerged(
          decoded(n, EntityFieldVersions(v3)),
          EntityFieldVersions(v3),
          fieldsToUpload: const {'tags'},
        ),
      );
      final added = (await entryOf(EntityKind.note, n.id))!;
      expect(added.seq, greaterThan(otherSeq));
      expect(added.rev, 1);
      expect(added.changedFields, {'tags'});
      expect(added.hlc, v3);
    });

    test(
      'remote writes record no outbox entry; new entities count as taken',
      () async {
        final v = remoteAfter(store);
        final report = await sync().applyRemote([
          upsert(folder('rf'), v),
          upsert(note('rn'), v),
          upsert(page('rp', 'rn'), v),
          upsert(stroke('rs', 'rp'), v),
        ], policy: newerVersionWinsPolicy);
        expect(report.taken, 4);
        expect(await outboxCount(), 0);
        expect(report.affectedNoteIds, {'rn'});
      },
    );

    test(
      'HLC receive: the clock passes a remote value; +48 h leaves it',
      () async {
        final now = DateTime.now().millisecondsSinceEpoch;
        final near = Hlc(
          now + const Duration(hours: 1).inMilliseconds,
          3,
          kRemoteNode,
        );
        await sync().applyRemote([
          upsert(folder('f1'), near),
        ], policy: newerVersionWinsPolicy);
        expect(store.hlc.last < near, isFalse);
        final f = await store.library.createFolder(name: 'after');
        expect(f.version! > near, isTrue);

        final before = store.hlc.last;
        final far = Hlc(
          now + const Duration(hours: 48).inMilliseconds,
          0,
          kRemoteNode,
        );
        await sync().applyRemote([
          upsert(folder('f2'), far),
        ], policy: newerVersionWinsPolicy);
        expect(store.hlc.last, before);
        expect((await read(EntityKind.folder, 'f2'))!.versions.max, far);
      },
    );

    test(
      'ChangeBatch(origin: remote) with hints; orphans wait for their page',
      () async {
        final v = remoteAfter(store);
        await sync().applyRemote([
          upsert(stroke('s1', 'p1'), v),
        ], policy: newerVersionWinsPolicy);
        expect(
          await read(EntityKind.stroke, 's1'),
          isNotNull,
          reason: 'orphan stored',
        );
        expect(
          batches,
          isEmpty,
          reason: 'an orphan stroke is not in its own batch',
        );
        await sync().applyRemote([
          upsert(note('n1'), v),
          upsert(page('p1', 'n1'), v),
          upsert(recording('r1', 'n1'), v),
        ], policy: newerVersionWinsPolicy);
        await pumpEventQueue();
        final b = batches.single;
        expect(b.origin, ChangeOrigin.remote);
        final c = {for (final x in b.changes) x.id: x};
        expect(c['p1']!.noteId, 'n1');
        expect(c['r1']!.noteId, 'n1');
        expect(c['s1']!.noteId, 'n1');
        expect(c['s1']!.pageId, 'p1');
        final rows = await store.db.select(store.db.strokes).get();
        expect(rows.single.noteId, 'n1');
      },
    );

    test(
      'affected note: updatedAt = max(current, applied), no outbox',
      () async {
        final n = await store.library.createNote(title: 'n');
        await sync().acknowledge([
          for (final e in await sync().pendingChanges()) e.ack,
        ]);
        final stored = (await store.library.getNote(n.id))!;
        final pageId = stored.firstPageId!;
        final p = (await read(EntityKind.page, pageId))!.entity as Page;
        final later = stored.updatedAt + 5000;
        await sync().applyRemote([
          upsert(p.copyWith(updatedAt: later), remoteAfter(store)),
        ], policy: newerVersionWinsPolicy);
        expect((await store.library.getNote(n.id))!.updatedAt, later);
        await sync().applyRemote([
          upsert(p.copyWith(updatedAt: 1), remoteAfter(store)),
        ], policy: newerVersionWinsPolicy);
        expect((await store.library.getNote(n.id))!.updatedAt, later);
        expect(await outboxCount(), 0);
      },
    );

    test(
      'RemotePurge: the trash group, its contents and their entries',
      () async {
        final root = await store.library.createFolder(name: 'root');
        final child = await store.library.createFolder(
          name: 'child',
          parentId: root.id,
        );
        final inChild = await store.library.createNote(
          title: 'in child',
          folderId: child.id,
        );
        final other = await store.library.createNote(title: 'other');
        final session = await store.openSession(inChild.id);
        await session.openPage(session.pages.first.id);
        await session
            .execute(
              AddStrokes(
                pageId: session.pages.first.id,
                strokes: [
                  StrokeFixtures.synthetic(
                    pageId: session.pages.first.id,
                    ids: store.ids,
                  ),
                ],
              ),
            )
            .persisted;
        await session.close();
        await store.library.trashItems([
          FolderRef(root.id),
        ]); // entries of the group
        final countOther = (await sync().pendingChanges(limit: 1000))
            .where((e) => e.entityId == other.id || e.noteId == other.id)
            .length;
        batches.clear();
        final report = await sync().applyRemote([
          RemotePurge(EntityKind.folder, root.id),
        ], policy: newerVersionWinsPolicy);
        expect(report.purged, 1);
        expect(report.affectedNoteIds, {inChild.id});
        for (final id in [root.id, child.id]) {
          expect(await read(EntityKind.folder, id), isNull);
        }
        expect(await read(EntityKind.note, inChild.id), isNull);
        expect(await store.db.select(store.db.strokes).get(), isEmpty);
        expect(
          (await store.db.select(store.db.pages).get()).map((r) => r.noteId),
          everyElement(other.id),
        );
        final left = await sync().pendingChanges(limit: 1000);
        expect(
          left,
          hasLength(countOther),
          reason: 'only the other note\'s entries',
        );
        expect(
          left.where((e) => e.op == OutboxOp.purge),
          isEmpty,
          reason: 'no new purge entry',
        );
        await pumpEventQueue();
        final b = batches.single;
        expect(b.origin, ChangeOrigin.remote);
        expect(
          {
            for (final c in b.changes)
              if (c.purged) c.id,
          },
          {root.id, child.id, inChild.id},
        );
      },
    );

    test('RemotePurge of an active note; unknown ids purge nothing', () async {
      final n = await store.library.createNote(title: 'active');
      final report = await sync().applyRemote([
        RemotePurge(EntityKind.note, n.id),
        const RemotePurge(EntityKind.note, 'unknown'),
      ], policy: newerVersionWinsPolicy);
      expect(report.purged, 1);
      expect(await store.library.getNote(n.id), isNull);
      expect(await outboxCount(), 0);
    });

    test('validation: ArgumentError before anything is applied', () async {
      final v = remoteAfter(store);
      Future<void> bad(
        List<RemoteChange> changes, [
        Map<String, String> meta = const {},
      ]) => expectLater(
        sync().applyRemote(
          changes,
          policy: newerVersionWinsPolicy,
          metaUpdates: meta,
        ),
        throwsA(isA<ArgumentError>()),
      );
      final ok = upsert(folder('ok'), v);
      await bad([
        ok,
        RemoteUpsert(folder('nv'), EntityFieldVersions(v)),
      ]); // version null
      await bad([
        ok,
        RemoteUpsert(
          decoded(folder('mm'), EntityFieldVersions(v)),
          EntityFieldVersions(v, {'name': Hlc(v.millis + 1, 0, kRemoteNode)}),
        ),
      ]); // version != max
      await bad([ok, const RemotePurge(EntityKind.page, 'p1')]);
      await bad([ok, upsert(folder('bad id!'), v)]);
      await bad([ok], {'other.key': 'x'});
      await bad([ok], {'sync.big': 'x' * (256 * 1024 + 1)});
      expect(await read(EntityKind.folder, 'ok'), isNull);
      expect(batches, isEmpty);
    });

    test(
      'a WriteMerged invariant violation rolls everything back (StateError)',
      () async {
        final v = remoteAfter(store);
        final w = Hlc(v.millis + 1, 0, kRemoteNode);
        await expectLater(
          sync().applyRemote(
            [upsert(folder('first'), v), upsert(folder('second'), v)],
            policy: (local, remote, _) => remote.entity.id == 'first'
                ? const TakeRemote()
                : WriteMerged(
                    remote.entity,
                    EntityFieldVersions(w),
                    fieldsToUpload: const {},
                  ),
            metaUpdates: const {'sync.cursor': '1'},
          ),
          throwsA(isA<StateError>()),
        );
        expect(await read(EntityKind.folder, 'first'), isNull);
        expect(await sync().readMeta('sync.cursor'), isNull);
        expect(batches, isEmpty);
        // The store keeps working.
        await sync().applyRemote([
          upsert(folder('first'), v),
        ], policy: newerVersionWinsPolicy);
        expect(await read(EntityKind.folder, 'first'), isNotNull);
      },
    );

    test('later changes of one call see the earlier results', () async {
      final v = remoteAfter(store);
      final w = Hlc(v.millis + 1, 0, kRemoteNode);
      final policy = RecordingPolicy(newerVersionWinsPolicy);
      await sync().applyRemote([
        upsert(folder('f', name: 'one'), v),
        upsert(folder('f', name: 'two'), w),
      ], policy: policy.call);
      expect(policy.calls[0].local, isNull);
      expect((policy.calls[1].local!.entity as Folder).name, 'one');
      expect(
        ((await read(EntityKind.folder, 'f'))!.entity as Folder).name,
        'two',
      );
    });
  });

  group('device-local fields (CORE-2-1)', () {
    test('a new remote asset without bytes is listed for download', () async {
      final v = remoteAfter(store);
      final asset = Asset(
        id: 'b' * 64,
        ownerId: kLocalOwnerId,
        type: AssetType.image,
        mimeType: 'image/png',
        size: 10,
        createdAt: 1,
        storagePath: 'users/u/assets/${'b' * 64}',
        hasLocalBytes: true, // a local value of the handed-over entity: ignored
        version: v,
      );
      await sync().applyRemote([
        RemoteUpsert(asset, EntityFieldVersions(v)),
      ], policy: newerVersionWinsPolicy);
      final missing = await store.assets.listAssets(hasLocalBytes: false);
      expect(missing.map((a) => a.id), [asset.id]);
      expect(await store.assets.readBytes(asset.id), isNull);
    });

    test(
      'an asset with local bytes keeps them through TakeRemote and WriteMerged',
      () async {
        final put = await store.assets.put(
          Uint8List.fromList([1, 2, 3]),
          type: AssetType.image,
          mimeType: 'image/png',
        );
        final v = remoteAfter(store);
        final remote = put.copyWith(
          storagePath: 'users/u/assets/${put.id}',
          hasLocalBytes: false,
        );
        await sync().applyRemote([
          upsert(remote, v),
        ], policy: (_, _, _) => const TakeRemote());
        var got = (await store.assets.getAsset(put.id))!;
        expect(
          (got.hasLocalBytes, got.storagePath),
          (true, remote.storagePath),
        );
        final w = remoteAfter(store);
        await sync().applyRemote(
          [upsert(remote, w)],
          policy: (_, r, _) =>
              WriteMerged(r.entity, r.versions, fieldsToUpload: const {}),
        );
        got = (await store.assets.getAsset(put.id))!;
        expect(got.hasLocalBytes, isTrue);
        expect(await store.assets.readBytes(put.id), [1, 2, 3]);
      },
    );

    test('orphan chunks (some keys only) → a new row without bytes', () async {
      final id = 'c' * 64;
      await store.blobs.chunks.put(
        chunkKey(id, 0),
        Uint8List(kAssetChunkBytes),
      );
      final v = remoteAfter(store);
      final asset = Asset(
        id: id,
        ownerId: kLocalOwnerId,
        type: AssetType.pdf,
        mimeType: 'application/pdf',
        size: kAssetChunkBytes * 2 + 1,
        createdAt: 1,
        version: v,
      );
      await sync().applyRemote([
        RemoteUpsert(asset, EntityFieldVersions(v)),
      ], policy: newerVersionWinsPolicy);
      expect((await store.assets.getAsset(id))!.hasLocalBytes, isFalse);
      // Every chunk key present → a new row has the bytes.
      final id2 = 'd' * 64;
      await store.blobs.chunks.put(chunkKey(id2, 0), Uint8List.fromList([7]));
      await sync().applyRemote([
        RemoteUpsert(
          Asset(
            id: id2,
            ownerId: kLocalOwnerId,
            type: AssetType.image,
            mimeType: 'image/png',
            size: 1,
            createdAt: 1,
            version: v,
          ),
          EntityFieldVersions(v),
        ),
      ], policy: newerVersionWinsPolicy);
      expect((await store.assets.getAsset(id2))!.hasLocalBytes, isTrue);
      expect(await store.assets.readBytes(id2), [7]);
    });

    test(
      'a remote note keeps lastOpenedAt (TakeRemote and WriteMerged)',
      () async {
        final n = await store.library.createNote(title: 'n');
        await store.library.markOpened(n.id);
        final opened = (await store.library.getNote(n.id))!.lastOpenedAt;
        expect(opened, isNotNull);
        await sync().applyRemote([
          upsert(n.copyWith(title: 'r1'), remoteAfter(store)),
        ], policy: (_, _, _) => const TakeRemote());
        var got = (await store.library.getNote(n.id))!;
        expect((got.title, got.lastOpenedAt, got.pageCount), ('r1', opened, 1));
        final v = remoteAfter(store);
        await sync().applyRemote(
          [upsert(n.copyWith(title: 'r2'), v)],
          policy: (_, r, _) =>
              WriteMerged(r.entity, r.versions, fieldsToUpload: const {}),
        );
        got = (await store.library.getNote(n.id))!;
        expect(
          (got.title, got.lastOpenedAt, got.firstPageId),
          ('r2', opened, n.firstPageId),
        );
        final recent = await store.library.watchRecentNotes().first;
        expect(recent.map((x) => x.id), [n.id]);
      },
    );

    test(
      'a new note row: lastOpenedAt null, derived values from its pages',
      () async {
        final v = remoteAfter(store);
        final handed = Note(
          id: 'rn',
          ownerId: kLocalOwnerId,
          title: 'remote',
          sortKey: 'a0',
          createdAt: 1,
          updatedAt: 1,
          version: v,
          pageCount: 99,
          firstPageId: 'nope',
          lastOpenedAt: 1,
        );
        await sync().applyRemote([
          RemoteUpsert(handed, EntityFieldVersions(v)),
          upsert(page('p2', 'rn').copyWith(sortKey: 'a2'), v),
          upsert(page('p1', 'rn').copyWith(sortKey: 'a1'), v),
        ], policy: newerVersionWinsPolicy);
        final got = (await store.library.getNote('rn'))!;
        expect(got.lastOpenedAt, isNull);
        expect(got.pageCount, 2);
        expect(got.firstPageId, 'p1');
      },
    );

    test(
      'contentRevision: existing page + 1 once per call, new page row 0',
      () async {
        final v = remoteAfter(store);
        await sync().applyRemote([
          upsert(note('n'), v),
          RemoteUpsert(
            page('p', 'n', contentRevision: 7).copyWith(version: v),
            EntityFieldVersions(v),
          ),
        ], policy: newerVersionWinsPolicy);
        Future<int> rev() async =>
            ((await read(EntityKind.page, 'p'))!.entity as Page)
                .contentRevision;
        expect(await rev(), 0);
        final w = remoteAfter(store);
        await sync().applyRemote([
          upsert(stroke('s1', 'p'), w),
          upsert(stroke('s2', 'p'), w),
        ], policy: newerVersionWinsPolicy);
        expect(await rev(), 1);
        await sync().applyRemote([
          upsert(page('p', 'n').copyWith(sortKey: 'b0'), remoteAfter(store)),
          upsert(stroke('s3', 'p'), remoteAfter(store)),
        ], policy: newerVersionWinsPolicy);
        expect(await rev(), 2);
        // KeepLocal writes nothing.
        await sync().applyRemote([
          upsert(stroke('s1', 'p'), remoteAfter(store)),
        ], policy: (_, _, _) => const KeepLocal());
        expect(await rev(), 2);
      },
    );
  });

  group('pendingLocalFields (CORE-2-9, CORE-3-3)', () {
    Future<Note> purgedLocally() async {
      final n = await store.library.createNote(title: 'gone');
      await store.library.trashItems([NoteRef(n.id)]);
      await store.trash.purge([NoteRef(n.id)]);
      final e = (await entryOf(EntityKind.note, n.id))!;
      expect(e.op, OutboxOp.purge);
      return n;
    }

    test('null without entry, changedFields of an upsert entry', () async {
      final n = await store.library.createNote(title: 'n');
      await store.library.setFavorite([n.id], true);
      await sync().acknowledge([
        for (final e in await sync().pendingChanges()) e.ack,
      ]);
      final policy = RecordingPolicy((_, _, _) => const KeepLocal());
      await sync().applyRemote([
        upsert(n, remoteAfter(store)),
      ], policy: policy.call);
      await store.library.renameNote(n.id, 'x');
      await sync().applyRemote([
        upsert(n, remoteAfter(store)),
      ], policy: policy.call);
      expect(policy.calls[0].pending, isNull);
      expect(policy.calls[1].pending, {'title'});
    });

    test(
      'a pending purge: local null, pending {*}; KeepLocal keeps it',
      () async {
        final n = await purgedLocally();
        final before = (await entryOf(EntityKind.note, n.id))!;
        final policy = RecordingPolicy((_, _, _) => const KeepLocal());
        await sync().applyRemote([
          upsert(n, remoteAfter(store)),
        ], policy: policy.call);
        expect(policy.calls.single.local, isNull);
        expect(policy.calls.single.pending, {kAllFields});
        expect(await store.library.getNote(n.id), isNull);
        final after = (await entryOf(EntityKind.note, n.id))!;
        expect(
          (after.seq, after.rev, after.op),
          (before.seq, before.rev, OutboxOp.purge),
        );
      },
    );

    test(
      'a pending purge + TakeRemote(dropPendingLocal: false) → row, no entry',
      () async {
        final n = await purgedLocally();
        await sync().applyRemote([
          upsert(n, remoteAfter(store)),
        ], policy: (_, _, _) => const TakeRemote(dropPendingLocal: false));
        expect(await read(EntityKind.note, n.id), isNotNull);
        expect(await entryOf(EntityKind.note, n.id), isNull);
      },
    );

    test(
      'a pending purge + WriteMerged({title}) → upsert entry, seq kept',
      () async {
        final n = await purgedLocally();
        final before = (await entryOf(EntityKind.note, n.id))!;
        final v = remoteAfter(store);
        await sync().applyRemote(
          [upsert(n, v)],
          policy: (_, r, _) => WriteMerged(
            r.entity,
            r.versions,
            fieldsToUpload: const {'title'},
          ),
        );
        expect(await read(EntityKind.note, n.id), isNotNull);
        final after = (await entryOf(EntityKind.note, n.id))!;
        expect(after.op, OutboxOp.upsert);
        expect(after.changedFields, {'title'});
        expect(after.seq, before.seq);
        expect(after.rev, before.rev + 1);
      },
    );

    test('a pending purge + WriteMerged({}) → no entry', () async {
      final n = await purgedLocally();
      await sync().applyRemote(
        [upsert(n, remoteAfter(store))],
        policy: (_, r, _) =>
            WriteMerged(r.entity, r.versions, fieldsToUpload: const {}),
      );
      expect(await read(EntityKind.note, n.id), isNotNull);
      expect(await entryOf(EntityKind.note, n.id), isNull);
    });
  });

  group('origin (CORE-2-8)', () {
    test(
      'reassignOwner → remote, duplicateNoteForRecovery → local with * entries',
      () async {
        final n = await store.library.createNote(title: 'n');
        await sync().acknowledge([
          for (final e in await sync().pendingChanges()) e.ack,
        ]);
        batches.clear();
        await sync().reassignOwner(from: kLocalOwnerId, to: 'uid-1');
        await pumpEventQueue();
        expect(batches.single.origin, ChangeOrigin.remote);
        expect(await outboxCount(), 0);
        batches.clear();
        final copy = (await sync().duplicateNoteForRecovery(
          n.id,
          titleSuffix: ' (copy)',
        ))!;
        await pumpEventQueue();
        expect(batches.single.origin, ChangeOrigin.local);
        final entries = await sync().pendingChanges();
        expect(entries.map((e) => e.changedFields), everyElement({kAllFields}));
        expect(entries.map((e) => e.entityId), contains(copy));
      },
    );
  });

  group('sessions', () {
    test(
      'N-7 through applyRemote: remote content change, history untouched',
      () async {
        final n = await store.library.createNote(title: 'n');
        final session = await store.openSession(n.id);
        final pageId = session.pages.first.id;
        await session.openPage(pageId);
        await session
            .execute(
              AddStrokes(
                pageId: pageId,
                strokes: [
                  StrokeFixtures.synthetic(pageId: pageId, ids: store.ids),
                ],
              ),
            )
            .persisted;
        final depth = session.history.undoDepth;
        final changes = <PageContentChange>[];
        final s = session.pageChanges(pageId).listen(changes.add);
        await sync().applyRemote([
          upsert(stroke('remote-s', pageId), remoteAfter(store)),
        ], policy: newerVersionWinsPolicy);
        await pumpEventQueue();
        expect(changes.last.origin, ChangeOrigin.remote);
        expect(session.pageIfLoaded(pageId)!.strokeById('remote-s'), isNotNull);
        expect(session.history.undoDepth, depth);
        await s.cancel();
        await session.close();
      },
    );

    test('a RemotePurge of an open note makes its session read-only', () async {
      final n = await store.library.createNote(title: 'n');
      final session = await store.openSession(n.id);
      await sync().applyRemote([
        RemotePurge(EntityKind.note, n.id),
      ], policy: newerVersionWinsPolicy);
      expect(session.isReadOnly, isTrue);
      await session.close();
    });
  });

  test('write-Future rule: pending while a failed commit is retried', () async {
    await store.close(); // one database at a time (drift debug warning)
    fakeAsync((async) {
      late DriftNoteStore s;
      openStore().then((x) => s = x);
      async.flushMicrotasks();
      s.queue.failNextCommits(1);
      RemoteApplyReport? report;
      s.sync
          .applyRemote([
            upsert(
              folder('f'),
              remoteAt(DateTime.now().millisecondsSinceEpoch),
            ),
          ], policy: newerVersionWinsPolicy)
          .then((r) => report = r);
      async.flushMicrotasks();
      expect(report, isNull);
      async.elapse(const Duration(milliseconds: 100));
      expect(report?.taken, 1);
      s.close();
      async.flushMicrotasks();
    });
  });
}
