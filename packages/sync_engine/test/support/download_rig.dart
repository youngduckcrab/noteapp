// Receiving rig (test/ only): device A runs a DownloadPipeline on the fake server; device B
// writes through its own FakeLocalStore + UploadPipeline (real HLCs and field versions) or
// chunks are committed raw. Everything in virtual time.
import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/src/codec/chunk_codec.dart';
import 'package:sync_engine/src/codec/chunk_id.dart';
import 'package:sync_engine/src/engine/download_pipeline.dart';
import 'package:sync_engine/src/engine/upload_pipeline.dart';
import 'package:sync_engine/src/merge/merge_recorder.dart';
import 'package:sync_engine/src/merge/page_resurrection.dart';
import 'package:sync_engine/src/merge/purged_set.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import 'delegating_sync_store.dart';
import 'fake_time.dart';

final DateTime start = DateTime.utc(2026, 11, 1, 9);
const String nodeA = 'a1a1a1a1a1a1a1a1';
const String nodeB = 'b2b2b2b2b2b2b2b2';
const String nodeC = 'c3c3c3c3c3c3c3c3';
const String uid = 'user-1';

final class DownloadRig {
  DownloadRig(
    this.async, {
    this.config = const SyncConfig(),
    this.codecFormat = ChunkCodec.formatVersion,
  }) {
    base = async.getClock(start);
    server = FakeSyncServer(clock: base);
    a = FakeLocalStore(
      nodeId: nodeA,
      clock: Clock(() => base.now().add(aOffset)),
      ownerId: uid,
    );
    sync = DelegatingSyncStore(a.sync);
    backend = server.connect(uid: uid, link: link);
    purged = PurgedSet(sync: sync, localChanges: a.localChanges);
    aPush = UploadPipeline(
      sync: sync,
      backend: backend,
      config: config,
      serverNowMillis: () => base.now().millisecondsSinceEpoch,
      refreshSession: () async {},
      onPurgesCommitted: (p) => purged.addCommitted(p, nowMillis: wallMillis),
      onPushNeeded: () => pushNeeded++,
    );
    resurrection = PageResurrection(sync: sync);
    pipeline = newPipeline();
    b = FakeLocalStore(
      nodeId: nodeB,
      clock: Clock(() => base.now().add(bOffset)),
      ownerId: uid,
    );
    bPush = UploadPipeline(
      sync: b.sync,
      backend: server.connect(uid: uid, link: FakeNetworkLink()),
      config: config,
      // B believes its own clock (a bad clock passes its own K4).
      serverNowMillis: () => base.now().add(bOffset).millisecondsSinceEpoch,
      refreshSession: () async {},
    );
  }

  final FakeAsync async;
  final SyncConfig config;
  final int codecFormat;
  late final Clock base;
  late final FakeSyncServer server;
  final FakeNetworkLink link = FakeNetworkLink();
  late final FakeSyncBackend backend;
  late final FakeLocalStore a, b;
  late final DelegatingSyncStore sync;
  late final PurgedSet purged;
  late final UploadPipeline aPush, bPush;
  late final PageResurrection resurrection;
  late DownloadPipeline pipeline;

  Duration aOffset = Duration.zero, bOffset = Duration.zero;

  /// serverNowMillis of A's pipeline; null → base clock. [noSample] → null.
  int? serverNowOverride;
  bool noSample = false;

  int pushNeeded = 0;
  final List<RemoteChunk> ownChunks = [];
  final List<List<PurgeRecord>> guarded = [];
  final List<Map<EntityRef, MergeOutcomeKind>> groups = [];
  final List<PageRepair> restored = [];

  int get wallMillis => base.now().add(aOffset).millisecondsSinceEpoch;

