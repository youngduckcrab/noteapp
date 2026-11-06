// The recorder service on CORE's fake store in fake time (m5-7/06-pdf 8.2 T31b): the store's
// clock and the recording clock follow fakeAsync; the store's draft, asset and recording calls
// go through logging wrappers that can hold appends open (a frozen tab / a CORE commit retry)
// and fail put / createRecording / readAll / settings reads.
import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_io/src/config.dart';
import 'package:media_io/src/platform/web_locks.dart';
import 'package:media_io/src/platform/web_locks_stub.dart';
import 'package:media_io/src/record/buffer_ledger.dart';
import 'package:media_io/src/record/recorder_service.dart';
import 'package:media_io/src/record/recording_output.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;

import 'fake_engines.dart';
import 'fake_stopwatch.dart';

/// Runs [future] to completion in fake time without moving the clock (microtasks and timers
/// due now). Fails when it does not complete.
T settle<T>(FakeAsync async, Future<T> future) {
  var done = false;
  T? value;
  Object? error;
  StackTrace? stack;
  future.then(
    (v) {
      value = v;
      done = true;
    },
    onError: (Object e, StackTrace st) {
      error = e;
      stack = st;
      done = true;
    },
  );
  for (var i = 0; i < 50 && !done; i++) {
    async.elapse(Duration.zero);
  }
  if (!done) fail('the future did not complete');
  if (error != null) Error.throwWithStackTrace(error!, stack!);
  return value as T;
}

/// What the wrappers saw, in order: 'begin', 'append', 'readAll', 'listDrafts', 'discard',
/// 'put', 'createRecording', 'settings.get'.
final class StoreLog {
  final List<String> calls = [];

  /// Only these names, in order.
  List<String> only(Set<String> names) => [
    for (final c in calls)
      if (names.contains(c)) c,
  ];
}

final class LoggedDrafts implements core.RecordingDraftStore {
  LoggedDrafts(this.inner, this.log);

  final core.RecordingDraftStore inner;
  final StoreLog log;

  /// While set, appends wait for it before reaching the store (a frozen tab).
  Completer<void>? appendGate;

  /// The next readAll throws this.
  Object? readAllError;

  /// The next appends throw these, in order (a blob write failure — 6.8.5).
  final List<Object> appendErrors = [];

  /// Every append that reached the store: (bytes, activeMs).
  final List<({int bytes, int activeMs})> appends = [];

  @override
  Future<core.RecordingDraft> begin({
    required core.RecordingId recordingId,
    required core.NoteId noteId,
    required String mimeType,
    required core.EpochMillis startedAt,
  }) {
    log.calls.add('begin');
    return inner.begin(
      recordingId: recordingId,
      noteId: noteId,
      mimeType: mimeType,
      startedAt: startedAt,
    );
  }

  @override
  Future<void> append(
    String draftId,
    Uint8List chunk, {
    required int activeMs,
  }) async {
    final gate = appendGate;
    if (gate != null) await gate.future;
    log.calls.add('append');
    if (appendErrors.isNotEmpty) {
      Error.throwWithStackTrace(appendErrors.removeAt(0), StackTrace.current);
    }
    appends.add((bytes: chunk.length, activeMs: activeMs));
    await inner.append(draftId, chunk, activeMs: activeMs);
  }

  void openAppends() {
    final g = appendGate;
    appendGate = null;
    g?.complete();
  }

  @override
  Future<List<core.RecordingDraft>> listDrafts() {
    log.calls.add('listDrafts');
    return inner.listDrafts();
  }

  @override
  Future<Uint8List> readAll(String draftId) {
    log.calls.add('readAll');
    final e = readAllError;
    if (e != null) {
      readAllError = null;
      return Future.error(e);
    }
    return inner.readAll(draftId);
  }

  @override
  Future<void> discard(String draftId) {
    log.calls.add('discard');
    return inner.discard(draftId);
  }
}

final class LoggedAssets implements core.AssetStore {
  LoggedAssets(this.inner, this.log);

  final core.AssetStore inner;
  final StoreLog log;

  /// put() throws these, in order.
  final List<Object> putErrors = [];

  /// The bytes given to put.
  final List<Uint8List> putBytes = [];

  @override
  Future<core.Asset> put(
    Uint8List bytes, {
    required core.AssetType type,
    required String mimeType,
    String? fileName,
  }) {
    log.calls.add('put');
    putBytes.add(bytes);
    if (putErrors.isNotEmpty) return Future.error(putErrors.removeAt(0));
    return inner.put(bytes, type: type, mimeType: mimeType, fileName: fileName);
  }

  @override
  Future<core.Asset?> getAsset(core.AssetId id) => inner.getAsset(id);

  @override
  Future<Uint8List?> readBytes(core.AssetId id) => inner.readBytes(id);

  @override
  Future<bool> hasBytes(core.AssetId id) => inner.hasBytes(id);

  @override
  Future<void> putDownloadedBytes(core.AssetId id, Uint8List bytes) =>
      inner.putDownloadedBytes(id, bytes);

  @override
  Future<List<core.Asset>> listAssets({bool? hasLocalBytes, bool? uploaded}) =>
      inner.listAssets(hasLocalBytes: hasLocalBytes, uploaded: uploaded);

  @override
  Future<void> markUploaded(core.AssetId id, String storagePath) =>
      inner.markUploaded(id, storagePath);

  @override
  Future<core.AssetStorageUsage> usage() => inner.usage();

  @override
  Stream<core.AssetId> get bytesArrived => inner.bytesArrived;
}

final class LoggedRecordings implements core.RecordingRepository {
  LoggedRecordings(this.inner, this.log);

