// Internal (not exported). One push of the outbox (6.5.2): read pending entries, snapshot
// them, check owner and future clocks (6.2.5 K4), pack chunks (6.4.3), commit, acknowledge.
// Scheduling, backoff and phase changes belong to the engine controller; runOnce reports
// what happened in a PushResult.
import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart';

import '../backend/remote_chunk.dart';
import '../backend/sync_backend.dart';
import '../codec/chunk_packer.dart';
import '../common/errors.dart';
import '../config.dart';
import '../model/records.dart';
import '../model/scopes.dart';
import '../status/sync_issue.dart';

/// Why a push did not run (6.5.2 step 0).
enum PushSkip {
  /// This device's clock is off by more than 24 h (6.2.5 K3).
  clockBlocked,

  /// No server-time sample yet: K4 has no reference (6.2.5).
  noClockSample,
}

/// What one [UploadPipeline.runOnce] did.
@immutable
final class PushResult {
  const PushResult({
    this.skipped,
    this.commits = 0,
    this.acked = 0,
    this.recordsSent = 0,
    this.chunksSent = 0,
    this.hasMore = false,
    this.heldUntilServerMillis,
    this.error,
    this.reauthRequired = false,
  });

  final PushSkip? skipped;

  /// Successful commitChunks calls.
  final int commits;

  /// Outbox entries acknowledged (sent ones + ackOnly).
  final int acked;
  final int recordsSent, chunksSent;

  /// The read was full (maxEntriesPerPush): push again at once (6.5.2 step 6).
  final bool hasMore;

  /// Only clock-held entries are left: the earliest server time (ms) one may be sent
  /// (6.2.5 K4). Null when none are held.
  final int? heldUntilServerMillis;

  /// What stopped the push: a SyncBackendException (backoff / phase by its code) or an error
  /// thrown without retry by the local store (localStoreFailure after 5 in a row, 6.5.4).
  final Object? error;

  /// unauthenticated and refreshSession failed (reauthRequired, 6.5.4).
  final bool reauthRequired;

  bool get succeeded => error == null && skipped == null;

  SyncErrorCode? get errorCode => switch (error) {
    SyncBackendException(:final code) => code,
    _ => null,
  };

  @override
  String toString() =>
      'PushResult(skipped: $skipped, commits: $commits, acked: $acked, '
      'more: $hasMore, held: $heldUntilServerMillis, error: $error)';
}

/// The engine's outbox sender (6.5). Not reentrant: the engine runs it on its serial
/// executor (6.1).
final class UploadPipeline {
  UploadPipeline({
    required this.sync,
    required this.backend,
    required this.config,
    required this.serverNowMillis,
    required this.refreshSession,
    this.isClockBlocked = _never,
    this.onPurgesCommitted = _noPurges,
    this.onScopesCommitted = _noScopes,
    this.onPushNeeded = _nothing,
  }) : _packer = ChunkPacker(config: config, authorNodeId: sync.deviceNodeId);

  final SyncStore sync;
  final SyncBackend backend;
  final SyncConfig config;

  /// Estimated server time in ms (6.2.4); null while there is no sample.
  final int? Function() serverNowMillis;

  /// AuthBackend.refreshSession: throws when the session cannot be refreshed.
  final Future<void> Function() refreshSession;

  /// 6.2.5 K3.
  final bool Function() isClockBlocked;

  /// Committed purge records (the stored purged set, 6.7.4 — PurgedSet).
  final Future<void> Function(List<PurgeRecord> purges) onPurgesCommitted;

  /// A commit of records in these scopes succeeded (PurgeGuard's recent-upload window,
  /// 6.7.4).
  final void Function(Set<String> scopes) onScopesCommitted;

  /// Schedules a push (PushScheduler.trigger) — used after [commitRepairs].
  final void Function() onPushNeeded;

  final ChunkPacker _packer;

  /// Entries kept local in memory (6.5.6 step 5): ref → (rev, reason). Released when the
  /// entry's rev changes or the app restarts.
  final Map<EntityRef, ({int rev, SyncIssueCode reason})> _quarantine = {};

  /// Entries held back by K4: ref → server time (ms) from which they may be sent.
  final Map<EntityRef, int> _clockHeld = {};

  static bool _never() => false;
  static Future<void> _noPurges(List<PurgeRecord> purges) async {}
  static void _noScopes(Set<String> scopes) {}
  static void _nothing() {}

