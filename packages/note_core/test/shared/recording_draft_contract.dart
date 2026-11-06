// Shared body (m5-7/02-core 6.7.2): RecordingDraftStore — meta before the row, append order
// and validation, empty keep-alive chunks, listDrafts reconciliation and the row-less meta
// rebuild, 0-chunk drafts, orphan cleanup, readAll, discard (also cut after step ①). Store
// internals (row loss, orphan chunks, write order) go through [DraftStoreHooks]. The fake store
// runs it (test/media/recording_draft_contract_fake_test.dart), the real store since CORE T31
// (test/media/recording_draft_contract_real_test.dart).
// Web-safe.
import 'dart:async';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:note_core/note_core.dart';
import 'package:test/test.dart';

/// What the shared body needs from a store's internals.
abstract interface class DraftStoreHooks {
  /// The blob keys and row writes in the order they happened (`row:<draftId>` for a row).
  List<String> get writeOrder;

  /// The row of [draftId] is lost (a web row not yet durable when the tab closed).
  Future<void> loseRow(String draftId);

  /// A chunk under a prefix with neither a row nor a meta (a cut deletion).
  Future<void> putOrphanChunk(String draftId);

  /// Whether any blob key of [draftId] is stored.
  Future<bool> hasBlobs(String draftId);

  /// discard() cut after step ① (chunks and meta gone, the row left).
  Future<void> discardBlobsOnly(String draftId);

  /// A store over the same data, opened anew (first use runs the orphan cleanup); null when
  /// the store cannot be reopened (the fake).
  Future<NoteStore>? reopen();
}

