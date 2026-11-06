// Draft writer (m5-7/06-pdf 6.8.5; 8.2 T31a — D13, M-2, v2.1 PDF-M5, review S-5): chunks go to
// RecordingDraftStore in order, one append at a time; while paused an empty chunk every second
// (only when nothing is queued); queued + unsaved over 8 MiB stops the recording (backlogFull);
// a failed append keeps the chunk as unsaved and the next chunk writes it first (the error
// clears); StateError (the draft was recovered elsewhere) → draftLost and nothing more; drain.
// Fake time (fake_async) and GatedDraftStore; the last group runs on CORE's fake store
// (createFakeNoteStore v2 — contract 7.6).
import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_io/src/record/draft_writer.dart';
import 'package:media_io/src/tuning.dart';
import 'package:note_core/testing.dart' as core_testing;

import '../support/gated_draft_store.dart';

Uint8List _chunk(int length, [int fill = 1]) =>
    Uint8List(length)..fillRange(0, length, fill);

void main() {
  late List<(DraftWriterSignal, Object?)> signals;

  DraftWriter writer(
    GatedDraftStore store,
    int Function() activeMs, {
    int backlogMaxBytes = MediaTuning.webMemoryBacklogMaxBytes,
  }) => DraftWriter(
    drafts: store,
    draftId: 'draft-1',
    activeMs: activeMs,
    keepAliveMs: MediaTuning.pausedKeepAliveMs(1000),
    backlogMaxBytes: backlogMaxBytes,
    onSignal: (s, e) => signals.add((s, e)),
  );

  setUp(() => signals = []);

  test('in order, one append at a time, activeMs read as each starts', () {
    fakeAsync((async) {
      final store = GatedDraftStore(now: () => async.elapsed)
        ..gate = Completer.sync();
      var active = 0;
      final w = writer(store, () => active);
      for (var i = 1; i <= 5; i++) {
        active = i * 1000;
        w.add(_chunk(10, i));
      }
      async.flushMicrotasks();
      expect(store.appends, hasLength(1));
      expect(store.appends.single.activeMs, 1000);
      expect(w.queuedBytes, 50);
      active = 7000;
      store.open();
      async.flushMicrotasks();
      expect(store.written.map((c) => c.first), [1, 2, 3, 4, 5]);
      expect(store.maxInFlight, 1);
      expect(store.appends.map((a) => a.activeMs), [
        1000,
        7000,
        7000,
        7000,
        7000,
      ]);
      expect(store.appends.every((a) => a.draftId == 'draft-1'), isTrue);
      expect(w.isIdle, isTrue);
      expect(w.backlogBytes, 0);
      expect(signals, isEmpty);
    });
  });

  test('paused: an empty chunk every second, only while nothing is queued', () {
    fakeAsync((async) {
      final store = GatedDraftStore(now: () => async.elapsed);
      final w = writer(store, () => 1500)..paused = true;
      async.elapse(const Duration(milliseconds: 999));
      expect(store.appends, isEmpty);
      async.elapse(const Duration(milliseconds: 1));
      expect(store.appends, hasLength(1));
      expect(store.appends.single.chunk, isEmpty);
      expect(store.appends.single.activeMs, 1500);
      async.elapse(const Duration(seconds: 3));
      expect(store.appends, hasLength(4));
      // A held append (CORE retrying a commit): no empty chunk joins the queue behind it.
      store.gate = Completer.sync();
      w.add(_chunk(8));
      async.elapse(const Duration(seconds: 5));
      expect(store.appends, hasLength(5));
      expect(store.appends.last.chunk, hasLength(8));
      store.open();
      async.elapse(const Duration(seconds: 1));
      expect(store.appends, hasLength(6));
      expect(store.appends.last.chunk, isEmpty);
      w.paused = false;
      async.elapse(const Duration(seconds: 10));
      expect(store.appends, hasLength(6));
      expect(w.paused, isFalse);
    });
  });

  test('queued + unsaved over 8 MiB → backlogFull once per crossing', () {
    fakeAsync((async) {
      const mib = 1024 * 1024;
      final store = GatedDraftStore()..gate = Completer.sync();
      final w = writer(store, () => 0);
      for (var i = 0; i < 8; i++) {
        w.add(_chunk(mib));
      }
      async.flushMicrotasks();
      expect(w.backlogBytes, 8 * mib);
      expect(signals, isEmpty);
      w.add(_chunk(1));
      expect(signals.map((s) => s.$1), [DraftWriterSignal.backlogFull]);
      w.add(_chunk(1));
      expect(signals, hasLength(1));
      store.open();
      async.flushMicrotasks();
      expect(w.backlogBytes, 0);
      // An unsaved chunk counts too.
      store
        ..gate = Completer.sync()
        ..failures.add(Exception('disk full'));
      w.add(_chunk(4 * mib));
      async.flushMicrotasks();
      store.open();
      async.flushMicrotasks();
      expect(w.unsavedBytes, 4 * mib);
      store.gate = Completer.sync();
      w
        ..add(_chunk(4 * mib))
        ..add(_chunk(1));
      expect(signals.map((s) => s.$1), [
        DraftWriterSignal.backlogFull,
        DraftWriterSignal.storageFailed,
        DraftWriterSignal.backlogFull,
      ]);
      store.open();
      async.flushMicrotasks();
    });
  });

  test('a failed append stays unsaved; the next chunk writes it first', () {
    fakeAsync((async) {
      final store = GatedDraftStore();
      final w = writer(store, () => 0);
      final failure = Exception('IndexedDB write failed');
      store.failures.add(failure);
      w.add(_chunk(10, 1));
      async.flushMicrotasks();
      expect(signals, [(DraftWriterSignal.storageFailed, failure)]);
      expect(w.error, failure);
      expect((w.unsavedBytes, w.queuedBytes), (10, 0));
      expect(store.written, isEmpty);
      // The second failure of the same chunk is not reported again.
      store.failures.add(Exception('still failing'));
      w.add(_chunk(20, 2));
      async.flushMicrotasks();
      expect(signals, hasLength(1));
      expect((w.unsavedBytes, w.queuedBytes), (10, 20));
      // The storage is back: unsaved first, then the new chunk; the error clears.
      w.add(_chunk(5, 3));
      async.flushMicrotasks();
      expect(store.written.map((c) => c.first), [1, 2, 3]);
      expect(w.error, isNull);
      expect((w.unsavedBytes, w.queuedBytes), (0, 0));
      expect(signals.last, (DraftWriterSignal.storageRecovered, null));
    });
  });

  test('the keep-alive tick retries unsaved chunks while paused', () {
    fakeAsync((async) {
      final store = GatedDraftStore();
      final w = writer(store, () => 0)..paused = true;
      store.failures.add(Exception('busy'));
      w.add(_chunk(10));
      async.flushMicrotasks();
      expect(w.unsavedBytes, 10);
      async.elapse(const Duration(seconds: 1));
      expect(store.written, hasLength(1));
      expect(store.written.single, hasLength(10));
      expect(w.error, isNull);
      w.paused = false;
    });
  });

  test('StateError (draft recovered elsewhere) → draftLost, nothing more', () {
    fakeAsync((async) {
      final store = GatedDraftStore();
      final w = writer(store, () => 0)..paused = true;
      final lost = StateError('Unknown recording draft draft-1');
      store.failures.add(lost);
      w
        ..add(_chunk(10))
        ..add(_chunk(10));
      async.flushMicrotasks();
      expect(signals, [(DraftWriterSignal.draftLost, lost)]);
      expect(w.isLost, isTrue);
      expect(w.paused, isFalse);
      expect(w.backlogBytes, 0);
      w.add(_chunk(10));
      async.elapse(const Duration(seconds: 5));
      expect(store.appends, hasLength(1));
    });
  });

  test('StateError on a keep-alive chunk → draftLost too', () {
    fakeAsync((async) {
      final store = GatedDraftStore();
      final w = writer(store, () => 0)..paused = true;
      store.failures.add(StateError('gone'));
      async.elapse(const Duration(seconds: 1));
      expect(signals.single.$1, DraftWriterSignal.draftLost);
      expect(w.isLost, isTrue);
    });
  });

  test('a keep-alive failure other than StateError loses nothing', () {
    fakeAsync((async) {
      final store = GatedDraftStore();
      final w = writer(store, () => 0)..paused = true;
      store.failures.add(Exception('busy'));
      async.elapse(const Duration(seconds: 2));
      expect(store.appends, hasLength(2));
      expect(signals, isEmpty);
      expect(w.error, isNull);
      w.paused = false;
    });
  });

  test(
    'drain waits for the append in flight (no time limit), writes the rest',
    () {
      fakeAsync((async) {
        final store = GatedDraftStore()..gate = Completer.sync();
        final w = writer(store, () => 0)
          ..add(_chunk(1, 1))
          ..add(_chunk(1, 2));
        List<Uint8List>? left;
        w.drain().then((v) => left = v);
        async.elapse(const Duration(minutes: 5)); // CORE retrying a commit
        expect(left, isNull);
        store.open();
        async.flushMicrotasks();
        expect(left, isEmpty);
        expect(store.written.map((c) => c.first), [1, 2]);
      });
    },
  );

  test('drain writes unsaved once more and returns what is still left', () {
    fakeAsync((async) {
      final store = GatedDraftStore();
      final w = writer(store, () => 0);
      store.failures.add(Exception('quota'));
      w.add(_chunk(3, 1));
      async.flushMicrotasks();
      store.failures.add(Exception('quota again'));
      w.add(_chunk(4, 2));
      async.flushMicrotasks();
      store.failures.add(Exception('quota once more'));
      List<Uint8List>? left;
      w.drain().then((v) => left = v);
      async.flushMicrotasks();
      expect(left!.map((c) => (c.first, c.length)), [(1, 3), (2, 4)]);
      // Once storage works the same call empties it.
      w.drain().then((v) => left = v);
      async.flushMicrotasks();
      expect(left, isEmpty);
      expect(store.written.map((c) => c.first), [1, 2]);
    });
  });

  test('a chunk over 4 MiB is split for CORE (each ≤ 4 MiB)', () {
    fakeAsync((async) {
      final store = GatedDraftStore();
      writer(
        store,
        () => 0,
      ).add(_chunk(MediaTuning.draftChunkMaxBytes * 2 + 5));
      async.flushMicrotasks();
      expect(store.written.map((c) => c.length), [
        MediaTuning.draftChunkMaxBytes,
        MediaTuning.draftChunkMaxBytes,
        5,
      ]);
    });
  });

  test('close drops memory and stops the keep-alive', () {
    fakeAsync((async) {
      final store = GatedDraftStore()..gate = Completer.sync();
      final w = writer(store, () => 0)
        ..paused = true
        ..add(_chunk(10))
        ..add(_chunk(10));
      async.flushMicrotasks();
      w.close();
      expect(w.backlogBytes, 0);
      store.open();
      async.elapse(const Duration(seconds: 5));
      expect(store.appends, hasLength(1));
      w.add(_chunk(1));
      async.flushMicrotasks();
      expect(store.appends, hasLength(1));
    });
  });

  group('on CORE\'s fake store', () {
    test('chunks and keep-alive chunks reach the draft', () async {
      final store = core_testing.createFakeNoteStore();
      final draft = await store.recordingDrafts.begin(
        recordingId: 'rec-1',
        noteId: 'note-1',
        mimeType: 'audio/webm;codecs=opus',
        startedAt: 0,
      );
      final w = DraftWriter(
        drafts: store.recordingDrafts,
        draftId: draft.draftId,
        activeMs: () => 2000,
        keepAliveMs: 1000,
        onSignal: (s, e) => signals.add((s, e)),
      )..add(Uint8List.fromList([1, 2, 3]));
      w.add(Uint8List.fromList([4, 5]));
      expect(await w.drain(), isEmpty);
      expect(await store.recordingDrafts.readAll(draft.draftId), [
        1,
        2,
        3,
        4,
        5,
      ]);
      final row = (await store.recordingDrafts.listDrafts()).single;
      expect((row.chunkCount, row.bytes, row.activeMs), (2, 5, 2000));
      expect(signals, isEmpty);
      await store.close();
    });

    test('a discarded draft → StateError → draftLost', () async {
      final store = core_testing.createFakeNoteStore();
      final draft = await store.recordingDrafts.begin(
        recordingId: 'rec-2',
        noteId: 'note-1',
        mimeType: 'audio/mp4',
        startedAt: 0,
      );
      await store.recordingDrafts.discard(
        draft.draftId,
      ); // another tab recovered it
      final w = DraftWriter(
        drafts: store.recordingDrafts,
        draftId: draft.draftId,
        activeMs: () => 0,
        keepAliveMs: 1000,
        onSignal: (s, e) => signals.add((s, e)),
      )..add(Uint8List.fromList([1]));
      expect(await w.drain(), isEmpty);
      expect(signals.single.$1, DraftWriterSignal.draftLost);
      expect(signals.single.$2, isA<StateError>());
      await store.close();
    });
  });
}
