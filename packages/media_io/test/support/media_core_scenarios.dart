// The T40 scenarios (m5-7/06-pdf 8.2 T40): the recorder service on CORE's REAL store — judged at
// integration step 4-d (`ws test --run-skipped -t integration --package media_io`, file
// test/integration/media_real_core_test.dart) — and the same bodies on CORE's fake store
// (test/unit/media_fake_core_test.dart, every run). note_core/testing_vm.dart
// openTestNoteStore (drift on a file + the per-path blob store) with a fake engine: record →
// stop → an audio asset and a Recording row; a Recording before its asset → CORE ArgumentError
// (M-1 is the store's rule too); a draft survives closing and reopening the store and is
// recovered; an empty chunk moves the draft's updatedAt (the paused keep-alive, 6.8.5); a note
// purged before recovery → nothing recovered and nothing left; audioBytesOf.
//
// The same bodies also run on CORE's fake store (an untagged file — every `ws test` run), so the
// flow is checked outside the integration stage too. VM only (dart:io). No wall-clock assertions: the store clock and the recording clock are one
// FakeAsync's clock, moved by hand (FakeAsync.elapse outside its zone — nothing runs in it).
import 'dart:io';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_io/src/config.dart';
import 'package:media_io/src/platform/web_locks_stub.dart';
import 'package:media_io/src/record/recorder_service.dart';
import 'package:media_io/src/record/recording_output.dart';
import 'package:media_io/src/record/recover_attempts.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;
import 'package:note_core/testing_vm.dart' as core_vm;

import 'fake_engines.dart';
import 'fake_stopwatch.dart';

final DateTime _start = DateTime.utc(2026, 11, 6, 9);

/// Opens, reopens and closes the store of one test (real file store or CORE's fake store).
abstract interface class MediaCoreStores {
  String get label;
  Future<core.NoteStore> open();

  /// The same data in a new store object: the file store closes [store] and opens the same
  /// file again; the fake store hands [store] back.
  Future<core.NoteStore> reopen(core.NoteStore store);
  Future<void> close(core.NoteStore store);
}

final class FileCoreStores implements MediaCoreStores {
  FileCoreStores(this.time)
    : _dir = Directory.systemTemp.createTempSync('media_real_core_');

  final FakeAsync time;
  final Directory _dir;

  @override
  String get label => 'real CORE (file)';

  String get _path => '${_dir.path}/notes.db';

  @override
  Future<core.NoteStore> open() =>
      core_vm.openTestNoteStore(filePath: _path, clock: time.getClock(_start));

  @override
  Future<core.NoteStore> reopen(core.NoteStore store) async {
    await store.close();
    return open();
  }

  @override
  Future<void> close(core.NoteStore store) async {
    await store.close();
    if (_dir.existsSync()) _dir.deleteSync(recursive: true);
  }
}

final class FakeCoreStores implements MediaCoreStores {
  FakeCoreStores(this.time);

  final FakeAsync time;

  @override
  String get label => 'CORE fake store';

  @override
  Future<core.NoteStore> open() async =>
      core_testing.createFakeNoteStore(clock: time.getClock(_start));

  @override
  Future<core.NoteStore> reopen(core.NoteStore store) async => store;

  @override
  Future<void> close(core.NoteStore store) => store.close();
}

/// One test's world: the store, a note, the hand-moved clock.
final class _World {
  _World(this.time, this.stores, this.store, this.noteId);

  final FakeAsync time;
  final MediaCoreStores stores;
  core.NoteStore store;
  final core.NoteId noteId;

  /// The recorder service on [store] with [engine] (web-like: chunks into the draft store).
  MediaRecorderService service(FakeRecorderEngine engine) =>
      MediaRecorderService(
        stores: () => RecorderStores.of(store),
        now: store.clock.now,
        config: const MediaIoConfig(),
        engine: engine,
        locks: const UnavailableWebLocks(),
        stopwatch: () => FakeStopwatch(() => time.elapsed),
      );

  /// Moves the store clock and the recording clock together.
  void elapse(Duration d) => time.elapse(d);
}

typedef _Body = Future<void> Function(_World w);

/// Runs [body] on [stores].
void _storeTest(
  String name,
  MediaCoreStores Function(FakeAsync time) stores,
  _Body body,
) {
  test(name, () async {
    final time = FakeAsync(initialTime: _start);
    final s = stores(time);
    final store = await s.open();
    final note = await store.library.createNote(title: 'Lecture');
    final w = _World(time, s, store, note.id);
    try {
      await body(w);
    } finally {
      await s.close(w.store);
    }
  });
}

/// Waits (microtasks and the store's own async work, no wall-clock bound in the assertion)
/// until [done].
Future<void> _until(bool Function() done, String what) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await pumpEventQueue();
  }
  expect(done(), isTrue, reason: what);
}

/// start → recording → [seconds] one-second chunks of [chunkBytes] each.
Future<FakeRecorderEngine> _record(
  _World w,
  MediaRecorderService service,
  FakeRecorderEngine engine,
  core.RecordingId id, {
  int seconds = 3,
  int chunkBytes = 100,
}) async {
  await service.start(recordingId: id, noteId: w.noteId);
  await _until(
    () => service.status.phase == core.RecorderPhase.recording,
    'recording',
  );
  for (var i = 0; i < seconds; i++) {
    w.elapse(const Duration(seconds: 1));
    engine.session!.chunk(Uint8List.fromList(List.filled(chunkBytes, i + 1)));
    await pumpEventQueue();
  }
  return engine;
}