  DownloadPipeline newPipeline({int? codecFormat}) => DownloadPipeline(
    sync: sync,
    backend: backend,
    config: config,
    purged: purged,
    wallMillis: () => wallMillis,
    serverNowMillis: () => noSample
        ? null
        : serverNowOverride ?? base.now().millisecondsSinceEpoch,
    onOwnChunk: ownChunks.add,
    purgeGuard: (p) async => guarded.add(p),
    afterGroup: (outcomes) async {
      groups.add(outcomes);
      final repairs = await resurrection.check(outcomes);
      if (repairs.isEmpty) return;
      await aPush.commitRepairs([for (final r in repairs) r.write]);
      restored.addAll(repairs);
    },
    codecFormat: codecFormat ?? this.codecFormat,
  );

  T run<T>(Future<T> future) => runFake(async, future);

  /// load() of the pipeline and the purged set (connect, 6.6.1).
  void connect() {
    run(purged.load());
    run(pipeline.load());
  }

  ApplyResult catchUp() {
    final r = run(pipeline.catchUp());
    expect(r.succeeded, isTrue, reason: '$r');
    return r;
  }

  ApplyResult apply(List<RemoteChunk> chunks) =>
      run(pipeline.applyChunks(chunks));

  ApplyResult release() => run(pipeline.releaseHeld());

  /// B pushes its whole outbox (one or more pushes).
  void pushB() {
    while (true) {
      final r = run(bPush.runOnce());
      expect(r.succeeded, isTrue, reason: '$r');
      if (!r.hasMore) return;
    }
  }

  PushResult pushA() => run(aPush.runOnce());

  /// Every chunk on the server, (serverTime, id) order.
  List<RemoteChunk> serverChunks() => [
    for (final c in server.chunksOf(uid)) c.chunk,
  ];

  /// Commits [records] as one raw chunk; returns it as stored.
  RemoteChunk commit(
    List<SyncRecord> records, {
    String author = nodeB,
    String scope = 'lib',
    ChunkKind kind = ChunkKind.delta,
    int format = ChunkCodec.formatVersion,
  }) {
    final payload = ChunkCodec.encode(records);
    final id = chunkIdOf(author, payload);
    server.commitRaw(uid, [
      ChunkWrite(
        id: id,
        scope: scope,
        authorNodeId: author,
        recordCount: records.length,
        format: format,
        kind: kind,
        maxHlc: ChunkCodec.maxHlcOf(records).toString(),
        payload: payload,
      ),
    ]);
    return serverChunks().lastWhere((c) => c.id == id);
  }

  static UpsertRecord recordOf(
    FakeLocalStore store,
    EntityKind kind,
    String id,
  ) => UpsertRecord.fromVersioned(store.rows[EntityRef(kind, id)]!);

  /// A local edit of [changes] on an existing row of [store].
  static void edit(
    FakeLocalStore store,
    EntityKind kind,
    String id,
    Map<String, Object?> changes,
  ) {
    final row = store.rows[EntityRef(kind, id)]!;
    store.localWrite([
      FakeLocalWrite(kind, {
        ...SyncDoc.fromEntity(row.entity).json,
        ...changes,
      }, changedFields: changes.keys.toSet()),
    ]);
  }

  bool hasRow(EntityKind kind, String id) =>
      a.rows.containsKey(EntityRef(kind, id));

  /// A's row equals B's (entity JSON without Note.updatedAt, and field versions).
  void expectSameRow(EntityKind kind, String id) {
    final ref = EntityRef(kind, id);
    expect(canonicalOf(a.rows[ref]), canonicalOf(b.rows[ref]), reason: '$ref');
  }

  static Object? canonicalOf(VersionedEntity? row) {
    if (row == null) return null;
    final json = Map.of(SyncDoc.fromEntity(row.entity).json);
    if (row.entity.kind == EntityKind.note) json.remove('updatedAt');
    return {'entity': json, 'versions': row.versions.toJson()};
  }
}

void withDownloadRig(
  void Function(DownloadRig r) body, {
  SyncConfig config = const SyncConfig(),
  int codecFormat = ChunkCodec.formatVersion,
}) {
  fakeAsync(
    (async) =>
        body(DownloadRig(async, config: config, codecFormat: codecFormat)),
    initialTime: start,
  );
}
