// What a change chunk carries (6.4.4).
import 'package:note_core/note_core.dart';

import 'sync_doc.dart';

sealed class SyncRecord {
  const SyncRecord();
  EntityRef get ref;
}

/// Full snapshot of one entity plus CORE field versions (D2). RecordGate checks
/// doc.version == versions.max before apply (CORE rejects violations, contract 7.2.10).
final class UpsertRecord extends SyncRecord {
  const UpsertRecord(this.doc, this.versions);

  /// SyncDoc.fromEntity(local.entity) + local.versions.
  factory UpsertRecord.fromVersioned(VersionedEntity local) =>
      UpsertRecord(SyncDoc.fromEntity(local.entity), local.versions);

  final SyncDoc doc;
  final EntityFieldVersions versions;

  @override
  EntityRef get ref => doc.ref;

  /// RemoteUpsert(doc.toEntity(), versions). Throws FormatException.
  RemoteUpsert toRemoteChange() => RemoteUpsert(doc.toEntity(), versions);

  @override
  bool operator ==(Object other) =>
      other is UpsertRecord && other.doc == doc && other.versions == versions;

  @override
  int get hashCode => Object.hash(doc, versions);

  @override
  String toString() => 'UpsertRecord(${doc.kind.name} ${doc.id})';
}

/// Permanent deletion (trash purge) of a folder or note and its trash group.
final class PurgeRecord extends SyncRecord {
  const PurgeRecord(this.ref, this.hlc);
  @override
  final EntityRef ref;
  final Hlc hlc;

  /// RemotePurge(ref.kind, ref.id)
  RemotePurge toRemoteChange() => RemotePurge(ref.kind, ref.id);

  @override
  bool operator ==(Object other) =>
      other is PurgeRecord && other.ref == ref && other.hlc == hlc;

  @override
  int get hashCode => Object.hash(ref, hlc);

  @override
  String toString() => 'PurgeRecord(${ref.kind.name} ${ref.id})';
}
