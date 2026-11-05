// T15: compaction (6.13). The Compactor turns one scope into snapshot chunks of the merged
// state and deletes only the chunks merged into them (SYNC-3-2 ②): a scope with a newer chunk
// format, a device with sync.deferredFrom, a held chunk (SYNC-2-4) or a collapsed hold is
// left alone; malformed chunks stay on the server; a purged note's scope compacts to nothing;
// chunks written meanwhile survive; two devices compacting at once only duplicate the
// snapshot; the compacting device gets the records of R it had not applied from its own
// snapshot (SYNC-3-2 ①). The engine runs it when a scope is due (n ≥ minChunksPerScope,
// 24 h), live, foreground and with nothing pending, after a random wait.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/src/codec/chunk_codec.dart';
import 'package:sync_engine/src/codec/chunk_id.dart';
import 'package:sync_engine/src/compaction/compactor.dart';
import 'package:sync_engine/src/engine/held_chunks.dart';
import 'package:sync_engine/src/engine/meta_keys.dart';
import 'package:sync_engine/src/merge/purged_set.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import '../support/engine_harness.dart';

const _uid = 'user-1';
const _writer = 'c0c0c0c0c0c0c0c0';

/// Small trigger for the engine tests: 5 chunks, no wait between runs of a scope's trigger.
const _small = SyncConfig(compaction: CompactionConfig(minChunksPerScope: 5));

/// The chunks of [scope] on the server, in (serverTime, id) order.
List<RemoteChunk> _scopeChunks(SyncTestHarness h, String scope) => [
  for (final s in h.server.chunksOf(_uid))
    if (s.chunk.scope == scope) s.chunk,
];

List<RemoteChunk> _deltas(SyncTestHarness h, String scope) => [
  for (final c in _scopeChunks(h, scope))
    if (c.kind == ChunkKind.delta) c,
];

/// [count] strokes on [page] from [d], one push (one chunk) each.
List<String> _strokes(
  SyncTestHarness h,
  TestDevice d,
  String page,
  int count, {
  int seed = 0,
}) {
  final ids = <String>[];
  for (var i = 0; i < count; i++) {
    ids.add(d.addStroke(page, seed: seed + i, points: 10));
    h.elapse(const Duration(milliseconds: 700));
  }
  h.settle();
  return ids;
}

/// A device's Compactor on its own link, as the engine builds it (6.13 unit runs).
final class _Run {
  _Run(this.h, this.device, {SyncConfig config = const SyncConfig()}) {
    purged = PurgedSet(
      sync: device.store.sync,
      localChanges: device.store.localChanges,
    );
    h.run(purged.load());
    compactor = Compactor(
      sync: device.store.sync,
      backend: h.server.connect(uid: _uid, link: link),
      config: config,
      purged: purged,
    );
  }

  final SyncTestHarness h;
  final TestDevice device;
  final FakeNetworkLink link = FakeNetworkLink();
  late final PurgedSet purged;
  late final Compactor compactor;

  CompactionResult compact(
    String scope, {
    HeldChunks? held,
    ServerCursor? deferredFrom,
  }) => h.run(
    compactor.compact(
      scope,
      held: held ?? HeldChunks(),
      deferredFrom: deferredFrom,
    ),
  );
}

/// A chunk of [records] written by [_writer] (or [node]) in [scope], committed raw.
ChunkWrite _raw(
  List<SyncRecord> records,
  String scope, {
  String node = _writer,
  int? format,
  Uint8List? payload,
}) {
  final bytes = payload ?? ChunkCodec.encode(records);
  return ChunkWrite(
    id: chunkIdOf(node, bytes),
    scope: scope,
    authorNodeId: node,
    recordCount: records.isEmpty ? 1 : records.length,
    format: format ?? ChunkCodec.formatVersion,
    kind: ChunkKind.delta,
    maxHlc: records.isEmpty
        ? Hlc(1, 0, node).toString()
        : ChunkCodec.maxHlcOf(records).toString(),
    payload: bytes,
  );
}

