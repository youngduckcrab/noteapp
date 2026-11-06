// lib/src/record/recorder_service.dart — MediaRecorderService implements core.AudioRecorderService
// (m5-7/06-pdf 6.6, 4.2.3; contract 7.2.4 v2.1). Internal — other areas use CORE's port
// (core.audioRecorderServiceProvider, overridden by mediaIoOverrides — 4.2.2, PDF T37).
//
// States (6.6.1): idle → starting → recording ⇄ paused → finishing → idle; recording / paused →
// idle on cancel() and on a draft another window took (draftLost). One status value = one
// core.RecorderStatus, made with copyWith. Inside the service 'busy' is starting … finishing:
// start() then throws StateError and stop() follows that busy state (not CORE's UI-only
// isActive): stop() during starting waits for the start, during finishing returns the stop in
// progress (6.6.3 — never null while the engine records).
//
// Start order (4.2.3): starting → draft begin (with the media.bitRate read) → (web) the Web Lock
// 'noteapp-rec-<draftId>' → engine start → EngineStarted: clock start, recording. A failed start
// lets the lock go, discards the draft, goes idle + error and rethrows.
// Stop order (6.6.3, M-1, M-4): engine stop → clock stop → drain the draft writer → the bytes
// (web readAll / native file) → unsaved joined only when not empty → the length from the file's
// timeline → WebM head patch (one copy) → AssetStore.put(audio) → createRecording → draft discard
// → lock release → idle. A failed save keeps the draft (and the lock — recovery is for the next
// start-up) and throws MediaIoException(saveFailed). BufferLedger counts the full-size buffers.
// (P-B) A web recording of at least stopHandoffMinBytes leaves Blob([bytes]) in the playback
// hand-off right after createRecording (6.6.5 ③ — the panel's open after stop reads no bytes).
import 'dart:async';
import 'dart:typed_data';

import 'package:note_core/note_core.dart' as core;

import '../config.dart';
import '../errors.dart';
import '../platform/web_locks.dart';
import '../platform/web_locks_stub.dart';
import '../playback/handoff_blob.dart';
import '../providers.dart';
import '../tuning.dart';
import 'buffer_ledger.dart';
import 'draft_writer.dart';
import 'recorder_engine.dart';
import 'recording_clock.dart';
import 'recording_output.dart';
import 'recovery.dart';

final class MediaRecorderService implements core.AudioRecorderService {
  MediaRecorderService({
    required RecorderStores Function() stores,
    required this._now,
    required this.config,
    required this.engine,
    this._locks = const UnavailableWebLocks(),
    this._stopwatch = Stopwatch.new,
    BufferLedger? ledger,
    RecorderDiagnostics? diagnostics,
    this._handoff,
  }) : _storesOf = stores,
       ledger = ledger ?? BufferLedger(),
       diagnostics = diagnostics ?? RecorderDiagnostics();

  final RecorderStores Function() _storesOf;
  final DateTime Function() _now;
  final MediaIoConfig config;
  final RecorderEngine engine;
  final WebLocks _locks;
  final Stopwatch Function() _stopwatch;

  /// (P-B, 6.6.5 ③) The player hand-off: a large web recording leaves its Blob there on stop.
  final PlaybackHandoff? _handoff;

  /// The full-size buffers of the stop and recovery paths (6.6.5 — tests read peakCount).
  final BufferLedger ledger;

  /// Developer counters (6.14 — PDF T37).
  final RecorderDiagnostics diagnostics;

  late final DraftRecovery _recovery = DraftRecovery(
    stores: _stores,
    now: _now,
    config: config,
    engine: engine,
    locks: _locks,
    ledger: ledger,
    diagnostics: diagnostics,
    activeDraftId: () => _session?.draft?.draftId,
  );

  RecorderStores? _cachedStores;
  RecorderStores _stores() => _cachedStores ??= _storesOf();

  core.RecorderStatus _status = const core.RecorderStatus();
  final StreamController<core.RecorderStatus> _ctrl =
      StreamController.broadcast(sync: true);

