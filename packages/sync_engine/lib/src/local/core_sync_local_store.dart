import 'package:note_core/note_core.dart';

import 'sync_local_store.dart';

/// Production adapter: sync = store.sync, assets = store.assets,
/// localChanges = store.changes where origin ∈ {local, undo, redo}.
final class CoreSyncLocalStore implements SyncLocalStore {
  CoreSyncLocalStore(NoteStore store);

  @override
  SyncStore get sync => throw UnimplementedError('SYNC T16');

  @override
  AssetStore get assets => throw UnimplementedError('SYNC T16');

  @override
  Stream<void> get localChanges => throw UnimplementedError('SYNC T16');
}