/// The T40 scenarios on [stores].
void mediaCoreScenarios(MediaCoreStores Function(FakeAsync time) stores) {
  _storeTest(
    'record → stop → an audio asset and a Recording row; audioBytesOf',
    stores,
    (w) async {
      final engine = FakeRecorderEngine();
      final service = w.service(engine);
      final id = w.store.ids.newId();
      await _record(w, service, engine, id);
      final recording = await service.stop();
      expect(recording, isNotNull);
      expect(recording!.id, id);
      expect(recording.noteId, w.noteId);
      expect(recording.durationMs, 3000, reason: 'not WebM → the clock');
      final rows = await w.store.recordings.recordingsOf(w.noteId);
      expect([for (final r in rows) r.id], [id]);
      final asset = await w.store.assets.getAsset(recording.assetId);
      expect(asset?.type, core.AssetType.audio);
      expect(asset?.mimeType, startsWith('audio/webm'));
      final bytes = await w.store.assets.readBytes(recording.assetId);
      expect(bytes, hasLength(300));
      expect(bytes!.first, 1);
      expect(bytes.last, 3);
      expect(await w.store.recordingDrafts.listDrafts(), isEmpty);
      expect(await w.store.recordings.audioBytesOf(w.noteId), 300);
      await service.dispose();
    },
  );

  _storeTest(
    'a Recording before its asset (the order turned round) → CORE ArgumentError, no row',
    stores,
    (w) async {
      await expectLater(
        w.store.recordings.createRecording(
          id: w.store.ids.newId(),
          noteId: w.noteId,
          assetId: w.store.ids.newId(),
          durationMs: 1000,
          startedAt: w.store.clock.now().millisecondsSinceEpoch,
        ),
        throwsArgumentError,
      );
      expect(await w.store.recordings.recordingsOf(w.noteId), isEmpty);
      expect(await w.store.recordings.audioBytesOf(w.noteId), 0);
    },
  );

  _storeTest(
    'a draft survives closing and reopening the store → recovered as it was',
    stores,
    (w) async {
      final engineA = FakeRecorderEngine();
      final a = w.service(engineA);
      final id = w.store.ids.newId();
      await _record(w, a, engineA, id, seconds: 2);
      await a.dispose(); // the tab goes without stop(): the draft stays
      final drafts = await w.store.recordingDrafts.listDrafts();
      expect(drafts, hasLength(1));
      expect(drafts.single.recordingId, id);
      expect(drafts.single.bytes, 200);

      w.store = await w.stores.reopen(w.store);
      w.elapse(
        const Duration(seconds: 11),
      ); // past the recent-update window (10 s)
      final b = w.service(FakeRecorderEngine());
      final pending = await b.pendingDrafts();
      expect([for (final d in pending) d.recordingId], [id]);
      final recovered = await b.recoverDraft(pending.single.draftId);
      expect(recovered, isNotNull);
      expect(recovered!.id, id, reason: 'the original recording id');
      expect(recovered.title, '복구된 녹음');
      expect(recovered.durationMs, 2000, reason: 'the draft activeMs');
      expect(await w.store.assets.readBytes(recovered.assetId), hasLength(200));
      expect(await w.store.recordingDrafts.listDrafts(), isEmpty);
      expect(await RecoverAttempts(w.store.settings).read(), isEmpty);
      expect(await b.recoverDraft(pending.single.draftId), isNull);
      expect(await w.store.recordings.recordingsOf(w.noteId), hasLength(1));
      await b.dispose();
    },
  );

  _storeTest(
    "an empty chunk moves the draft's updatedAt (the paused keep-alive)",
    stores,
    (w) async {
      final drafts = w.store.recordingDrafts;
      final draft = await drafts.begin(
        recordingId: w.store.ids.newId(),
        noteId: w.noteId,
        mimeType: 'audio/webm;codecs=opus',
        startedAt: w.store.clock.now().millisecondsSinceEpoch,
      );
      await drafts.append(draft.draftId, Uint8List(64), activeMs: 1000);
      final before = (await drafts.listDrafts()).single;
      w.elapse(const Duration(seconds: 5));
      await drafts.append(draft.draftId, Uint8List(0), activeMs: 1000);
      final after = (await drafts.listDrafts()).single;
      expect(
        after.updatedAt,
        w.store.clock.now().millisecondsSinceEpoch,
        reason: 'updatedAt after the empty chunk',
      );
      expect(after.updatedAt - before.updatedAt, 5000);
      expect(after.bytes, 64, reason: 'no bytes added');
      expect(after.activeMs, 1000);
      // Still recent for another recorder: not offered for recovery.
      final other = w.service(FakeRecorderEngine());
      w.elapse(const Duration(seconds: 9));
      expect(await other.pendingDrafts(), isEmpty);
      await other.dispose();
    },
  );

  _storeTest(
    'the note purged before recovery → nothing recovered, no draft or attempt left',
    stores,
    (w) async {
      final engineA = FakeRecorderEngine();
      final a = w.service(engineA);
      final id = w.store.ids.newId();
      await _record(w, a, engineA, id, seconds: 1);
      await a.dispose();
      w.elapse(const Duration(seconds: 11));
      final b = w.service(FakeRecorderEngine());
      final pending = await b.pendingDrafts();
      expect(pending, hasLength(1));
      await w.store.library.trashItems([core.NoteRef(w.noteId)]);
      await w.store.trash.purge([core.NoteRef(w.noteId)]);
      expect(await b.recoverDraft(pending.single.draftId), isNull);
      expect(await w.store.recordingDrafts.listDrafts(), isEmpty);
      expect(await RecoverAttempts(w.store.settings).read(), isEmpty);
      expect(await w.store.recordings.getRecording(id), isNull);
      await b.dispose();
    },
  );
}