/// A note scope with a page and [strokes] stroke chunks written by a live device A.
({TestDevice a, String note, String page, List<String> strokes}) _noteScope(
  SyncTestHarness h, {
  int strokes = 6,
  SyncConfig? config,
}) {
  final a = h.device('A', config: config);
  final note = a.createNote('N');
  h.settle();
  final page = a.pageIdsOf(note).single;
  return (a: a, note: note, page: page, strokes: _strokes(h, a, page, strokes));
}

void main() {
  group('Compactor.dueScopes (6.13 trigger statistics)', () {
    test(
      'n ≥ minChunksPerScope and now − c ≥ minInterval; most chunks first',
      () {
        const config = CompactionConfig(minChunksPerScope: 3);
        final stats = ScopeStats();
        for (var i = 0; i < 5; i++) {
          stats.addChunk('busy');
        }
        for (var i = 0; i < 3; i++) {
          stats
            ..addChunk('edge')
            ..addChunk('recent');
        }
        for (var i = 0; i < 2; i++) {
          stats.addChunk('few');
        }
        const day = 24 * 3600 * 1000;
        const now = 10 * day;
        stats.markCompacted('recent', now - day + 1, chunks: 3);
        expect(Compactor.dueScopes(stats, config, nowMillis: now), [
          'busy',
          'edge',
        ]);
        // Exactly 24 h after the last run: due again.
        stats.markCompacted('recent', now - day, chunks: 3);
        expect(Compactor.dueScopes(stats, config, nowMillis: now), [
          'busy',
          'edge',
          'recent',
        ]);
        // markAttempted keeps n and moves c.
        stats.markAttempted('busy', now);
        expect(stats.countOf('busy'), 5);
        expect(Compactor.dueScopes(stats, config, nowMillis: now), [
          'edge',
          'recent',
        ]);
      },
    );
  });

  group('one compaction', () {
    harnessTest(
      'snapshot = the merged state; only merged chunks deleted; a new '
      "device's first sync reads less and converges",
      (h, async) {
        final s = _noteScope(h);
        final b = h.device('B');
        h.settle();
        s.a.recolorStroke(s.strokes.first, 0xff0000ff);
        b.eraseStroke(s.strokes.last);
        h.settle();
        final before = h.server.mergedState(_uid);
        final chunksBefore = _scopeChunks(h, s.note);
        expect(chunksBefore.length, greaterThanOrEqualTo(8));
        final readsBefore = h.server.readCount(_uid);
        final c = h.device('C');
        h.settle();
        final readsWithout = h.server.readCount(_uid) - readsBefore;

        final run = _Run(h, s.a);
        final result = run.compact(s.note);
        expect(result.completed, isTrue, reason: '$result');
        expect(result.fetched, chunksBefore.length);
        expect(result.malformed, 0);
        expect(result.snapshotRecords, 1 + s.strokes.length);
        final after = _scopeChunks(h, s.note);
        expect(after, hasLength(result.snapshotChunks));
        for (final chunk in after) {
          expect(chunk.kind, ChunkKind.snapshot);
          expect(chunk.authorNodeId, s.a.store.sync.deviceNodeId);
        }
        expect(result.deleted, chunksBefore.length);
        expect(h.server.mergedState(_uid), before);
        expect(run.link.callCount(FakeOp.delete), 1);

        h.settle();
        final readsAgain = h.server.readCount(_uid);
        final d = h.device('D');
        h.settle();
        final readsWith = h.server.readCount(_uid) - readsAgain;
        expect(readsWith, lessThan(readsWithout));
        h.checkConverged([s.a, b, c, d]);
      },
    );

    harnessTest('the snapshot keeps future-HLC records (compaction stores, it '
        'does not apply K1)', (h, async) {
      final s = _noteScope(h, strokes: 2);
      final future = Hlc(
        h.serverClock
            .now()
            .add(const Duration(hours: 48))
            .millisecondsSinceEpoch,
        0,
        _writer,
      );
      final stroke = s.a.doc(EntityKind.stroke, s.strokes.first)!;
      final record = UpsertRecord(
        stroke.withFields({
          'deletedAt': future.millis,
          if (stroke.json.containsKey('version')) 'version': future.toString(),
        }),
        EntityFieldVersions(future),
      );
      h.server.commitRaw(_uid, [
        _raw([record], s.note),
      ]);
      final before = h.server.mergedState(_uid);
      expect(before[record.ref]!.versions.max, future);

      final result = _Run(h, h.device('X', signedIn: false)).compact(s.note);
      expect(result.completed, isTrue, reason: '$result');
      final snapshot = [
        for (final c in _scopeChunks(h, s.note))
          ...ChunkCodec.decode(c.payload),
      ];
      final kept = snapshot.whereType<UpsertRecord>().singleWhere(
        (r) => r.ref == record.ref,
      );
      expect(kept.versions.max, future);
      expect(kept.doc.json['deletedAt'], future.millis);
      expect(h.server.mergedState(_uid), before);
    });

    harnessTest('chunks written while compacting stay (not in R)', (h, async) {
      final s = _noteScope(h, strokes: 4);
      final b = h.device('B');
      h.settle();
      final run = _Run(h, s.a);
      // B pushes 500 ms after its stroke (debounce) and the commit reaches the server
      // 50 ms later: after R was read (T + 50 ms), before the delete (T + 250 ms).
      final late = b.addStroke(s.page, seed: 99, points: 10);
      h.elapse(const Duration(milliseconds: 400));
      final result = run.compact(s.note);
      h.settle();
      expect(result.completed, isTrue, reason: '$result');
      final deltas = _deltas(h, s.note);
      expect(deltas, hasLength(1));
      expect(
        ChunkCodec.decode(deltas.single.payload).single.ref,
        EntityRef(EntityKind.stroke, late),
      );
      final d = h.device('D');
      h.settle();
      expect(d.doc(EntityKind.stroke, late), isNotNull);
      h.checkConverged([s.a, b, d]);
    });

    harnessTest('two devices at once: two snapshots, the same state', (
      h,
      async,
    ) {
      final s = _noteScope(h, strokes: 5);
      final b = h.device('B');
      h.settle();
      final before = h.server.mergedState(_uid);
      final runA = _Run(h, s.a), runB = _Run(h, b);
      final results = h.run(
        Future.wait([
          runA.compactor.compact(s.note, held: HeldChunks()),
          runB.compactor.compact(s.note, held: HeldChunks()),
        ]),
      );
      expect(results.every((r) => r.completed), isTrue, reason: '$results');
      final after = _scopeChunks(h, s.note);
      expect(after.every((c) => c.kind == ChunkKind.snapshot), isTrue);
      expect(
        {for (final c in after) c.authorNodeId},
        {s.a.store.sync.deviceNodeId, b.store.sync.deviceNodeId},
      );
      expect(h.server.mergedState(_uid), before);
      h.settle();
      final d = h.device('D');
      h.settle();
      expectNoStrokeLost([s.a, b, d], s.strokes);
      h.checkConverged([s.a, b, d]);
    });

    harnessTest('a snapshot chunk already in R (the same snapshot again, or '
        'a one-record delta with the same payload) is kept: not rewritten, not '
        'deleted', (h, async) {
      final s = _noteScope(h, strokes: 3);
      final run = _Run(h, s.a);
      expect(run.compact(s.note).completed, isTrue);
      final first = _scopeChunks(h, s.note);
      final commits = run.link.callCount(FakeOp.commit);
      final again = run.compact(s.note);
      expect(again.completed, isTrue, reason: '$again');
      expect(again.committed, 0);
      expect(again.deleted, 0);
      expect(run.link.callCount(FakeOp.commit), commits);
      expect(_scopeChunks(h, s.note), first);

      // A's only lib chunk after this: its one-record delta with the purge below. The
      // snapshot of that record has the same payload, so the same id.
      s.a.trashNote(s.note);
      h.settle();
      s.a.purgeNote(s.note);
      h.settle();
      expect(run.compact(SyncScopes.library).completed, isTrue);
      final lib = run.compact(SyncScopes.library);
      expect(lib.completed, isTrue, reason: '$lib');
      expect(lib.committed, 0);
      expect(lib.deleted, 0);
    });

    harnessTest("a purged note's scope: no snapshot, its decoded chunks "
        'deleted; the purge stays in lib', (h, async) {
      final s = _noteScope(h, strokes: 3);
      final bad = _raw(
        const [],
        s.note,
        payload: Uint8List.fromList([9, 9, 9]),
      );
      h.server.commitRaw(_uid, [bad]);
      s.a.trashNote(s.note);
      h.settle();
      s.a.purgeNote(s.note);
      h.settle();
      final run = _Run(h, s.a);
      final result = run.compact(s.note);
      expect(result.completed, isTrue, reason: '$result');
      expect(result.snapshotChunks, 0);
      expect(result.malformed, 1);
      expect(_scopeChunks(h, s.note).map((c) => c.id), [bad.id]);

      final lib = run.compact(SyncScopes.library);
      expect(lib.completed, isTrue, reason: '$lib');
      final libRecords = [
        for (final c in _scopeChunks(h, SyncScopes.library))
          ...ChunkCodec.decode(c.payload),
      ];
      final noteRef = EntityRef(EntityKind.note, s.note);
      expect(libRecords.whereType<PurgeRecord>().map((r) => r.ref), [noteRef]);
      expect(
        libRecords.whereType<UpsertRecord>().map((r) => r.ref),
        isNot(contains(noteRef)),
      );
      final d = h.device('D');
      h.settle();
      expect(d.doc(EntityKind.note, s.note), isNull);
      h.checkConverged([s.a, d]);
    });

    harnessTest('over maxScopeBytes: skipped, nothing committed or deleted', (
      h,
      async,
    ) {
      final s = _noteScope(h, strokes: 3);
      final chunks = _scopeChunks(h, s.note);
      final run = _Run(
        h,
        s.a,
        config: const SyncConfig(
          compaction: CompactionConfig(maxScopeBytes: 300),
        ),
      );
      final result = run.compact(s.note);
      expect(result.skipped, CompactionSkip.tooLarge);
      expect(run.link.callCount(FakeOp.commit), 0);
      expect(run.link.callCount(FakeOp.delete), 0);
      expect(_scopeChunks(h, s.note), chunks);
    });

    harnessTest('a chunk this device holds (K1) in R, or a collapsed hold: '
        'skipped (SYNC-2-4)', (h, async) {
      final s = _noteScope(h, strokes: 2);
      final chunks = _scopeChunks(h, s.note);
      final run = _Run(h, s.a);
      final held = HeldChunks()
        ..hold(chunks.first.id, chunks.first.serverTime, 1);
      expect(run.compact(s.note, held: held).skipped, CompactionSkip.heldChunk);
      final collapsed = HeldChunks.decode('{"*": [0, 1]}');
      expect(collapsed.collapsed, isNotNull);
      expect(
        run.compact(s.note, held: collapsed).skipped,
        CompactionSkip.collapsedHold,
      );
      expect(run.link.callCount(FakeOp.commit), 0);
      expect(run.link.callCount(FakeOp.delete), 0);
      expect(_scopeChunks(h, s.note), chunks);
    });

    harnessTest('a commit failure deletes nothing; the next run starts over', (
      h,
      async,
    ) {
      final s = _noteScope(h, strokes: 3);
      final chunks = _scopeChunks(h, s.note);
      final run = _Run(h, s.a);
      run.link.failNext(const FakeNetworkError(), op: FakeOp.commit);
      final failed = run.compact(s.note);
      expect(failed.error, isA<SyncBackendException>());
      expect(failed.committed, 0);
      expect(failed.deleted, 0);
      expect(_scopeChunks(h, s.note), chunks);
      final retry = run.compact(s.note);
      expect(retry.completed, isTrue, reason: '$retry');
      expect(_deltas(h, s.note), isEmpty);
    });
  });

  group('SYNC-3-2: nothing a device cannot read is lost', () {
    harnessTest('① a fmt 2 chunk in the scope → not compacted (no commit, no '
        'delete); a device with sync.deferredFrom does not compact', (
      h,
      async,
    ) {
      final s = _noteScope(h, strokes: 2);
      final newer = _raw(
        const [],
        s.note,
        format: 2,
        payload: Uint8List.fromList([2, 0, 1]),
      );
      h.server.commitRaw(_uid, [newer]);
      final chunks = _scopeChunks(h, s.note);
      final run = _Run(h, h.device('X', signedIn: false));
      expect(run.compact(s.note).skipped, CompactionSkip.newerFormat);
      expect(run.link.callCount(FakeOp.commit), 0);
      expect(run.link.callCount(FakeOp.delete), 0);
      expect(_scopeChunks(h, s.note), chunks);

      final other = _Run(h, s.a);
      final deferred = other.compact(
        SyncScopes.library,
        deferredFrom: const ServerCursor(1),
      );
      expect(deferred.skipped, CompactionSkip.deferredFormat);
      expect(other.link.callCount(FakeOp.any), 0);
    });

    harnessTest('② a malformed chunk stays on the server; the rest is '
        'compacted', (h, async) {
      final s = _noteScope(h, strokes: 3);
      final bad = _raw(
        const [],
        s.note,
        payload: Uint8List.fromList([1, 0xff, 0xff, 0xff]),
      );
      h.server.commitRaw(_uid, [bad]);
      final before = h.server.mergedState(_uid);
      final result = _Run(h, s.a).compact(s.note);
      expect(result.completed, isTrue, reason: '$result');
      expect(result.malformed, 1);
      final deltas = _deltas(h, s.note);
      expect(deltas.map((c) => c.id), [bad.id]);
      expect(h.server.mergedState(_uid), before);
    });

    harnessTest('③ R holds a chunk this device has not received: after the '
        'originals are gone it gets the record from its own snapshot '
        '(created), converges, nothing lost', (h, async) {
      final b = h.device('B');
      final note = b.createNote('from B');
      h.settle();
      final page = b.pageIdsOf(note).single;
      final strokes = _strokes(h, b, page, 3);
      // A is not attached yet: nothing of B's is on A.
      final a = h.device('A', signedIn: false);
      h.settle();
      expect(a.doc(EntityKind.note, note), isNull);
      final run = _Run(h, a);
      expect(run.compact(note).completed, isTrue);
      expect(run.compact(SyncScopes.library).completed, isTrue);
      expect(_deltas(h, note), isEmpty);
      expect(_deltas(h, SyncScopes.library), isEmpty);
      for (final c in h.server.chunksOf(_uid)) {
        expect(c.chunk.authorNodeId, a.store.sync.deviceNodeId);
      }

      a.auth.setUser(const AuthUser(uid: _uid));
      h.settle();
      expect(a.engine.status.phase, SyncPhase.live);
      expect(a.doc(EntityKind.note, note), isNotNull);
      for (final id in strokes) {
        expect(a.doc(EntityKind.stroke, id), isNotNull, reason: id);
      }
      expect(a.engine.debug.ownChunksSkipped, 0);
      h.checkConverged([a, b]);
    });
  });

  group('in the engine (trigger, 6.13)', () {
    harnessTest('a due scope while live, foreground and nothing pending: '
        'compacted after the random wait; sync.scopeStats = {n: snapshot '
        'chunks, c: now}', (h, async) {
      final s = _noteScope(h, config: _small);
      final b = h.device('B');
      h.settle();
      expect(_deltas(h, s.note).length, greaterThanOrEqualTo(6));
      final before = h.server.mergedState(_uid);
      h.elapse(const Duration(minutes: 2));
      h.settle();
      expect(_deltas(h, s.note), isEmpty);
      final snapshots = _scopeChunks(h, s.note);
      expect(snapshots, isNotEmpty);
      expect(
        snapshots.every((c) => c.authorNodeId == s.a.store.sync.deviceNodeId),
        isTrue,
      );
      expect(h.server.mergedState(_uid), before);
      final stats = ScopeStats.decode(s.a.store.meta[MetaKeys.scopeStats]);
      expect(stats.countOf(s.note), snapshots.length);
      expect(stats.lastCompactedOf(s.note), greaterThan(0));
      expect(s.a.engine.debug.ownChunksSkipped, greaterThan(0));

      // Not again within 24 h, even with new chunks.
      _strokes(h, s.a, s.page, 6, seed: 50);
      h.elapse(const Duration(minutes: 3));
      h.settle();
      expect(_deltas(h, s.note), hasLength(6));
      h.checkConverged([s.a, b]);
    });

    harnessTest('disabled: never compacted', (h, async) {
      final off = h.device(
        'Off',
        config: const SyncConfig(
          compaction: CompactionConfig(enabled: false, minChunksPerScope: 5),
        ),
      );
      final note = off.createNote('disabled');
      h.settle();
      _strokes(h, off, off.pageIdsOf(note).single, 6);
      h.elapse(const Duration(minutes: 3));
      h.settle();
      expect(_deltas(h, note).length, greaterThanOrEqualTo(7));
    });

    harnessTest('in the background: not compacted until foreground again', (
      h,
      async,
    ) {
      final bg = h.device('Bg', config: _small);
      h.settle();
      bg.engine.setLifecycle(SyncLifecycle.background);
      final note = bg.createNote('background');
      h.settle();
      _strokes(h, bg, bg.pageIdsOf(note).single, 6);
      h.elapse(const Duration(minutes: 3));
      h.settle();
      expect(_deltas(h, note).length, greaterThanOrEqualTo(7));
      bg.engine.setLifecycle(SyncLifecycle.foreground);
      h.settle();
      h.elapse(const Duration(minutes: 3));
      h.settle();
      expect(_deltas(h, note), isEmpty);
    });

    harnessTest('with an upload pending (quarantined) the device does not '
        'compact', (h, async) {
      final a = h.device('A', config: _small);
      final note = a.createNote('N');
      h.settle();
      final page = a.pageIdsOf(note).single;
      _strokes(h, a, page, 6);
      final bad = a.addStroke(page, seed: 77, points: 10);
      a.link.rejectCommitsWhere(
        (chunk) => ChunkCodec.decode(chunk.payload).any((r) => r.ref.id == bad),
        SyncErrorCode.invalidArgument,
      );
      h.settle();
      expect(a.engine.status.pendingUploads, 1);
      h.elapse(const Duration(minutes: 3));
      h.settle();
      expect(_deltas(h, note).length, greaterThanOrEqualTo(7));
    });

    harnessTest('a device that saw a newer chunk format (sync.deferredFrom) '
        'does not compact', (h, async) {
      final a = h.device('A', config: _small);
      final note = a.createNote('N');
      h.settle();
      h.server.commitRaw(_uid, [
        _raw(
          const [],
          SyncScopes.library,
          format: 2,
          payload: Uint8List.fromList([2, 0, 0]),
        ),
      ]);
      h.settle();
      expect(a.store.meta[MetaKeys.deferredFrom], isNotNull);
      _strokes(h, a, a.pageIdsOf(note).single, 6);
      h.elapse(const Duration(minutes: 3));
      h.settle();
      expect(_deltas(h, note).length, greaterThanOrEqualTo(7));
    });
  });
}

/// Every stroke in [ids] exists on every device.
void expectNoStrokeLost(Iterable<TestDevice> devices, Iterable<String> ids) {
  for (final d in devices) {
    for (final id in ids) {
      expect(d.doc(EntityKind.stroke, id), isNotNull, reason: '${d.name}: $id');
    }
  }
}
