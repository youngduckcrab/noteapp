import 'package:note_core/note_core.dart';

import 'sync_local_store.dart';

/// Production adapter: sync = store.sync, assets = store.assets,
/// localChanges = store.changes where origin ∈ {local, undo, redo}.
final class CoreSyncLocalStore implements SyncLocalStore {
  CoreSyncLocalStore(NoteStore store) : _store = store;

  final NoteStore _store;

  /// Origins that schedule a push (5.1.3 '보내기 예약 신호'): remote writes (applyRemote,
  /// commitRepairs, reassignOwner) and loads do not.
  static const Set<ChangeOrigin> _localOrigins = {
    ChangeOrigin.local,
    ChangeOrigin.undo,
    ChangeOrigin.redo,
  };

  @override
  SyncStore get sync => _store.sync;

  @override
  AssetStore get assets => _store.assets;

  /// One event per local / undo / redo commit (ChangeBatch.origin only — 4.9, C12-02).
  @override
  Stream<void> get localChanges => _store.changes
      .where((batch) => _localOrigins.contains(batch.origin))
      .map((_) {});
}
