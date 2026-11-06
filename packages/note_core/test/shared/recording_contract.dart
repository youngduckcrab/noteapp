// Shared body (m5-7/02-core 6.6): RecordingRepository — validation, idempotence per id,
// rename / delete, order, owner filter, watch, audioBytesOf, the title key. The fake store
// runs it now (test/repo/recording_contract_fake_test.dart), the real store from CORE T30.
// Web-safe.
import 'dart:async';
import 'dart:typed_data';

import 'package:note_core/note_core.dart';
import 'package:test/test.dart';

void defineRecordingContract(FutureOr<NoteStore> Function() open) {
  late NoteStore store;
  late Note note;
  late Asset audio;
  late Asset audio2;

  setUp(() async {
    store = await open();
    note = await store.library.createNote(title: '녹음');
    audio = await store.assets.put(
      Uint8List.fromList(List.filled(100, 1)),
      type: AssetType.audio,
      mimeType: 'audio/mp4',
    );
    audio2 = await store.assets.put(
      Uint8List.fromList(List.filled(40, 2)),
      type: AssetType.audio,
      mimeType: 'audio/mp4',
    );
  });
  tearDown(() => store.close());

  Future<Recording> create(
    String id, {
    int startedAt = 1000,
    String? title,
    AssetId? assetId,
    NoteId? noteId,
    int durationMs = 5000,
  }) => store.recordings.createRecording(
    id: id,
    noteId: noteId ?? note.id,
    assetId: assetId ?? audio.id,
    durationMs: durationMs,
    startedAt: startedAt,
    title: title,
  );

  test('createRecording: the row, a ChangeBatch, getRecording', () async {
    final batches = <ChangeBatch>[];
    final sub = store.changes.listen(batches.add);
    addTearDown(sub.cancel);
    final r = await create('rec-1', title: '  1교시  ');
    expect(r.id, 'rec-1');
    expect(r.noteId, note.id);
    expect(r.assetId, audio.id);
    expect(r.durationMs, 5000);
    expect(r.startedAt, 1000);
    expect(r.title, '1교시');
    expect(r.createdAt, r.updatedAt);
    expect(r.version, isNotNull);
    expect(await store.recordings.getRecording('rec-1'), r);
    await Future<void>.delayed(Duration.zero);
    expect(
      batches
          .expand((b) => b.changes)
          .where((c) => c.kind == EntityKind.recording),
      [isA<EntityChange>().having((c) => c.id, 'id', 'rec-1')],
    );
    // The JSON always has the title key.
    expect(r.toJson().containsKey('title'), isTrue);
    expect((await create('rec-2')).toJson()['title'], isNull);
  });

  test(
    'idempotent per id: the stored row, no write, before validation',
    () async {
      final first = await create('rec-1', durationMs: 5000);
      final batches = <ChangeBatch>[];
      final sub = store.changes.listen(batches.add);
      addTearDown(sub.cancel);
      final again = await create(
        'rec-1',
        durationMs: 9999,
        assetId: audio2.id,
        title: 'other',
      );
      expect(again, first);
      // Even arguments that would fail validation return the stored row.
      expect(await create('rec-1', durationMs: -1), first);
      await store.recordings.deleteRecording('rec-1');
      final deleted = await store.recordings.getRecording('rec-1');
      expect(await create('rec-1'), deleted, reason: 'not revived');
      await Future<void>.delayed(Duration.zero);
      expect(
        batches
            .expand((b) => b.changes)
            .where((c) => c.kind == EntityKind.recording),
        hasLength(1),
        reason: 'only the delete wrote',
      );
    },
  );

  test('validation', () async {
    await expectLater(create('bad id!'), throwsArgumentError);
    await expectLater(
      create('r-n', noteId: 'missing'),
      throwsA(isA<EntityNotFoundException>()),
    );
    final pdf = await store.assets.put(
      Uint8List.fromList([1, 2, 3]),
      type: AssetType.pdf,
      mimeType: 'application/pdf',
    );
    await expectLater(create('r-a', assetId: pdf.id), throwsArgumentError);
    await expectLater(create('r-b', assetId: 'f' * 64), throwsArgumentError);
    await expectLater(create('r-c', durationMs: -1), throwsArgumentError);
    await expectLater(create('r-d', title: '가' * 101), throwsArgumentError);
    expect((await create('r-e', title: '가' * 100)).title, '가' * 100);
    expect((await create('r-f', title: '   ')).title, isNull);
    // A trashed note still takes recordings (the sound is not lost).
    await store.library.trashItems([NoteRef(note.id)]);
    expect((await create('r-g')).noteId, note.id);
  });

  test('recordingsOf / watchRecordings: active, startedAt then id', () async {
    final seen = <List<String>>[];
    final sub = store.recordings
        .watchRecordings(note.id)
        .listen((l) => seen.add([for (final r in l) r.id]));
    addTearDown(sub.cancel);
    await Future<void>.delayed(Duration.zero);
    await create('b', startedAt: 2000);
    await create('a', startedAt: 2000);
    await create('c', startedAt: 1000);
    await store.recordings.deleteRecording('a');
    await Future<void>.delayed(Duration.zero);
    expect((await store.recordings.recordingsOf(note.id)).map((r) => r.id), [
      'c',
      'b',
    ]);
    expect(seen.first, isEmpty);
    expect(seen.last, ['c', 'b']);
    // No duplicate emission for a commit that changes nothing visible.
    final count = seen.length;
    await store.library.renameNote(note.id, '새 이름');
    await Future<void>.delayed(Duration.zero);
    expect(seen.length, count);
  });

  test('renameRecording / deleteRecording', () async {
    await create('r1', title: 'a');
    await store.recordings.renameRecording('r1', '  b ');
    expect((await store.recordings.getRecording('r1'))!.title, 'b');
    await store.recordings.renameRecording('r1', null);
    expect((await store.recordings.getRecording('r1'))!.title, isNull);
    await expectLater(
      store.recordings.renameRecording('r1', 'x' * 101),
      throwsArgumentError,
    );
    await expectLater(
      store.recordings.renameRecording('nope', 'x'),
      throwsA(isA<EntityNotFoundException>()),
    );
    await store.recordings.deleteRecording('r1');
    final deleted = (await store.recordings.getRecording('r1'))!;
    expect(deleted.isDeleted, isTrue);
    await store.recordings.deleteRecording('r1'); // already deleted: nothing
    expect(await store.recordings.getRecording('r1'), deleted);
    await expectLater(
      store.recordings.renameRecording('r1', 'x'),
      throwsA(isA<EntityNotFoundException>()),
    );
    await expectLater(
      store.recordings.deleteRecording('nope'),
      throwsA(isA<EntityNotFoundException>()),
    );
  });

  test('audioBytesOf: distinct assets of the active recordings', () async {
    expect(await store.recordings.audioBytesOf(note.id), 0);
    await create('r1');
    await create('r2'); // the same asset
    await create('r3', assetId: audio2.id);
    expect(await store.recordings.audioBytesOf(note.id), 140);
    await store.recordings.deleteRecording('r3');
    expect(await store.recordings.audioBytesOf(note.id), 100);
  });
}
