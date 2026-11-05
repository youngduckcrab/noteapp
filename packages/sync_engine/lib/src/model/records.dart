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
      throw UnimplementedError('SYNC T2');

  final SyncDoc doc;
  final EntityFieldVersions versions;

  @override
  EntityRef get ref => throw UnimplementedError('SYNC T2');

  /// RemoteUpsert(doc.toEntity(), versions). Throws FormatException.
  RemoteUpsert toRemoteChange() => throw UnimplementedError('SYNC T2');
}

/// Permanent deletion (trash purge) of a folder or note and its trash group.
final class PurgeRecord extends SyncRecord {
  const PurgeRecord(this.ref, this.hlc);
  @override
  final EntityRef ref;
  final Hlc hlc;

  /// RemotePurge(ref.kind, ref.id)
  RemotePurge toRemoteChange() => throw UnimplementedError('SYNC T2');
}
