// CountingNoteStore (docs/plans/01-infra.md 5.7): CORE's fake store with
// counters and injectable delays / failures.
import 'dart:async';
import 'dart:typed_data';

import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';

/// A [NoteStore] that delegates to [inner] (a fresh `createFakeNoteStore()`
/// by default) and counts flush / close / refreshStorageInfo calls.
///
/// - [flushGate]: when set, flush() and exportBackupJson() wait for it (a
///   commit that keeps being retried, 계약 7.2.9 v1.2).
/// - [emitStatus]: replaces [persistenceStatus] and sends it to
///   [persistenceStatusStream] (which still sends the current value first to
///   every new listener, 계약 7.2.12 v1.1).
/// - [refreshResult]: when set, refreshStorageInfo() returns it and
///   [storageInfo] becomes it. [refreshGate] (when set) holds
///   refreshStorageInfo() until it completes; [refreshError] makes it throw.
/// - [exportBackupResult]: a Uint8List to return or an error to throw.
///   [exportGate] (when set) holds exportBackupJson() only (after
///   [flushGate]) — a cancel while the export itself is pending.
///   exportBackupJson() never reaches the B2 fake (UnimplementedError there).
final class CountingNoteStore implements NoteStore {
  CountingNoteStore({
    NoteStore? inner,
    this.flushDelay = Duration.zero,
    this.flushError,
    this.closeDelay = Duration.zero,
    this.closeError,
    this.flushGate,
    this.refreshResult,
    this.refreshGate,
    this.refreshError,
    this.exportBackupResult,
    this.exportGate,
  }) : inner = inner ?? createFakeNoteStore();

  final NoteStore inner;

  Duration flushDelay;
  Object? flushError;
  Duration closeDelay;
  Object? closeError;
  Completer<void>? flushGate;
  StorageInfo? refreshResult;
  Completer<void>? refreshGate;
  Object? refreshError;
  Object? exportBackupResult;
  Completer<void>? exportGate;

  int flushCount = 0;
  int closeCount = 0;
  int refreshCount = 0;
  int exportCount = 0;

  StorageInfo? _refreshed;
  PersistenceStatus? _status;
  final StreamController<PersistenceStatus> _statusEvents =
      StreamController<PersistenceStatus>.broadcast(sync: true);

  /// Makes [status] the current persistence status and sends it to the
  /// listeners of [persistenceStatusStream].
  void emitStatus(PersistenceStatus status) {
    _status = status;
    _statusEvents.add(status);
  }

  /// Listeners currently attached to [persistenceStatusStream].
  bool get hasStatusListeners => _statusEvents.hasListener;

  @override
  PersistenceStatus get persistenceStatus => _status ?? inner.persistenceStatus;

  @override
  Stream<PersistenceStatus> get persistenceStatusStream =>
      Stream<PersistenceStatus>.multi((controller) {
        controller.add(persistenceStatus);
        final own = _statusEvents.stream.listen(controller.add);
        // The inner store's later changes, while emitStatus was not used.
        final fromInner = inner.persistenceStatusStream.skip(1).listen((s) {
          if (_status == null) controller.add(s);
        });
        controller.onCancel = () async {
          await own.cancel();
          await fromInner.cancel();
        };
      }, isBroadcast: true);

  @override
  StorageInfo get storageInfo => _refreshed ?? inner.storageInfo;

  @override
  Future<StorageInfo> refreshStorageInfo() async {
    refreshCount++;
    final gate = refreshGate;
    if (gate != null) await gate.future;
    if (refreshError case final error?) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
    final result = refreshResult;
    if (result == null) return inner.refreshStorageInfo();
    _refreshed = result;
    return result;
  }

  @override
  Future<void> flush() async {
    flushCount++;
    final gate = flushGate;
    if (gate != null) await gate.future;
    if (flushDelay > Duration.zero) await Future<void>.delayed(flushDelay);
    if (flushError case final error?) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
    await inner.flush();
  }

  @override
  Future<void> close() async {
    closeCount++;
    if (closeDelay > Duration.zero) await Future<void>.delayed(closeDelay);
    if (closeError case final error?) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
    await inner.close();
  }

  @override
  Future<Uint8List> exportBackupJson() async {
    exportCount++;
    final gate = flushGate;
    if (gate != null) await gate.future;
    final ownGate = exportGate;
    if (ownGate != null) await ownGate.future;
    return switch (exportBackupResult) {
      final Uint8List bytes => bytes,
      null => throw UnimplementedError(
        'CountingNoteStore.exportBackupResult is not set',
      ),
      final Object error => Error.throwWithStackTrace(
        error,
        StackTrace.current,
      ),
    };
  }

  @override
  OwnerId get ownerId => inner.ownerId;
  @override
  LibraryRepository get library => inner.library;
  @override
  TrashRepository get trash => inner.trash;
  @override
  PenPresetRepository get penPresets => inner.penPresets;
  @override
  SettingsRepository get settings => inner.settings;
  @override
  NoteContentReader get content => inner.content;
  @override
  AssetStore get assets => inner.assets;
  @override
  ThumbnailCache get thumbnails => inner.thumbnails;
  @override
  SyncStore get sync => inner.sync;
  @override
  Stream<ChangeBatch> get changes => inner.changes;
  @override
  IdGenerator get ids => inner.ids;
  // Clock comes from package:clock, which note_core does not export and the
  // app does not depend on: the type is inferred from NoteStore.clock.
  @override
  // ignore: always_declare_return_types
  get clock => inner.clock;

  @override
  Future<NoteSession> openSession(
    NoteId noteId, {
    NoteSessionOptions options = const NoteSessionOptions(),
  }) => inner.openSession(noteId, options: options);
}
