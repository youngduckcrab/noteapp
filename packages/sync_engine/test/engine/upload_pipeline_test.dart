// UploadPipeline.runOnce (6.5.2–6.5.6, 6.2.5 K4) on the fake server and fake local store,
// all in virtual time.
import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/src/codec/chunk_codec.dart';
import 'package:sync_engine/src/engine/upload_pipeline.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import '../support/delegating_sync_store.dart';
import '../support/fake_time.dart';
import '../support/local_writes.dart';

final DateTime start = DateTime.utc(2026, 11, 1, 9);
const String node = 'a1a1a1a1a1a1a1a1';
const String uid = 'user-1';

final class Rig {
  Rig(this.async, {this.config = const SyncConfig()}) {
    base = async.getClock(start);
    server = FakeSyncServer(clock: base);
    store = FakeLocalStore(
      nodeId: node,
      clock: Clock(() => base.now().add(storeOffset)),
      ownerId: uid,
    );
    sync = DelegatingSyncStore(store.sync);
    backend = server.connect(uid: uid, link: link);
    pipeline = UploadPipeline(
      sync: sync,
      backend: backend,
      config: config,
      serverNowMillis: () =>
          serverNowOverride ?? base.now().millisecondsSinceEpoch,
      refreshSession: () async {
        refreshes++;
        if (failRefresh) {
          throw const SyncBackendException(
            SyncErrorCode.unauthenticated,
            'refresh failed',
          );
        }
      },
      isClockBlocked: () => clockBlocked,
      onPurgesCommitted: (purges) async => committedPurges.addAll(purges),
      onScopesCommitted: scopesCommitted.add,
      onPushNeeded: () => pushNeeded++,
    );
  }

  final FakeAsync async;
  final SyncConfig config;
  late final Clock base;
  late final FakeSyncServer server;
  late final FakeLocalStore store;
  late final DelegatingSyncStore sync;
  final FakeNetworkLink link = FakeNetworkLink();
  late final FakeSyncBackend backend;
  late final UploadPipeline pipeline;

  Duration storeOffset = Duration.zero;
  int? serverNowOverride;
  bool noSample = false;
  bool clockBlocked = false;
  bool failRefresh = false;
  int refreshes = 0;
  int pushNeeded = 0;
  final List<PurgeRecord> committedPurges = [];

  /// onScopesCommitted calls, one per successful commit group.
  final List<Set<String>> scopesCommitted = [];

  PushResult push() => runFake(async, pipeline.runOnce());

  /// Every record on the server, chunk by chunk in (serverTime, id) order.
  List<SyncRecord> serverRecords() => [
    for (final c in server.chunksOf(uid)) ...ChunkCodec.decode(c.chunk.payload),
  ];

  Set<EntityRef> serverRefs() => {for (final r in serverRecords()) r.ref};

  Set<String> pendingIds() => {for (final e in store.outbox) e.entityId};

  UpsertRecord local(EntityKind kind, String id) =>
      UpsertRecord.fromVersioned(store.rows[EntityRef(kind, id)]!);
}

void withRig(
  void Function(Rig r) body, {
  SyncConfig config = const SyncConfig(),
}) {
  fakeAsync((async) => body(Rig(async, config: config)), initialTime: start);
}

