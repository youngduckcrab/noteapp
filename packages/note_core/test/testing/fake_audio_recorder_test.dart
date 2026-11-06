// FakeAudioRecorder (m5-7/02-core 6.8.3): phase order, offsetNowMs without pauses, 1 s chunks
// and empty keep-alive chunks, interrupt, the M-1 order of stop (asset batch before the
// recording batch), stopDurationErrorMs, 0 ms → null, cancel, start guards, a failed store
// keeps the draft, abandon → pendingDrafts after 10 s → recoverDraft, the exclusions, inside
// and outside fake_async, and the same flow on the real in-memory CORE (VM, since CORE T31).
@TestOn('vm')
library;

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';
import 'package:note_core/testing_vm.dart';
import 'package:test/test.dart';

void main() {
  late DateTime now;
  late NoteStore store;
  late Note note;
  setUp(() async {
    now = DateTime.utc(2026, 11, 6, 9);
    store = createFakeNoteStore(clock: Clock(() => now));
    note = await store.library.createNote(title: '녹음');
  });
  tearDown(() => store.close());

  Future<void> settle() => store.flush();

  test('start: starting → recording; offsetNowMs excludes pauses', () async {
    final r = FakeAudioRecorder(store: store);
    final phases = <RecorderPhase>[];
    final sub = r.statusStream.listen((s) => phases.add(s.phase));
    addTearDown(sub.cancel);
    expect(await r.checkSupport(), AudioSupport.supported);
    expect(r.offsetNowMs(), isNull);
    await r.start(recordingId: 'rec-1', noteId: note.id);
    await Future<void>.delayed(
      Duration.zero,
    ); // stream events arrive asynchronously
    expect(phases.toSet().toList(), [
      RecorderPhase.idle,
      RecorderPhase.starting,
      RecorderPhase.recording,
    ]);
    expect(r.status.recordingId, 'rec-1');
    expect(r.status.noteId, note.id);
    expect(r.status.mimeType, 'audio/mp4');
    expect(r.status.backgroundCapable, isFalse);
    expect(r.status.crossPlatformPlayable, isTrue);
    r.advance(const Duration(milliseconds: 1500));
    expect(r.offsetNowMs(), 1500);
    await r.pause();
    expect(r.status.phase, RecorderPhase.paused);
    expect(r.offsetNowMs(), isNull);
    r.advance(const Duration(seconds: 3));
    await r.resume();
    r.advance(const Duration(milliseconds: 700));
    expect(r.offsetNowMs(), 2200);
    expect(r.status.activeMs, 2200);
  });

  test(
    'chunks: 16 bytes per recorded second; empty keep-alives while paused',
    () async {
      final r = FakeAudioRecorder(store: store);
      await r.start(recordingId: 'rec-1', noteId: note.id);
      r.advance(const Duration(milliseconds: 2500));
      await r.abandon(); // waits for the queued chunks
      var d = (await store.recordingDrafts.listDrafts()).single;
      expect(d.chunkCount, 2);
      expect(d.bytes, 32);
      expect(d.activeMs, 2000);

      final r2 = FakeAudioRecorder(store: store);
      await r2.start(recordingId: 'rec-2', noteId: note.id);
      r2.advance(const Duration(seconds: 1));
      await r2.pause();
      now = now.add(const Duration(seconds: 30));
      r2.advance(const Duration(seconds: 2));
      await r2.abandon();
      d = (await store.recordingDrafts.listDrafts()).firstWhere(
        (d) => d.recordingId == 'rec-2',
      );
      expect(d.chunkCount, 1, reason: 'keep-alives add no chunk');
      expect(
        d.updatedAt,
        now.millisecondsSinceEpoch,
        reason: 'but update the draft',
      );
    },
  );

  test('interrupt → paused, interrupted; resume clears it', () async {
    final r = FakeAudioRecorder(store: store);
    await r.start(recordingId: 'rec-1', noteId: note.id);
    r.interrupt();
    expect(r.status.phase, RecorderPhase.paused);
    expect(r.status.interrupted, isTrue);
    await r.resume();
    expect(r.status.phase, RecorderPhase.recording);
    expect(r.status.interrupted, isFalse);
  });

  test(
    'stop: the asset batch before the recording batch (M-1), draft gone',
    () async {
      final batches = <ChangeBatch>[];
      final sub = store.changes.listen(batches.add);
      addTearDown(sub.cancel);
      final r = FakeAudioRecorder(store: store)..stopDurationErrorMs = 40;
      await r.start(recordingId: 'rec-1', noteId: note.id);
      r.advance(const Duration(milliseconds: 3200));
      final rec = (await r.stop())!;
      expect(rec.id, 'rec-1');
      expect(rec.noteId, note.id);
      expect(rec.durationMs, 3240);
      expect(rec.startedAt, now.millisecondsSinceEpoch);
      expect(r.status, const RecorderStatus());
      final asset = (await store.assets.getAsset(rec.assetId))!;
      expect(asset.type, AssetType.audio);
      expect(asset.mimeType, 'audio/mp4');
      expect(await store.assets.readBytes(rec.assetId), isNotEmpty);
      expect(await store.recordingDrafts.listDrafts(), isEmpty);
      await Future<void>.delayed(Duration.zero);
      final kinds = [
        for (final b in batches)
          for (final c in b.changes)
            if (c.kind == EntityKind.asset || c.kind == EntityKind.recording)
              c.kind,
      ];
      expect(kinds, [EntityKind.asset, EntityKind.recording]);
    },
  );

  test(
    'stop: 0 ms → null, no recording; not active → null; cancel → no row',
    () async {
      final r = FakeAudioRecorder(store: store);
      expect(await r.stop(), isNull);
      await r.start(recordingId: 'rec-1', noteId: note.id);
      expect(await r.stop(), isNull);
      expect(await store.recordings.getRecording('rec-1'), isNull);
      expect(await store.recordingDrafts.listDrafts(), isEmpty);
      await r.start(recordingId: 'rec-2', noteId: note.id);
      r.advance(const Duration(seconds: 2));
      await r.cancel();
      expect(r.status.phase, RecorderPhase.idle);
      expect(await store.recordings.getRecording('rec-2'), isNull);
      expect(await store.recordingDrafts.listDrafts(), isEmpty);
    },
  );

  test('start guards: UnsupportedError when not supported, StateError while active', () async {
    for (final support in [
      AudioSupport.unsupported,
      AudioSupport.permissionDenied,
      AudioSupport.permissionPermanentlyDenied,
    ]) {
      final r = FakeAudioRecorder(store: store, support: support);
      expect(await r.checkSupport(), support);
      await expectLater(
        r.start(recordingId: 'rec-x', noteId: note.id),
        throwsUnsupportedError,
      );
    }
    final r = FakeAudioRecorder(store: store);
    await r.start(recordingId: 'rec-1', noteId: note.id);
    await expectLater(
      r.start(recordingId: 'rec-2', noteId: note.id),
      throwsStateError,
    );
  });

  test(
    'a failed save keeps the draft: idle with error, the exception',
    () async {
      final r = FakeAudioRecorder(store: store)..stopDurationErrorMs = -100000;
      await r.start(recordingId: 'rec-1', noteId: note.id);
      r.advance(const Duration(seconds: 2));
      await expectLater(r.stop(), throwsArgumentError);
      expect(r.status.phase, RecorderPhase.idle);
      expect(r.status.error, isA<ArgumentError>());
      expect(
        (await store.recordingDrafts.listDrafts()).single.recordingId,
        'rec-1',
      );
    },
  );

  test(
    'abandon → a new recorder sees the draft after 10 s and recovers it',
    () async {
      final a = FakeAudioRecorder(store: store);
      await a.start(recordingId: 'rec-1', noteId: note.id);
      a.advance(const Duration(milliseconds: 4300));
      await a.abandon();
      expect(a.status.phase, RecorderPhase.idle);
      final b = FakeAudioRecorder(store: store);
      expect(await b.pendingDrafts(), isEmpty, reason: 'updated within 10 s');
      now = now.add(const Duration(seconds: 9));
      expect(await b.pendingDrafts(), isEmpty);
      now = now.add(const Duration(seconds: 2));
      final pending = await b.pendingDrafts();
      expect(pending, hasLength(1));
      expect(pending.single.recordingId, 'rec-1');
      final rec = (await b.recoverDraft(pending.single.draftId))!;
      expect(rec.id, 'rec-1');
      expect(rec.title, '복구된 녹음');
      expect(rec.durationMs, 4000);
      expect(await b.pendingDrafts(), isEmpty);
      expect(await store.recordingDrafts.listDrafts(), isEmpty);
    },
  );

  test("exclusions: this recorder's active draft, recent drafts; recoverDraft StateError", () async {
    final a = FakeAudioRecorder(store: store);
    await a.start(recordingId: 'rec-1', noteId: note.id);
    a.advance(const Duration(seconds: 1));
    await Future<void>.delayed(
      Duration.zero,
    ); // the queued chunk reaches the store
    await settle();
    now = now.add(const Duration(minutes: 5));
    final draftId = (await store.recordingDrafts.listDrafts()).single.draftId;
    expect(await a.pendingDrafts(), isEmpty, reason: 'its own active session');
    await expectLater(a.recoverDraft(draftId), throwsStateError);
    final b = FakeAudioRecorder(store: store);
    expect(
      (await b.pendingDrafts()).single.draftId,
      draftId,
      reason: 'old for b',
    );
    a.advance(const Duration(seconds: 1));
    await Future<void>.delayed(Duration.zero);
    await settle();
    expect(await b.pendingDrafts(), isEmpty, reason: 'recently updated');
    await expectLater(b.recoverDraft(draftId), throwsStateError);
    await expectLater(b.recoverDraft('nope'), throwsStateError);
  });

  test('an empty draft recovers to null and is discarded', () async {
    final a = FakeAudioRecorder(store: store);
    await a.start(recordingId: 'rec-1', noteId: note.id);
    await a.abandon();
    now = now.add(const Duration(minutes: 1));
    final b = FakeAudioRecorder(store: store);
    final d = (await b.pendingDrafts()).single;
    expect(await b.recoverDraft(d.draftId), isNull);
    expect(await store.recordingDrafts.listDrafts(), isEmpty);
  });

  test('deterministic inside fake_async (no timers of its own)', () {
    fakeAsync((async) {
      final s = createFakeNoteStore(clock: async.getClock(DateTime.utc(2026)));
      late Note n;
      s.library.createNote(title: 'fa').then((v) => n = v);
      async.flushMicrotasks();
      final r = FakeAudioRecorder(store: s);
      Recording? rec;
      r.start(recordingId: 'rec-1', noteId: n.id);
      async.flushMicrotasks();
      expect(r.status.phase, RecorderPhase.recording);
      r.advance(const Duration(seconds: 3));
      r.stop().then((v) => rec = v);
      async.flushMicrotasks();
      expect(rec!.durationMs, 3000);
      expect(async.pendingTimers, isEmpty);
      s.close();
      async.flushMicrotasks();
    });
  });

  // The real in-memory CORE writes drafts since CORE T31 (storage/drift_recording_draft_store):
  // the recorder's whole flow — stop (asset, then recording; draft gone) and abandon →
  // pendingDrafts after 10 s → recoverDraft — on openTestNoteStore (outside fake_async; the
  // in-memory IndexedDB ends on its own timers).
  test(
    'on the real in-memory CORE: stop, and abandon → recoverDraft',
    () async {
      final real = await openTestNoteStore(clock: Clock(() => now));
      addTearDown(real.close);
      final n = await real.library.createNote(title: 'real');
      final r = FakeAudioRecorder(store: real)..stopDurationErrorMs = 0;
      await r.start(recordingId: 'rec-1', noteId: n.id);
      r.advance(const Duration(milliseconds: 2500));
      final rec = (await r.stop())!;
      expect((rec.id, rec.durationMs), ('rec-1', 2500));
      expect(await real.assets.readBytes(rec.assetId), isNotEmpty);
      expect(await real.recordingDrafts.listDrafts(), isEmpty);
      expect(await real.recordings.recordingsOf(n.id), [rec]);

      final a = FakeAudioRecorder(store: real);
      await a.start(recordingId: 'rec-2', noteId: n.id);
      a.advance(const Duration(milliseconds: 3100));
      await a.abandon();
      final b = FakeAudioRecorder(store: real);
      expect(await b.pendingDrafts(), isEmpty, reason: 'updated within 10 s');
      now = now.add(const Duration(seconds: 11));
      final pending = (await b.pendingDrafts()).single;
      expect(pending.recordingId, 'rec-2');
      expect(pending.chunkCount, 3);
      final recovered = (await b.recoverDraft(pending.draftId))!;
      expect((recovered.id, recovered.durationMs), ('rec-2', 3000));
      expect(await real.recordingDrafts.listDrafts(), isEmpty);
    },
  );
}