  /// Quarantined entries and why (rejectedByServer, entityTooLarge, foreignOwnerData).
  Map<EntityRef, SyncIssueCode> get quarantined => {
    for (final MapEntry(:key, :value) in _quarantine.entries) key: value.reason,
  };

  /// SyncStatus.quarantinedUploads.
  int get quarantinedCount => _quarantine.length;

  /// Entries held back by K4 (6.2.5): ref → server ms from which they may go.
  Map<EntityRef, int> get clockHeld => Map.unmodifiable(_clockHeld);

  /// Repair writes (6.7.2, 6.7.3) go through here: commitRepairs is origin remote, so no
  /// localChanges event follows and the push is scheduled directly (6.5.1, 5.1.2 S-9).
  Future<void> commitRepairs(List<RepairWrite> repairs) async {
    if (repairs.isEmpty) return;
    await sync.commitRepairs(repairs);
    onPushNeeded();
  }

  /// One push (6.5.2).
  Future<PushResult> runOnce() async {
    if (isClockBlocked()) {
      return const PushResult(skipped: PushSkip.clockBlocked);
    }
    final serverNow = serverNowMillis();
    if (serverNow == null) {
      return const PushResult(skipped: PushSkip.noClockSample);
    }

    // 1. Pending entries, quarantined / clock-held ones skipped.
    final limit = config.maxEntriesPerPush;
    final (entries, full) = await _readSendable(limit, serverNow);

    // 2–3. Snapshots and checks.
    final upserts = [
      for (final e in entries)
        if (e.op == OutboxOp.upsert) e,
    ];
    final rows = upserts.isEmpty
        ? const <VersionedEntity?>[]
        : await sync.readVersioned([for (final e in upserts) e.ref]);
    final items = <PackItem<OutboxEntry>>[];
    final ackOnly = <OutboxEntry>[];
    final limitMillis =
        serverNow +
        const Duration(hours: 24).inMilliseconds -
        config.futureRecordMargin.inMilliseconds;
    for (final (i, entry) in upserts.indexed) {
      final row = rows[i];
      if (row == null) {
        ackOnly.add(entry);
        continue;
      }
      final record = UpsertRecord.fromVersioned(row);
      final owner = record.doc.ownerId;
      if (owner != null && owner != backend.uid) {
        _quarantine[entry.ref] = (
          rev: entry.rev,
          reason: SyncIssueCode.foreignOwnerData,
        );
        continue;
      }
      final maxMillis = record.versions.max.millis;
      if (maxMillis > limitMillis) {
        _clockHeld[entry.ref] = maxMillis - (limitMillis - serverNow);
        continue;
      }
      _clockHeld.remove(entry.ref);
      items.add(
        PackItem(
          record,
          scope: SyncScopes.scopeOf(record, noteIdHint: _hint(entry.noteId)),
          tag: entry,
        ),
      );
    }
    for (final entry in entries) {
      if (entry.op != OutboxOp.purge) continue;
      final record = PurgeRecord(entry.ref, entry.hlc);
      items.add(
        PackItem(record, scope: SyncScopes.scopeOfPurge(record), tag: entry),
      );
    }

    // 4. Chunks and commits.
    final packed = _packer.pack(items);
    for (final item in packed.tooLarge) {
      _quarantine[item.tag.ref] = (
        rev: item.tag.rev,
        reason: SyncIssueCode.entityTooLarge,
      );
    }

    // 5. Commit by commit; acknowledge after each.
    final run = _Run(this);
    try {
      if (packed.commits.isEmpty && ackOnly.isNotEmpty) {
        await run.acknowledge(ackOnly);
      }
      var pendingAckOnly = ackOnly;
      for (final commit in packed.commits) {
        await run.send(commit.chunks, extraAcks: pendingAckOnly);
        pendingAckOnly = const [];
      }
    } on _ReauthRequired catch (e) {
      return run.result(error: e.cause, reauthRequired: true);
    } on SyncBackendException catch (e) {
      return run.result(error: e);
    } on Object catch (e) {
      // Thrown without retry by the local store (ack) — 6.5.4 last row.
      return run.result(error: e);
    }

    // 6. More to do?
    return run.result(
      hasMore: full,
      heldUntil: _clockHeld.isEmpty
          ? null
          : _clockHeld.values.reduce((a, b) => a < b ? a : b),
    );
  }