  final core.RecordingRepository inner;
  final StoreLog log;

  /// createRecording throws these, in order.
  final List<Object> createErrors = [];

  @override
  Future<core.Recording> createRecording({
    required core.RecordingId id,
    required core.NoteId noteId,
    required core.AssetId assetId,
    required int durationMs,
    required core.EpochMillis startedAt,
    String? title,
  }) {
    log.calls.add('createRecording');
    if (createErrors.isNotEmpty) {
      return Future.error(createErrors.removeAt(0));
    }
    return inner.createRecording(
      id: id,
      noteId: noteId,
      assetId: assetId,
      durationMs: durationMs,
      startedAt: startedAt,
      title: title,
    );
  }

  @override
  Stream<List<core.Recording>> watchRecordings(core.NoteId noteId) =>
      inner.watchRecordings(noteId);

  @override
  Future<List<core.Recording>> recordingsOf(core.NoteId noteId) =>
      inner.recordingsOf(noteId);

  @override
  Future<core.Recording?> getRecording(core.RecordingId id) =>
      inner.getRecording(id);

  @override
  Future<void> renameRecording(core.RecordingId id, String? title) =>
      inner.renameRecording(id, title);

  @override
  Future<void> deleteRecording(core.RecordingId id) =>
      inner.deleteRecording(id);

  @override
  Future<int> audioBytesOf(core.NoteId noteId) => inner.audioBytesOf(noteId);
}

final class LoggedSettings implements core.SettingsRepository {
  LoggedSettings(this.inner, this.log);

  final core.SettingsRepository inner;
  final StoreLog log;

  /// get() of these keys throws.
  final Set<String> failingKeys = {};

  @override
  Future<T> get<T>(core.SettingKey<T> key) {
    log.calls.add('settings.get');
    if (failingKeys.contains(key.name)) {
      return Future.error(StateError('settings read failed'));
    }
    return inner.get(key);
  }

  @override
  Stream<T> watch<T>(core.SettingKey<T> key) => inner.watch(key);

  @override
  Future<void> set<T>(core.SettingKey<T> key, T value) => inner.set(key, value);

  @override
  Future<void> reset<T>(core.SettingKey<T> key) => inner.reset(key);

  @override
  Stream<core.SettingsSnapshot> watchAll() => inner.watchAll();
}

/// One 'tab': a recorder service with its own engine and logged stores over a shared store.
final class RecorderTab {
  RecorderTab(
    this.world, {
    FakeRecorderEngine? engine,
    WebLocks? locks,
    MediaIoConfig config = const MediaIoConfig(),
  }) : engine = engine ?? FakeRecorderEngine() {
    drafts = LoggedDrafts(world.store.recordingDrafts, log);
    assets = LoggedAssets(world.store.assets, log);
    recordings = LoggedRecordings(world.store.recordings, log);
    settings = LoggedSettings(world.store.settings, log);
    service = MediaRecorderService(
      stores: () => RecorderStores(
        drafts: drafts,
        assets: assets,
        recordings: recordings,
        settings: settings,
      ),
      now: world.store.clock.now,
      config: config,
      engine: this.engine,
      locks: locks ?? const UnavailableWebLocks(),
      stopwatch: () => FakeStopwatch(() => world.async.elapsed),
      ledger: ledger,
    );
  }

  final RecorderWorld world;
  final FakeRecorderEngine engine;
  final StoreLog log = StoreLog();
  final BufferLedger ledger = BufferLedger();
  late final LoggedDrafts drafts;
  late final LoggedAssets assets;
  late final LoggedRecordings recordings;
  late final LoggedSettings settings;
  late final MediaRecorderService service;

  /// Every status the service emitted (from construction).
  late final List<core.RecorderStatus> statuses = _listen();

  List<core.RecorderStatus> _listen() {
    final out = <core.RecorderStatus>[];
    service.statusStream.listen(out.add);
    return out;
  }

  List<core.RecorderPhase> get phases => [for (final s in statuses) s.phase];

  FakeEngineSession get session => engine.session!;

  T wait<T>(Future<T> f) => settle(world.async, f);

  /// start() and let the engine's EngineStarted in.
  void start(core.RecordingId recordingId, {core.NoteId? noteId}) {
    statuses; // listen from here at the latest
    wait(
      service.start(recordingId: recordingId, noteId: noteId ?? world.noteId),
    );
  }

  /// Fake time passes; a web chunk of [chunkBytes] per [chunkEvery] while recording.
  void record(
    Duration total, {
    Duration chunkEvery = const Duration(seconds: 1),
    int chunkBytes = 64,
  }) {
    var left = total;
    while (left > Duration.zero) {
      final step = left < chunkEvery ? left : chunkEvery;
      world.async.elapse(step);
      left -= step;
      if (engine.writesDraftChunks &&
          service.status.phase == core.RecorderPhase.recording) {
        session.chunk(Uint8List(chunkBytes));
        world.async.elapse(Duration.zero);
      }
    }
  }
}

/// CORE's fake store in fake time, one note in it.
final class RecorderWorld {
  RecorderWorld(this.async)
    : store = core_testing.createFakeNoteStore(
        clock: async.getClock(DateTime.utc(2026, 11, 6, 9)),
      ) {
    noteId = settle(async, store.library.createNote(title: 'Lecture')).id;
  }

  final FakeAsync async;
  final core.NoteStore store;
  late final core.NoteId noteId;

  /// A fresh, valid recording id.
  core.RecordingId recordingId() => store.ids.newId();

  T wait<T>(Future<T> f) => settle(async, f);

  void close() => settle(async, store.close());
}
