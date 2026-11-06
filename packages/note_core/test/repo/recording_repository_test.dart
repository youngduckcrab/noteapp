// CORE T30 — RecordingRepository on SQLite (m5-7/02-core 6.6) beyond the shared body:
// idempotence per id against the stored row (the arguments lose; a deleted row stays), the
// outbox ({*} for a new row, {title}, {deletedAt}, noteId hint), strokes keep their
// recordingId after a delete (R-7), a purged note → EntityNotFoundException, the owner
// filter, remote recordings in the same list / watch, watch emissions only on a visible
// change, audioBytesOf from the asset rows (bytes need not be on this device).
@TestOn('vm')
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:note_core/src/storage/drift_recording_repository.dart';
import 'package:note_core/testing.dart' show newerVersionWinsPolicy;
import 'package:test/test.dart';

import '../storage/storage_support.dart';
import '../sync/support/sync_support.dart';

void main() {
  late DriftNoteStore store;
  late Note n;
  late Asset audio;

  setUp(() async {
    store = await openStore();
    n = await store.library.createNote(title: '녹음');
    audio = await store.assets.put(
      Uint8List.fromList(List.filled(64, 7)),
      type: AssetType.audio,
      mimeType: 'audio/webm',
    );
  });
  tearDown(() => store.close());

  RecordingRepository repo() => store.recordings;

  Future<Recording> create(
    String id, {
    NoteId? noteId,
    AssetId? assetId,
    int durationMs = 3000,
    int startedAt = 500,
    String? title,
  }) => repo().createRecording(
    id: id,
    noteId: noteId ?? n.id,
    assetId: assetId ?? audio.id,
    durationMs: durationMs,
    startedAt: startedAt,
    title: title,
  );

  Future<OutboxEntry?> entryOf(String id) async =>
      (await store.sync.pendingChanges(limit: 100000))
          .where((e) => e.entityId == id)
          .firstOrNull;

  Future<void> ackAll() async => store.sync.acknowledge([
    for (final e in await store.sync.pendingChanges(limit: 100000)) e.ack,
  ]);

  test('the real store serves the recordings repository', () {
    expect(repo(), isA<DriftRecordingRepository>());
  });

  test(
    'a new row: {*} with the noteId hint, field versions = one stamp',
    () async {
      final r = await create('rec-1', title: '1교시');
      final e = (await entryOf('rec-1'))!;
      expect((e.kind, e.op), (EntityKind.recording, OutboxOp.upsert));
      expect(e.changedFields, {kAllFields});
      expect((e.noteId, e.pageId), (n.id, null));
      expect(e.hlc, r.version);
      final v = (await store.sync.readVersioned([
        const EntityRef(EntityKind.recording, 'rec-1'),
      ])).single!;
      expect(v.versions, EntityFieldVersions(r.version!));
      expect(v.entity, r);
    },
  );

  test(
    'rename → {title}; delete → {deletedAt}; same title writes nothing',
    () async {
      await create('rec-1', title: 'a');
      await ackAll();
      await repo().renameRecording('rec-1', 'b');
      expect((await entryOf('rec-1'))!.changedFields, {'title'});
      await ackAll();
      await repo().renameRecording('rec-1', '  b  ');
      expect(await entryOf('rec-1'), isNull, reason: 'the same value');
      await repo().deleteRecording('rec-1');
      final e = (await entryOf('rec-1'))!;
      expect(e.changedFields, {'deletedAt'});
      expect(e.noteId, n.id);
      final row = (await repo().getRecording('rec-1'))!;
      expect((row.title, row.isDeleted), ('b', true));
    },
  );

  test(
    'idempotent: other arguments lose to the stored row and are counted',
    () async {
      final first = await create('rec-1', durationMs: 3000);
      final real = repo() as DriftRecordingRepository;
      expect(real.debugIdempotentMismatches, 0);
      await ackAll();
      final other = await store.assets.put(
        Uint8List.fromList(List.filled(10, 9)),
        type: AssetType.audio,
        mimeType: 'audio/webm',
      );
      await ackAll();
      final again = await create('rec-1', durationMs: 2990, assetId: other.id);
      expect(again, first);
      expect(real.debugIdempotentMismatches, 1);
      expect(await create('rec-1'), first);
      expect(real.debugIdempotentMismatches, 1, reason: 'same arguments');
      expect(await store.sync.pendingChanges(), isEmpty, reason: 'no write');
    },
  );

  test('a delete keeps the strokes linked to the recording (R-7)', () async {
    await create('rec-1');
    final pageId = (await store.library.getNote(n.id))!.firstPageId!;
    final linked = stroke(
      's1',
      pageId,
    ).copyWith(recordingId: 'rec-1', recordingOffsetMs: 1200);
    await store.queue.run((tx) => tx.putLocal(linked, const {kAllFields}));
    await repo().deleteRecording('rec-1');
    final row = await (store.db.select(
      store.db.strokes,
    )..where((t) => t.id.equals('s1'))).getSingle();
    expect(
      (row.recordingId, row.recordingOffsetMs, row.deletedAt),
      ('rec-1', 1200, null),
    );
  });

  test('a purged note is not found; a trashed one takes recordings', () async {
    await store.library.trashItems([NoteRef(n.id)]);
    expect((await create('rec-1')).noteId, n.id);
    await store.trash.purge([NoteRef(n.id)]);
    await expectLater(create('rec-2'), throwsA(isA<EntityNotFoundException>()));
  });

  test('another owner\'s note lists nothing', () async {
    final foreign = note('0193f1d2-7c40-7000-8000-00000000b001')
        .copyWith(ownerId: 'someone-else');
    await store.sync.applyRemote([
      upsert(foreign, remoteAfter(store)),
      upsert(
        recording('0193f1d2-7c40-7000-8000-00000000b0r1', foreign.id),
        remoteAfter(store),
      ),
    ], policy: newerVersionWinsPolicy);
    expect(await repo().recordingsOf(foreign.id), isEmpty);
    expect(await repo().audioBytesOf(foreign.id), 0);
    expect(
      await repo().getRecording('0193f1d2-7c40-7000-8000-00000000b0r1'),
      isNotNull,
      reason: 'getRecording is by id',
    );
  });

  test('remote recordings join the list and the watch; equal values are not re-sent', () async {
    final seen = <List<String>>[];
    final sub = repo()
        .watchRecordings(n.id)
        .listen((l) => seen.add([for (final r in l) r.id]));
    addTearDown(sub.cancel);
    await pumpEventQueue();
    await create('local', startedAt: 2000);
    await pumpEventQueue();
    final remote = recording('remote', n.id).copyWith(title: '원격');
    await store.sync.applyRemote([
      upsert(remote, remoteAfter(store)),
    ], policy: newerVersionWinsPolicy);
    await pumpEventQueue();
    expect(seen, [
      <String>[],
      ['local'],
      ['remote', 'local'],
    ]);
    // A recording of another note and a stroke write do not emit.
    final other = await store.library.createNote(title: 'other');
    await repo().createRecording(
      id: 'elsewhere',
      noteId: other.id,
      assetId: audio.id,
      durationMs: 1,
      startedAt: 1,
    );
    await pumpEventQueue();
    expect(seen, hasLength(3));
    final titled = (await repo().recordingsOf(n.id)).first;
    expect(titled.title, '원격');
  });

  test('audioBytesOf counts asset sizes without local bytes', () async {
    final remoteAsset = Asset(
      id: 'd' * 64,
      ownerId: kLocalOwnerId,
      type: AssetType.audio,
      mimeType: 'audio/mp4',
      size: 1000,
      createdAt: 1,
    );
    await store.sync.applyRemote([
      upsert(remoteAsset, remoteAfter(store)),
    ], policy: newerVersionWinsPolicy);
    final stored =
        (await store.sync.readVersioned([
              EntityRef(EntityKind.asset, remoteAsset.id),
            ])).single!.entity
            as Asset;
    expect(stored.hasLocalBytes, isFalse);
    await create('r1');
    await create('r2', assetId: remoteAsset.id);
    expect(await repo().audioBytesOf(n.id), 64 + 1000);
  });
}
