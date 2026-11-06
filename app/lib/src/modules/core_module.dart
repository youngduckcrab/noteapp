/// Local storage adapter (docs/plans/01-infra.md 4.5.9, 6.4 `CoreModule`,
/// contract 7.2.12 / 7.3.3; 2nd round docs/plans/m5-7/01-infra.md 4.6.4,
/// 6.9 — the native storage paths).
library;

import 'dart:async';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:note_core/note_core.dart';

import '../bootstrap/app_module.dart';
import '../errors/app_error_log.dart';
import '../storage/native_storage_paths.dart';

/// Opens local storage via package:note_core (계약 7.2.12, X1) and owns
/// the store's lifetime.
final class CoreModule extends AppModule {
  CoreModule({
    this._open = openNoteStore,
    this._deleteLocalData = deleteLocalNoteData,
    this._configFor = defaultNoteStoreConfig,
    this._nativePaths = resolveNativeStoragePaths,
  });

  static const String moduleId = 'core';

  final Future<NoteStore> Function(NoteStoreConfig) _open;
  final Future<void> Function(NoteStoreConfig) _deleteLocalData;
  final NoteStoreConfig Function(AppModuleContext context) _configFor;
  final Future<NativeStoragePaths?> Function() _nativePaths;

  AppErrorLog? _errorLog;
  NoteStoreConfig? _lastConfig;
  Future<NoteStore>? _opening;
  NoteStore? _store;
  StreamSubscription<PersistenceStatus>? _status;
  bool _abandoned = false;
  Future<void>? _abandonedCleanup;

  /// Stores this module already closed (or started closing): never twice.
  final Set<NoteStore> _closed = Set<NoteStore>.identity();

  @override
  String get id => moduleId;
  @override
  String get label => '노트 저장소 여는 중';
  @override
  Duration get startTimeout => const Duration(seconds: 20); // critical

  /// paths = await nativePaths() (a throw → context.errorLog, source: module,
  /// and paths = null — CORE then reports storageUnavailable on a native
  /// build); non-null paths → `context.publish<NativeStoragePaths>(paths)`
  /// (defaultNoteStoreConfig reads them). If onStartAbandoned() ran while the
  /// paths were resolved → return without opening. Then (1st round)
  /// config = configFor(context); _opening = open(config); store = await
  /// _opening; if onStartAbandoned() already ran → return without publishing
  /// (the late store is closed there). Else `context.publish<NoteStore>(store)`;
  /// subscribes store.persistenceStatusStream (its first event is the current
  /// status, right after listen — 계약 7.2.12 v1.1) and logs every NEW
  /// lastError (lastErrorAt differs from the last seen event; a non-null
  /// lastError in the first event is logged once) to context.errorLog
  /// (source: module, 계약 7.4.5).
  @override
  Future<void> start(AppModuleContext context) async {
    _errorLog = context.errorLog;
    NativeStoragePaths? paths;
    try {
      paths = await _nativePaths();
    } on Object catch (error, stackTrace) {
      context.errorLog.add(
        AppErrorRecord.fromError(
          error,
          stackTrace,
          source: AppErrorSource.module,
        ),
      );
    }
    if (_abandoned) return;
    if (paths != null) context.publish<NativeStoragePaths>(paths);
    final config = _configFor(context);
    _lastConfig = config;
    final opening = _open(config);
    _opening = opening;
    final store = await opening;
    if (_abandoned) return;
    _store = store;
    context.publish<NoteStore>(store);
    _watchStatus(store, context.errorLog);
  }

  void _watchStatus(NoteStore store, AppErrorLog errorLog) {
    var first = true;
    EpochMillis? lastSeenErrorAt;
    _status = store.persistenceStatusStream.listen(
      (status) {
        final error = status.lastError;
        final isNew = first || status.lastErrorAt != lastSeenErrorAt;
        first = false;
        lastSeenErrorAt = status.lastErrorAt;
        if (error == null || !isNew) return;
        final at = status.lastErrorAt;
        errorLog.add(
          AppErrorRecord.fromError(
            'note_core write failed '
            '(consecutiveFailures: ${status.consecutiveFailures}): $error',
            null,
            source: AppErrorSource.module,
            now: at == null ? null : DateTime.fromMillisecondsSinceEpoch(at),
          ),
        );
      },
      onError: (Object error, StackTrace stackTrace) {
        errorLog.add(
          AppErrorRecord.fromError(
            error,
            stackTrace,
            source: AppErrorSource.module,
          ),
        );
      },
    );
  }

