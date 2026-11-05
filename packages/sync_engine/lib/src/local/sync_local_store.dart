import 'package:note_core/note_core.dart';

abstract interface class SyncLocalStore {
  /// CORE SyncStore (contract 7.2.10): outbox, readVersioned, applyRemote, commitRepairs,
  /// meta KV, reassignOwner, duplicateNoteForRecovery.
  SyncStore get sync;

  /// CORE AssetStore (contract 7.2.11): getAsset, listAssets, readBytes, hasBytes,
  /// putDownloadedBytes, markUploaded, bytesArrived.
  AssetStore get assets;

  /// One event per CORE commit whose ChangeBatch.origin is local, undo or redo — local edits,
  /// repository commands (trash purge included), markUploaded, duplicateNoteForRecovery
  /// (contract 7.2.10 v1.1). Commits with origin remote (applyRemote, commitRepairs,
  /// reassignOwner) do not fire; the engine schedules its own push after commitRepairs
  /// (6.5.1). Each event also marks the local-purge view stale (6.7.4).
  Stream<void> get localChanges;
}