  _Session? _session;
  Future<void>? _starting;
  Future<core.Recording?>? _stopping;
  bool _disposed = false;

  /// Locks of drafts whose save failed: kept until dispose (the draft is for the next start-up).
  final List<WebLockHold> _keptLocks = [];

  // ---- status -----------------------------------------------------------------------------

  @override
  core.RecorderStatus get status => _status;

  @override
  Stream<core.RecorderStatus> get statusStream => Stream.multi((c) {
    c.add(_status);
    final sub = _ctrl.stream.listen(c.add);
    c.onCancel = sub.cancel;
  });

  void _emit(core.RecorderStatus next) {
    if (next == _status) return;
    _status = next;
    if (!_ctrl.isClosed) _ctrl.add(next);
  }

  /// status.error while recording / paused: the interruption reason, else the storage error.
  Object? _errorOf(_Session s) => s.interruptError ?? s.storageError;

  void _emitSession(
    _Session s, {
    core.RecorderPhase? phase,
    bool? interrupted,
  }) {
    if (_session != s) return;
    _emit(
      _status.copyWith(
        phase: phase,
        activeMs: s.clock.elapsedMs,
        interrupted: interrupted,
        error: _errorOf(s),
        clearError: _errorOf(s) == null,
      ),
    );
  }

  void _toIdle({Object? error, bool interrupted = false}) {
    _session = null;
    _stopping = null;
    _emit(core.RecorderStatus(error: error, interrupted: interrupted));
  }

  // ---- support ----------------------------------------------------------------------------

  @override
  Future<core.AudioSupport> checkSupport({bool requestPermission = false}) =>
      engine.checkSupport(requestPermission: requestPermission);

  // ---- start ------------------------------------------------------------------------------

