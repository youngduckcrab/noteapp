// DownloadPipeline (6.6.1–6.6.3, 6.7.4 purged view and narrow gap) on the fake server and fake
// local stores, all in virtual time.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/src/codec/chunk_codec.dart';
import 'package:sync_engine/src/codec/chunk_id.dart';
import 'package:sync_engine/src/engine/download_pipeline.dart';
import 'package:sync_engine/src/engine/held_records.dart';
import 'package:sync_engine/src/engine/meta_keys.dart';
import 'package:sync_engine/src/engine/serial_executor.dart';
import 'package:sync_engine/src/engine/upload_pipeline.dart';
import 'package:sync_engine/src/merge/merge_recorder.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import '../support/download_rig.dart';
import '../support/local_writes.dart';
import '../support/raw_records.dart';

/// A bookmark upsert (a kind no app knows) of [id] on note [noteId] at [hlc].
Uint8List bookmark(String id, Hlc hlc, {String noteId = 'n2'}) =>
    rawUpsertRecord(
      'bookmark',
      {'id': id, 'noteId': noteId, 'version': hlc.toString()},
      {'b': hlc.toString()},
    );

/// The sync.heldRecords keys among [meta].
Set<String> heldKeysOf(Map<String, String> meta) => {
  for (final k in MetaKeys.heldRecordKeys)
    if (meta.containsKey(k)) k,
};

