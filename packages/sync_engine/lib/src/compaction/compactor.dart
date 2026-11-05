// Internal (not exported). Compaction (6.13): one scope's chunks become snapshot chunks of
// the merged state, then the chunks merged into them are deleted. The snapshot is committed
// first, and only chunks whose records are in it are deleted: chunks that do not decode stay
// on the server, and a scope with a chunk format this app cannot read — or a device that has
// seen one (sync.deferredFrom) — is not compacted (SYNC-3-2 ②). This device applies its own
// snapshot chunks on receive (6.6.3 step 2), so records of R it had not applied yet are not
// lost (SYNC-3-2 ①). The engine controller decides when (trigger, jitter) and runs one
// compaction as one step of its serial executor; step 5 (sync.scopeStats) is the download
// pipeline's, which owns that key.
import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart';

import '../backend/remote_chunk.dart';
import '../backend/sync_backend.dart';
import '../codec/chunk_codec.dart';
import '../codec/chunk_packer.dart';
import '../common/errors.dart';
import '../common/server_cursor.dart';
import '../config.dart';
import '../engine/held_chunks.dart';
import '../engine/meta_keys.dart' show ScopeStats;
import '../merge/field_merge.dart';
import '../merge/purged_set.dart';
import '../model/records.dart';
import '../model/scopes.dart';

/// Why a scope was not compacted (nothing committed, nothing deleted).
enum CompactionSkip {
  /// sync.deferredFrom is set: this app has seen a chunk format it cannot read (6.6.5).
  deferredFormat,

  /// sync.held is in the collapsed {"*": …} form (6.2.5 K2).
  collapsedHold,

  /// Some chunk of the scope has fmt > ChunkCodec.formatVersion.
  newerFormat,

  /// Some chunk of the scope is held on this device (6.2.5 K1, SYNC-2-4).
  heldChunk,

  /// The scope is larger than CompactionConfig.maxScopeBytes.
  tooLarge,

  /// A merged record does not fit a chunk on its own (chunkHardLimitBytes).
  recordTooLarge,

  /// No chunk decoded: nothing to merge.
  nothingToMerge,
}

/// What one [Compactor.compact] did.
@immutable
final class CompactionResult {
  const CompactionResult({
    required this.scope,
    this.skipped,
    this.fetched = 0,
    this.malformed = 0,
    this.snapshotChunks = 0,
    this.snapshotRecords = 0,
    this.committed = 0,
    this.deleted = 0,
    this.error,
  });

  final String scope;

  /// Non-null: the scope was left as it is.
  final CompactionSkip? skipped;

  /// Chunks of the scope read (R).
  final int fetched;

  /// Chunks of R that did not decode: left out of the snapshot and never deleted.
  final int malformed;

  /// Snapshot chunks packed / records in them.
  final int snapshotChunks, snapshotRecords;

  /// Snapshot chunks committed — those whose id was not already in R (all of them unless
  /// [error]).
  final int committed;

  /// Chunk ids sent in delete requests.
  final int deleted;

  /// The backend call that stopped the run (a SyncBackendException). Commit failure: nothing
  /// was deleted, the next run starts over. Delete failure: the snapshot is in, some merged
  /// chunks stay (duplicates of the snapshot — harmless, the next run deletes them).
  final Object? error;

  /// The snapshot is committed and every merged chunk deleted.
  bool get completed => skipped == null && error == null;

  @override
  String toString() =>
      'CompactionResult($scope, skipped: ${skipped?.name}, fetched: $fetched, '
      'malformed: $malformed, snapshot: $snapshotChunks/$snapshotRecords, '
      'committed: $committed, deleted: $deleted, error: $error)';
}

/// Compacts one scope at a time (6.13 steps 1–4). Not reentrant: the engine runs it on its
/// serial executor.
final class Compactor {
  Compactor({
    required this.sync,
    required this.backend,
    required this.config,
    required this.purged,
    this.codecFormat = ChunkCodec.formatVersion,
  }) : _packer = ChunkPacker(config: config, authorNodeId: sync.deviceNodeId);

  final SyncStore sync;
  final SyncBackend backend;
  final SyncConfig config;

  /// The permanent-deletion view (6.7.4): a purged note's scope compacts to nothing.
  final PurgedSet purged;

  /// Newest chunk format this app reads (6.6.5).
  final int codecFormat;

  final ChunkPacker _packer;

  /// Chunk ids per delete request (6.13 step 4).
  static const int deleteBatch = 400;

  /// The scopes whose statistics meet the trigger (6.13: n ≥ minChunksPerScope and
  /// now − c ≥ minInterval), most chunks first, then by name. The engine checks the rest
  /// (phase live, no pending upload, foreground, enabled, no collapsed hold).
  static List<String> dueScopes(
    ScopeStats stats,
    CompactionConfig config, {
    required int nowMillis,
  }) {
    final due = [
      for (final scope in stats.scopes)
        if (stats.countOf(scope) >= config.minChunksPerScope &&
            nowMillis - stats.lastCompactedOf(scope) >=
                config.minInterval.inMilliseconds)
          scope,
    ];
    due.sort((a, b) {
      final byCount = stats.countOf(b).compareTo(stats.countOf(a));
      return byCount != 0 ? byCount : a.compareTo(b);
    });
    return due;
  }