  @override
  Future<void> start({
    required core.RecordingId recordingId,
    required core.NoteId noteId,
  }) {
    if (_disposed) {
      return Future.error(StateError('The recorder was disposed'));
    }
    if (_status.phase != core.RecorderPhase.idle) {
      return Future.error(StateError('Another recording is active'));
    }
    final done = Completer<void>();
    final starting = done.future;
    _starting = starting;
    _emit(
      core.RecorderStatus(
        phase: core.RecorderPhase.starting,
        recordingId: recordingId,
        noteId: noteId,
        mimeType: engine.draftMimeType,
      ),
    );
    _start(
      recordingId,
      noteId,
    ).then(done.complete, onError: done.completeError);
    starting.then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
      if (identical(_starting, starting)) _starting = null;
    });
    return starting;
  }

  Future<void> _start(core.RecordingId recordingId, core.NoteId noteId) async {
    final s = _Session(
      recordingId: recordingId,
      noteId: noteId,
      clock: RecordingClock(stopwatch: _stopwatch),
    );
    _session = s;
    try {
      final support = await engine.checkSupport(requestPermission: false);
      if (support != core.AudioSupport.supported) {
        throw UnsupportedError('Recording is not supported here ($support)');
      }
      final stores = _stores();
      final startedAt = _now().millisecondsSinceEpoch;
      // the bit rate is read while begin runs, so the start does not get longer (4.6)
      final bitRate = _readBitRate(stores.settings);
      s.draft = await stores.drafts.begin(
        recordingId: recordingId,
        noteId: noteId,
        mimeType: engine.draftMimeType,
        startedAt: startedAt,
      );
      final draftId = s.draft!.draftId;
      try {
        s.lock = await _locks.acquire(recordingLockName(draftId));
      } on Object {
        s.lock = null; // the time rule only
      }
      if (engine.writesDraftChunks) {
        s.writer = DraftWriter(
          drafts: stores.drafts,
          draftId: draftId,
          activeMs: () => s.clock.elapsedMs,
          keepAliveMs: MediaTuning.pausedKeepAliveMs(config.webDraftChunkMs),
          onSignal: (signal, error) => _onWriterSignal(s, signal, error),
        );
      }
      final effective = await bitRate;
      diagnostics
        ..lastBitRate = effective.bitRate
        ..lastBitRateSource = effective.source;
      final engineSession = await engine.start(
        RecorderEngineRequest(
          recordingId: recordingId,
          noteId: noteId,
          config: config,
          bitRate: effective.bitRate,
          onChunk: (chunk) => _onChunk(s, chunk),
        ),
      );
      s.engine = engineSession;
      final started = Completer<void>();
      s.events = engineSession.events.listen(
        (e) => _onEngineEvent(s, e, started),
        onError: (Object e) => _onEngineEvent(s, EngineFailed(e), started),
      );
      await started.future;
    } on Object catch (e) {
      await _abortStart(s);
      // not supported: like CORE's recorders, no error in the status (only the exception)
      if (_session == s) _toIdle(error: e is UnsupportedError ? null : e);
      rethrow;
    }
  }

  /// A failed start: lock released, engine cancelled, draft discarded (4.2.3).
  Future<void> _abortStart(_Session s) async {
    s.closeTimers();
    s.cancelEvents();
    final writer = s.writer;
    if (writer != null) {
      writer.close();
      await writer.drain();
    }
    final engineSession = s.engine;
    if (engineSession != null) {
      try {
        await engineSession.cancel();
      } on Object {
        // already failed
      }
    }
    s.lock?.release();
    final draft = s.draft;
    if (draft != null) {
      try {
        await _stores().drafts.discard(draft.draftId);
      } on Object {
        // nothing more to do — an orphan draft is recovered (or dropped) later
      }
    }
  }

  Future<({int bitRate, BitRateSource source})> _readBitRate(
    core.SettingsRepository settings,
  ) async {
    try {
      final v = await settings.get(MediaSettingKeys.bitRate);
      if (v == 0) {
        return (bitRate: config.bitRate, source: BitRateSource.config);
      }
      if (v >= 32000 && v <= 128000) {
        return (bitRate: v, source: BitRateSource.setting);
      }
      return (bitRate: config.bitRate, source: BitRateSource.settingIgnored);
    } on Object {
      // a setting never blocks recording (4.6)
      return (bitRate: config.bitRate, source: BitRateSource.config);
    }
  }

  // ---- engine events, chunks, writer signals ---------------------------------------------

  void _onEngineEvent(
    _Session s,
    RecorderEngineEvent e,
    Completer<void> started,
  ) {
    if (_session != s) return;
    switch (e) {
      case EngineStarted():
        if (started.isCompleted || s.started) return;
        s.started = true;
        s.clock.start();
        final engineSession = s.engine!;
        _emit(
          _status.copyWith(
            phase: core.RecorderPhase.recording,
            mimeType: engineSession.mimeType,
            crossPlatformPlayable: engineSession.crossPlatformPlayable,
            backgroundCapable: engineSession.backgroundCapable,
            activeMs: 0,
          ),
        );
        s.statusTimer = Timer.periodic(
          MediaTuning.statusTick,
          (_) => _emitSession(s),
        );
        started.complete();
      case EngineFailed(:final error):
        if (!started.isCompleted) {
          started.completeError(
            MediaIoException(
              MediaErrorCode.engineFailed,
              detail: 'start',
              cause: error,
            ),
          );
          return;
        }
        _systemPause(
          s,
          MediaIoException(MediaErrorCode.engineFailed, cause: error),
        );
      case EnginePaused(:final bySystem, :final reason):
        if (!bySystem) {
          if (_status.phase == core.RecorderPhase.recording) {
            _enterPaused(s, interrupted: false);
          }
          return;
        }
        _systemPause(s, reason == null ? null : MediaIoException(reason));
      case EngineResumed():
        if (_status.phase == core.RecorderPhase.paused) _enterRecording(s);
    }
  }

  void _systemPause(_Session s, MediaIoException? reason) {
    final phase = _status.phase;
    if (phase == core.RecorderPhase.recording) {
      s.interruptError = reason;
      _enterPaused(s, interrupted: true);
    } else if (phase == core.RecorderPhase.paused) {
      // already paused (by the user): the system reason wins (e.g. the microphone is gone)
      if (reason != null) s.interruptError = reason;
      _emitSession(s, interrupted: true);
    }
  }

  void _enterPaused(_Session s, {required bool interrupted}) {
    s.clock.pause();
    s.writer?.paused = true; // keep-alive empty chunks (6.8.5)
    if (!interrupted) s.interruptError = null;
    _emitSession(s, phase: core.RecorderPhase.paused, interrupted: interrupted);
  }

  void _enterRecording(_Session s) {
    s.clock.resume();
    s.writer?.paused = false;
    s.interruptError = null;
    _emitSession(s, phase: core.RecorderPhase.recording, interrupted: false);
  }

  void _onChunk(_Session s, Uint8List chunk) {
    final writer = s.writer;
    if (_session != s || writer == null) return;
    writer.add(chunk);
    if (s.started && _status.phase == core.RecorderPhase.recording) {
      _emitSession(s);
    }
  }

  void _onWriterSignal(_Session s, DraftWriterSignal signal, Object? error) {
    if (_session != s) return;
    switch (signal) {
      case DraftWriterSignal.storageFailed:
        s.storageError = MediaIoException(
          MediaErrorCode.storageFailed,
          cause: error,
        );
        _emitSession(s);
      case DraftWriterSignal.storageRecovered:
        s.storageError = null;
        _emitSession(s);
      case DraftWriterSignal.backlogFull:
        if (_status.phase != core.RecorderPhase.recording) return;
        unawaited(_pauseForBacklog(s));
      case DraftWriterSignal.draftLost:
        unawaited(_loseDraft(s));
    }
  }

  Future<void> _pauseForBacklog(_Session s) async {
    try {
      await s.engine?.pause();
    } on Object {
      // paused below anyway
    }
    if (_session != s || _status.phase != core.RecorderPhase.recording) return;
    s.interruptError = const MediaIoException(MediaErrorCode.storageBacklog);
    _enterPaused(s, interrupted: true);
  }

  /// (v2.1) append → StateError: another window recovered or discarded the draft (6.8.5).
  Future<void> _loseDraft(_Session s) async {
    final phase = _status.phase;
    if (phase != core.RecorderPhase.recording &&
        phase != core.RecorderPhase.paused) {
      return; // starting / finishing deal with it themselves
    }
    _toIdle(
      error: const MediaIoException(MediaErrorCode.draftLost),
      interrupted: true,
    );
    s.closeTimers();
    s.clock.stop();
    s.cancelEvents();
    try {
      await s.engine?.cancel();
    } on Object {
      // the tracks are stopped either way
    }
    s.lock?.release();
  }

  // ---- pause / resume ---------------------------------------------------------------------

  @override
  Future<void> pause() async {
    final s = _session;
    if (s == null || _status.phase != core.RecorderPhase.recording) return;
    await s.engine!.pause();
    if (_session == s && _status.phase == core.RecorderPhase.recording) {
      _enterPaused(s, interrupted: false);
    }
  }

  @override
  Future<void> resume() async {
    final s = _session;
    if (s == null || _status.phase != core.RecorderPhase.paused) return;
    await s.engine!.resume(); // web: StateError while hidden (M-2)
    if (_session == s && _status.phase == core.RecorderPhase.paused) {
      _enterRecording(s);
    }
  }

  @override
  int? offsetNowMs() {
    final s = _session;
    return s == null ? null : offsetNowMsOf(_status.phase, s.clock);
  }

  // ---- stop -------------------------------------------------------------------------------

  @override
  Future<core.Recording?> stop() async {
    if (_status.phase == core.RecorderPhase.finishing) return _stopping;
    if (_status.phase == core.RecorderPhase.starting) {
      final starting = _starting;
      if (starting != null) {
        try {
          await starting;
        } on Object {
          return null; // the start failed: nothing recorded (start()'s caller has the error)
        }
      }
      final stopping = _stopping;
      if (stopping != null) return stopping;
    }
    final phase = _status.phase;
    if (phase != core.RecorderPhase.recording &&
        phase != core.RecorderPhase.paused) {
      return null;
    }
    return _stopping = _finish(_session!);
  }

  Future<core.Recording?> _finish(_Session s) async {
    _emitSession(s, phase: core.RecorderPhase.finishing);
    s.closeTimers();
    final stores = _stores();
    final draft = s.draft!;
    final engineSession = s.engine!;

    RecorderEngineFile? file;
    try {
      file = (await engineSession.stop()).file;
    } on Object {
      // web: the chunks so far are in the draft; native: the file the engine left, if any
      if (!engine.writesDraftChunks) {
        file = await _leftoverFile(s.recordingId);
      }
    }
    final activeMs = s.clock.stop();
    s.cancelEvents();
    final unsaved = await s.writer?.drain() ?? const <Uint8List>[];
    s.writer?.close();
    if (s.writer?.isLost ?? false) {
      // another window took the draft while the last chunks were written (6.8.5)
      s.lock?.release();
      await _deleteFile(file);
      _toIdle(
        error: const MediaIoException(MediaErrorCode.draftLost),
        interrupted: true,
      );
      return null;
    }

    BufferHold? hold;
    try {
      // ① the bytes — one full-size buffer (6.6.5)
      var bytes = engine.writesDraftChunks
          ? await stores.drafts.readAll(draft.draftId)
          : (file == null ? Uint8List(0) : await file.read());
      hold = ledger.hold(bytes.length);
      final joined = joinUnsaved(bytes, unsaved, hold: hold, ledger: ledger);
      bytes = joined.bytes;
      hold = joined.hold;

      if (activeMs == 0 || bytes.isEmpty) {
        ledger.release(hold);
        hold = null;
        await _discardDraft(stores, draft.draftId);
        s.lock?.release();
        await _deleteFile(file);
        _toIdle();
        return null;
      }

      // ② the length from the file's timeline (6.6.4)
      final mimeType = engineSession.mimeType;
      final length = await measureRecording(
        bytes,
        mimeType: mimeType,
        clockMs: activeMs,
        file: file,
      );
      // ③ the head-only Duration patch (WebM — one copy, 6.6.5 ②)
      final patched = patchRecordingHead(
        bytes,
        mimeType: mimeType,
        durationMs: length.durationMs,
        hold: hold,
        ledger: ledger,
      );
      bytes = patched.bytes;
      hold = patched.hold;
      // ④ M-1: the asset first, then the recording row
      final recording = await storeRecording(
        stores,
        bytes,
        recordingId: s.recordingId,
        noteId: s.noteId,
        mimeType: mimeType,
        durationMs: length.durationMs,
        startedAt: draft.startedAt,
      );
      // ⑤ (web, P-B) ≥ stopHandoffMinBytes → Blob([bytes]) for the next open (no second read).
      if (engine.writesDraftChunks) {
        _handoff?.offer(recording.assetId, bytes, mimeType);
      }
      await _discardDraft(stores, draft.draftId);
      s.lock?.release();
      await _deleteFile(file);
      ledger.release(hold);
      hold = null;
      diagnostics.lastRecording = (
        mimeType: mimeType,
        durationMs: length.durationMs,
        source: length.source,
        clockMs: activeMs,
        patched: patched.patched,
      );
      _toIdle();
      return recording;
    } on Object catch (e) {
      if (hold != null) ledger.release(hold);
      diagnostics.lastSaveFailed = e;
      // the draft (and its lock) stay — the next start-up recovers it (CP-PDF-5)
      final lock = s.lock;
      if (lock != null) _keptLocks.add(lock);
      final failure = MediaIoException(
        MediaErrorCode.saveFailed,
        detail: 'the draft is kept for recovery',
        cause: e,
      );
      _toIdle(error: failure);
      throw failure;
    }
  }

  Future<RecorderEngineFile?> _leftoverFile(core.RecordingId id) async {
    try {
      return await engine.leftoverFile(id);
    } on Object {
      return null;
    }
  }

  Future<void> _discardDraft(RecorderStores stores, String draftId) async {
    try {
      await stores.drafts.discard(draftId);
    } on StateError {
      // already gone
    }
  }

  Future<void> _deleteFile(RecorderEngineFile? file) async {
    if (file == null) return;
    try {
      await file.delete();
    } on Object {
      // left for deleteOrphanFiles
    }
  }

  // ---- cancel -----------------------------------------------------------------------------

  @override
  Future<void> cancel() async {
    if (_status.phase == core.RecorderPhase.starting) {
      try {
        await _starting;
      } on Object {
        return;
      }
    }
    if (_status.phase == core.RecorderPhase.finishing) {
      try {
        await _stopping;
      } on Object {
        // the stop's caller has the error
      }
      return;
    }
    final s = _session;
    final phase = _status.phase;
    if (s == null ||
        (phase != core.RecorderPhase.recording &&
            phase != core.RecorderPhase.paused)) {
      return;
    }
    _toIdle();
    s.closeTimers();
    s.clock.stop();
    s.cancelEvents();
    try {
      await s.engine?.cancel(); // native: deletes the file
    } on Object {
      // discarded below anyway
    }
    final writer = s.writer;
    if (writer != null) {
      writer.close();
      await writer
          .drain(); // the append in flight, so nothing lands after the discard
    }
    await _discardDraft(_stores(), s.draft!.draftId);
    s.lock?.release();
  }

  // ---- recovery ---------------------------------------------------------------------------

  @override
  Future<List<core.RecordingDraft>> pendingDrafts() {
    if (_disposed) return Future.value(const []);
    return _recovery.pending();
  }

  @override
  Future<core.Recording?> recoverDraft(String draftId) {
    if (_disposed) {
      return Future.error(StateError('The recorder was disposed'));
    }
    return _recovery.recover(draftId);
  }

  /// Drafts out of automatic recovery (6.10.3 — the panel's stuck line, PDF T36b).
  Future<List<core.RecordingDraft>> stuckDrafts() => _recovery.stuck();

  // ---- dispose ----------------------------------------------------------------------------

  /// Provider teardown (4.2.3): a recording is NOT finished — web writes the last chunk, stops
  /// the tracks and lets the lock go; native stops the recorder and keeps the file and the
  /// draft row → recovered on the next launch (6.10).
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final starting = _starting;
    if (starting != null) {
      try {
        await starting;
      } on Object {
        // nothing started
      }
    }
    final stopping = _stopping;
    if (stopping != null) {
      try {
        await stopping;
      } on Object {
        // the draft stays
      }
    }
    final s = _session;
    final phase = _status.phase;
    if (s != null &&
        (phase == core.RecorderPhase.recording ||
            phase == core.RecorderPhase.paused)) {
      s.closeTimers();
      s.clock.stop();
      try {
        await s.engine
            ?.abandon(); // web: requestData → the last chunk to onChunk
      } on Object {
        // keep what is written
      }
      s.cancelEvents();
      final writer = s.writer;
      if (writer != null) {
        await writer.drain();
        writer.close();
      }
      s.lock?.release();
      _toIdle();
    }
    for (final lock in _keptLocks) {
      lock.release();
    }
    _keptLocks.clear();
    try {
      await engine.dispose();
    } on Object {
      // nothing more
    }
    unawaited(_ctrl.close());
  }
}

/// One recording from start() to idle.
final class _Session {
  _Session({
    required this.recordingId,
    required this.noteId,
    required this.clock,
  });

  final core.RecordingId recordingId;
  final core.NoteId noteId;
  final RecordingClock clock;
  core.RecordingDraft? draft;
  WebLockHold? lock;
  DraftWriter? writer;
  RecorderEngineSession? engine;
  StreamSubscription<RecorderEngineEvent>? events;
  Timer? statusTimer;
  bool started = false;

  /// Why the system paused (hiddenTab, microphoneLost, storageBacklog, engineFailed).
  MediaIoException? interruptError;

  /// storageFailed while unsaved chunks remain (6.8.5).
  MediaIoException? storageError;

  /// Not awaited: an engine stream has no onCancel to wait for, and the done future of a
  /// cancelled subscription can belong to the root zone.
  void cancelEvents() {
    final done = events?.cancel();
    events = null;
    if (done != null) unawaited(done);
  }

  void closeTimers() {
    statusTimer?.cancel();
    statusTimer = null;
    writer?.paused = false;
  }
}