int needsAppUpdateCount(ApplyResult r) =>
    r.issues.where((i) => i.code == SyncIssueCode.needsAppUpdate).length;

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

  group('lib-scope pageObject (S2-3 — 07-sync 6.2.4, 6.2.7)', () {
    EntityRef objectRef(String id) => EntityRef(EntityKind.pageObject, id);

    test('a lib-scope page object finds its note through the page record of '
        'the batch, else the local page row; an unknown page keeps it as an '
        'orphan', () {
      withDownloadRig((r) {
        r.b.localWrite([noteWrite('N'), pageWrite('P', 'N')]);
        r.pushB();
        r.connect();
        r.catchUp();
        // Z: an unsent local purge here, with an orphan page row P9 of Z left behind.
        r.a.localPurge(note('Z'), group: const []);
        r.run(
          r.a.sync.applyRemote([
            RemoteUpsert(
              EntityJson.decode(EntityKind.page, {
                ...pageWrite('P9', 'Z').json,
                'createdAt': 1,
                'updatedAt': 1,
                'version': Hlc(1, 0, nodeC).toString(),
              }),
              EntityFieldVersions(Hlc(1, 0, nodeC)),
            ),
          ], policy: (l, remote, p) => const TakeRemote()),
        );
        expect(r.hasRow(EntityKind.page, 'P9'), isTrue);
        r.pipeline = r.newPipeline();
        r.connect();
        expect(r.purged.local, {note('Z')});

        final c = FakeLocalStore(nodeId: nodeC, clock: r.base, ownerId: uid)
          ..localWrite([
            pageWrite('P8', 'Z'),
            objectWrite('O1', 'P8'),
            objectWrite('O2', 'P9', type: 'sticker'),
            strokeWrite('S1', 'P9'),
            objectWrite('O3', 'P', type: 'text'),
            objectWrite('O4', 'P-unknown'),
          ]);
        r.commit([
          DownloadRig.recordOf(c, EntityKind.page, 'P8'),
          DownloadRig.recordOf(c, EntityKind.pageObject, 'O1'),
          DownloadRig.recordOf(c, EntityKind.pageObject, 'O2'),
          DownloadRig.recordOf(c, EntityKind.stroke, 'S1'),
          DownloadRig.recordOf(c, EntityKind.pageObject, 'O3'),
          DownloadRig.recordOf(c, EntityKind.pageObject, 'O4'),
        ], author: nodeC);
        final result = r.catchUp();
        // P8 by its noteId, O1 through P8 in the batch, O2 and S1 through the local row P9.
        expect(result.dropped, 4);
        expect(r.hasRow(EntityKind.page, 'P8'), isFalse);
        expect(r.hasRow(EntityKind.pageObject, 'O1'), isFalse);
        expect(r.hasRow(EntityKind.pageObject, 'O2'), isFalse);
        expect(r.hasRow(EntityKind.stroke, 'S1'), isFalse);
        expect(r.hasRow(EntityKind.pageObject, 'O3'), isTrue);
        expect(r.hasRow(EntityKind.pageObject, 'O4'), isTrue, reason: 'orphan');
        expect(r.a.outbox.map((e) => e.ref), [note('Z')]);
        expect(
          r.a.rows[objectRef('O3')]!.versions,
          DownloadRig.recordOf(c, EntityKind.pageObject, 'O3').versions,
        );
      });
    });

    test('note scope: the page objects and handwriting result of a received '
        'purge are gone, and later ones from an unaware device are dropped; '
        'another note passes', () {
      withDownloadRig((r) {
        r.b.localWrite([
          noteWrite('N'),
          pageWrite('P', 'N'),
          objectWrite('O0', 'P'),
          handwritingWrite('P', 'N'),
          noteWrite('M'),
          pageWrite('Q', 'M'),
        ]);
        r.pushB();
        r.connect();
        r.catchUp();
        expect(r.hasRow(EntityKind.pageObject, 'O0'), isTrue);
        expect(r.hasRow(EntityKind.handwriting, 'hw_P'), isTrue);

        r.async.elapse(const Duration(seconds: 1));
        r.b.localWrite([
          FakeLocalWrite(
            EntityKind.note,
            {
              ...r.b.rows[note('N')]!.entity.toJson(),
              'deletedAt': 5,
              'trashRootId': 'N',
            },
            changedFields: const {'deletedAt', 'trashRootId'},
          ),
        ]);
        r.b.localPurge(note('N'), group: const []);
        r.pushB();
        r.catchUp();
        expect(r.hasRow(EntityKind.pageObject, 'O0'), isFalse);
        expect(r.hasRow(EntityKind.handwriting, 'hw_P'), isFalse);
        expect(r.purged.isStored(note('N')), isTrue);

        r.async.elapse(const Duration(seconds: 1));
        final c = FakeLocalStore(nodeId: nodeC, clock: r.base, ownerId: uid)
          ..localWrite([
            objectWrite('O5', 'P', type: 'math'),
            handwritingWrite('P', 'N', text: '늦게 온 결과'),
            handwritingWrite('Q', 'M'),
            objectWrite('O6', 'Q'),
          ]);
        r.commit(
          [
            DownloadRig.recordOf(c, EntityKind.pageObject, 'O5'),
            DownloadRig.recordOf(c, EntityKind.handwriting, 'hw_P'),
          ],
          author: nodeC,
          scope: 'N',
        );
        r.commit(
          [
            DownloadRig.recordOf(c, EntityKind.handwriting, 'hw_Q'),
            DownloadRig.recordOf(c, EntityKind.pageObject, 'O6'),
          ],
          author: nodeC,
          scope: 'M',
        );
        final result = r.catchUp();
        expect(result.dropped, 2);
        expect(r.hasRow(EntityKind.pageObject, 'O5'), isFalse);
        expect(r.hasRow(EntityKind.handwriting, 'hw_P'), isFalse);
        expect(r.hasRow(EntityKind.handwriting, 'hw_Q'), isTrue);
        expect(r.hasRow(EntityKind.pageObject, 'O6'), isTrue);
      });
    });
  });
  group('S-13 받기 — unknown kinds held in sync.heldRecords (S2-7a, 07-sync '
      '6.3.3)', () {
    /// Note n2 from C plus a bookmark upsert and purge, in one chunk.
    RemoteChunk mixedChunk(DownloadRig r) {
      final c = FakeLocalStore(nodeId: nodeC, clock: r.base, ownerId: uid)
        ..localWrite([noteWrite('n2')]);
      final known = DownloadRig.recordOf(c, EntityKind.note, 'n2');
      final hlc = Hlc(start.millisecondsSinceEpoch, 0, nodeC);
      return r.commitRecordBytes([
        bookmark('b1', hlc),
        ChunkCodec.encodeRecord(known),
        rawPurgeRecord('bookmark', 'b0', hlc.toString()),
      ], maxHlc: known.versions.max);
    }

    test('the known record applies, the cursor moves, the unknown records are '
        'held (the chunk\'s all), one needsAppUpdate; the sync.heldRecords keys '
        'ride on the last applyRemote call with the cursor', () {
      withDownloadRig((r) {
        final chunk = mixedChunk(r);
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
        expect(r.pipeline.heldRecordCount, 2);
        expect(r.pipeline.heldRecordsMarked, isFalse);
        expect(r.pipeline.heldRecords.kinds, {'bookmark'});
        final last = r.sync.applyMetaUpdates.last;
        expect(last, contains(MetaKeys.cursor));
        expect(heldKeysOf(last), {
          MetaKeys.heldRecords,
          MetaKeys.heldRecordParts.first,
        });
        expect(r.sync.writeMetaCalls.expand(heldKeysOf), isEmpty);
        expect({
          for (final k in MetaKeys.heldRecordKeys) k: r.a.meta[k] ?? '',
        }, r.pipeline.heldRecords.encode());
      });
    });

    test('a chunk of unknown records only: nothing to apply, the keys go with '
        'the cursor in one writeMeta', () {
      withDownloadRig((r) {
        final hlc = Hlc(start.millisecondsSinceEpoch, 0, nodeC);
        final chunk = r.commitRecordBytes([bookmark('b1', hlc)], maxHlc: hlc);
        r.connect();
        final result = r.catchUp();
        expect(needsAppUpdateCount(result), 1);
        expect(r.sync.applyRefs, isEmpty);
        final write = r.sync.writeMetaCalls.single;
        expect(write[MetaKeys.cursor], '${chunk.serverTime}');
        expect(heldKeysOf(write), hasLength(2));
        expect(r.pipeline.heldRecordCount, 1);
      });
    });

    test('received again (overlap, a later session) → no duplicate, no new '
        'issue, no key written again', () {
      withDownloadRig((r) {
        mixedChunk(r);
        r.connect();
        r.catchUp();
        final stored = r.pipeline.heldRecords.encode();
        // Same session: the catch-up overlap re-reads the chunk (LRU skip).
        expect(r.catchUp().issues, isEmpty);
        // A later session from the beginning: decoded again, deduplicated.
        r.run(r.sync.writeMeta({MetaKeys.cursor: MetaKeys.cleared}));
        r.pipeline = r.newPipeline();
        r.connect();
        expect(r.pipeline.heldRecordCount, 2, reason: 'loaded from the meta');
        final calls = r.sync.applyMetaUpdates.length;
        final again = r.catchUp();
        expect(again.chunks, 1);
        expect(again.issues, isEmpty);
        expect(r.pipeline.heldRecords.encode(), stored);
        expect(r.sync.applyMetaUpdates.skip(calls).expand(heldKeysOf), isEmpty);
      });
    });

    test(
      'K1 + K2: the chunk is held for its future known record; the release '
      're-reads it — the known record applies, no new issue, one copy held',
      () {
        withDownloadRig((r) {
          const day = Duration(hours: 24);
          final c = FakeLocalStore(
            nodeId: nodeC,
            clock: Clock(() => r.base.now().add(const Duration(hours: 48))),
            ownerId: uid,
          )..localWrite([noteWrite('future')]);
          final future = DownloadRig.recordOf(c, EntityKind.note, 'future');
          final hlc = Hlc(start.millisecondsSinceEpoch, 0, nodeC);
          final chunk = r.commitRecordBytes([
            bookmark('b1', hlc),
            ChunkCodec.encodeRecord(future),
          ], maxHlc: future.versions.max);
          r.connect();
          final first = r.catchUp();
          expect(first.held, 1);
          expect(needsAppUpdateCount(first), 1);
          expect(r.pipeline.held.entries.keys, [chunk.id]);
          expect(r.pipeline.heldRecordCount, 1);

          final releaseAt = future.versions.max.millis - day.inMilliseconds;
          r.async.elapse(day + const Duration(hours: 1));
          r.serverNowOverride = releaseAt;
          final released = r.release();
          expect(released.chunks, 1);
          expect(released.applied, 1);
          expect(needsAppUpdateCount(released), 0);
          expect(r.hasRow(EntityKind.note, 'future'), isTrue);
          expect(r.pipeline.held.isEmpty, isTrue);
          expect(r.pipeline.heldRecordCount, 1);
        });
      },
    );

    test('a store failure on the last call: neither the memory nor the meta '
        'takes the held records; receiving again holds them and reports once '
        'more', () {
      withDownloadRig((r) {
        mixedChunk(r);
        r.connect();
        r.sync.nextApplyError = Exception('disk full');
        final failed = r.run(r.pipeline.catchUp());
        expect(failed.error, isNotNull);
        expect(r.pipeline.heldRecordCount, 0);
        expect(r.a.meta[MetaKeys.heldRecords] ?? '', '');
        final retry = r.catchUp();
        expect(needsAppUpdateCount(retry), 1);
        expect(r.pipeline.heldRecordCount, 2);
        expect(r.a.meta[MetaKeys.heldRecords], isNotEmpty);
      });
    });

    test(
      'over the caps: none of the chunk is stored, the mark takes it; a later '
      'chunk of the same kind the mark covers is not stored and reports '
      'nothing new',
      () {
        withDownloadRig((r) {
          r.pipeline = r.newPipeline(
            heldRecordsMaxPartBytes: 300,
            heldRecordsMaxTotalBytes: 400,
          );
          final hlc = Hlc(start.millisecondsSinceEpoch, 0, nodeC);
          final big = r.commitRecordBytes([
            bookmark('b1', hlc),
            bookmark('b2', hlc),
          ], maxHlc: hlc);
          r.connect();
          final first = r.catchUp();
          expect(first.issues.map((i) => i.message), [
            '2 record(s) of kind bookmark held until the app is updated',
          ]);
          expect(r.pipeline.heldRecordCount, 0);
          final mark = r.pipeline.heldRecords.mark!;
          expect(mark.from, big.serverTime);
          expect(mark.kinds, {'bookmark'});
          expect(r.pipeline.heldRecordsMarked, isTrue);

          r.async.elapse(const Duration(seconds: 1));
          r.commitRecordBytes([bookmark('b3', hlc)], maxHlc: hlc);
          final later = r.catchUp();
          expect(later.chunks, 1);
          expect(later.issues, isEmpty);
          expect(r.pipeline.heldRecordCount, 0);
        });
      },
    );

    test('load: the stored value is read back; a corrupt value becomes an '
        'all-kinds mark and is written back at once (warning)', () {
      withDownloadRig((r) {
        mixedChunk(r);
        r.connect();
        r.catchUp();
        r.pipeline = r.newPipeline();
        r.connect();
        expect(r.pipeline.heldRecordCount, 2);
        expect(r.warnings, isEmpty);

        r.run(r.sync.writeMeta({MetaKeys.heldRecordParts.first: '{"p":1,'}));
        r.pipeline = r.newPipeline();
        final writes = r.sync.writeMetaCalls.length;
        r.connect();
        expect(r.pipeline.heldRecordCount, 0);
        expect(r.pipeline.heldRecords.mark?.kinds, {'*'});
        expect(r.warnings.single, contains('corrupt'));
        final converted = r.sync.writeMetaCalls[writes];
        expect(converted.keys.toSet(), MetaKeys.heldRecordKeys.toSet());
        expect(converted, r.pipeline.heldRecords.encode());

        r.pipeline = r.newPipeline();
        r.connect();
        expect(r.warnings, hasLength(1), reason: 'the converted value is fine');
        expect(r.pipeline.heldRecordsMarked, isTrue);
      });
    });

    test(
      'an older app holds the new kinds of the other device (real kinds)',
      () {
        withDownloadRig((r) {
          r.b.localWrite([
            noteWrite('n1'),
            pageWrite('p1', 'n1'),
            strokeWrite('s1', 'p1'),
            handwritingWrite('p1', 'n1', strokeIds: const ['s1']),
          ]);
          r.pushB();
          final old = EntityKind.values.toSet()..remove(EntityKind.handwriting);
          r.pipeline = r.newPipeline(knownKinds: old);
          r.connect();
          final result = r.catchUp();
          expect(needsAppUpdateCount(result), 1);
          expect(r.hasRow(EntityKind.stroke, 's1'), isTrue);
          expect(r.hasRow(EntityKind.handwriting, 'hw_p1'), isFalse);
          expect(r.pipeline.heldRecords.kinds, {'handwriting'});
          expect(r.pipeline.heldRecordCount, 1);
        });
      },
    );
  });
  group('S-13 다시 적용 — held records re-applied after an app update (S2-7b, '
      '07-sync 6.3.4, 6.3.5)', () {
    final old = EntityKind.values.toSet()..remove(EntityKind.handwriting);
    final oldNames = {for (final k in old) k.name};
    EntityRef hw(String pageId) =>
        EntityRef(EntityKind.handwriting, HandwritingText.idFor(pageId));

    /// B writes note n1, page p1, stroke s1 and the handwriting result of p1 and pushes
    /// (one chunk); A, an older app, receives it: the stroke applies, the handwriting
    /// result is held. Returns the chunk.
    RemoteChunk oldAppReceives(DownloadRig r) {
      r.b.localWrite([
        noteWrite('n1'),
        pageWrite('p1', 'n1'),
        strokeWrite('s1', 'p1'),
        handwritingWrite('p1', 'n1', strokeIds: const ['s1']),
      ]);
      r.pushB();
      r.pipeline = r.newPipeline(knownKinds: old);
      r.connect();
      final result = r.catchUp();
      expect(needsAppUpdateCount(result), 1);
      expect(r.hasRow(EntityKind.stroke, 's1'), isTrue);
      expect(r.a.rows.containsKey(hw('p1')), isFalse);
      expect(r.pipeline.heldRecords.kinds, contains('handwriting'));
      return r.serverChunks().singleWhere(
        (c) =>
            ChunkCodec.decodeTolerant(c.payload).records
                .any((x) => x.ref == hw('p1')),
      );
    }

    /// The app update: a new pipeline that knows every kind, loaded.
    void update(DownloadRig r, {int? maxTotalBytes}) {
      r.pipeline = r.newPipeline(
        heldRecordsMaxTotalBytes:
            maxTotalBytes ?? HeldRecords.defaultMaxTotalBytes,
      );
      r.connect();
    }

    ApplyResult reapply(DownloadRig r) {
      final result = r.run(r.pipeline.reapplyHeldRecords());
      expect(result.succeeded, isTrue, reason: '$result');
      return result;
    }

    test('① ⑧ the held record applies as a synthetic chunk: not put in the '
        'LRU, cursor and scope statistics unchanged, counted as re-applied '
        '(not chunks / applied / latestServerTime); it leaves sync.heldRecords '
        'with the apply call', () {
      withDownloadRig((r) {
        final chunk = oldAppReceives(r);
        expect(r.pipeline.heldRecordCount, 1);
        update(r);
        expect(r.pipeline.heldRecordCount, 1, reason: 'loaded');
        final cursor = r.pipeline.cursor;
        final stats = r.pipeline.scopeStats.encode();
        final calls = r.sync.applyRefs.length;
        final result = reapply(r);
        expect(result.reappliedChunks, 1);
        expect(result.reappliedRecords, 1);
        expect(result.chunks, 0);
        expect(result.applied, 0);
        expect(result.latestServerTime, isNull);
        expect(result.issues, isEmpty);
        expect(r.sync.applyRefs.skip(calls), [
          [hw('p1')],
        ]);
        r.expectSameRow(EntityKind.handwriting, HandwritingText.idFor('p1'));
        expect(r.pipeline.wasApplied(chunk.id), isFalse);
        expect(r.pipeline.cursor, cursor);
        expect(r.pipeline.scopeStats.encode(), stats);
        expect(r.pipeline.heldRecordCount, 0);
        final meta = r.sync.applyMetaUpdates.last;
        expect(meta, isNot(contains(MetaKeys.cursor)));
        expect(heldKeysOf(meta), {
          MetaKeys.heldRecords,
          MetaKeys.heldRecordParts.first,
        });
        expect(r.a.meta[MetaKeys.heldRecords], '');
        // Nothing left: a second re-apply does nothing.
        expect(reapply(r).reappliedChunks, 0);
      });
    });

    test('② right after the re-apply, the overlap catch-up receives the '
        'original chunk again: decoded and applied normally, every outcome '
        'kept (idempotent)', () {
      withDownloadRig((r) {
        final chunk = oldAppReceives(r);
        update(r);
        reapply(r);
        final dump = r.a.canonicalDump();
        final groups = r.groups.length;
        final again = r.catchUp();
        expect(again.duplicates, 0, reason: 'the chunk is not in the LRU');
        expect(again.chunks, r.serverChunks().length);
        expect(r.pipeline.wasApplied(chunk.id), isTrue);
        final outcomes = {for (final g in r.groups.skip(groups)) ...g};
        expect(outcomes[hw('p1')], MergeOutcomeKind.kept);
        expect(outcomes.values.toSet(), {MergeOutcomeKind.kept});
        expect(r.a.canonicalDump(), dump);
        expect(needsAppUpdateCount(again), 0);
        expect(r.pipeline.heldRecordCount, 0);
      });
    });

    test('③ stored and marked chunks are never split: over the cap the whole '
        'chunk goes to the mark; after the update load rewinds to it, the '
        're-apply takes the stored chunk and the catch-up the marked one — '
        'every record applies', () {
      withDownloadRig((r) {
        r.b.localWrite([
          noteWrite('n1'),
          for (final p in ['p1', 'p2', 'p3']) pageWrite(p, 'n1'),
          for (final p in ['p1', 'p2', 'p3']) handwritingWrite(p, 'n1'),
        ]);
        Uint8List bytesOf(EntityKind kind, String id) =>
            ChunkCodec.encodeRecord(DownloadRig.recordOf(r.b, kind, id));
        final hlc = r.b.rows[note('n1')]!.versions.max;
        r.commitRecordBytes([
          bytesOf(EntityKind.note, 'n1'),
          for (final p in ['p1', 'p2', 'p3']) bytesOf(EntityKind.page, p),
        ], maxHlc: hlc);
        r.async.elapse(const Duration(seconds: 1));
        final c1 = r.commitRecordBytes([
          bytesOf(EntityKind.handwriting, 'hw_p1'),
        ], maxHlc: hlc);
        r.async.elapse(const Duration(seconds: 1));
        final c2 = r.commitRecordBytes([
          bytesOf(EntityKind.handwriting, 'hw_p2'),
          bytesOf(EntityKind.handwriting, 'hw_p3'),
        ], maxHlc: hlc);
        r.async.elapse(const Duration(hours: 1));
        final c3 = r.commit([
          DownloadRig.recordOf(
            FakeLocalStore(nodeId: nodeC, clock: r.base, ownerId: uid)
              ..localWrite([noteWrite('n9')]),
            EntityKind.note,
            'n9',
          ),
        ]);
        // A cap that holds c1's record and not one more entry.
        final probe = HeldRecords(knownKinds: oldNames)
          ..add(
            c1,
            ChunkCodec.decodeTolerant(
              c1.payload,
              isKnownKind: oldNames.contains,
            ).unknown,
          );
        final text = probe.encode();
        final one = text.values.fold(0, (n, v) => n + utf8.encode(v).length);
        final entry = text[MetaKeys.heldRecordParts.first]!.length - 20;
        final cap = one + entry ~/ 2;

        r.pipeline = r.newPipeline(
          knownKinds: old,
          heldRecordsMaxTotalBytes: cap,
        );
        r.connect();
        final first = r.catchUp();
        expect(first.issues.map((i) => i.message), [
          '3 record(s) of kind handwriting held until the app is updated',
        ]);
        expect(
          r.pipeline.heldRecords
              .knownChunks((_) => true)
              .map((c) => c.chunk.id),
          [c1.id],
          reason: 'c2 is not half stored',
        );
        expect(r.pipeline.heldRecords.mark?.from, c2.serverTime);
        expect(r.pipeline.cursor, c3.serverTime);

        final writes = r.sync.writeMetaCalls.length;
        update(r, maxTotalBytes: cap);
        final rewind = r.sync.writeMetaCalls.skip(writes).single;
        final back = c2.serverTime.minus(const SyncConfig().cursorOverlap);
        expect(rewind[MetaKeys.cursor], '$back');
        expect(heldKeysOf(rewind), {MetaKeys.heldRecords});
        expect(r.pipeline.cursor, back);
        expect(r.pipeline.heldRecordsMarked, isFalse);
        expect(r.pipeline.heldRecordCount, 1);

        final reapplied = reapply(r);
        expect(reapplied.reappliedRecords, 1);
        expect(r.a.rows.containsKey(hw('p1')), isTrue);
        expect(r.a.rows.containsKey(hw('p2')), isFalse);
        final caught = r.catchUp();
        expect(caught.issues, isEmpty);
        for (final p in ['p1', 'p2', 'p3']) {
          r.expectSameRow(EntityKind.handwriting, HandwritingText.idFor(p));
        }
        expect(r.pipeline.heldRecords.isEmpty, isTrue);
        expect(r.pipeline.cursor, c3.serverTime);
      });
    });

    /// A, an older app, holds C's handwriting result whose HLC is 48 h ahead (alone in its
    /// chunk — nothing known to hold), then is updated and re-applies: K1.
    (RemoteChunk, UpsertRecord) futureHandwriting(DownloadRig r) {
      final c = FakeLocalStore(
        nodeId: nodeC,
        clock: Clock(() => r.base.now().add(const Duration(hours: 48))),
        ownerId: uid,
      )..localWrite([handwritingWrite('p9', 'n9')]);
      final record = DownloadRig.recordOf(c, EntityKind.handwriting, 'hw_p9');
      final chunk = r.commitRecordBytes([
        ChunkCodec.encodeRecord(record),
      ], maxHlc: record.versions.max);
      r.pipeline = r.newPipeline(knownKinds: old);
      r.connect();
      final first = r.catchUp();
      expect(first.held, 0, reason: 'unknown records do not pass the gate');
      expect(r.pipeline.held.isEmpty, isTrue);
      expect(r.pipeline.heldRecordCount, 1);
      return (chunk, record);
    }

    test('④ ⑤ a re-applied record K1 holds keeps its bytes with ra '
        '(sync.held unchanged); its original chunk deleted by compaction, '
        'releaseHeld applies it from sync.heldRecords once ra ≤ g\'', () {
      withDownloadRig((r) {
        const day = Duration(hours: 24);
        final (chunk, record) = futureHandwriting(r);
        update(r);
        final heldText = r.a.meta[MetaKeys.held] ?? '';
        final result = reapply(r);
        expect(result.held, 1);
        expect(result.reappliedChunks, 1);
        expect(result.reappliedRecords, 0);
        expect(r.a.rows.containsKey(hw('p9')), isFalse);
        expect(r.pipeline.held.isEmpty, isTrue);
        expect(r.a.meta[MetaKeys.held] ?? '', heldText);
        expect(r.pipeline.heldRecordCount, 1);
        expect(r.pipeline.heldRecordsAwaitRelease, isTrue);
        final releaseAt = record.versions.max.millis - day.inMilliseconds;
        expect(
          r.a.meta[MetaKeys.heldRecordParts.first],
          contains('"ra":$releaseAt'),
        );
        expect(
          reapply(r).reappliedChunks,
          0,
          reason: 'a record with ra waits for releaseHeld',
        );

        // Compaction elsewhere deleted the original chunk.
        r.server.serveDelete(uid, [chunk.id]);
        expect(r.serverChunks().map((c) => c.id), isNot(contains(chunk.id)));
        r.async.elapse(const Duration(hours: 1));
        expect(r.release().reappliedChunks, 0, reason: 'not yet due');
        r.async.elapse(day);
        r.serverNowOverride = releaseAt;
        final released = r.release();
        expect(released.reappliedChunks, 1);
        expect(released.reappliedRecords, 1);
        expect(released.chunks, 0);
        expect(r.a.rows[hw('p9')]?.versions.toJson(), record.versions.toJson());
        expect(r.pipeline.heldRecordCount, 0);
        expect(r.pipeline.heldRecordsAwaitRelease, isFalse);
        expect(r.a.meta[MetaKeys.heldRecords], '');
      });
    });

    test('⑥ releaseHolds: false — the original chunk\'s other record K1 held '
        'on receive stays in sync.held while the re-apply settles the '
        'handwriting; K2 then releases it', () {
      withDownloadRig((r) {
        r.b.localWrite([
          noteWrite('n1'),
          pageWrite('p1', 'n1'),
          handwritingWrite('p1', 'n1'),
        ]);
        final c = FakeLocalStore(
          nodeId: nodeC,
          clock: Clock(() => r.base.now().add(const Duration(hours: 48))),
          ownerId: uid,
        )..localWrite([noteWrite('future')]);
        final future = DownloadRig.recordOf(c, EntityKind.note, 'future');
        final chunk = r.commitRecordBytes([
          for (final (kind, id) in [
            (EntityKind.note, 'n1'),
            (EntityKind.page, 'p1'),
            (EntityKind.handwriting, 'hw_p1'),
          ])
            ChunkCodec.encodeRecord(DownloadRig.recordOf(r.b, kind, id)),
          ChunkCodec.encodeRecord(future),
        ], maxHlc: future.versions.max);
        r.pipeline = r.newPipeline(knownKinds: old);
        r.connect();
        expect(r.catchUp().held, 1);
        expect(r.pipeline.held.entries.keys, [chunk.id]);
        expect(r.pipeline.heldRecordCount, 1);

        update(r);
        final heldText = r.a.meta[MetaKeys.held];
        final result = reapply(r);
        expect(result.reappliedRecords, 1);
        r.expectSameRow(EntityKind.handwriting, 'hw_p1');
        expect(r.pipeline.held.entries.keys, [chunk.id]);
        expect(r.a.meta[MetaKeys.held], heldText);
        expect(r.pipeline.heldRecordCount, 0);
        expect(r.hasRow(EntityKind.note, 'future'), isFalse);

        r.async.elapse(const Duration(hours: 25));
        r.serverNowOverride =
            future.versions.max.millis -
            const Duration(hours: 24).inMilliseconds;
        final released = r.release();
        expect(released.chunks, 1);
        expect(r.hasRow(EntityKind.note, 'future'), isTrue);
        expect(r.pipeline.held.isEmpty, isTrue);
        expect(r.pipeline.heldRecordCount, 0, reason: 'known now: applied');
      });
    });

    test('⑦ a store failure: nothing changes in memory or in the meta; a '
        'second try applies', () {
      withDownloadRig((r) {
        oldAppReceives(r);
        update(r);
        Map<String, String> meta() => {
          for (final k in MetaKeys.heldRecordKeys) k: r.a.meta[k] ?? '',
        };
        final stored = meta();
        final inMemory = r.pipeline.heldRecords.encode();
        r.sync.nextApplyError = Exception('disk full');
        final failed = r.run(r.pipeline.reapplyHeldRecords());
        expect(failed.error, isNotNull);
        expect(r.pipeline.heldRecordCount, 1);
        expect(r.pipeline.heldRecords.encode(), inMemory);
        expect(meta(), stored);
        expect(r.a.rows.containsKey(hw('p1')), isFalse);
        expect(reapply(r).reappliedRecords, 1);
        r.expectSameRow(EntityKind.handwriting, HandwritingText.idFor('p1'));
        expect(r.pipeline.heldRecordCount, 0);
      });
    });

    test('kinds still unknown stay held: an updated app re-applies what it '
        'knows and keeps the bookmark records', () {
      withDownloadRig((r) {
        final hlc = Hlc(start.millisecondsSinceEpoch, 0, nodeC);
        r.commitRecordBytes([bookmark('b1', hlc)], maxHlc: hlc);
        oldAppReceives(r);
        expect(r.pipeline.heldRecordCount, 2);
        update(r);
        expect(reapply(r).reappliedRecords, 1);
        expect(r.pipeline.heldRecordCount, 1);
        expect(r.pipeline.heldRecords.kinds, {'bookmark'});
        expect(reapply(r).reappliedChunks, 0);
      });
    });

    test('a corrupt head: the all-kinds mark of an unknown writer rewinds at '
        'once to the beginning; the records are received and held again', () {
      withDownloadRig((r) {
        oldAppReceives(r);
        r.async.elapse(const Duration(hours: 1));
        r.run(r.sync.writeMeta({MetaKeys.heldRecords: '{"v":'}));
        r.pipeline = r.newPipeline(knownKinds: old);
        r.connect();
        expect(r.warnings.single, contains('corrupt'));
        expect(r.pipeline.cursor, ServerCursor.zero);
        expect(r.pipeline.heldRecords.isEmpty, isTrue);
        final again = r.catchUp();
        expect(needsAppUpdateCount(again), 1);
        expect(r.pipeline.heldRecordCount, 1);
      });
    });

    test('a corrupt part: the same app keeps the all-kinds mark (it would not '
        'read more); after the update load rewinds to the head\'s earliest '
        'serverTime and the catch-up applies the record', () {
      withDownloadRig((r) {
        final chunk = oldAppReceives(r);
        r.async.elapse(const Duration(hours: 1));
        r.b.localWrite([noteWrite('n5')]);
        r.pushB();
        r.catchUp();
        final cursor = r.pipeline.cursor!;
        r.run(r.sync.writeMeta({MetaKeys.heldRecordParts.first: '{"p":1,'}));
        r.pipeline = r.newPipeline(knownKinds: old);
        r.connect();
        expect(r.pipeline.heldRecords.mark?.kinds, {'*'});
        expect(r.pipeline.cursor, cursor, reason: 'same app: no rewind');

        update(r);
        expect(r.pipeline.heldRecordsMarked, isFalse);
        expect(
          r.pipeline.cursor,
          chunk.serverTime.minus(const SyncConfig().cursorOverlap),
        );
        r.catchUp();
        r.expectSameRow(EntityKind.handwriting, HandwritingText.idFor('p1'));
        expect(r.pipeline.cursor, cursor);
      });
    });
  });
}
