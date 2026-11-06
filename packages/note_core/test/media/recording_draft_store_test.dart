// CORE T31 — the SQLite draft store beyond the shared contract (m5-7/02-core 6.7.2–6.7.3):
// many appends in call order, the append Future pending while its row commit is retried
// (failNextCommits), a cut between ① and ② reconciled by listDrafts after a reopen, the lost
// row rebuilt from the meta and written again, the first-use orphan cleanup on reopen,
// keep-alive chunks, discard order and idempotence, the limits, a row-less meta blocking a
// second begin, and drafts being device-local (no outbox, no ChangeBatch).
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/db/note_database.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:note_core/src/storage/outbox_writer.dart';
import 'package:test/test.dart';

import '../storage/storage_support.dart';
import 'draft_store_support.dart';

Uint8List _chunk(int n, int fill) => Uint8List.fromList(List.filled(n, fill));

void main() {
  late String path;
  late IdbFactory blobFactory;
  late DateTime now;
  late DriftNoteStore store;
  late Note note;

  Clock clock() => Clock(() => now);

  Future<DriftNoteStore> reopen() async {
    final s = await openDraftStore(path, blobFactory, clock: clock());
    addTearDown(s.close);
    return s;
  }

  setUp(() async {
    final dir = await Directory.systemTemp.createTemp('core_draft_store_');
    addTearDown(() => dir.delete(recursive: true));
    path = '${dir.path}/notes.sqlite';
    blobFactory = newIdbFactoryMemory();
    now = DateTime.utc(2026, 11, 6, 10);
    store = await reopen();
    note = await store.library.createNote(title: 'drafts');
  });

  Future<RecordingDraft> begin(
    NoteStore s,
    String recordingId, {
    int startedAt = 1000,
  }) => s.recordingDrafts.begin(
    recordingId: recordingId,
    noteId: note.id,
    mimeType: 'audio/webm',
    startedAt: startedAt,
  );

  Future<RecordingDraftRow?> row(DriftNoteStore s, String draftId) =>
      (s.db.select(
        s.db.recordingDrafts,
      )..where((t) => t.draftId.equals(draftId))).getSingleOrNull();

  Future<List<String>> blobKeys(DriftNoteStore s, String draftId) =>
      s.recordingDrafts.blobs.keys('rd/$draftId/');

  test('120 appends without awaiting land in call order (with keep-alive '
      'chunks between them); the meta and every chunk come before their row '
      'writes', () async {
    final d = await begin(store, 'rec-1');
    final writes = <Future<void>>[];
    var expected = <int>[];
    for (var i = 0; i < 120; i++) {
      final c = _chunk(1 + i % 7, i % 251);
      expected = [...expected, ...c];
      writes.add(
        store.recordingDrafts.append(d.draftId, c, activeMs: (i + 1) * 1000),
      );
      if (i % 10 == 9) {
        writes.add(
          store.recordingDrafts.append(
            d.draftId,
            Uint8List(0),
            activeMs: (i + 1) * 1000 + 500,
          ),
        );
      }
    }
    await Future.wait(writes);
    final listed = (await store.recordingDrafts.listDrafts()).single;
    expect(listed.chunkCount, 120);
    expect(listed.bytes, expected.length);
    expect(listed.activeMs, 120500);
    expect(await store.recordingDrafts.readAll(d.draftId), expected);
    final stored = (await row(store, d.draftId))!;
    expect((stored.chunkCount, stored.bytes), (120, expected.length));
    final order = store.recordingDrafts.debugWriteOrder;
    expect(order.first, 'rd/${d.draftId}/meta');
    expect(order[1], 'row:${d.draftId}');
    expect(order.skip(2), [
      for (var i = 0; i < 120; i++)
        'rd/${d.draftId}/${i.toString().padLeft(6, '0')}',
    ]);
  });

  test(
    'append copies the chunk when called (the caller may reuse its buffer)',
    () async {
      final d = await begin(store, 'rec-1');
      final buffer = _chunk(4, 7);
      final write = store.recordingDrafts.append(
        d.draftId,
        buffer,
        activeMs: 1,
      );
      buffer.fillRange(0, 4, 0);
      await write;
      expect(await store.recordingDrafts.readAll(d.draftId), [7, 7, 7, 7]);
    },
  );

  test('a failed row commit: the chunk is stored, append stays pending while '
      'the queue retries and completes after the commit', () {
    fakeAsync((async) {
      int pumpUntil(bool Function() done, {int maxMs = 10000}) {
        var ms = 0;
        async.flushMicrotasks();
        while (!done() && ms < maxMs) {
          async.elapse(const Duration(milliseconds: 1));
          ms++;
        }
        expect(done(), isTrue, reason: 'not reached in $maxMs ms');
        return ms;
      }

      T run<T>(Future<T> f) {
        T? value;
        var ok = false;
        f.then((v) {
          value = v;
          ok = true;
        });
        pumpUntil(() => ok);
        return value as T;
      }

      final s = run(openStore());
      final n = run(s.library.createNote(title: 'n'));
      final d = run(
        s.recordingDrafts.begin(
          recordingId: 'rec-1',
          noteId: n.id,
          mimeType: 'audio/webm',
          startedAt: 1,
        ),
      );

      s.queue.failNextCommits(1);
      var done = false;
      s.recordingDrafts
          .append(d.draftId, _chunk(3, 1), activeMs: 1000)
          .then((_) => done = true);
      pumpUntil(() => s.persistenceStatus.consecutiveFailures == 1);
      final failedAt = async.elapsed;
      expect(done, isFalse);
      expect(
        run(s.recordingDrafts.blobs.keys('rd/${d.draftId}/')),
        contains('rd/${d.draftId}/000000'),
        reason: '① is done',
      );
      pumpUntil(() => done);
      // The first retry comes 100 ms after the failure (kWriteRetryBackoff).
      expect(
        async.elapsed - failedAt,
        greaterThanOrEqualTo(const Duration(milliseconds: 99)),
      );
      s.close();
      pumpUntil(() => async.pendingTimers.isEmpty);
    });
  });

  test(
    'a cut between ① and ② (the chunk stored, its row update lost): after '
    'a reopen listDrafts counts the chunk and the next append follows it',
    () async {
      final d = await begin(store, 'rec-1');
      await store.recordingDrafts.append(
        d.draftId,
        _chunk(3, 1),
        activeMs: 1000,
      );
      await store.recordingDrafts.blobs.put(
        'rd/${d.draftId}/000001',
        _chunk(5, 2),
      );
      await store.close();
      final s = await reopen();
      final listed = (await s.recordingDrafts.listDrafts()).single;
      expect(listed.chunkCount, 2);
      expect(listed.bytes, 8);
      expect(listed.activeMs, 1000);
      await s.recordingDrafts.append(d.draftId, _chunk(2, 3), activeMs: 3000);
      expect(await s.recordingDrafts.readAll(d.draftId), [
        1, 1, 1, 2, 2, 2, 2, 2, 3, 3, //
      ]);
      expect((await row(s, d.draftId))!.chunkCount, 3);
    },
  );

  test('a lost row is rebuilt from the meta and written again (updatedAt = '
      'startedAt, activeMs 0); a reopened store lists the same', () async {
    final d = await begin(store, 'rec-1', startedAt: 4242);
    await store.recordingDrafts.append(d.draftId, _chunk(6, 1), activeMs: 9);
    await (store.db.delete(
      store.db.recordingDrafts,
    )..where((t) => t.draftId.equals(d.draftId))).go();
    final rebuilt = (await store.recordingDrafts.listDrafts()).single;
    expect((rebuilt.updatedAt, rebuilt.activeMs), (4242, 0));
    expect((rebuilt.chunkCount, rebuilt.bytes), (1, 6));
    final stored = (await row(store, d.draftId))!;
    expect(
      (stored.recordingId, stored.updatedAt, stored.bytes),
      ('rec-1', 4242, 6),
    );
    await store.close();
    final s = await reopen();
    expect(await s.recordingDrafts.listDrafts(), [rebuilt]);
  });

  test('first use after a reopen removes only prefixes with neither a row nor '
      'a meta; a meta-only prefix and a 0-chunk row stay', () async {
    final withRow = await begin(store, 'rec-row');
    final metaOnly = await begin(store, 'rec-meta', startedAt: 500);
    await store.recordingDrafts.append(
      metaOnly.draftId,
      _chunk(2, 9),
      activeMs: 1,
    );
    await (store.db.delete(
      store.db.recordingDrafts,
    )..where((t) => t.draftId.equals(metaOnly.draftId))).go();
    final blobs = store.recordingDrafts.blobs;
    await blobs.put('rd/orphan/000000', _chunk(4, 1));
    await blobs.put('rd/orphan/000001', _chunk(4, 1));
    // A key outside 'rd/' (an asset chunk) is never touched.
    await blobs.put('${'a' * 64}/000000', _chunk(4, 1));
    await store.close();

    final s = await reopen();
    final listed = await s.recordingDrafts.listDrafts();
    expect(listed.map((d) => d.draftId), [metaOnly.draftId, withRow.draftId]);
    expect(await blobKeys(s, 'orphan'), isEmpty);
    expect(await blobKeys(s, metaOnly.draftId), [
      'rd/${metaOnly.draftId}/000000',
      'rd/${metaOnly.draftId}/meta',
    ]);
    expect(await s.recordingDrafts.blobs.keys('a' * 64), hasLength(1));
  });

  test('a keep-alive chunk changes activeMs and updatedAt only; no blob is '
      'written', () async {
    final d = await begin(store, 'rec-1');
    await store.recordingDrafts.append(d.draftId, _chunk(3, 1), activeMs: 1000);
    final writes = store.recordingDrafts.debugWriteOrder.length;
    now = now.add(const Duration(seconds: 7));
    await store.recordingDrafts.append(d.draftId, Uint8List(0), activeMs: 2000);
    expect(store.recordingDrafts.debugWriteOrder, hasLength(writes));
    final stored = (await row(store, d.draftId))!;
    expect(stored.chunkCount, 1);
    expect(stored.bytes, 3);
    expect(stored.activeMs, 2000);
    expect(stored.updatedAt, now.millisecondsSinceEpoch);
  });

  test('discard: chunks and meta first, then the row (a failed row commit '
      'leaves the row until the retry); a second discard is a no-op', () {
    fakeAsync((async) {
      void pumpUntil(bool Function() done) {
        var ms = 0;
        async.flushMicrotasks();
        while (!done() && ms < 10000) {
          async.elapse(const Duration(milliseconds: 1));
          ms++;
        }
        expect(done(), isTrue);
      }

      T run<T>(Future<T> f) {
        T? value;
        var ok = false;
        f.then((v) {
          value = v;
          ok = true;
        });
        pumpUntil(() => ok);
        return value as T;
      }

      final s = run(openStore());
      final n = run(s.library.createNote(title: 'n'));
      final d = run(
        s.recordingDrafts.begin(
          recordingId: 'rec-1',
          noteId: n.id,
          mimeType: 'audio/webm',
          startedAt: 1,
        ),
      );
      run(s.recordingDrafts.append(d.draftId, _chunk(3, 1), activeMs: 1));
      s.queue.failNextCommits(1);
      var done = false;
      s.recordingDrafts.discard(d.draftId).then((_) => done = true);
      pumpUntil(() => s.persistenceStatus.consecutiveFailures == 1);
      expect(done, isFalse);
      expect(run(s.recordingDrafts.blobs.keys('rd/${d.draftId}/')), isEmpty);
      expect(run(row(s, d.draftId)), isNotNull, reason: '② not committed');
      pumpUntil(() => done);
      expect(run(row(s, d.draftId)), isNull);
      run(s.recordingDrafts.discard(d.draftId));
      run(s.recordingDrafts.discard('never'));
      s.close();
      pumpUntil(() => async.pendingTimers.isEmpty);
    });
  });

  test('limits: a 4 MiB chunk is taken, one byte more and a negative '
      'activeMs are ArgumentErrors that change nothing', () async {
    final d = await begin(store, 'rec-1');
    await store.recordingDrafts.append(
      d.draftId,
      Uint8List(4 * 1024 * 1024),
      activeMs: 1,
    );
    await expectLater(
      store.recordingDrafts.append(
        d.draftId,
        Uint8List(4 * 1024 * 1024 + 1),
        activeMs: 2,
      ),
      throwsArgumentError,
    );
    await expectLater(
      store.recordingDrafts.append(d.draftId, _chunk(1, 1), activeMs: -1),
      throwsArgumentError,
    );
    final stored = (await row(store, d.draftId))!;
    expect(
      (stored.chunkCount, stored.bytes, stored.activeMs),
      (1, 4 * 1024 * 1024, 1),
    );
    expect(await blobKeys(store, d.draftId), hasLength(2)); // chunk + meta
  });

  test('one draft per recording: a second begin is a StateError, also while '
      'only the meta of the first is left; it leaves no blob behind', () async {
    final d = await begin(store, 'rec-1');
    await expectLater(begin(store, 'rec-1'), throwsStateError);
    await (store.db.delete(
      store.db.recordingDrafts,
    )..where((t) => t.draftId.equals(d.draftId))).go();
    await expectLater(begin(store, 'rec-1'), throwsStateError);
    final prefixes = {
      for (final k in await store.recordingDrafts.blobs.keys('rd/'))
        k.split('/')[1],
    };
    expect(prefixes, {d.draftId});
    // Another recording is fine.
    await begin(store, 'rec-2');
  });

  test('the meta is UTF-8 JSON of the draft (v1)', () async {
    final d = await begin(store, 'rec-1', startedAt: 99);
    final meta = await store.recordingDrafts.blobs.get('rd/${d.draftId}/meta');
    expect(jsonDecode(utf8.decode(meta!)), {
      'v': 1,
      'recordingId': 'rec-1',
      'noteId': note.id,
      'mimeType': 'audio/webm',
      'startedAt': 99,
    });
  });

  test('drafts are device-local: no outbox entry, no ChangeBatch, not in '
      'the backup', () async {
    await store.db.delete(store.db.outbox).go();
    final batches = <ChangeBatch>[];
    final sub = store.changes.listen(batches.add);
    addTearDown(sub.cancel);
    final d = await begin(store, 'rec-1');
    await store.recordingDrafts.append(d.draftId, _chunk(3, 1), activeMs: 1);
    await store.recordingDrafts.listDrafts();
    await store.recordingDrafts.discard(d.draftId);
    await Future<void>.delayed(Duration.zero);
    expect(await readOutbox(store.db), isEmpty);
    expect(batches, isEmpty);
    final backup = utf8.decode(await store.exportBackupJson());
    expect(backup, isNot(contains('rec-1')));
  });
}