  /// One compaction of [scope] (6.13 steps 1–4). [held] and [deferredFrom] are the download
  /// pipeline's `sync.held` and `sync.deferredFrom`. Backend errors end up in
  /// [CompactionResult.error]; local-store errors (reading the purged set) are thrown.
  Future<CompactionResult> compact(
    String scope, {
    required HeldChunks held,
    ServerCursor? deferredFrom,
  }) async {
    CompactionResult skip(CompactionSkip why, {int fetched = 0}) =>
        CompactionResult(scope: scope, skipped: why, fetched: fetched);

    // 1. Preconditions, then R = every chunk of the scope.
    if (deferredFrom != null) return skip(CompactionSkip.deferredFormat);
    if (held.collapsed != null) return skip(CompactionSkip.collapsedHold);
    final chunks = <RemoteChunk>[];
    var bytes = 0;
    Object? token;
    try {
      do {
        final page = await backend.fetchScope(
          scope,
          pageToken: token,
          limit: config.fetchPageSize,
        );
        for (final c in page.chunks) {
          bytes += c.payload.length;
          if (bytes > config.compaction.maxScopeBytes) {
            return skip(CompactionSkip.tooLarge, fetched: chunks.length + 1);
          }
          chunks.add(c);
        }
        token = page.nextPageToken;
      } while (token != null);
    } on SyncBackendException catch (e) {
      return CompactionResult(scope: scope, fetched: chunks.length, error: e);
    }
    final fetched = chunks.length;
    if (chunks.any((c) => c.format > codecFormat)) {
      return skip(CompactionSkip.newerFormat, fetched: fetched);
    }
    if (chunks.any((c) => held.contains(c.id))) {
      return skip(CompactionSkip.heldChunk, fetched: fetched);
    }

    // 2. Decode; malformed chunks stay out of the snapshot and out of step 4.
    final merged = <String>[];
    var malformed = 0;
    final upserts = <EntityRef, UpsertRecord>{};
    final purges = <EntityRef, PurgeRecord>{};
    for (final c in chunks) {
      final List<SyncRecord> records;
      try {
        records = ChunkCodec.decode(c.payload);
      } on FormatException {
        malformed++;
        continue;
      }
      merged.add(c.id);
      for (final r in records) {
        switch (r) {
          case UpsertRecord():
            final before = upserts[r.ref];
            upserts[r.ref] = before == null
                ? r
                : FieldMerge.mergeRecords(before, r);
          case PurgeRecord():
            final before = purges[r.ref];
            if (before == null || before.hlc.compareTo(r.hlc) < 0) {
              purges[r.ref] = r;
            }
        }
      }
    }
    if (merged.isEmpty) {
      return CompactionResult(
        scope: scope,
        skipped: CompactionSkip.nothingToMerge,
        fetched: fetched,
        malformed: malformed,
      );
    }

    // Purges: kept, and the upserts of purged refs dropped ('lib'); a purged note's scope
    // compacts to nothing.
    await purged.refreshIfStale();
    final notePurged =
        scope != SyncScopes.library &&
        (purged.isStored(EntityRef(EntityKind.note, scope)) ||
            purges.containsKey(EntityRef(EntityKind.note, scope)));
    final snapshot = <SyncRecord>[
      if (!notePurged) ...[
        for (final MapEntry(key: ref, value: r) in upserts.entries)
          if (!purges.containsKey(ref)) r,
        ...purges.values,
      ],
    ];

    // 3. Pack and commit the snapshot; every commit must succeed before anything is
    // deleted.
    final packed = _packer.pack([
      for (final r in snapshot) PackItem(r, scope: scope, tag: null),
    ], kind: ChunkKind.snapshot);
    if (packed.tooLarge.isNotEmpty) {
      return CompactionResult(
        scope: scope,
        skipped: CompactionSkip.recordTooLarge,
        fetched: fetched,
        malformed: malformed,
      );
    }
    final snapshotIds = <String>{
      for (final commit in packed.commits)
        for (final c in commit.chunks) c.write.id,
    };
    var committed = 0;
    CompactionResult partial({Object? error, int deleted = 0}) =>
        CompactionResult(
          scope: scope,
          fetched: fetched,
          malformed: malformed,
          snapshotChunks: snapshotIds.length,
          snapshotRecords: snapshot.length,
          committed: committed,
          deleted: deleted,
          error: error,
        );
    // A snapshot chunk whose id is already in R has the same author and payload (6.4.5):
    // the same records are on the server — kept as they are, not written again (a rewrite
    // may not change the kind, 6.14) and not deleted.
    final inR = {for (final c in chunks) c.id};
    for (final commit in packed.commits) {
      final writes = [
        for (final c in commit.chunks)
          if (!inR.contains(c.write.id)) c.write,
      ];
      if (writes.isEmpty) continue;
      try {
        await backend.commitChunks(writes);
      } on SyncBackendException catch (e) {
        return partial(error: e);
      }
      committed += writes.length;
    }

    // 4. Delete the merged chunks — never a malformed one, never one that is (or has the
    // id of) a snapshot chunk.
    final doomed = [
      for (final id in merged)
        if (!snapshotIds.contains(id)) id,
    ];
    var deleted = 0;
    for (var i = 0; i < doomed.length; i += deleteBatch) {
      final end = i + deleteBatch < doomed.length
          ? i + deleteBatch
          : doomed.length;
      final batch = doomed.sublist(i, end);
      try {
        await backend.deleteChunks(batch);
      } on SyncBackendException catch (e) {
        return partial(error: e, deleted: deleted);
      }
      deleted += batch.length;
    }
    return partial(deleted: deleted);
  }
}
