import 'package:clock/clock.dart';
import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart';

import '../local/sync_local_store.dart';

/// In-memory SyncLocalStore. `sync` and `assets` implement the CORE contract sentences of
/// 7.2.10 / 7.2.11 (v1.1) one to one (table 5.1.4, locked by the shared SyncStore contract
/// suite that also runs on real CORE). Rows hold real CORE values (EntityJson.decode) with
/// EntityFieldVersions; HLC is note_core HlcClock(nodeId: nodeId, clock: clock).
/// v1.1 points the suite checks (C-09, C-25):
///  - policy pendingLocalFields: entry changedFields, null without entry, {kAllFields} for an
///    op-purge entry (row gone → local == null);
///  - applyRemote / commitRepairs ignore device-local values of the handed-over entity:
///    Note.lastOpenedAt kept (new row null), pageCount / firstPageId recomputed from active
///    pages, Page.contentRevision current + 1 when the page row or its strokes were written
///    (new row 0), Asset.hasLocalBytes kept (new row: whether the fake blob map has the bytes);
///  - ChangeBatch origin: localWrite / localPurge / assets.put / markUploaded /
///    duplicateNoteForRecovery fire localChanges; applyRemote / commitRepairs / reassignOwner
///    do not.
final class FakeLocalStore implements SyncLocalStore {
  FakeLocalStore({
    required String nodeId,
    required Clock clock,
    OwnerId ownerId = kLocalOwnerId,
  });

  @override
  SyncStore get sync => throw UnimplementedError('SYNC T6');

  @override
  AssetStore get assets => throw UnimplementedError('SYNC T6');

  @override
  Stream<void> get localChanges => throw UnimplementedError('SYNC T6');

  /// One local commit as CORE records it (CORE 6.5 / 6.10): one fresh HLC for the call;
  /// each write's changedFields ('*' = all) get it in the field versions; 'version' and
  /// 'updatedAt' are set; outbox entries merge (seq kept, rev++, field union, purge wins)
  /// with the noteId / pageId hints; the parent note's updatedAt is bumped without outbox
  /// (C-9); one localChanges event.
  void localWrite(List<FakeLocalWrite> writes) =>
      throw UnimplementedError('SYNC T6');

  /// Trash purge as CORE does it (CORE 6.8): rows of [group] and of the group notes' pages /
  /// strokes / recordings removed, one purge entry per folder / note of the group, their
  /// pending upserts become purges; one localChanges event (origin local). A later applyRemote
  /// on such an entity follows contract 7.2.10 v1.3 (C13-02): TakeRemote deletes the purge
  /// entry whatever dropPendingLocal says; WriteMerged(F) turns it into an upsert entry of F
  /// (seq kept, rev + 1; deleted when F is empty).
  void localPurge(EntityRef ref, {required List<EntityRef> group}) =>
      throw UnimplementedError('SYNC T6');

  /// Sets the device-local Note.lastOpenedAt like CORE markOpened (no outbox, no
  /// localChanges) — for contract check C-25.
  void markOpened(NoteId noteId) => throw UnimplementedError('SYNC T6');

  /// The next [count] writes through sync / assets throw StateError (localStoreFailure tests).
  /// This models an error thrown without retry; real CORE keeps a failing commit pending
  /// while its write queue retries (5.1.2 S-20), which the fake does not model.
  void failNextWrites(int count) => throw UnimplementedError('SYNC T6');

  Map<EntityRef, VersionedEntity> get rows =>
      throw UnimplementedError('SYNC T6');

  List<OutboxEntry> get outbox => throw UnimplementedError('SYNC T6');

  Map<String, String> get meta => throw UnimplementedError('SYNC T6');

  /// Every row as sorted JSON {entity.toJson(), versions.toJson()}, soft-deleted included,
  /// Note.updatedAt left out (CORE derives it locally — 5.1.2 S-11). For convergence checks.
  Map<String, Object?> canonicalDump() => throw UnimplementedError('SYNC T6');
}

@immutable
final class FakeLocalWrite {
  const FakeLocalWrite(this.kind, this.json, {required this.changedFields});
  final EntityKind kind;

  /// CORE 6.3 keys; 'version' / 'updatedAt' are set by the store.
  final Map<String, Object?> json;

  /// JSON keys (no meta keys) or {'*'}.
  final Set<String> changedFields;
}
