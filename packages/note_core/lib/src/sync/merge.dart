// lib/src/sync/merge.dart — contract 00-overview 7.2.10 / CORE 4.6, 6.10.3.
import 'package:meta/meta.dart';

import '../common/ids.dart';
import '../model/sync_entity.dart';
import 'field_versions.dart';

sealed class RemoteChange {
  const RemoteChange();
  EntityKind get kind;
  String get id;
}

final class RemoteUpsert extends RemoteChange {
  const RemoteUpsert(this.entity, this.versions);
  final SyncEntity entity;
  final EntityFieldVersions versions;
  @override
  EntityKind get kind => entity.kind;
  @override
  String get id => entity.id;
}

final class RemotePurge extends RemoteChange {
  // folder or note: purges its trash group
  const RemotePurge(this.kind, this.id);
  @override
  final EntityKind kind;
  @override
  final String id;
}

sealed class MergeDecision {
  const MergeDecision();
}

final class KeepLocal extends MergeDecision {
  const KeepLocal();
}

final class TakeRemote extends MergeDecision {
  const TakeRemote({
    this.dropPendingLocal = true,
  }); // writes remote entity + remote versions

  /// (v1.3) A pending purge entry is deleted whatever dropPendingLocal says (the row exists again).
  final bool dropPendingLocal;
}

final class WriteMerged extends MergeDecision {
  const WriteMerged(this.entity, this.versions, {required this.fieldsToUpload});
  final SyncEntity entity; // its version must equal versions.max
  final EntityFieldVersions versions;

  /// The entity's outbox entry fields become EXACTLY this set (empty → entry deleted),
  /// rev bumped, seq kept. (v1.3) A pending purge entry becomes an upsert entry of this set.
  final Set<String> fieldsToUpload;
}

/// SYNC provides the rule; CORE calls it inside the apply transaction.
/// pendingLocalFields = changedFields of the entity's pending outbox entry, null if none.
/// (v1.1) An entry with op == purge (row already gone, so local == null) passes {kAllFields}.
typedef RemoteMergePolicy = MergeDecision Function(
  VersionedEntity? local,
  VersionedEntity remote,
  Set<String>? pendingLocalFields,
);

@immutable
final class RemoteApplyReport {
  // CORE 4.6
  const RemoteApplyReport({
    required this.taken,
    required this.kept,
    required this.merged,
    required this.purged,
    required this.affectedNoteIds,
  });

  // taken includes newly created entities
  final int taken, kept, merged, purged;
  final Set<NoteId> affectedNoteIds;
}

typedef RepairWrite = ({SyncEntity entity, Set<String> fields});