  /// start() exceeded 20 s (INFRA-2-9). Marks the attempt abandoned; when
  /// _opening later completes with a NoteStore it is closed AT ONCE (close
  /// failure → errorLog, source: module); a late open failure is ignored (the
  /// timeout is already reported). Completes when that close has finished, so
  /// a retry's openNoteStore / deleteLocalNoteData never meets the late store
  /// (CORE 6.18: StateError while a store with that config is open).
  /// Idempotent; never closes a store twice.
  @override
  Future<void> onStartAbandoned() => _abandonedCleanup ??= _cleanUpLate();

  Future<void> _cleanUpLate() async {
    _abandoned = true;
    final opening = _opening;
    if (opening == null) return;
    final NoteStore late;
    try {
      late = await opening;
    } on Object {
      return; // The timeout is already reported.
    }
    if (identical(_store, late)) {
      // start() finished in the same turn as the timeout and published it.
      _store = null;
      _cancelStatus();
    }
    await _close(late);
  }

  /// [noteStoreProvider.overrideWithValue(store)] — the only CORE override.
  @override
  List<Override> overrides() {
    final store = _store;
    if (store == null) {
      throw StateError('CoreModule.overrides() before a successful start()');
    }
    return [noteStoreProvider.overrideWithValue(store)];
  }

  /// store.flush(); the caller enforces 500 ms.
  @override
  Future<void> onAppHidden() async {
    await _store?.flush();
  }

  /// Cancels the status subscription, then store.close().
  @override
  Future<void> stop() async {
    final store = _store;
    _store = null;
    _cancelStatus();
    if (store != null && _closed.add(store)) await store.close();
  }

  /// No event reaches the listener once cancel() was called; its Future is
  /// not awaited (a broadcast stream's cancel can complete in the root zone,
  /// which a fake_async test never runs).
  void _cancelStatus() {
    unawaited(_status?.cancel());
    _status = null;
  }

  /// `() => deleteLocalData(<config of the last start attempt>)`.
  @override
  Future<void> Function()? get resetLocalData => _resetLocalData;

  Future<void> _resetLocalData() async {
    final config = _lastConfig;
    if (config == null) {
      throw StateError('CoreModule.resetLocalData before start()');
    }
    await _deleteLocalData(config);
  }

  /// True for NoteStoreOpenException with reason migrationFailed, corrupted
  /// or unknown. False for storageUnavailable (reset cannot help),
  /// newerSchema (would destroy data a newer build can read) and timeouts.
  @override
  bool canResetAfter(Object error) =>
      error is NoteStoreOpenException &&
      switch (error.reason) {
        NoteStoreOpenFailure.migrationFailed ||
        NoteStoreOpenFailure.corrupted ||
        NoteStoreOpenFailure.unknown => true,
        NoteStoreOpenFailure.storageUnavailable ||
        NoteStoreOpenFailure.newerSchema => false,
      };

  /// Closes [store] once; a failure goes to the error log (source: module).
  Future<void> _close(NoteStore store) async {
    if (!_closed.add(store)) return;
    try {
      await store.close();
    } on Object catch (error, stackTrace) {
      _errorLog?.add(
        AppErrorRecord.fromError(
          error,
          stackTrace,
          source: AppErrorSource.module,
        ),
      );
    }
  }
}

/// NoteStoreConfig(
///   ownerId: context.ownerId,            // new database only (S7)
///   web: WebStorageConfig(
///     sqlite3WasmPath: context.web.resolveAppUrl('sqlite3.wasm'),
///     driftWorkerPath: context.web.resolveAppUrl('drift_worker.js'),
///   ),
///   nativeDatabasePath: paths?.databasePath,
///   nativeAssetDirectoryPath: paths?.assetDirectoryPath,
/// ) with paths = `context.maybe<NativeStoragePaths>()` — every other field
/// keeps the CORE 4.8 default (databaseName 'noteapp',
/// requestPersistentStorage true, …).
/// 계약 7.2.12 · 7.4.3 (v1.1, C11-11): on the web both paths are ABSOLUTE
/// URLs resolved against document.baseURI; CORE's Uri.base.resolve(path)
/// returns them unchanged. Never relative in production.
/// 계약 7.2.6 (v2.1, 공통-1): BOTH native fields come from the same published
/// NativeStoragePaths, or neither is set (the 1st-round shell passed none,
/// so the 1st-round APK could not keep notes). Static check:
/// tool/test/native_config_test.dart ('app shell storage paths').
NoteStoreConfig defaultNoteStoreConfig(AppModuleContext context) {
  final paths = context.maybe<NativeStoragePaths>();
  return NoteStoreConfig(
    ownerId: context.ownerId,
    web: WebStorageConfig(
      sqlite3WasmPath: context.web.resolveAppUrl('sqlite3.wasm'),
      driftWorkerPath: context.web.resolveAppUrl('drift_worker.js'),
    ),
    nativeDatabasePath: paths?.databasePath,
    nativeAssetDirectoryPath: paths?.assetDirectoryPath,
  );
}
