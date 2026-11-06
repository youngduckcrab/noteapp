// DownloadPipeline (6.6.1–6.6.3, 6.7.4 purged view and narrow gap) on the fake server and fake
// local stores, all in virtual time.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/src/codec/chunk_codec.dart';
import 'package:sync_engine/src/codec/chunk_id.dart';
import 'package:sync_engine/src/engine/download_pipeline.dart';
import 'package:sync_engine/src/engine/meta_keys.dart';
import 'package:sync_engine/src/engine/serial_executor.dart';
import 'package:sync_engine/src/engine/upload_pipeline.dart';
import 'package:sync_engine/src/merge/merge_recorder.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import '../support/download_rig.dart';
import '../support/local_writes.dart';
import '../support/raw_records.dart';

EntityRef note(String id) => EntityRef(EntityKind.note, id);
EntityRef page(String id) => EntityRef(EntityKind.page, id);
EntityRef stroke(String id) => EntityRef(EntityKind.stroke, id);

List<List<String>> ids(List<List<EntityRef>> calls) => [
  for (final c in calls) [for (final r in c) r.id],
];

List<bool> carriesCursor(List<Map<String, String>> metas) => [
  for (final m in metas) m.containsKey('sync.cursor'),
];

void main() {
  group('pages and cursor', () {
    test('first sync reads page by page from the beginning and stores the '
        'cursor with each page', () {
      withDownloadRig((r) {
        for (var i = 0; i < 5; i++) {
          r.b.localWrite([noteWrite('n$i')]);
          r.pushB();
          r.async.elapse(const Duration(seconds: 1));
        }
        r.connect();
        expect(r.pipeline.cursor, isNull);
        final result = r.catchUp();
        expect(result.pages, 3);
        expect(result.chunks, 5);
        expect(result.applied, 5);
        for (var i = 0; i < 5; i++) {
          r.expectSameRow(EntityKind.note, 'n$i');
        }
        final chunks = r.serverChunks();
        expect(r.pipeline.cursor, chunks.last.serverTime);
        expect(r.a.meta['sync.cursor'], '${chunks.last.serverTime}');
        expect(r.sync.applyMetaUpdates.map((m) => m['sync.cursor']), [
          '${chunks[1].serverTime}',
          '${chunks[3].serverTime}',
          '${chunks[4].serverTime}',
        ]);
        expect(r.pipeline.scopeStats.countOf('lib'), 5);
      }, config: const SyncConfig(fetchPageSize: 2));
    });

    test('catching up re-reads from cursor − 5 min: a chunk that became '
        'visible late is applied, the rest is skipped by the LRU (S13)', () {
      withDownloadRig((r) {
        r.b.localWrite([noteWrite('early')]);
        r.server.delayVisibilityOfNextCommit(const Duration(minutes: 2));
        r.pushB();
        r.async.elapse(const Duration(seconds: 1));
        r.b.localWrite([noteWrite('later')]);
        r.pushB();
        r.connect();
        final first = r.catchUp();
        expect(first.chunks, 1);
        expect(r.hasRow(EntityKind.note, 'early'), isFalse);
        expect(r.hasRow(EntityKind.note, 'later'), isTrue);
        final cursor = r.pipeline.cursor!;
        final early = r.serverChunks().first;
        expect(early.serverTime < cursor, isTrue);

        r.async.elapse(const Duration(minutes: 3));
        final second = r.catchUp();
        expect(second.chunks, 1);
        expect(second.duplicates, 1);
        r.expectSameRow(EntityKind.note, 'early');
        expect(r.pipeline.cursor, cursor, reason: 'the cursor keeps the max');
      });
    });

    test('a store failure mid-batch stops it without meta; receiving the '
        'page again is idempotent', () {
      withDownloadRig((r) {
        r.b.localWrite([for (var i = 0; i < 5; i++) noteWrite('n$i')]);
        r.pushB();
        r.connect();
        r.sync.failApplyAt = 2;
        final failed = r.run(r.pipeline.catchUp());
        expect(failed.error, same(r.sync.failApplyError));
        expect(failed.applied, 2);
        expect(r.pipeline.cursor, isNull);
        expect(r.a.meta.containsKey('sync.cursor'), isFalse);
        expect(r.a.meta.containsKey('sync.scopeStats'), isFalse);
        expect(r.hasRow(EntityKind.note, 'n1'), isTrue);
        expect(r.hasRow(EntityKind.note, 'n2'), isFalse);
        expect(r.pipeline.wasApplied(r.serverChunks().single.id), isFalse);

        final retry = r.catchUp();
        expect(retry.issues, isEmpty);
        for (var i = 0; i < 5; i++) {
          r.expectSameRow(EntityKind.note, 'n$i');
        }
        expect(r.pipeline.cursor, r.serverChunks().single.serverTime);
        expect(r.pipeline.scopeStats.countOf('lib'), 1);
      }, config: const SyncConfig(maxRecordsPerApply: 2));
    });
  });

  group('chunk filtering', () {
    test('own delta chunks are skipped, own snapshot chunks are applied '
        '(SYNC-3-2 ①)', () {
      withDownloadRig((r) {
        r.a.localWrite([noteWrite('mine')]);
        expect(r.pushA().succeeded, isTrue);
        r.connect();
        r.catchUp();
        final own = r.serverChunks().single;
        expect(r.sync.applyRefs, isEmpty, reason: 'not decoded, not applied');
        expect(r.ownChunks.map((c) => c.id), [own.id]);
        expect(r.pipeline.cursor, own.serverTime);
        expect(r.pipeline.scopeStats.countOf('lib'), 1);

        // A compaction snapshot by A: one record A has, one A never received.
        r.b.localWrite([noteWrite('other')]);
        final mine = DownloadRig.recordOf(r.a, EntityKind.note, 'mine');
        final other = DownloadRig.recordOf(r.b, EntityKind.note, 'other');
        final before = DownloadRig.canonicalOf(r.a.rows[mine.ref]);
        r.async.elapse(const Duration(seconds: 1));
        final snapshot = r.commit(
          [mine, other],
          author: nodeA,
          kind: ChunkKind.snapshot,
        );
        final result = r.catchUp();
        expect(result.applied, 2);
        expect(r.groups.single, {
          mine.ref: MergeOutcomeKind.kept,
          other.ref: MergeOutcomeKind.created,
        });
        expect(DownloadRig.canonicalOf(r.a.rows[mine.ref]), before);
        r.expectSameRow(EntityKind.note, 'other');
        expect(r.a.outbox, isEmpty, reason: 'no write for the kept record');
        expect(r.ownChunks.last.id, snapshot.id);
        expect(r.pipeline.scopeStats.countOf('lib'), 1, reason: 'n not added');
        expect(r.pipeline.cursor, snapshot.serverTime);
      });
    });

    test('chunks applied in this session are skipped (LRU), also twice in '
        'one batch; the LRU forgets the least recent', () {
      withDownloadRig((r) {
        for (var i = 0; i < 3; i++) {
          r.b.localWrite([noteWrite('n$i')]);
          r.pushB();
        }
        r.connect();
        final chunks = r.serverChunks();
        final first = r.apply([chunks[0], chunks[0]]);
        expect(first.chunks, 1);
        expect(first.duplicates, 1);
        expect(r.sync.applyRefs, hasLength(1));
        final again = r.apply([chunks[0]]);
        expect((again.chunks, again.duplicates), (0, 1));
        expect(r.sync.applyRefs, hasLength(1));

        r.apply([chunks[1], chunks[2]]);
        expect(r.pipeline.wasApplied(chunks[0].id), isFalse);
        final forgotten = r.apply([chunks[0]]);
        expect(forgotten.chunks, 1, reason: 'evicted: applied again');
        expect(r.groups.last, {note('n0'): MergeOutcomeKind.kept});
      }, config: const SyncConfig(appliedChunkMemory: 2));
    });

    test('an applied chunk committed again (lost ack) skips the apply but the '
        'cursor follows its newer serverTime', () {
      withDownloadRig((r) {
        r.b.localWrite([noteWrite('n0')]);
        r.pushB();
        r.connect();
        final c = r.serverChunks().single;
        r.apply([c]);
        expect(r.pipeline.cursor, c.serverTime);
        final applies = r.sync.applyRefs.length;
        final metas = r.sync.writeMetaCalls.length;
        final again = RemoteChunk(
          id: c.id,
          scope: c.scope,
          authorNodeId: c.authorNodeId,
          recordCount: c.recordCount,
          format: c.format,
          kind: c.kind,
          maxHlc: c.maxHlc,
          payload: c.payload,
          serverTime: ServerCursor(c.serverTime.micros + 5000000),
        );
        final result = r.apply([again]);
        expect((result.chunks, result.duplicates), (0, 1));
        expect(r.sync.applyRefs, hasLength(applies));
        expect(r.pipeline.cursor, again.serverTime);
        expect(r.sync.writeMetaCalls, hasLength(metas + 1));
        expect(
          r.sync.writeMetaCalls.last['sync.cursor'],
          '${again.serverTime}',
        );
        // An older copy does not move it back.
        r.apply([c]);
        expect(r.pipeline.cursor, again.serverTime);
      });
    });

    test('an undecodable chunk is skipped (malformedRemoteData) and the '
        'cursor moves past it', () {
      withDownloadRig((r) {
        final bad = Uint8List.fromList([1, 2, 3]);
        r.server.commitRaw(uid, [
          ChunkWrite(
            id: chunkIdOf(nodeB, bad),
            scope: 'lib',
            authorNodeId: nodeB,
            recordCount: 1,
            format: 1,
            kind: ChunkKind.delta,
            maxHlc: Hlc(start.millisecondsSinceEpoch, 0, nodeB).toString(),
            payload: bad,
          ),
        ]);
        r.async.elapse(const Duration(seconds: 1));
        r.b.localWrite([noteWrite('n1')]);
        r.pushB();
        r.connect();
        final result = r.catchUp();
        expect(result.issues.map((i) => i.code), [
          SyncIssueCode.malformedRemoteData,
        ]);
        r.expectSameRow(EntityKind.note, 'n1');
        expect(r.pipeline.cursor, r.serverChunks().last.serverTime);
      });
    });

    test('(S2-4b) a record of a kind this app does not know is left out: the '
        'known records of its chunk apply, needsAppUpdate names the kind, the '
        'cursor moves on', () {
      withDownloadRig((r) {
        final c = FakeLocalStore(nodeId: nodeC, clock: r.base, ownerId: uid)
          ..localWrite([noteWrite('n2')]);
        final known = DownloadRig.recordOf(c, EntityKind.note, 'n2');
        final hlc = Hlc(start.millisecondsSinceEpoch, 0, nodeC);
        final chunk = r.commitRecordBytes([
          rawUpsertRecord(
            'bookmark',
            {'id': 'b1', 'noteId': 'n2', 'version': hlc.toString()},
            {'b': hlc.toString()},
          ),
          ChunkCodec.encodeRecord(known),
          rawPurgeRecord('bookmark', 'b0', hlc.toString()),
        ], maxHlc: known.versions.max);
        r.connect();
        final result = r.catchUp();
        expect(result.issues.map((i) => (i.code, i.message)), [
          (
            SyncIssueCode.needsAppUpdate,
            '2 record(s) of kind bookmark held until the app is updated',
          ),
        ]);
        expect(r.hasRow(EntityKind.note, 'n2'), isTrue);
        expect(r.pipeline.cursor, chunk.serverTime);
        expect(r.pipeline.knownKinds, EntityKind.values.toSet());
      });
    });

    test('(S2-4b) knownKinds: an older app leaves the records of the other '
        'kinds out; the default pipeline applies them', () {
      withDownloadRig((r) {
        r.b.localWrite([
          noteWrite('n1'),
          pageWrite('p1', 'n1'),
          handwritingWrite('p1', 'n1'),
          objectWrite('o1', 'p1'),
        ]);
        r.pushB();
        final old = EntityKind.values.toSet()
          ..removeAll({EntityKind.handwriting, EntityKind.pageObject});
        r.pipeline = r.newPipeline(knownKinds: old);
        r.connect();
        final result = r.catchUp();
        expect(result.issues.map((i) => (i.code, i.message)), [
          (
            SyncIssueCode.needsAppUpdate,
            '2 record(s) of kind handwriting, pageObject held until the app '
                'is updated',
          ),
        ]);
        expect(r.hasRow(EntityKind.page, 'p1'), isTrue);
        expect(r.hasRow(EntityKind.handwriting, 'hw_p1'), isFalse);
        expect(r.hasRow(EntityKind.pageObject, 'o1'), isFalse);
        expect(r.pipeline.knownKinds, old);

        r.pipeline = r.newPipeline();
        r.run(r.sync.writeMeta({MetaKeys.cursor: MetaKeys.cleared}));
        r.connect();
        final again = r.catchUp();
        expect(again.issues, isEmpty);
        expect(r.hasRow(EntityKind.handwriting, 'hw_p1'), isTrue);
        expect(r.hasRow(EntityKind.pageObject, 'o1'), isTrue);
      });
    });

    test('a newer-format chunk is deferred (needsAppUpdate, '
        'sync.deferredFrom) and received again after an app update', () {
      withDownloadRig((r) {
        final c = FakeLocalStore(nodeId: nodeC, clock: r.base, ownerId: uid)
          ..localWrite([noteWrite('n2')]);
        final deferred = r.commit(
          [DownloadRig.recordOf(c, EntityKind.note, 'n2')],
          author: nodeC,
          format: 2,
        );
        r.async.elapse(const Duration(seconds: 1));
        r.b.localWrite([noteWrite('n1')]);
        r.pushB();
        r.connect();
        final result = r.catchUp();
        expect(result.issues.map((i) => i.code), [
          SyncIssueCode.needsAppUpdate,
        ]);
        expect(r.hasRow(EntityKind.note, 'n2'), isFalse);
        expect(r.hasRow(EntityKind.note, 'n1'), isTrue);
        expect(r.a.meta['sync.deferredFrom'], '${deferred.serverTime}');
        expect(r.a.meta['sync.deferredFormat'], '1');
        final cursor = r.pipeline.cursor!;
        expect(cursor > deferred.serverTime, isTrue);

        // Same app again: nothing moves.
        r.pipeline = r.newPipeline();
        r.run(r.pipeline.load());
        expect(r.pipeline.cursor, cursor);
        expect(r.pipeline.deferredFrom, deferred.serverTime);

        // An app that reads format 2: back to the deferred chunk, keys cleared.
        r.pipeline = r.newPipeline(codecFormat: 2);
        r.run(r.pipeline.load());
        expect(r.pipeline.cursor, deferred.serverTime);
        expect(r.pipeline.deferredFrom, isNull);
        expect(r.a.meta['sync.deferredFrom'], '');
        expect(r.a.meta['sync.deferredFormat'], '');
        r.catchUp();
        expect(r.hasRow(EntityKind.note, 'n2'), isTrue);
      });
    });
  });

  group('apply groups', () {
    test('at most 2,000 records per applyRemote; only the last call of the '
        'batch carries the meta', () {
      withDownloadRig((r) {
        r.b.localWrite([
          for (var i = 0; i < 2001; i++)
            noteWrite('n${i.toString().padLeft(4, '0')}'),
        ]);
        r.pushB();
        r.connect();
        final result = r.catchUp();
        expect(result.applied, 2001);
        expect(r.sync.applyRefs.map((c) => c.length), [2000, 1]);
        expect(r.sync.applyMetaUpdates.first, isEmpty);
        expect(r.sync.applyMetaUpdates.last, contains('sync.cursor'));
        expect(r.groups, hasLength(2), reason: 'checks once per group');
      });
    });

    test('groups are also cut by encoded bytes', () {
      withDownloadRig((r) {
        r.b.localWrite([for (var i = 0; i < 3; i++) noteWrite('n$i')]);
        r.pushB();
        r.connect();
        r.catchUp();
        expect(ids(r.sync.applyRefs), [
          ['n0'],
          ['n1'],
          ['n2'],
        ]);
        expect(carriesCursor(r.sync.applyMetaUpdates), [false, false, true]);
      }, config: const SyncConfig(maxBytesPerApply: 1));
    });

    test('while applyRemote does not complete (CORE write retry) nothing '
        'else starts and nothing fails; then it goes on (S-20)', () {
      withDownloadRig((r) {
        r.b.localWrite([noteWrite('n1'), noteWrite('n2')]);
        r.pushB();
        r.a.localWrite([noteWrite('local')]);
        r.connect();
        final executor = SerialExecutor();
        final gate = r.sync.applyGate = Completer<void>();
        ApplyResult? received;
        PushResult? pushed;
        unawaited(
          executor.run(() => r.pipeline.catchUp()).then((v) => received = v),
        );
        unawaited(
          executor.run(() => r.aPush.runOnce()).then((v) => pushed = v),
        );
        r.async.elapse(const Duration(hours: 1));
        expect(received, isNull);
        expect(pushed, isNull, reason: 'the push waits behind the apply');
        expect(r.sync.applyRefs, hasLength(1), reason: 'no next group');
        expect(r.serverChunks().where((c) => c.authorNodeId == nodeA), isEmpty);
        expect(r.a.meta['sync.cursor'], isNull);

        gate.complete();
        r.sync.applyGate = null;
        r.async.elapse(const Duration(seconds: 5));
        expect(received!.succeeded, isTrue);
        expect(received!.applied, 2);
        expect(r.a.meta['sync.cursor'], isNotNull);
        expect(pushed!.succeeded, isTrue);
        expect(pushed!.recordsSent, 1);
      }, config: const SyncConfig(maxRecordsPerApply: 1));
    });
  });

  group('rejections (bisect)', () {
    void writeFour(DownloadRig r) {
      r.b.localWrite([for (var i = 0; i < 4; i++) noteWrite('n$i')]);
      r.pushB();
      r.connect();
    }

    test('a record CORE rejects is found by bisecting and skipped; the meta '
        'rides on the last half', () {
      withDownloadRig((r) {
        writeFour(r);
        r.sync.rejectRefs.add(note('n1'));
        final result = r.catchUp();
        expect(result.rejected, 1);
        expect(result.issues.single.code, SyncIssueCode.malformedRemoteData);
        expect(result.issues.single.ref, note('n1'));
        expect(ids(r.sync.applyRefs), [
          ['n0', 'n1', 'n2', 'n3'],
          ['n0', 'n1'],
          ['n0'],
          ['n1'],
          ['n2', 'n3'],
        ]);
        expect(carriesCursor(r.sync.applyMetaUpdates), [
          true,
          false,
          false,
          false,
          true,
        ]);
        expect(r.sync.writeMetaCalls, isEmpty);
        for (final id in ['n0', 'n2', 'n3']) {
          r.expectSameRow(EntityKind.note, id);
        }
        expect(r.hasRow(EntityKind.note, 'n1'), isFalse);
        expect(r.pipeline.cursor, r.serverChunks().single.serverTime);
      });
    });

    test('when the rejected record carries the meta, writeMeta stores it', () {
      withDownloadRig((r) {
        writeFour(r);
        r.sync.rejectRefs.add(note('n3'));
        r.catchUp();
        expect(ids(r.sync.applyRefs).last, ['n3']);
        expect(carriesCursor(r.sync.applyMetaUpdates).last, isTrue);
        expect(r.sync.writeMetaCalls.single, contains('sync.cursor'));
        expect(
          r.a.meta['sync.cursor'],
          '${r.serverChunks().single.serverTime}',
        );
        expect(r.hasRow(EntityKind.note, 'n2'), isTrue);
      });
    });

    test('bisect budget spent (maxBisectSteps: 1): the piece goes record by '
        'record and only the last single call carries the meta (SYNC-3-4)', () {
      withDownloadRig((r) {
        writeFour(r);
        r.sync.rejectRefs.add(note('n2'));
        r.catchUp();
        expect(ids(r.sync.applyRefs), [
          ['n0', 'n1', 'n2', 'n3'],
          ['n0', 'n1'],
          ['n2', 'n3'],
          ['n2'],
          ['n3'],
        ]);
        expect(carriesCursor(r.sync.applyMetaUpdates), [
          true,
          false,
          true,
          false,
          true,
        ]);
        expect(r.sync.writeMetaCalls, isEmpty);
        expect(r.hasRow(EntityKind.note, 'n3'), isTrue);
        expect(r.hasRow(EntityKind.note, 'n2'), isFalse);
      }, config: const SyncConfig(maxBisectSteps: 1));
    });

    test('bisect budget spent and the last record is rejected: one writeMeta '
        'stores the meta, the cursor moves on', () {
      withDownloadRig((r) {
        writeFour(r);
        r.sync.rejectRefs.add(note('n3'));
        r.catchUp();
        expect(ids(r.sync.applyRefs), [
          ['n0', 'n1', 'n2', 'n3'],
          ['n0', 'n1'],
          ['n2', 'n3'],
          ['n2'],
          ['n3'],
        ]);
        expect(carriesCursor(r.sync.applyMetaUpdates), [
          true,
          false,
          true,
          false,
          true,
        ]);
        expect(r.sync.writeMetaCalls, hasLength(1));
        expect(r.sync.writeMetaCalls.single, contains('sync.cursor'));
        expect(r.pipeline.cursor, r.serverChunks().single.serverTime);
        expect(r.hasRow(EntityKind.note, 'n2'), isTrue);
        expect(r.hasRow(EntityKind.note, 'n3'), isFalse);
      }, config: const SyncConfig(maxBisectSteps: 1));
    });

    /// B: note N, page P; A receives, then deletes P. B (not knowing) writes stroke S on P,
    /// then note X. Returns the outcome-group count before A receives S and X.
    int deletedPageThenStroke(DownloadRig r) {
      r.b.localWrite([noteWrite('N'), pageWrite('P', 'N')]);
      r.pushB();
      r.connect();
      r.catchUp();
      DownloadRig.edit(r.a, EntityKind.page, 'P', {'deletedAt': r.wallMillis});
      r.async.elapse(const Duration(seconds: 1));
      r.b.localWrite([strokeWrite('S', 'P')]);
      r.pushB();
      r.async.elapse(const Duration(seconds: 1));
      r.b.localWrite([noteWrite('X')]);
      r.pushB();
      return r.groups.length;
    }

    test('a stroke created by the front half survives the back half failing: '
        'the page comes back once after the group (SYNC-2-3)', () {
      withDownloadRig((r) {
        final before = deletedPageThenStroke(r);
        r.sync.rejectRefs.add(note('X'));
        r.catchUp();
        expect(ids(r.sync.applyRefs).skip(1), [
          ['S', 'X'],
          ['S'],
          ['X'],
        ]);
        expect(r.groups.length - before, 1, reason: 'checks once per group');
        expect(r.groups.last, {stroke('S'): MergeOutcomeKind.created});
        expect(r.restored.map((p) => p.pageId), ['P']);
        final p = r.a.rows[page('P')]!;
        expect((p.entity as Page).deletedAt, isNull);
        expect(r.pushNeeded, 1, reason: 'repairs schedule a push');
      });
    });

    test('policy outcomes of a rolled-back call do not count: no '
        'resurrection from a stroke that was never written', () {
      withDownloadRig((r) {
        final before = deletedPageThenStroke(r);
        r.sync.rejectRefs.add(stroke('S'));
        r.catchUp();
        expect(ids(r.sync.applyRefs).skip(1), [
          ['S', 'X'],
          ['S'],
          ['X'],
        ]);
        expect(r.groups.length - before, 1);
        expect(r.groups.last, {note('X'): MergeOutcomeKind.created});
        expect(r.restored, isEmpty);
        expect((r.a.rows[page('P')]!.entity as Page).deletedAt, isNotNull);
        expect(r.hasRow(EntityKind.stroke, 'S'), isFalse);
      });
    });
  });

  group('permanent deletions (6.7.4)', () {
    /// B: note N with page P and stroke S1, note K; A receives all.
    void shared(DownloadRig r) {
      r.b.localWrite([
        noteWrite('N'),
        pageWrite('P', 'N'),
        strokeWrite('S1', 'P'),
        noteWrite('K'),
      ]);
      r.pushB();
      r.connect();
      r.catchUp();
    }

    bool orphanOf(DownloadRig r, String noteId) => r.a.rows.values.any(
      (row) => switch (row.entity) {
        final Page p => p.noteId == noteId,
        final Stroke s => s.pageId == 'P' || s.pageId == 'P2',
        _ => false,
      },
    );

    test('connect: an unsent local purge in the outbox drops the note\'s '
        'remote upserts and its child records — no orphan rows (SYNC-2-2)', () {
      withDownloadRig((r) {
        shared(r);
        r.a.localPurge(note('N'), group: const []);
        r.pipeline = r.newPipeline();
        r.connect();
        expect(r.purged.local, {note('N')});

        DownloadRig.edit(r.b, EntityKind.note, 'N', {'title': 'renamed'});
        r.b.localWrite([pageWrite('P2', 'N'), strokeWrite('S2', 'P2')]);
        r.pushB();
        final result = r.catchUp();
        // New session (empty LRU): N, P, S1 read again from cursor − 5 min, plus the
        // rename, P2 and S2.
        expect(result.dropped, 6);
        expect(r.hasRow(EntityKind.note, 'N'), isFalse);
        expect(orphanOf(r, 'N'), isFalse);
        expect(r.a.outbox.map((e) => (e.ref, e.op)), [
          (note('N'), OutboxOp.purge),
        ]);

        // The purge goes up and moves into the stored set.
        expect(r.pushA().succeeded, isTrue);
        expect(r.purged.isStored(note('N')), isTrue);
        final sent = ChunkCodec.decode(r.serverChunks().last.payload);
        expect(sent, [isA<PurgeRecord>()]);
      });
    });

    test('a local purge after connecting marks the view stale; it is read '
        'again before the next apply', () {
      withDownloadRig((r) {
        shared(r);
        expect(r.purged.isStale, isFalse);
        r.a.localPurge(note('K'), group: const []);
        r.async.flushMicrotasks();
        expect(r.purged.isStale, isTrue);
        DownloadRig.edit(r.b, EntityKind.note, 'K', {'title': 'renamed'});
        r.pushB();
        final result = r.catchUp();
        expect(result.dropped, 1);
        expect(r.purged.isStale, isFalse);
        expect(r.purged.local, {note('K')});
        expect(r.hasRow(EntityKind.note, 'K'), isFalse);
      });
    });

    test('received purges are stored in sync.purged.* with the batch and '
        'drop the child records of the same batch', () {
      withDownloadRig((r) {
        shared(r);
        r.b.localPurge(note('N'), group: const []);
        r.pushB();
        final result = r.catchUp();
        expect(r.hasRow(EntityKind.note, 'N'), isFalse);
        expect(orphanOf(r, 'N'), isFalse);
        expect(r.purged.isStored(note('N')), isTrue);
        expect(r.guarded.single.map((p) => p.ref), [note('N')]);
        expect(
          r.a.meta.keys.where((k) => k.startsWith('sync.purged.')),
          hasLength(1),
        );
        expect(result.applied, 1);
        r.async.elapse(const Duration(seconds: 1));
        DownloadRig.edit(r.b, EntityKind.note, 'K', {'title': 'x'});
        r.pushB();
        // A late page of N (from a device that did not know) is dropped.
        final c = FakeLocalStore(nodeId: nodeC, clock: r.base, ownerId: uid)
          ..localWrite([pageWrite('P3', 'N')]);
        r.commit(
          [DownloadRig.recordOf(c, EntityKind.page, 'P3')],
          author: nodeC,
          scope: 'N',
        );
        expect(r.catchUp().dropped, 1);
        expect(r.hasRow(EntityKind.page, 'P3'), isFalse);
      });
    });

    test('narrow gap: a local purge during an apply, before its signal, lets '
        'the next groups write orphan rows of N — harmless (SYNC-3-3)', () {
      withDownloadRig((r) {
        shared(r);
        // A deleted page P earlier; the echo of that deletion comes back with a new stroke.
        DownloadRig.edit(r.a, EntityKind.page, 'P', {
          'deletedAt': r.wallMillis,
        });
        final deletedP = DownloadRig.recordOf(r.a, EntityKind.page, 'P');
        r.b.localWrite([strokeWrite('S2', 'P')]);
        final s2 = DownloadRig.recordOf(r.b, EntityKind.stroke, 'S2');
        r.async.elapse(const Duration(seconds: 1));
        final c = FakeLocalStore(nodeId: nodeC, clock: r.base, ownerId: uid)
          ..localWrite([noteWrite('K', title: 'from C')]);
        r.commit([
          DownloadRig.recordOf(c, EntityKind.note, 'K'),
        ], author: nodeC);
        r.async.elapse(const Duration(seconds: 1));
        r.commit([deletedP, s2], author: nodeC, scope: 'N');
        r.run(r.purged.refreshIfStale());

        var purgedDuringApply = false;
        r.sync.afterApply = (_) {
          if (purgedDuringApply) return;
          purgedDuringApply = true;
          r.a.localPurge(note('N'), group: const []);
        };
        final result = r.catchUp();
        expect(purgedDuringApply, isTrue);
        expect(result.applied, 3);
        // (orphans) page P and stroke S2 were written without their note.
        expect(r.hasRow(EntityKind.note, 'N'), isFalse);
        expect(r.hasRow(EntityKind.page, 'P'), isTrue);
        expect(r.hasRow(EntityKind.stroke, 'S2'), isTrue);
        // (b) not in the outbox; N's purge entry stays.
        expect(r.a.outbox.map((e) => (e.ref, e.op)), [
          (note('N'), OutboxOp.purge),
        ]);
        // (d) no resurrection of a page whose note row is gone.
        expect(r.groups.last, {stroke('S2'): MergeOutcomeKind.created});
        expect(r.restored, isEmpty);
        expect((r.a.rows[page('P')]!.entity as Page).deletedAt, isNotNull);

        // The purge is sent as usual.
        expect(r.pushA().succeeded, isTrue);
        final sent = ChunkCodec.decode(r.serverChunks().last.payload).single;
        expect(sent, isA<PurgeRecord>());
        expect(sent.ref, note('N'));

        // (c) the next batch refreshes the view first: N's children are dropped.
        r.async.elapse(const Duration(seconds: 1));
        r.b.localWrite([strokeWrite('S3', 'P')]);
        r.pushB();
        final next = r.catchUp();
        expect(next.dropped, 2, reason: 'S2 and S3 of B, scope N');
        expect(r.hasRow(EntityKind.stroke, 'S3'), isFalse);
      }, config: const SyncConfig(maxRecordsPerApply: 1));
    });
  });
}