void main() {
  test('commits the pending entries in scope chunks and acknowledges them', () {
    withRig((r) {
      r.store.localWrite([
        noteWrite('n1'),
        pageWrite('p1', 'n1'),
        strokeWrite('s1', 'p1'),
      ]);
      final result = r.push();
      expect(result.succeeded, isTrue, reason: '$result');
      expect(result.commits, 1);
      expect(result.chunksSent, 2);
      expect(result.recordsSent, 3);
      expect(result.acked, 3);
      expect(result.hasMore, isFalse);
      expect(r.store.outbox, isEmpty);
      final chunks = r.server.chunksOf(uid).map((c) => c.chunk).toList();
      expect(chunks.map((c) => c.scope).toSet(), {'lib', 'n1'});
      expect(chunks.map((c) => c.serverTime).toSet(), hasLength(1));
      expect(chunks.every((c) => c.authorNodeId == node), isTrue);
      expect(
        r.serverRecords(),
        unorderedEquals([
          r.local(EntityKind.note, 'n1'),
          r.local(EntityKind.page, 'p1'),
          r.local(EntityKind.stroke, 's1'),
        ]),
      );
      expect(r.push().commits, 0, reason: 'nothing left');
    });
  });

  test('an entry rewritten while its commit is in flight stays pending', () {
    withRig((r) {
      r.store.localWrite([noteWrite('n1')]);
      final sent = r.store.outbox.single;
      final future = r.pipeline.runOnce();
      r.async.elapse(const Duration(milliseconds: 20));
      r.store.localWrite([
        noteWrite('n1', title: 'renamed', fields: const {'title'}),
      ]);
      final result = runFake(r.async, future);
      expect(result.commits, 1);
      final left = r.store.outbox.single;
      expect(left.seq, sent.seq);
      expect(left.rev, sent.rev + 1);
      r.push();
      expect(r.store.outbox, isEmpty);
      final notes = r.serverRecords().whereType<UpsertRecord>().toList();
      expect(notes.last.doc.json['title'], 'renamed');
    });
  });

  test(
    'entries whose row is gone are acknowledged without sending (ackOnly)',
    () {
      withRig((r) {
        r.store.localWrite([noteWrite('n1'), noteWrite('n2')]);
        r.sync.hiddenRows.add(const EntityRef(EntityKind.note, 'n2'));
        final result = r.push();
        expect(result.acked, 2);
        expect(result.recordsSent, 1);
        expect(r.serverRefs(), {const EntityRef(EntityKind.note, 'n1')});
        expect(r.store.outbox, isEmpty);

        r.store.localWrite([noteWrite('n3')]);
        r.sync.hiddenRows.add(const EntityRef(EntityKind.note, 'n3'));
        final only = r.push();
        expect(only.commits, 0);
        expect(only.acked, 1);
        expect(r.store.outbox, isEmpty);
      });
    },
  );

  test('purge entries go as PurgeRecords and reach the purged set after the '
      'commit only', () {
    withRig((r) {
      r.store.localWrite([noteWrite('n1'), pageWrite('p1', 'n1')]);
      r.push();
      r.store.localPurge(
        const EntityRef(EntityKind.note, 'n1'),
        group: const [],
      );
      final purge = r.store.outbox.single;
      expect(purge.op, OutboxOp.purge);

      r.link.failNext(const FakeNetworkError(), op: FakeOp.commit);
      expect(r.push().errorCode, SyncErrorCode.network);
      expect(r.committedPurges, isEmpty);

      final result = r.push();
      expect(result.succeeded, isTrue);
      final sent = r.serverRecords().whereType<PurgeRecord>().single;
      expect(sent, PurgeRecord(purge.ref, purge.hlc));
      expect(r.server.chunksOf(uid).last.chunk.scope, 'lib');
      expect(r.committedPurges, [sent]);
      expect(r.store.outbox, isEmpty);
    });
  });

  test('rows owned by another account are quarantined; the rest is sent', () {
    withRig((r) {
      r.store.localWrite([noteWrite('n1', owner: 'local'), noteWrite('n2')]);
      final result = r.push();
      expect(result.succeeded, isTrue);
      expect(r.serverRefs(), {const EntityRef(EntityKind.note, 'n2')});
      expect(r.pipeline.quarantined, {
        const EntityRef(EntityKind.note, 'n1'): SyncIssueCode.foreignOwnerData,
      });
      expect(r.pipeline.quarantinedCount, 1);
      expect(r.pendingIds(), {'n1'});
      expect(r.push().commits, 0, reason: 'same rev stays quarantined');

      // A new rev releases it; owned by the account now, it is sent.
      r.store.localWrite([
        noteWrite('n1', fields: const {'ownerId'}),
      ]);
      expect(r.push().commits, 1);
      expect(r.pipeline.quarantinedCount, 0);
      expect(r.store.outbox, isEmpty);
    });
  });

  test('several commits: a failure stops after the acknowledged ones', () {
    withRig((r) {
      r.store.localWrite([
        noteWrite('n1'),
        pageWrite('p1', 'n1'),
        noteWrite('n2'),
        pageWrite('p2', 'n2'),
        noteWrite('n3'),
        pageWrite('p3', 'n3'),
      ]);
      var reject = true;
      r.link.rejectCommitsWhere(
        (c) => reject && c.scope == 'n2',
        SyncErrorCode.unavailable,
      );
      final result = r.push();
      expect(result.errorCode, SyncErrorCode.unavailable);
      expect(result.commits, 2, reason: "commits: 'lib', 'n1', then 'n2'");
      expect(result.acked, 4);
      expect(r.pendingIds(), {'p2', 'p3'});
      expect(r.serverRefs().map((ref) => ref.id).toSet(), {
        'n1',
        'n2',
        'n3',
        'p1',
      });

      reject = false;
      final retry = r.push();
      expect(retry.succeeded, isTrue);
      expect(retry.commits, 2);
      expect(r.store.outbox, isEmpty);
    }, config: const SyncConfig(maxChunksPerCommit: 1));
  });

  test('a lost ack is retried with the same chunk ids: no duplicates', () {
    withRig((r) {
      r.store.localWrite([noteWrite('n1'), pageWrite('p1', 'n1')]);
      r.link.failNext(const FakeAckLost(), op: FakeOp.commit);
      final lost = r.push();
      expect(lost.errorCode, SyncErrorCode.network);
      expect(r.store.outbox, hasLength(2));
      final ids = [for (final c in r.server.chunksOf(uid)) c.chunk.id];
      expect(ids, hasLength(2));
      final retry = r.push();
      expect(retry.succeeded, isTrue);
      expect(r.store.outbox, isEmpty);
      expect(
        [for (final c in r.server.chunksOf(uid)) c.chunk.id]..sort(),
        [...ids]..sort(),
      );
      expect(r.serverRecords(), hasLength(2));
    });
  });

  group('invalidArgument (6.5.6)', () {
    bool holds(ChunkWrite c, String id) =>
        ChunkCodec.decode(c.payload).any((rec) => rec.ref.id == id);

    test('bisects down to the rejected record, quarantines it and sends the '
        'rest', () {
      withRig((r) {
        r.store.localWrite([
          noteWrite('n1'),
          pageWrite('p1', 'n1'),
          for (var i = 0; i < 6; i++) strokeWrite('s$i', 'p1', seed: i),
        ]);
        r.link.rejectCommitsWhere(
          (c) => holds(c, 's3'),
          SyncErrorCode.invalidArgument,
        );
        final result = r.push();
        expect(result.succeeded, isTrue, reason: '$result');
        expect(r.pipeline.quarantined, {
          const EntityRef(EntityKind.stroke, 's3'):
              SyncIssueCode.rejectedByServer,
        });
        expect(r.pendingIds(), {'s3'});
        expect(r.serverRefs().map((ref) => ref.id).toSet(), {
          'n1', 'p1', 's0', 's1', 's2', 's4', 's5', //
        });
        final again = r.push();
        expect(again.commits, 0);
        expect(again.succeeded, isTrue);
      });
    });

    test('later pushes read past a quarantined entry (afterSeq)', () {
      withRig((r) {
        r.store.localWrite([noteWrite('bad')]);
        r.store.localWrite([noteWrite('n1')]);
        r.store.localWrite([noteWrite('n2')]);
        r.link.rejectCommitsWhere(
          (c) => holds(c, 'bad'),
          SyncErrorCode.invalidArgument,
        );
        final first = r.push();
        expect(first.succeeded, isTrue);
        expect(first.commits, 0);
        expect(first.hasMore, isTrue);
        expect(r.pipeline.quarantinedCount, 1);
        final second = r.push();
        expect(second.commits, 1);
        expect(r.pendingIds(), {'bad', 'n2'});
        r.push();
        expect(r.pendingIds(), {'bad'});
        expect(r.serverRefs().map((ref) => ref.id).toSet(), {'n1', 'n2'});
      }, config: const SyncConfig(maxEntriesPerPush: 1));
    });

    test('runs out of bisect steps → the error is returned for backoff', () {
      withRig((r) {
        r.store.localWrite([
          noteWrite('n1'),
          pageWrite('p1', 'n1'),
          for (var i = 0; i < 4; i++) strokeWrite('s$i', 'p1', seed: i),
        ]);
        r.link.rejectCommitsWhere(
          (c) => holds(c, 's2'),
          SyncErrorCode.invalidArgument,
        );
        final result = r.push();
        expect(result.errorCode, SyncErrorCode.invalidArgument);
        expect(r.pipeline.quarantinedCount, 0);
        expect(r.pendingIds(), containsAll(['s2']));
      }, config: const SyncConfig(maxBisectSteps: 1));
    });
  });

  group('unauthenticated (6.5.4)', () {
    test('refreshes once and retries at once', () {
      withRig((r) {
        r.store.localWrite([noteWrite('n1')]);
        r.link.failNext(
          const FakeErrorCode(SyncErrorCode.unauthenticated),
          op: FakeOp.commit,
        );
        final result = r.push();
        expect(result.succeeded, isTrue);
        expect(r.refreshes, 1);
        expect(r.store.outbox, isEmpty);
      });
    });

    test('a second unauthenticated or a failed refresh → reauthRequired', () {
      withRig((r) {
        r.store.localWrite([noteWrite('n1')]);
        r.link.failNext(
          const FakeErrorCode(SyncErrorCode.unauthenticated),
          op: FakeOp.commit,
          times: 2,
        );
        final twice = r.push();
        expect(twice.reauthRequired, isTrue);
        expect(twice.errorCode, SyncErrorCode.unauthenticated);
        expect(r.refreshes, 1);

        r.failRefresh = true;
        r.link.failNext(
          const FakeErrorCode(SyncErrorCode.unauthenticated),
          op: FakeOp.commit,
        );
        final refused = r.push();
        expect(refused.reauthRequired, isTrue);
        expect(r.refreshes, 2);
        expect(r.store.outbox, hasLength(1));
      });
    });
  });

  group('clock (6.2.5)', () {
    test('K4: a record past serverNow + 24 h − 1 min stays local, the rest is '
        'sent; it goes once the server time catches up', () {
      withRig((r) {
        r.store.localWrite([noteWrite('ok')]);
        r.storeOffset = const Duration(hours: 48);
        r.store.localWrite([noteWrite('future')]);
        final futureMillis = r
            .store
            .rows[const EntityRef(EntityKind.note, 'future')]!
            .versions
            .max
            .millis;
        final first = r.push();
        expect(first.succeeded, isTrue);
        expect(r.serverRefs().map((ref) => ref.id).toSet(), {'ok'});
        expect(r.pendingIds(), {'future'});
        final sendableAt =
            futureMillis -
            const Duration(hours: 24).inMilliseconds +
            const Duration(minutes: 1).inMilliseconds;
        expect(first.heldUntilServerMillis, sendableAt);
        expect(r.pipeline.clockHeld, {
          const EntityRef(EntityKind.note, 'future'): sendableAt,
        });
        expect(r.pipeline.quarantinedCount, 0);

        r.serverNowOverride = sendableAt - 1;
        expect(r.push().commits, 0);
        expect(r.pendingIds(), {'future'});

        r.serverNowOverride = sendableAt;
        final late = r.push();
        expect(late.commits, 1);
        expect(late.heldUntilServerMillis, isNull);
        expect(r.store.outbox, isEmpty);
        expect(r.pipeline.clockHeld, isEmpty);
      });
    });

    test('no server-time sample or a blocked clock → no push', () {
      fakeAsync((async) {
        final base = async.getClock(start);
        final server = FakeSyncServer(clock: base);
        final store = FakeLocalStore(nodeId: node, clock: base, ownerId: uid);
        var blocked = false;
        int? sample;
        final pipeline = UploadPipeline(
          sync: store.sync,
          backend: server.connect(uid: uid, link: FakeNetworkLink()),
          config: const SyncConfig(),
          serverNowMillis: () => sample,
          refreshSession: () async {},
          isClockBlocked: () => blocked,
        );
        store.localWrite([noteWrite('n1')]);
        expect(
          runFake(async, pipeline.runOnce()).skipped,
          PushSkip.noClockSample,
        );
        sample = base.now().millisecondsSinceEpoch;
        blocked = true;
        expect(
          runFake(async, pipeline.runOnce()).skipped,
          PushSkip.clockBlocked,
        );
        expect(server.chunksOf(uid), isEmpty);
        expect(store.outbox, hasLength(1));
        blocked = false;
        expect(runFake(async, pipeline.runOnce()).commits, 1);
      }, initialTime: start);
    });
  });

  test('commitRepairs schedules a push and the repair entries are sent', () {
    withRig((r) {
      r.store.localWrite([noteWrite('n1', folderId: 'f-gone')]);
      r.push();
      final row = r.store.rows[const EntityRef(EntityKind.note, 'n1')]!;
      final repaired = EntityJson.decode(EntityKind.note, {
        ...row.entity.toJson(),
        'folderId': null,
        'sortKey': 'a5',
      });
      runFake(
        r.async,
        r.pipeline.commitRepairs([
          (entity: repaired, fields: const {'folderId', 'sortKey'}),
        ]),
      );
      expect(r.pushNeeded, 1);
      expect(r.store.outbox.single.changedFields, {'folderId', 'sortKey'});
      runFake(r.async, r.pipeline.commitRepairs(const []));
      expect(r.pushNeeded, 1, reason: 'nothing to repair');
      r.push();
      final last = r.serverRecords().whereType<UpsertRecord>().last;
      expect(last.doc.json['folderId'], isNull);
      expect(last.doc.json['sortKey'], 'a5');
      expect(r.store.outbox, isEmpty);
    });
  });

  test('a full read reports hasMore', () {
    withRig((r) {
      r.store.localWrite([noteWrite('n1'), noteWrite('n2'), noteWrite('n3')]);
      final first = r.push();
      expect(first.acked, 2);
      expect(first.hasMore, isTrue);
      final second = r.push();
      expect(second.acked, 1);
      expect(second.hasMore, isFalse);
    }, config: const SyncConfig(maxEntriesPerPush: 2));
  });

  test('a record over the hard limit is quarantined as entityTooLarge', () {
    withRig(
      (r) {
        r.store.localWrite([
          noteWrite('n1'),
          pageWrite('p1', 'n1'),
          strokeWrite('big', 'p1', points: 2000),
          strokeWrite('small', 'p1', points: 5),
        ]);
        final result = r.push();
        expect(result.succeeded, isTrue);
        expect(r.pipeline.quarantined, {
          const EntityRef(EntityKind.stroke, 'big'):
              SyncIssueCode.entityTooLarge,
        });
        expect(r.pendingIds(), {'big'});
        expect(r.serverRefs().map((ref) => ref.id).toSet(), {
          'n1',
          'p1',
          'small',
        });
      },
      config: const SyncConfig(
        chunkSoftLimitBytes: 4000,
        chunkHardLimitBytes: 8000,
      ),
    );
  });

  test('an error thrown by acknowledge without retry is returned; the retry '
      'sends the same chunk again', () {
    withRig((r) {
      r.store.localWrite([noteWrite('n1')]);
      r.store.failNextWrites(1);
      final failed = r.push();
      expect(failed.error, isA<StateError>());
      expect(failed.commits, 1);
      expect(r.store.outbox, hasLength(1));
      final retry = r.push();
      expect(retry.succeeded, isTrue);
      expect(r.store.outbox, isEmpty);
      expect(r.server.chunksOf(uid), hasLength(1));
    });
  });
  group('onScopesCommitted: handwriting-only chunks are no edit (2nd round, '
      'SYNC-M3)', () {
    /// Note n1 with page p1 and stroke s1, sent; the calls so far are dropped.
    void seed(Rig r) {
      r.store.localWrite([
        noteWrite('n1'),
        pageWrite('p1', 'n1'),
        strokeWrite('s1', 'p1'),
      ]);
      r.push();
      expect(r.scopesCommitted.expand((s) => s).toSet(), {'lib', 'n1'});
      r.scopesCommitted.clear();
    }

    /// The record kinds of each n1 chunk on the server, in commit order.
    List<Set<EntityKind>> n1Chunks(Rig r) => [
      for (final c in r.server.chunksOf(uid))
        if (c.chunk.scope == 'n1')
          {for (final rec in ChunkCodec.decode(c.chunk.payload)) rec.ref.kind},
    ];

    test('a commit carrying only a handwriting result → its scope is not '
        'reported', () {
      withRig((r) {
        seed(r);
        r.store.localWrite([
          handwritingWrite('p1', 'n1', strokeIds: const ['s1']),
        ]);
        final result = r.push();
        expect(result.succeeded, isTrue, reason: '$result');
        expect(r.store.outbox, isEmpty);
        expect(n1Chunks(r).last, {EntityKind.handwriting});
        expect(r.scopesCommitted.single, isNot(contains('n1')));
      });
    });

    test('a stroke and a handwriting result in one chunk → the scope is '
        'reported', () {
      withRig((r) {
        seed(r);
        r.store.localWrite([
          strokeWrite('s2', 'p1'),
          handwritingWrite('p1', 'n1', strokeIds: const ['s1', 's2']),
        ]);
        r.push();
        expect(n1Chunks(r).last, {EntityKind.stroke, EntityKind.handwriting});
        expect(r.scopesCommitted.single, contains('n1'));
      });
    });

    test('a handwriting tail chunk and a stroke chunk in one commit group → '
        'the scope is reported (for the stroke chunk)', () {
      withRig((r) {
        seed(r);
        r.store.localWrite([
          strokeWrite('s2', 'p1'),
          strokeWrite('s3', 'p1'),
          handwritingWrite('p1', 'n1', strokeIds: const ['s2', 's3']),
        ]);
        final result = r.push();
        expect(result.commits, 1);
        final chunks = n1Chunks(r);
        expect(chunks.sublist(chunks.length - 2), [
          {EntityKind.stroke},
          {EntityKind.handwriting},
        ]);
        expect(r.scopesCommitted.single, contains('n1'));
      }, config: const SyncConfig(maxRecordsPerChunk: 2));
    });

    test('the same chunks in two commit groups → only the stroke group '
        'reports the scope', () {
      withRig(
        (r) {
          seed(r);
          r.store.localWrite([
            strokeWrite('s2', 'p1'),
            strokeWrite('s3', 'p1'),
            handwritingWrite('p1', 'n1', strokeIds: const ['s2', 's3']),
          ]);
          final result = r.push();
          expect(result.commits, greaterThanOrEqualTo(2));
          final withN1 = [
            for (final scopes in r.scopesCommitted)
              if (scopes.contains('n1')) scopes,
          ];
          expect(withN1, hasLength(1), reason: '${r.scopesCommitted}');
          expect(n1Chunks(r).last, {EntityKind.handwriting});
        },
        config: const SyncConfig(maxRecordsPerChunk: 2, maxChunksPerCommit: 1),
      );
    });
  });
}
