import 'package:note_core/note_core.dart';

/// SYNC's merge rule (6.3.4), passed as `policy:` to SyncStore.applyRemote. Pure (no I/O,
/// no clock, no randomness): CORE calls it inside the apply transaction (7.3.2 S-2).
abstract final class SyncMergePolicy {
  /// Matches typedef RemoteMergePolicy. A returned WriteMerged always has
  /// entity.version == versions.max.
  static MergeDecision decide(
    VersionedEntity? local,
    VersionedEntity remote,
    Set<String>? pendingLocalFields,
  ) => throw UnimplementedError('SYNC T4');
}
