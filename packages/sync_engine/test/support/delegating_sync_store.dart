// A SyncStore that forwards to another one, with test hooks (test/ only): hide rows from
// readVersioned, record applyRemote / writeMeta calls, hold applyRemote open (CORE write
// retry, S-20), reject calls holding given refs like CORE (policy runs, then the whole call
// rolls back with ArgumentError), throw a store error without retry.
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

  /// Refs of every applyRemote call, in order (rejected calls included).
  final List<List<EntityRef>> applyRefs = [];

  /// A call holding one of these refs runs the policy on its upserts, then throws
  /// ArgumentError without writing (CORE S-7: the whole call is rolled back).
  final Set<EntityRef> rejectRefs = {};

  /// Thrown (once) by the next applyRemote call — a store error without retry.
  Exception? nextApplyError;

  /// Thrown (once) by applyRemote call number [failApplyAt] (1-based over applyRefs).
  int? failApplyAt;
  Exception failApplyError = Exception('injected store failure');

  /// Runs after each applyRemote call that wrote (1-based call number).
  void Function(int call)? afterApply;

  /// updates of every writeMeta call, in order.
  final List<Map<String, String>> writeMetaCalls = [];

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
    final refs = [for (final c in changes) EntityRef(c.kind, c.id)];
    applyRefs.add(refs);
    final call = applyRefs.length;
    final gate = applyGate;
    if (gate != null) await gate.future;
    final error = nextApplyError;
    if (error != null) {
      nextApplyError = null;
      throw error;
    }
    if (failApplyAt == call) throw failApplyError;
    if (refs.any(rejectRefs.contains)) {
      final rows = await inner.readVersioned(refs);
      for (final (i, change) in changes.indexed) {
        if (change case RemoteUpsert(:final entity, :final versions)) {
          policy(rows[i], VersionedEntity(entity, versions), null);
        }
      }
      throw ArgumentError.value(
        refs.where(rejectRefs.contains).toList(),
        'changes',
        'rejected by the test store',
      );
    }
    final report = await inner.applyRemote(
      changes,
      policy: policy,
      metaUpdates: metaUpdates,
    );
    afterApply?.call(call);
    return report;
  }

  @override
  Future<void> commitRepairs(List<RepairWrite> repairs) =>
      inner.commitRepairs(repairs);

  @override
  Future<String?> readMeta(String key) => inner.readMeta(key);

  @override
  Future<void> writeMeta(Map<String, String> updates) {
    writeMetaCalls.add(Map.of(updates));
    return inner.writeMeta(updates);
  }

  @override
  Future<void> reassignOwner({required OwnerId from, required OwnerId to}) =>
      inner.reassignOwner(from: from, to: to);

  @override
  Future<NoteId?> duplicateNoteForRecovery(
    NoteId noteId, {
    required String titleSuffix,
  }) => inner.duplicateNoteForRecovery(noteId, titleSuffix: titleSuffix);
}