  /// Reads up to [limit] entries, skipping quarantined (same rev) and clock-held (not yet
  /// due) ones; reads further (afterSeq) while a full page was all skipped (6.5.2 step 1).
  Future<(List<OutboxEntry>, bool)> _readSendable(
    int limit,
    int serverNow,
  ) async {
    int? afterSeq;
    while (true) {
      final page = await sync.pendingChanges(limit: limit, afterSeq: afterSeq);
      final full = page.length >= limit;
      final sendable = <OutboxEntry>[];
      for (final entry in page) {
        final q = _quarantine[entry.ref];
        if (q != null) {
          if (q.rev == entry.rev) continue;
          _quarantine.remove(entry.ref);
        }
        final heldUntil = _clockHeld[entry.ref];
        if (heldUntil != null && heldUntil > serverNow) continue;
        sendable.add(entry);
      }
      if (sendable.isNotEmpty || !full) return (sendable, full);
      afterSeq = page.last.seq;
    }
  }

  static NoteId? _hint(NoteId? noteId) =>
      noteId == null || noteId.isEmpty ? null : noteId;
}

/// unauthenticated after a failed refresh.
final class _ReauthRequired implements Exception {
  const _ReauthRequired(this.cause);
  final Object cause;
}

/// State of one runOnce: counters, the bisect budget, one refresh.
final class _Run {
  _Run(this.p);

  final UploadPipeline p;
  int commits = 0, acked = 0, records = 0, chunks = 0, bisectSteps = 0;
  bool refreshed = false;

  PushResult result({
    Object? error,
    bool reauthRequired = false,
    bool hasMore = false,
    int? heldUntil,
  }) => PushResult(
    commits: commits,
    acked: acked,
    recordsSent: records,
    chunksSent: chunks,
    hasMore: hasMore,
    heldUntilServerMillis: heldUntil,
    error: error,
    reauthRequired: reauthRequired,
  );

  Future<void> acknowledge(List<OutboxEntry> entries) async {
    if (entries.isEmpty) return;
    await p.sync.acknowledge([for (final e in entries) e.ack]);
    acked += entries.length;
  }

  /// Commits [group] as one commit; on invalidArgument bisects (6.5.6).
  Future<void> send(
    List<PackedChunk<OutboxEntry>> group, {
    List<OutboxEntry> extraAcks = const [],
  }) async {
    try {
      await _commit([for (final c in group) c.write]);
    } on SyncBackendException catch (e) {
      if (e.code != SyncErrorCode.invalidArgument) rethrow;
      if (bisectSteps >= p.config.maxBisectSteps) rethrow;
      bisectSteps++;
      if (group.length >= 2) {
        final half = group.length ~/ 2;
        await send(group.sublist(0, half), extraAcks: extraAcks);
        await send(group.sublist(half));
        return;
      }
      final items = group.single.items;
      if (items.length >= 2) {
        final half = items.length ~/ 2;
        var acks = extraAcks;
        for (final part in [items.sublist(0, half), items.sublist(half)]) {
          final repacked = p._packer.pack(part);
          await send([
            for (final c in repacked.commits) ...c.chunks,
          ], extraAcks: acks);
          acks = const [];
        }
        return;
      }
      final entry = items.single.tag;
      p._quarantine[entry.ref] = (
        rev: entry.rev,
        reason: SyncIssueCode.rejectedByServer,
      );
      await acknowledge(extraAcks);
      return;
    }
    commits++;
    chunks += group.length;
    p.onScopesCommitted({for (final c in group) c.write.scope});
    final sent = [
      for (final c in group)
        for (final item in c.items) item,
    ];
    records += sent.length;
    await acknowledge([for (final item in sent) item.tag, ...extraAcks]);
    final purges = [
      for (final item in sent)
        if (item.record case final PurgeRecord purge) purge,
    ];
    if (purges.isNotEmpty) await p.onPurgesCommitted(purges);
  }

  /// commitChunks; unauthenticated → refreshSession once per push and retry (6.5.4).
  Future<void> _commit(List<ChunkWrite> writes) async {
    try {
      await p.backend.commitChunks(writes);
    } on SyncBackendException catch (e) {
      if (e.code != SyncErrorCode.unauthenticated || refreshed) {
        if (e.code == SyncErrorCode.unauthenticated) throw _ReauthRequired(e);
        rethrow;
      }
      refreshed = true;
      try {
        await p.refreshSession();
      } on Object catch (refreshError) {
        throw _ReauthRequired(refreshError);
      }
      await _commit(writes);
    }
  }
}
