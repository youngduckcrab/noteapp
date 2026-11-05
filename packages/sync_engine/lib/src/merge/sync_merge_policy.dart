import 'package:note_core/note_core.dart';

import '../model/field_units.dart';
import '../model/records.dart';
import 'field_merge.dart';

/// SYNC's merge rule (6.3.4), passed as `policy:` to SyncStore.applyRemote. Pure (no I/O,
/// no clock, no randomness): CORE calls it inside the apply transaction (7.3.2 S-2).
abstract final class SyncMergePolicy {
  /// Matches typedef RemoteMergePolicy. A returned WriteMerged always has
  /// entity.version == versions.max.
  static MergeDecision decide(
    VersionedEntity? local,
    VersionedEntity remote,
    Set<String>? pendingLocalFields,
  ) {
    if (local == null) {
      // A pending entry without a row is an unsent local purge: CORE passes
      // {kAllFields} for it (contract 7.2.10 v1.1). Keep the purge (SYNC-2-2).
      if (pendingLocalFields != null) return const KeepLocal();
      return const TakeRemote(dropPendingLocal: true);
    }
    final l = UpsertRecord.fromVersioned(local);
    final r = UpsertRecord.fromVersioned(remote);
    final result = FieldMerge.merge(l, r);
    // remoteWon = units the local row must change; localWon = units the
    // server copy lacks.
    if (result.changedForA.isEmpty) return const KeepLocal();
    if (result.changedForB.isEmpty) {
      return const TakeRemote(dropPendingLocal: true);
    }
    final pending = pendingLocalFields == null
        ? null
        : _expand(pendingLocalFields, l);
    final upload = <String>{
      if (pending != null)
        for (final unit in result.changedForB)
          for (final f in unit)
            if (pending.contains(f)) f,
    };
    return WriteMerged(
      result.merged.doc.toEntity(),
      result.merged.versions,
      fieldsToUpload: upload,
    );
  }

  /// '*' → every non-meta key of the local snapshot.
  static Set<String> _expand(Set<String> pending, UpsertRecord local) {
    if (!pending.contains(kAllFields)) return pending;
    return {
      for (final f in pending)
        if (f != kAllFields) f,
      for (final k in local.doc.json.keys)
        if (!FieldUnits.metaKeys.contains(k)) k,
    };
  }
}
