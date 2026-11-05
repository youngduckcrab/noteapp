// A SyncStore that forwards to another one, with test hooks (test/ only): hide rows from
// readVersioned, record applyRemote calls, hold applyRemote open (CORE write retry, S-20).
import 'dart:async';

import 'package:note_core/note_core.dart';

final class DelegatingSyncStore implements SyncStore {
  DelegatingSyncStore(this.inner);

  final SyncStore inner;

  /// readVersioned returns null for these refs.
  final Set<EntityRef> hiddenRows = {};

  /// metaUpdates of every applyRemote call, in order.
  final List<Map<String, String>> applyMetaUpdates = [];

  /// When set, applyRemote waits for it before forwarding.
  Completer<void>? applyGate;

  @override
  String get deviceNodeId => inner.deviceNodeId;

  @override
  OwnerId get ownerId => inner.ownerId;

  @override
  Future<List<OutboxEntry>> pendingChanges({int limit = 500, int? afterSeq}) =>
      inner.pendingChanges(limit: limit, afterSeq: afterSeq);

  @override
  Stream<int> watchPendingCount() => inner.watchPendingCount();

  @override
  Future<void> acknowledge(List<OutboxAck> acks) => inner.acknowledge(acks);

  @override
  Future<List<VersionedEntity?>> readVersioned(List<EntityRef> refs) async {
    final rows = await inner.readVersioned(refs);
    return [
      for (final (i, row) in rows.indexed)
        hiddenRows.contains(refs[i]) ? null : row,
    ];
  }

  @override
  Future<RemoteApplyReport> applyRemote(
    List<RemoteChange> changes, {
    required RemoteMergePolicy policy,
    Map<String, String> metaUpdates = const {},
  }) async {
    applyMetaUpdates.add(Map.of(metaUpdates));
    final gate = applyGate;
    if (gate != null) await gate.future;
    return inner.applyRemote(changes, policy: policy, metaUpdates: metaUpdates);
  }

  @override
  Future<void> commitRepairs(List<RepairWrite> repairs) =>
      inner.commitRepairs(repairs);

  @override
  Future<String?> readMeta(String key) => inner.readMeta(key);

  @override
  Future<void> writeMeta(Map<String, String> updates) =>
      inner.writeMeta(updates);

  @override
  Future<void> reassignOwner({required OwnerId from, required OwnerId to}) =>
      inner.reassignOwner(from: from, to: to);

  @override
  Future<NoteId?> duplicateNoteForRecovery(
    NoteId noteId, {
    required String titleSuffix,
  }) => inner.duplicateNoteForRecovery(noteId, titleSuffix: titleSuffix);
}
