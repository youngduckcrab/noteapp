// T16 (integration stage, contract 7.7 step 5 v1.2 — C12-05 "SyncStore 계약 스위트 C-01~C-25
// (CoreSyncLocalStore(openTestNoteStore))"): the shared suite of
// test/contract/sync_store_contract.dart against real CORE through CoreSyncLocalStore, with
// the real-CORE-only checks (5.1.4): C-21 reopening the same file (realCore: true), (2nd
// round, 07-sync 6.6) C-26..C-31 of the shared suite and C-30's device-local recording drafts
// and search units here, and C-15's
// open session history (remote and repair writes stay out of undo; the session sees them as
// remote changes), and S-20 (5.1.2, contract 7.2.9 / 7.2.10 / 7.2.11 v1.3 — C13-04): while a
// commit fails and CORE's write queue retries it, the SyncStore / AssetStore writes SYNC
// makes stay pending — no value, no error — and none of them shows; once it commits, all
// of them do. The commit failure comes from moving the database file away
// (CoreTestStore.failCommits — openTestNoteStore takes no fault hook).
@Tags(['integration'])
@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';

import '../contract/sync_store_contract.dart';
import 'support/core_store_driver.dart';
import 'support/real_time.dart';

void main() {
  syncStoreContract(
    'CoreSyncLocalStore(openTestNoteStore)',
    CoreStoreDriver.open,
    realCore: true,
  );

  group('real CORE only', () {
    late ContractClock clock;
    late CoreStoreDriver d;

    setUp(() async {
      clock = ContractClock(kContractStart);
      d = await CoreStoreDriver.open(
        deviceNodeId: kContractNode,
        clock: clock.clock,
      );
      addTearDown(d.close);
    });

    test('C-30 (real CORE) recording drafts and search units are device-local: '
        'pendingChanges and watchPendingCount do not change', () async {
      final store = d.core.store;
      final n = await d.createNote('a');
      final asset = await d.putAsset(contractBytes(9, 300));
      await d.sync.acknowledge([
        for (final e in await d.sync.pendingChanges(limit: 100000)) e.ack,
      ]);
      final counts = <int>[];
      final sub = d.sync.watchPendingCount().listen(counts.add);
      await pumpEventQueue();
      expect(counts.last, 0);
      await store.recordingDrafts.begin(
        recordingId: store.ids.newId(),
        noteId: n,
        mimeType: 'audio/webm',
        startedAt: clock.millis,
      );
      await store.search.replaceUnits(SearchSource.pdf, '${asset.id}#0', const [
        SearchUnitDraft(body: '시험 범위'),
      ], sourceRev: '${asset.id}:1');
      await pumpEventQueue();
      expect(await d.sync.pendingChanges(limit: 100000), isEmpty);
      expect(counts, everyElement(0));
      await sub.cancel();
    });

    test('C-15 an open session: remote and repair writes are not undo steps; '
        'its own stroke stays the only one', () async {
      final store = d.core.store;
      final n = await d.createNote('a');
      final page = (await d.activePageIds(n)).single;
      final session = await store.openSession(n);
      addTearDown(session.close);
      await session.openPage(page);
      final stroke = StrokeFixtures.synthetic(
        pageId: page,
        ids: store.ids,
        seed: 1,
        createdAt: clock.millis,
      );
      session.execute(AddStrokes(pageId: page, strokes: [stroke]));
      await session.flush();
      expect(session.history.undoDepth, 1);

      clock.advance(const Duration(seconds: 1));
      final row = (await d.sync.readVersioned([EntityRef(EntityKind.note, n)]))
          .single!;
      await d.sync.applyRemote([
        remoteOf(
          row.entity,
          set: {'title': 'remote'},
          versions: EntityFieldVersions(
            Hlc(
              clock.now.add(const Duration(seconds: 1)).millisecondsSinceEpoch,
              0,
              kRemoteNode,
            ),
          ),
        ),
      ], policy: take);
      final after = (await d.sync.readVersioned([
        EntityRef(EntityKind.note, n),
      ])).single!;
      await d.sync.commitRepairs([
        (entity: after.entity, fields: const {'folderId', 'sortKey'}),
      ]);
      await pumpEventQueue();
      expect(session.note.title, 'remote');
      expect(session.history.undoDepth, 1);

      await session.undo();
      await session.flush();
      final content = await store.content.loadPage(page);
      expect(content.strokes, isEmpty);
      expect((await store.library.getNote(n))!.title, 'remote');
    });

    test(
      'S-20 while a commit fails and is retried, the SyncStore and AssetStore '
      'writes stay pending and nothing of them shows; then all commit',
      () async {
        final waits = RealTimeWaits();
        final store = d.core.store;
        StorageWarning? warning() =>
            storageWarningOf(store.storageInfo, store.persistenceStatus);
        Future<VersionedEntity> row(EntityKind kind, String id) async =>
            (await d.sync.readVersioned([EntityRef(kind, id)])).single!;
        Future<bool> folderPending(FolderId f) async =>
            (await d.sync.pendingChanges(limit: 100000))
                .any((e) => e.kind == EntityKind.folder && e.entityId == f);

        final f = await d.createFolder('F');
        final n = await d.createNote('before');
        final n2 = await d.createNote('second');
        final asset = await d.putAsset(contractBytes(20));
        final remoteBytes = contractBytes(21, 2000);
        final remoteAsset = remoteAssetJson(
          remoteBytes,
          ownerId: d.sync.ownerId,
          at: clock.millis,
          storagePath: 'x/y',
        );
        final remoteAssetId = remoteAsset['id']! as String;
        await d.sync.applyRemote([
          remoteJson(
            EntityKind.asset,
            remoteAsset,
            EntityFieldVersions(Hlc(clock.millis + 1000, 0, kRemoteNode)),
          ),
        ], policy: take);
        final folderAck = (await d.sync.pendingChanges(limit: 100000))
            .singleWhere((e) => e.kind == EntityKind.folder && e.entityId == f)
            .ack;
        final note0 = await row(EntityKind.note, n);
        final second0 = await row(EntityKind.note, n2);
        clock.advance(const Duration(seconds: 1));
        final policy = RecordingPolicy(take);
        final path = 'users/user-1/assets/${asset.id}';

        d.core.failCommits();
        final writes = <String, Future<Object?>>{
          'applyRemote': d.sync.applyRemote(
            [
              remoteOf(
                note0.entity,
                set: {'title': 'remote'},
                versions: EntityFieldVersions(
                  Hlc(clock.millis + 1000, 0, kRemoteNode),
                ),
              ),
            ],
            policy: policy.call,
            metaUpdates: {'sync.cursor': 'c1'},
          ),
          'acknowledge': d.sync.acknowledge([folderAck]),
          'writeMeta': d.sync.writeMeta({'sync.s20': 'x'}),
          'commitRepairs': d.sync.commitRepairs([
            (entity: second0.entity, fields: const {'sortKey'}),
          ]),
          'markUploaded': d.assets.markUploaded(asset.id, path),
          'putDownloadedBytes': d.assets.putDownloadedBytes(
            remoteAssetId,
            remoteBytes,
          ),
          'duplicateNoteForRecovery': d.sync.duplicateNoteForRecovery(
            n2,
            titleSuffix: ' (복구)',
          ),
          'reassignOwner': d.sync.reassignOwner(
            from: kLocalOwnerId,
            to: 'user-1',
          ),
        };
        final settled = <String, String>{};
        for (final MapEntry(:key, :value) in writes.entries) {
          unawaited(
            value.then(
              (_) => settled[key] = 'value',
              onError: (Object e) => settled[key] = 'error: $e',
            ),
          );
        }

        // A store that keeps committing ends this wait too (and fails below).
        await waits.until(
          'the store to report writeFailing (3 failed commits)',
          () =>
              warning() == StorageWarning.writeFailing ||
              settled.length == writes.length,
        );
        await pumpEventQueue();
        expect(
          settled,
          isEmpty,
          reason:
              'pending while CORE retries — a value means the fault injection '
              'did not take effect',
        );
        expect(store.persistenceStatus.pendingOps, greaterThan(0));
        expect(
          (await row(EntityKind.note, n)).entity.toJson()['title'],
          'before',
        );
        expect(await d.sync.readMeta('sync.cursor'), isNull);
        expect(await d.sync.readMeta('sync.s20'), isNull);
        expect(await folderPending(f), isTrue);
        expect((await row(EntityKind.note, n2)).versions, second0.versions);
        expect((await d.assets.getAsset(asset.id))!.storagePath, isNull);
        expect(d.sync.ownerId, kLocalOwnerId);

        d.core.healCommits();
        await waits.until(
          'every write to complete',
          () => settled.length == writes.length,
        );
        expect(settled, {for (final name in writes.keys) name: 'value'});
        expect(warning(), isNull);
        expect(store.persistenceStatus.consecutiveFailures, 0);

        expect(
          (await row(EntityKind.note, n)).entity.toJson()['title'],
          'remote',
        );
        expect(policy.calls, isNotEmpty);
        for (final call in policy.calls) {
          expect(
            call.local!.entity.toJson()['title'],
            'before',
            reason: 'a retried transaction sees the rolled-back row',
          );
        }
        expect(await d.sync.readMeta('sync.cursor'), 'c1');
        expect(await d.sync.readMeta('sync.s20'), 'x');
        expect(await folderPending(f), isFalse);
        expect(
          (await row(EntityKind.note, n2)).versions.of('sortKey') >
              second0.versions.max,
          isTrue,
        );
        expect((await d.assets.getAsset(asset.id))!.storagePath, path);
        expect(await d.assets.hasBytes(remoteAssetId), isTrue);
        final copy = (await writes['duplicateNoteForRecovery'])! as NoteId;
        expect(
          (await row(EntityKind.note, copy)).entity.toJson()['title'],
          endsWith(' (복구)'),
        );
        expect(d.sync.ownerId, 'user-1');
        expect(
          (await row(EntityKind.note, n)).entity.toJson()['ownerId'],
          'user-1',
        );
      },
      timeout: kIntegrationTimeout,
    );
  });
}
