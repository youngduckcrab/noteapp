// Helpers of the CORE T14 sync window tests: remote records, recording policies, a
// field-level LWW policy (the shape of SYNC 6.3.4) and a one-way push between stores.
import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/drift_note_store.dart';

const String kRemoteNode = '00000000000000ff';

/// A remote HLC value at [millis].
Hlc remoteAt(int millis, [int counter = 0]) =>
    Hlc(millis, counter, kRemoteNode);

/// A remote value just after every stamp [store] has made.
Hlc remoteAfter(DriftNoteStore store, [int plusMs = 1]) =>
    Hlc(store.hlc.last.millis + plusMs, 0, kRemoteNode);

/// [e] as SYNC hands it over: decoded from its JSON (local values at defaults) with
/// version = [versions].max.
SyncEntity decoded(SyncEntity e, EntityFieldVersions versions) =>
    EntityJson.decode(e.kind, {
      ...e.toJson(),
      'version': versions.max.toString(),
    });

/// A RemoteUpsert of [e] with [versions] (default: everything at [v]).
RemoteUpsert upsert(
  SyncEntity e,
  Hlc v, [
  Map<String, Hlc> overrides = const {},
]) {
  final versions = EntityFieldVersions(v, overrides);
  return RemoteUpsert(decoded(e, versions), versions);
}

/// One policy call as seen by CORE.
typedef PolicyCall = ({
  VersionedEntity? local,
  VersionedEntity remote,
  Set<String>? pending,
});

/// A policy that records its calls and answers with [decide].
final class RecordingPolicy {
  RecordingPolicy(this.decide);
  RecordingPolicy.always(MergeDecision d) : decide = ((_, _, _) => d);

  final MergeDecision Function(
    VersionedEntity? local,
    VersionedEntity remote,
    Set<String>? pending,
  )
  decide;
  final List<PolicyCall> calls = [];

  MergeDecision call(
    VersionedEntity? local,
    VersionedEntity remote,
    Set<String>? pending,
  ) {
    calls.add((local: local, remote: remote, pending: pending));
    return decide(local, remote, pending);
  }
}

/// JSON keys that are not LWW units (SYNC 6.3.1).
const Set<String> _metaKeys = {
  'id',
  'key',
  'version',
  'createdAt',
  'updatedAt',
};

/// Field-level LWW (the shape of SYNC 6.3.4, one unit per JSON key). With
/// [entityVersionOnly] a remote field wins only when it is newer than the local
/// ENTITY version — the control that diverges (SYNC 6.3.4 '엔티티 버전 하나로는 안 되는
/// 이유').
MergeDecision Function(VersionedEntity?, VersionedEntity, Set<String>?)
fieldLwwPolicy({bool entityVersionOnly = false}) => (local, remote, pending) {
  if (local == null) {
    return pending != null ? const KeepLocal() : const TakeRemote();
  }
  final l = local.entity.toJson();
  final r = remote.entity.toJson();
  final keys = {...l.keys, ...r.keys}.difference(_metaKeys);
  final merged = <String, Object?>{...l};
  final versionOf = <String, Hlc>{};
  final remoteWon = <String>{};
  final localWon = <String>{};
  for (final k in keys) {
    final lv = local.versions.of(k);
    final rv = remote.versions.of(k);
    final rWins = entityVersionOnly ? rv > local.versions.max : rv > lv;
    if (rWins) {
      remoteWon.add(k);
      merged[k] = r[k];
      versionOf[k] = rv;
    } else {
      if (lv > rv) localWon.add(k);
      versionOf[k] = lv;
    }
  }
  if (remoteWon.isEmpty) return const KeepLocal();
  if (localWon.isEmpty) return const TakeRemote();
  final base = versionOf.values.reduce((a, b) => a < b ? a : b);
  final versions = EntityFieldVersions(base, {
    for (final MapEntry(:key, :value) in versionOf.entries)
      if (value > base) key: value,
  });
  final lu = l['updatedAt'];
  final ru = r['updatedAt'];
  if (lu is int && ru is int) merged['updatedAt'] = lu > ru ? lu : ru;
  merged['version'] = versions.max.toString();
  final p = pending == null
      ? const <String>{}
      : pending.contains(kAllFields)
      ? keys
      : pending;
  return WriteMerged(
    EntityJson.decode(local.entity.kind, merged),
    versions,
    fieldsToUpload: p.intersection(localWon),
  );
};

/// Push of [from]'s outbox to [to] (snapshots read at push time), then ack on [from].
Future<RemoteApplyReport> push(
  NoteStore from,
  NoteStore to,
  RemoteMergePolicy policy,
) async {
  final entries = await from.sync.pendingChanges();
  final snaps = await from.sync.readVersioned([for (final e in entries) e.ref]);
  final changes = <RemoteChange>[
    for (var i = 0; i < entries.length; i++)
      if (snaps[i] case final v?)
        RemoteUpsert(v.entity, v.versions)
      else if (entries[i].kind == EntityKind.folder ||
          entries[i].kind == EntityKind.note)
        RemotePurge(entries[i].kind, entries[i].entityId),
  ];
  final report = await to.sync.applyRemote(changes, policy: policy);
  await from.sync.acknowledge([for (final e in entries) e.ack]);
  return report;
}