void defineRecordingDraftContract(
  FutureOr<(NoteStore, DraftStoreHooks)> Function(Clock clock) open,
) {
  late NoteStore store;
  late DraftStoreHooks hooks;
  late DateTime now;
  late Note note;

  setUp(() async {
    now = DateTime.utc(2026, 11, 6, 9);
    (store, hooks) = await open(Clock(() => now));
    note = await store.library.createNote(title: 'drafts');
  });
  tearDown(() => store.close());

  Uint8List chunk(int n, [int fill = 1]) =>
      Uint8List.fromList(List.filled(n, fill));

  Future<RecordingDraft> begin(String recordingId, {int startedAt = 1000}) =>
      store.recordingDrafts.begin(
        recordingId: recordingId,
        noteId: note.id,
        mimeType: 'audio/webm',
        startedAt: startedAt,
      );

  test('begin: the meta is written before the row; an empty draft', () async {
    final d = await begin('rec-1');
    expect(d.recordingId, 'rec-1');
    expect(d.noteId, note.id);
    expect([d.chunkCount, d.bytes, d.activeMs], [0, 0, 0]);
    expect(d.updatedAt, now.millisecondsSinceEpoch);
    final meta = hooks.writeOrder.indexOf('rd/${d.draftId}/meta');
    final row = hooks.writeOrder.indexOf('row:${d.draftId}');
    expect(meta, greaterThanOrEqualTo(0));
    expect(row, greaterThan(meta));
    expect(await store.recordingDrafts.listDrafts(), [d]);
  });

  test('begin: validation and one draft per recording', () async {
    await expectLater(
      store.recordingDrafts.begin(
        recordingId: 'bad id',
        noteId: note.id,
        mimeType: 'a',
        startedAt: 0,
      ),
      throwsArgumentError,
    );
    await expectLater(
      store.recordingDrafts.begin(
        recordingId: 'r',
        noteId: note.id,
        mimeType: '',
        startedAt: 0,
      ),
      throwsArgumentError,
    );
    await begin('rec-1');
    await expectLater(begin('rec-1'), throwsStateError);
  });

  test(
    'append: order, bytes, activeMs, updatedAt; readAll joins the chunks',
    () async {
      final d = await begin('rec-1');
      // Not awaited between calls: they still land in call order.
      final writes = [
        store.recordingDrafts.append(d.draftId, chunk(3, 1), activeMs: 1000),
        store.recordingDrafts.append(d.draftId, chunk(2, 2), activeMs: 2000),
        store.recordingDrafts.append(d.draftId, chunk(4, 3), activeMs: 3000),
      ];
      await Future.wait(writes);
      now = now.add(const Duration(seconds: 5));
      await store.recordingDrafts.append(
        d.draftId,
        Uint8List(0),
        activeMs: 3500,
      );
      final listed = (await store.recordingDrafts.listDrafts()).single;
      expect(listed.chunkCount, 3);
      expect(listed.bytes, 9);
      expect(listed.activeMs, 3500);
      expect(listed.updatedAt, now.millisecondsSinceEpoch);
      expect(await store.recordingDrafts.readAll(d.draftId), [
        1,
        1,
        1,
        2,
        2,
        3,
        3,
        3,
        3,
      ]);
    },
  );

  test(
    'append / readAll: unknown draft StateError; chunk and activeMs checks',
    () async {
      final d = await begin('rec-1');
      await expectLater(
        store.recordingDrafts.append('nope', chunk(1), activeMs: 0),
        throwsStateError,
      );
      await expectLater(
        store.recordingDrafts.readAll('nope'),
        throwsStateError,
      );
      await expectLater(
        store.recordingDrafts.append(
          d.draftId,
          Uint8List(4 * 1024 * 1024 + 1),
          activeMs: 0,
        ),
        throwsArgumentError,
      );
      await expectLater(
        store.recordingDrafts.append(d.draftId, chunk(1), activeMs: -1),
        throwsArgumentError,
      );
      await store.recordingDrafts.discard(d.draftId);
      await expectLater(
        store.recordingDrafts.append(d.draftId, chunk(1), activeMs: 0),
        throwsStateError,
      );
    },
  );

  test(
    'a lost row is rebuilt from the meta (activeMs 0, updatedAt = startedAt)',
    () async {
      final d = await begin('rec-1', startedAt: 777);
      await store.recordingDrafts.append(d.draftId, chunk(5), activeMs: 1000);
      await store.recordingDrafts.append(d.draftId, chunk(6), activeMs: 2000);
      await hooks.loseRow(d.draftId);
      final rebuilt = (await store.recordingDrafts.listDrafts()).single;
      expect(rebuilt.draftId, d.draftId);
      expect(rebuilt.recordingId, 'rec-1');
      expect(rebuilt.noteId, note.id);
      expect(rebuilt.mimeType, 'audio/webm');
      expect(rebuilt.startedAt, 777);
      expect(rebuilt.updatedAt, 777);
      expect(rebuilt.activeMs, 0);
      expect(rebuilt.chunkCount, 2);
      expect(rebuilt.bytes, 11);
      // The row is written again: the next calls take the normal path.
      expect(await store.recordingDrafts.listDrafts(), [rebuilt]);
      expect(await store.recordingDrafts.readAll(d.draftId), hasLength(11));
      final again = hooks.reopen();
      if (again != null) {
        final reopened = await again;
        addTearDown(reopened.close);
        expect(await reopened.recordingDrafts.listDrafts(), [rebuilt]);
      }
    },
  );

  test(
    'orphan cleanup removes only prefixes without a row and a meta',
    () async {
      final kept = await begin('rec-1');
      await hooks.putOrphanChunk('orphan-1');
      final reopened = hooks.reopen();
      final s = reopened == null ? store : await reopened;
      if (reopened != null) addTearDown(s.close);
      final listed = await s.recordingDrafts.listDrafts();
      expect(listed.map((d) => d.draftId), [kept.draftId]);
      if (reopened != null) expect(await hooks.hasBlobs('orphan-1'), isFalse);
      // A meta-only prefix (row lost) is a draft, not an orphan.
      await hooks.loseRow(kept.draftId);
      expect(
        (await s.recordingDrafts.listDrafts()).single.draftId,
        kept.draftId,
      );
      expect(await hooks.hasBlobs(kept.draftId), isTrue);
    },
  );

  test(
    'a draft with a row and 0 chunks is normal (native media writes rows only)',
    () async {
      final d = await begin('rec-1');
      await store.recordingDrafts.append(
        d.draftId,
        Uint8List(0),
        activeMs: 4000,
      );
      final listed = (await store.recordingDrafts.listDrafts()).single;
      expect(listed.chunkCount, 0);
      expect(listed.activeMs, 4000);
      expect(await store.recordingDrafts.readAll(d.draftId), isEmpty);
    },
  );

  test('listDrafts: every draft, startedAt order', () async {
    final b = await begin('rec-b', startedAt: 2000);
    final a = await begin('rec-a', startedAt: 1000);
    expect((await store.recordingDrafts.listDrafts()).map((d) => d.draftId), [
      a.draftId,
      b.draftId,
    ]);
  });

  test('discard: chunks, meta and row; unknown is a no-op; cut after ① = a 0-chunk draft', () async {
    final d = await begin('rec-1');
    await store.recordingDrafts.append(d.draftId, chunk(3), activeMs: 1000);
    await store.recordingDrafts.discard(d.draftId);
    expect(await store.recordingDrafts.listDrafts(), isEmpty);
    expect(await hooks.hasBlobs(d.draftId), isFalse);
    await store.recordingDrafts.discard(d.draftId);
    await store.recordingDrafts.discard('nope');
    final cut = await begin('rec-2');
    await store.recordingDrafts.append(cut.draftId, chunk(3), activeMs: 1000);
    await hooks.discardBlobsOnly(cut.draftId);
    final left = (await store.recordingDrafts.listDrafts()).single;
    expect(left.draftId, cut.draftId);
    expect(left.chunkCount, 0);
    expect(await store.recordingDrafts.readAll(cut.draftId), isEmpty);
  });
}
