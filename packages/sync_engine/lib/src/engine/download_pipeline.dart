// Internal (not exported). Receiving (6.6): fetch pages from the cursor (6.6.1–6.6.2), apply
// chunk batches (6.6.3), release held chunks (6.2.5 K2). The cursor, `sync.held`,
// `sync.scopeStats`, `sync.purged.*`, the deferred-format keys and (2nd round, S-13 —
// 07-sync 6.3.3) the `sync.heldRecords` keys are written in the same transaction as the last
// applied records, so a crash re-receives the same page (idempotent).
// Phases, backoff and issues over time belong to the engine controller.
import 'dart:collection';

import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart';

import '../backend/remote_chunk.dart';
import '../backend/sync_backend.dart';
import '../codec/chunk_codec.dart';
import '../common/errors.dart';
import '../common/lru_set.dart';
import '../common/server_cursor.dart';
import '../config.dart';
import '../merge/field_merge.dart';
import '../merge/merge_recorder.dart';
import '../merge/purged_set.dart';
import '../merge/record_gate.dart';
import '../merge/sync_merge_policy.dart';
import '../model/records.dart';
import '../model/scopes.dart';
import '../status/sync_issue.dart';
import 'held_chunks.dart';
import 'held_records.dart';
import 'meta_keys.dart';

/// What one applyChunks / catchUp / releaseHeld did.
@immutable
final class ApplyResult {
  const ApplyResult({
    this.chunks = 0,
    this.duplicates = 0,
    this.applied = 0,
    this.held = 0,
    this.dropped = 0,
    this.rejected = 0,
    this.pages = 0,
    this.ownSkipped = 0,
    this.issues = const [],
    this.latestServerTime,
    this.rewound = false,
    this.reappliedChunks = 0,
    this.reappliedRecords = 0,
    this.error,
  });

  /// Chunks handled (LRU duplicates excluded).
  final int chunks;

  /// Chunks skipped by the session LRU (already applied).
  final int duplicates;

  /// Records in committed applyRemote calls.
  final int applied;

  /// Records held back by K1 (6.2.5).
  final int held;

  /// Records dropped (permanently deleted entity or note — log only, 6.3.5).
  final int dropped;

  /// Records skipped by the gate or rejected by CORE (malformedRemoteData,
  /// foreignOwnerData).
  final int rejected;

  /// Fetched pages (catchUp).
  final int pages;

  /// This device's own delta chunks, skipped (6.6.3 step 2).
  final int ownSkipped;

  /// Non-blocking issues to report (malformedRemoteData, foreignOwnerData,
  /// needsAppUpdate), one per event.
  final List<SyncIssue> issues;

  /// Newest serverTime among the handled chunks (latency, 6.6.3 step 9).
  final ServerCursor? latestServerTime;

  /// releaseHeld went back to the collapsed hold's serverTime and received again (K2).
  final bool rewound;

  /// (S-13 — 07-sync 6.3.4) Synthetic chunks of held records re-applied, and the records of
  /// them in committed applyRemote calls. Kept out of [chunks], [applied] and
  /// [latestServerTime] (old serverTimes would distort chunksReceived and the latency).
  final int reappliedChunks, reappliedRecords;

  /// What stopped the work: a SyncBackendException (fetch) or an error the local store
  /// threw without retry (localStoreFailure after 5 in a row — the controller, 6.6.3 step 7).
  /// Nothing after the failing call was applied and the meta of the batch was not stored.
  final Object? error;

  bool get succeeded => error == null;

  SyncErrorCode? get errorCode => switch (error) {
    SyncBackendException(:final code) => code,
    _ => null,
  };

  ApplyResult operator +(ApplyResult o) => ApplyResult(
    chunks: chunks + o.chunks,
    duplicates: duplicates + o.duplicates,
    applied: applied + o.applied,
    held: held + o.held,
    dropped: dropped + o.dropped,
    rejected: rejected + o.rejected,
    pages: pages + o.pages,
    ownSkipped: ownSkipped + o.ownSkipped,
    issues: [...issues, ...o.issues],
    latestServerTime: switch ((latestServerTime, o.latestServerTime)) {
      (final a?, final b?) => ServerCursor.max(a, b),
      (final a, final b) => a ?? b,
    },
    rewound: rewound || o.rewound,
    reappliedChunks: reappliedChunks + o.reappliedChunks,
    reappliedRecords: reappliedRecords + o.reappliedRecords,
    error: error ?? o.error,
  );

  @override
  String toString() =>
      'ApplyResult(chunks: $chunks, dup: $duplicates, applied: $applied, held: $held, '
      'dropped: $dropped, rejected: $rejected, pages: $pages, '
      'reapplied: $reappliedChunks/$reappliedRecords, issues: ${issues.length}, '
      'error: $error)';
}

/// The engine's receiver (6.6). Not reentrant: the engine runs it on its serial executor.
final class DownloadPipeline {
  DownloadPipeline({
    required this.sync,
    required this.backend,
    required this.config,
    required this.purged,
    required this.wallMillis,
    this.serverNowMillis = _noSample,
    this.onOwnChunk = _ignoreChunk,
    this.purgeGuard = _noGuard,
    this.markdownGuard = _noMarkdownGuard,
    this.afterGroup = _noChecks,
    this.codecFormat = ChunkCodec.formatVersion,
    Set<EntityKind>? knownKinds,
    this.onWarning = _ignoreWarning,
    this.heldRecordsMaxPartBytes = HeldRecords.defaultMaxPartBytes,
    this.heldRecordsMaxTotalBytes = HeldRecords.defaultMaxTotalBytes,
  }) : _applied = LruSet(config.appliedChunkMemory),
       _held = HeldChunks(maxEntries: config.maxHeldChunks),
       knownKinds = Set.unmodifiable(knownKinds ?? EntityKind.values),
       _knownNames = {for (final k in knownKinds ?? EntityKind.values) k.name} {
    _heldRecords = _emptyHeldRecords();
    _heldRecordsText = _heldRecords.encode();
  }

  final SyncStore sync;
  final SyncBackend backend;
  final SyncConfig config;

  /// The permanent-deletion view (6.7.4). The pipeline refreshes it when stale (step 4)
  /// and stores received purges in it.
  final PurgedSet purged;

  /// The engine clock (= CORE NoteStore.clock), ms — `wall` of 6.2.5.
  final int Function() wallMillis;

  /// Estimated server time in ms (6.2.4); null while there is no sample (no K2 release).
  final int? Function() serverNowMillis;

  /// A chunk written by this device came back (clock-skew sample, 6.2.4 ②).
  final void Function(RemoteChunk chunk) onOwnChunk;

  /// PurgeGuard (6.7.4): runs before the purges of a batch are applied.
  final Future<void> Function(List<PurgeRecord> purges) purgeGuard;

  /// (v2.17-md, C217M-07 L2) Runs before the MD 문서 bodies of a batch are applied: the
  /// engine asks CORE (SyncStore.keepMarkdownConflictCopy) to keep the losing text of a
  /// concurrent edit (08-markdown 5.3).
  final Future<void> Function(List<UpsertRecord> bodies) markdownGuard;

  /// Step 8, once per apply group after all its pieces: folder cycles (6.7.2) and page
  /// resurrection (6.7.3) over the committed outcomes.
  final Future<void> Function(Map<EntityRef, MergeOutcomeKind> outcomes)
  afterGroup;

  /// Newest chunk format this app reads (6.6.5) — ChunkCodec.formatVersion.
  final int codecFormat;

  /// (2nd round, S-13 — 07-sync 6.3.3, 6.3.8) Kinds this app's codec knows (default: every
  /// EntityKind; fewer = an older app in tests). Chunks are read with
  /// ChunkCodec.decodeTolerant: the known records of a chunk apply, the records of other
  /// kinds are held in `sync.heldRecords` (HeldRecords — the chunk's all or none) and new
  /// ones are reported once as needsAppUpdate. The cursor moves on as for any chunk.
  final Set<EntityKind> knownKinds;
  final Set<String> _knownNames;

  /// A warning for the engine log (a corrupt `sync.heldRecords` value converted on load).
  final void Function(String message) onWarning;

  /// HeldRecords caps (tests shrink them; production uses the defaults — 6.3.2).
  final int heldRecordsMaxPartBytes, heldRecordsMaxTotalBytes;

  final LruSet<String> _applied;
  final MergeRecorder _recorder = MergeRecorder();

  ServerCursor? _cursor;
  ScopeStats _stats = ScopeStats();
  HeldChunks _held;
  ServerCursor? _deferredFrom;
  late HeldRecords _heldRecords;

  /// [_heldRecords] as stored (encode()), to write only the keys whose text changed.
  late Map<String, String> _heldRecordsText;

  static int? _noSample() => null;
  static void _ignoreWarning(String message) {}
  static void _ignoreChunk(RemoteChunk chunk) {}
  static Future<void> _noGuard(List<PurgeRecord> purges) async {}
  static Future<void> _noMarkdownGuard(List<UpsertRecord> bodies) async {}
  static Future<void> _noChecks(Map<EntityRef, MergeOutcomeKind> o) async {}

  /// `sync.cursor`: newest serverTime of the applied chunks (6.6.2). Null before the first
  /// sync.
  ServerCursor? get cursor => _cursor;

  /// `sync.held` in memory.
  HeldChunks get held => _held.copy();

  ScopeStats get scopeStats => _stats.copy();

  /// `sync.deferredFrom` (6.6.5): a chunk in a newer format was seen.
  ServerCursor? get deferredFrom => _deferredFrom;

  /// `sync.heldRecords` in memory (S-13).
  HeldRecords get heldRecords => _heldRecords.copy();

  /// SyncEngineDebug.heldRecords / heldRecordsMarked without a copy.
  int get heldRecordCount => _heldRecords.length;
  bool get heldRecordsMarked => _heldRecords.mark != null;

  /// Re-applied records wait for their K1 release time (ra) — [releaseHeld] has work even
  /// when `sync.held` is empty.
  bool get heldRecordsAwaitRelease => _heldRecords.hasReleaseTimes;

  HeldRecords _emptyHeldRecords() => HeldRecords(
    knownKinds: _knownNames,
    maxPartBytes: heldRecordsMaxPartBytes,
    maxTotalBytes: heldRecordsMaxTotalBytes,
  );

  /// Compaction step 5 (6.13): `sync.scopeStats[scope] = {n: snapshotChunks, c: atMillis}`
  /// (writeMeta). Run on the engine's serial executor, like every apply.
  Future<void> markCompacted(
    String scope, {
    required int snapshotChunks,
    required int atMillis,
  }) => _writeStats(
    _stats.copy()..markCompacted(scope, atMillis, chunks: snapshotChunks),
  );

  /// A compaction read [scope] and skipped it: c = [atMillis], n kept (ScopeStats).
  Future<void> markCompactionAttempted(String scope, {required int atMillis}) =>
      _writeStats(_stats.copy()..markAttempted(scope, atMillis));

  Future<void> _writeStats(ScopeStats stats) async {
    await sync.writeMeta({MetaKeys.scopeStats: stats.encode()});
    _stats = stats;
  }

  /// Chunk ids applied in this session (6.6.3 step 1).
  bool wasApplied(String chunkId) => _applied.contains(chunkId);

  /// Reads the pipeline's meta. When this app reads a newer format than the one that
  /// deferred chunks, goes back to them: cursor = min(cursor, deferredFrom), keys cleared
  /// (6.6.5). (S-13 — 07-sync 6.3.5) Likewise when the rewind mark of `sync.heldRecords` is
  /// due (a marked kind is known now, or an all-kinds mark after an app update): cursor =
  /// min(cursor, mark.from − cursorOverlap), mark cleared, LRU cleared.
  Future<void> load() async {
    _cursor = ServerCursor.tryParse(
      MetaKeys.present(await sync.readMeta(MetaKeys.cursor)),
    );
    _stats = ScopeStats.decode(await sync.readMeta(MetaKeys.scopeStats));
    _held = HeldChunks.decode(
      await sync.readMeta(MetaKeys.held),
      maxEntries: config.maxHeldChunks,
    );
    _deferredFrom = ServerCursor.tryParse(
      MetaKeys.present(await sync.readMeta(MetaKeys.deferredFrom)),
    );
    final deferredFormat = int.tryParse(
      MetaKeys.present(await sync.readMeta(MetaKeys.deferredFormat)) ?? '',
    );
    await _loadHeldRecords();
    final from = _deferredFrom;
    if (from != null &&
        (deferredFormat == null || codecFormat > deferredFormat)) {
      final cursor = _cursor;
      final back = cursor == null || from < cursor ? from : cursor;
      await sync.writeMeta({
        MetaKeys.cursor: back.toString(),
        MetaKeys.deferredFrom: MetaKeys.cleared,
        MetaKeys.deferredFormat: MetaKeys.cleared,
      });
      _cursor = back;
      _deferredFrom = null;
      _applied.clear();
    }
    await _rewindToHeldMark();
  }

  /// 6.3.5: the rewind mark fires once this app can read what it covers. The cursor goes back
  /// (a first sync, cursor null, reads from the beginning anyway) and the cleared mark is
  /// stored with it in one writeMeta.
  Future<void> _rewindToHeldMark() async {
    final next = _heldRecords.copy();
    final from = next.takeMarkIfDue();
    if (from == null) return;
    final cursor = _cursor;
    final back = from.minus(config.cursorOverlap);
    final target = cursor == null || cursor < back ? cursor : back;
    final text = next.encode();
    await sync.writeMeta({
      if (target != null && target != cursor) MetaKeys.cursor: '$target',
      for (final MapEntry(:key, :value) in text.entries)
        if (_heldRecordsText[key] != value) key: value,
    });
    _cursor = target;
    _heldRecords = next;
    _heldRecordsText = text;
    _applied.clear();
  }

  /// `sync.heldRecords` (6.3.2). A corrupt value becomes an all-kinds mark and is written back
  /// at once (warning) — what the next loads read is the converted value.
  Future<void> _loadHeldRecords() async {
    final values = <String, String?>{
      for (final key in MetaKeys.heldRecordKeys) key: await sync.readMeta(key),
    };
    final loaded = HeldRecords.decode(
      values,
      knownKinds: _knownNames,
      maxPartBytes: heldRecordsMaxPartBytes,
      maxTotalBytes: heldRecordsMaxTotalBytes,
    );
    final text = loaded.encode();
    if (loaded.wasCorrupt) {
      await sync.writeMeta(text);
      onWarning(
        'sync.heldRecords was corrupt: its records are dropped and every kind is '
        'marked for a rewind from ${loaded.mark?.from}',
      );
    }
    _heldRecords = loaded;
    // What is stored: a value another app version wrote (its 'a') is rewritten with the
    // next change.
    _heldRecordsText = loaded.wasCorrupt
        ? text
        : {
            for (final MapEntry(:key, :value) in values.entries)
              key: value ?? '',
          };
  }

  /// First sync (cursor null: from the beginning) or catching up (cursor − cursorOverlap),
  /// page by page to the last page (6.6.1). [onProgress] gets the chunks handled so far and
  /// the countChunks estimate (first sync only, null if unknown).
  Future<ApplyResult> catchUp({
    void Function(int chunks, int? total)? onProgress,
  }) => _catchUp(onProgress: onProgress);

  /// [reference] replaces the K1 reference g of every chunk (the collapsed-hold rewind).
  Future<ApplyResult> _catchUp({
    void Function(int chunks, int? total)? onProgress,
    int? reference,
  }) async {
    final since = _cursor?.minus(config.cursorOverlap);
    int? total;
    if (since == null && onProgress != null) {
      try {
        total = await backend.countChunks();
      } on SyncBackendException {
        total = null;
      }
    }
    var result = const ApplyResult();
    Object? token;
    do {
      final ChunkPage page;
      try {
        page = await backend.fetchChunks(
          since: since,
          pageToken: token,
          limit: config.fetchPageSize,
        );
      } on SyncBackendException catch (e) {
        return result + ApplyResult(error: e);
      }
      result +=
          await _apply(page.chunks, reference: reference) +
          const ApplyResult(pages: 1);
      if (!result.succeeded) return result;
      onProgress?.call(result.chunks + result.duplicates, total);
      token = page.nextPageToken;
    } while (token != null);
    return result;
  }

  /// 6.6.3 for one batch (a fetched page or a live batch).
  Future<ApplyResult> applyChunks(List<RemoteChunk> chunks) => _apply(chunks);

  /// (S-13 — 07-sync 6.3.4, contract 7.2.8 ⑤) After an app update: the stored records of
  /// kinds this app knows now (and without a release time) are applied as synthetic chunks
  /// (original id, scope, serverTime and author), in (serverTime, chunk id, index) order.
  /// A remote apply like any other — gate, merge, PurgeGuard, groups, afterGroup — except:
  /// the chunk ids do not enter the session LRU (the original chunk received again later
  /// decodes and applies normally — idempotent), `sync.held` is neither released nor
  /// extended (a record K1 holds keeps its bytes here with a release time, ra), the cursor,
  /// scope statistics and chunksReceived do not move, and own chunks are not skipped. The
  /// settled records leave `sync.heldRecords` with the last apply call. On an error nothing
  /// changes in memory and the caller tries again at its next connection. The engine runs it
  /// at attach after [load] and before [catchUp].
  Future<ApplyResult> reapplyHeldRecords() async {
    final chunks = _heldRecords.knownChunks(_knownNames.contains);
    if (chunks.isEmpty) return const ApplyResult();
    return _reapply(chunks);
  }

  /// K2 (6.2.5): with g' = min(serverNow, wall), receives the held chunks whose release
  /// time has come again (getChunks) and applies them with g' as the K1 reference; ids
  /// that did not come back (deleted by compaction) leave `sync.held`. The collapsed form
  /// moves the cursor back to its serverTime − cursorOverlap and receives everything after
  /// it again. (S-13 — 07-sync 6.3.4) Then the re-applied records K1 held (ra ≤ g') are
  /// applied again from `sync.heldRecords` with g' as the reference — they do not depend on
  /// the original chunk still being on the server. Nothing happens without a server-time
  /// sample.
  Future<ApplyResult> releaseHeld() async {
    final serverNow = serverNowMillis();
    if (serverNow == null) return const ApplyResult();
    final wall = wallMillis();
    final g = serverNow < wall ? serverNow : wall;
    final released = await _releaseChunks(g);
    if (!released.succeeded) return released;
    final due = _heldRecords.dueChunks(g);
    if (due.isEmpty) return released;
    return released + await _reapply(due, reference: g);
  }

  Future<ApplyResult> _reapply(List<ReapplyChunk> chunks, {int? reference}) =>
      _apply(
        [for (final c in chunks) c.chunk],
        reference: reference,
        release: true,
        reapply: {for (final c in chunks) c.chunk.id: c.indexes},
      );

  /// The K2 part of [releaseHeld] (1st round).
  Future<ApplyResult> _releaseChunks(int g) async {
    final collapsed = _held.collapsed;
    if (collapsed != null && _held.isCollapsedDue(g)) {
      final next = _held.copy()..clearCollapsed();
      final back = collapsed.from.minus(config.cursorOverlap);
      final cursor = _cursor;
      final target = cursor == null || back < cursor ? back : cursor;
      await sync.writeMeta({
        MetaKeys.cursor: target.toString(),
        MetaKeys.held: next.encode(),
      });
      _cursor = target;
      _held = next;
      _applied.clear();
      // Received again with g' as the K1 reference: K2 for every re-read record (g' ≥ g).
      return const ApplyResult(rewound: true) + await _catchUp(reference: g);
    }
    final due = _held.dueIds(g);
    if (due.isEmpty) return const ApplyResult();
    final found = <RemoteChunk>[];
    try {
      for (var i = 0; i < due.length; i += config.fetchPageSize) {
        final end = i + config.fetchPageSize;
        found.addAll(
          await backend.getChunks(
            due.sublist(i, end < due.length ? end : due.length),
          ),
        );
      }
    } on SyncBackendException catch (e) {
      return ApplyResult(error: e);
    }
    final returned = {for (final c in found) c.id};
    return _apply(
      found,
      reference: g,
      release: true,
      forgetHeld: [
        for (final id in due)
          if (!returned.contains(id)) id,
      ],
    );
  }

  /// [reference] replaces g = min(chunk serverTime, wall) as the K1 reference; [release]
  /// re-reads held chunks (no LRU skip, cursor and scope statistics unchanged).
  ///
  /// [reapply] (S-13 — 07-sync 6.3.4; chunk id → the original index of each record of the
  /// synthetic payload) makes [chunks] synthetic chunks of `sync.heldRecords` (with
  /// [release]): remember: false — keep() does not put their ids in the LRU; releaseHolds:
  /// false — `sync.held` is not touched (a hold of the original chunk's other records stays);
  /// a K1 hold becomes the record's ra instead (HeldRecords.settle); own delta chunks are not
  /// skipped and give no clock sample; the result counts reappliedChunks / reappliedRecords
  /// and no latestServerTime.
  Future<ApplyResult> _apply(
    List<RemoteChunk> chunks, {
    int? reference,
    bool release = false,
    List<String> forgetHeld = const [],
    Map<String, List<int>>? reapply,
  }) async {
    assert(reapply == null || release, 'a re-apply is a release');
    final now = wallMillis();
    final issues = <SyncIssue>[];
    void issue(SyncIssueCode code, String message, {EntityRef? ref}) =>
        issues.add(
          SyncIssue(
            code: code,
            message: message,
            firstAt: now,
            lastAt: now,
            ref: ref,
          ),
        );

    // 1. Session LRU (a release re-reads chunks on purpose).
    final seen = <String>{};
    final fresh = <RemoteChunk>[];
    var duplicates = 0;
    // Working copies: memory changes only once the meta is stored.
    var cursor = _cursor;
    for (final c in chunks) {
      if (!seen.add(c.id) || (!release && _applied.contains(c.id))) {
        duplicates++;
        // Already applied: a re-commit (lost ack, 6.5.3) brings the same content with a
        // newer serverTime — the cursor may follow it.
        if (!release && _applied.contains(c.id)) {
          cursor = cursor == null
              ? c.serverTime
              : ServerCursor.max(cursor, c.serverTime);
        }
      } else {
        fresh.add(c);
      }
    }

    final stats = _stats.copy();
    final held = _held.copy();
    final heldRecords = _heldRecords.copy();
    var heldRecordsChanged = false;
    var deferredFrom = _deferredFrom;
    ServerCursor? latest;
    var ownSkipped = 0;
    var heldChanged = false;
    for (final id in forgetHeld) {
      heldChanged = held.release(id) || heldChanged;
    }

    // 2–3. Own chunks, format, decoding (S-13: records of unknown kinds held, 6.3.3).
    final decoded = <(RemoteChunk, List<SyncRecord>)>[];
    // Re-apply: per decoded chunk, the original index of each of its records.
    final decodedIndexes = <List<int>>[];
    // Re-apply: records settled (gone from sync.heldRecords) and those K1 holds (→ ra).
    final settled = <(String, int)>[];
    final heldUntil = <(String, int), int>{};
    final newlyHeldKinds = <String>{};
    var newlyHeld = 0;
    for (final c in fresh) {
      if (reapply == null) {
        latest = latest == null
            ? c.serverTime
            : ServerCursor.max(latest, c.serverTime);
      }
      if (!release) {
        cursor = cursor == null
            ? c.serverTime
            : ServerCursor.max(cursor, c.serverTime);
      }
      final own = reapply == null && c.authorNodeId == sync.deviceNodeId;
      if (own) onOwnChunk(c);
      if (!release && !(own && c.kind == ChunkKind.snapshot)) {
        stats.addChunk(c.scope);
      }
      if (own && c.kind == ChunkKind.delta) {
        ownSkipped++;
        continue;
      }
      if (c.format > codecFormat) {
        issue(
          SyncIssueCode.needsAppUpdate,
          'chunk ${c.id} has format ${c.format} > $codecFormat',
        );
        final from = deferredFrom;
        if (from == null || c.serverTime < from) deferredFrom = c.serverTime;
        continue;
      }
      try {
        final payload = ChunkCodec.decodeTolerant(
          c.payload,
          isKnownKind: _knownNames.contains,
        );
        decoded.add((c, payload.records));
        if (reapply != null) {
          // The known records are the payload positions the unknown ones leave (in a
          // re-apply every kind is known — knownChunks — so normally all of them).
          final unknownAt = {for (final u in payload.unknown) u.index};
          final original = reapply[c.id]!;
          decodedIndexes.add([
            for (var i = 0; i < original.length; i++)
              if (!unknownAt.contains(i)) original[i],
          ]);
          continue;
        }
        if (payload.unknown.isNotEmpty) {
          // Dedup by (kind, id, fv): a chunk received again (overlap, K2 release) adds
          // nothing; one the mark covers is not stored.
          final n = heldRecords.add(c, payload.unknown);
          if (n > 0) {
            newlyHeld += n;
            heldRecordsChanged = true;
            newlyHeldKinds.addAll([
              for (final u in payload.unknown) u.kindName,
            ]);
          }
        }
      } on FormatException catch (e) {
        issue(SyncIssueCode.malformedRemoteData, 'chunk ${c.id}: ${e.message}');
        // Bytes this app cannot read although it knows their kinds: skipped like any
        // malformed chunk, and no longer kept.
        if (reapply != null) {
          settled.addAll([for (final i in reapply[c.id]!) (c.id, i)]);
        }
      }
    }
    if (newlyHeld > 0) {
      final names = newlyHeldKinds.toList()..sort();
      issue(
        SyncIssueCode.needsAppUpdate,
        '$newlyHeld record(s) of kind ${names.join(', ')} held until the app is '
        'updated',
      );
    }

    // 4. Permanent-deletion view up to date.
    await purged.refreshIfStale();

    // 5. Gate, holds, per-ref merge.
    final batchPurges = <EntityRef>{
      for (final (_, records) in decoded)
        for (final r in records)
          if (r is PurgeRecord &&
              (r.ref.kind == EntityKind.folder ||
                  r.ref.kind == EntityKind.note))
            r.ref,
    };
    bool isPurged(EntityRef ref) =>
        purged.contains(ref) || batchPurges.contains(ref);
    final elementNotes = await _libElementNotes(decoded);
    final uid = backend.uid;
    final merged = <EntityRef, SyncRecord>{};
    var heldCount = 0, dropped = 0, rejected = 0;
    for (final (n, (c, records)) in decoded.indexed) {
      final g = reference ?? RecordGate.referenceMillis(c.serverTime, now);
      int? releaseAt;
      for (final (j, record) in records.indexed) {
        final at = reapply == null ? null : (c.id, decodedIndexes[n][j]);
        final verdict = RecordGate.check(
          record,
          scope: c.scope,
          referenceMillis: g,
          uid: uid,
          isPurged: isPurged,
          elementNoteId: record is UpsertRecord && _isElement(record.doc.kind)
              ? elementNotes[record.doc.json['pageId']]
              : null,
          limit: config.clockSkewLimit,
        );
        switch (verdict) {
          case GateAccept():
            if (!_mergeInto(merged, record)) {
              rejected++;
              issue(
                SyncIssueCode.malformedRemoteData,
                '${record.ref} in ${c.id} does not merge with the same ref',
                ref: record.ref,
              );
            }
          case GateSkip(:final code, :final reason):
            rejected++;
            issue(code, '$reason (chunk ${c.id})', ref: record.ref);
          case GateDrop():
            dropped++;
          case GateHold(:final releaseAtMillis):
            heldCount++;
            if (at != null) {
              heldUntil[at] = releaseAtMillis;
              continue;
            }
            if (releaseAt == null || releaseAtMillis > releaseAt) {
              releaseAt = releaseAtMillis;
            }
        }
        // Accepted (applied, or rejected by the store below), skipped or dropped: done.
        if (at != null) settled.add(at);
      }
      if (reapply != null) continue;
      if (releaseAt != null) {
        held.hold(c.id, c.serverTime, releaseAt);
        heldChanged = true;
      } else if (held.release(c.id)) {
        heldChanged = true;
      }
    }
    if (reapply != null && (settled.isNotEmpty || heldUntil.isNotEmpty)) {
      heldRecords.settle(applied: settled, heldUntil: heldUntil);
      heldRecordsChanged = true;
    }
    final records = merged.values.toList(growable: false);
    final purges = [
      for (final r in records)
        if (r is PurgeRecord) r,
    ];

    // 6. PurgeGuard before the purges are applied.
    if (purges.isNotEmpty) await purgeGuard(purges);
    // 6b. (v2.17-md) The MD 문서 conflict-copy rule before the bodies are applied.
    final bodies = [
      for (final r in records)
        if (r is UpsertRecord && r.ref.kind == EntityKind.markdown) r,
    ];
    if (bodies.isNotEmpty) await markdownGuard(bodies);

    // Meta for the last call of this batch.
    final meta = <String, String>{
      if (cursor != null && cursor != _cursor) MetaKeys.cursor: '$cursor',
      ...purged.updatesFor(purges, nowMillis: now),
    };
    final statsText = stats.encode();
    if (statsText != _stats.encode()) meta[MetaKeys.scopeStats] = statsText;
    if (heldChanged) {
      final heldText = held.encode();
      if (heldText != _held.encode()) meta[MetaKeys.held] = heldText;
    }
    if (deferredFrom != _deferredFrom) {
      meta[MetaKeys.deferredFrom] = '$deferredFrom';
      meta[MetaKeys.deferredFormat] = '$codecFormat';
    }
    var heldRecordsText = _heldRecordsText;
    if (heldRecordsChanged) {
      heldRecordsText = heldRecords.encode();
      for (final MapEntry(:key, :value) in heldRecordsText.entries) {
        if (_heldRecordsText[key] != value) meta[key] = value;
      }
    }

    void keep() {
      _cursor = cursor;
      _stats = stats;
      _held = held;
      _heldRecords = heldRecords;
      _heldRecordsText = heldRecordsText;
      _deferredFrom = deferredFrom;
      purged.absorb(meta);
      if (reapply != null) return; // remember: false
      for (final c in fresh) {
        _applied.add(c.id);
      }
    }

    ApplyResult result({int applied = 0, Object? error}) => ApplyResult(
      chunks: reapply == null ? fresh.length : 0,
      reappliedChunks: reapply == null ? 0 : fresh.length,
      reappliedRecords: reapply == null ? 0 : applied,
      duplicates: duplicates,
      applied: reapply == null ? applied : 0,
      held: heldCount,
      dropped: dropped,
      rejected: rejected,
      ownSkipped: ownSkipped,
      issues: issues,
      latestServerTime: latest,
      error: error,
    );

    // 7–8. Apply groups; the meta rides on the very last call.
    final groups = _groups(records);
    var applied = 0;
    try {
      if (groups.isEmpty) {
        if (meta.isNotEmpty) await sync.writeMeta(meta);
        keep();
      }
      for (final (i, group) in groups.indexed) {
        final last = i == groups.length - 1;
        final outcome = await _applyGroup(group, last ? meta : const {}, (
          record,
          error,
        ) {
          rejected++;
          issue(
            SyncIssueCode.malformedRemoteData,
            '${record.ref} rejected by the local store: $error',
            ref: record.ref,
          );
        });
        applied += outcome;
        if (last) keep();
        try {
          await afterGroup(_recorder.outcomes);
        } on Object catch (e) {
          // The checks write through the store (commitRepairs): thrown without retry.
          throw _StoreFailure(e);
        }
        if (!last) await Future<void>.delayed(Duration.zero);
      }
    } on _StoreFailure catch (e) {
      return result(applied: applied, error: e.error);
    }
    return result(applied: applied);
  }

  /// One apply group (6.6.3 step 7): bisect on rejection, one by one when the bisect budget
  /// is spent. Returns the records in committed calls. [meta] goes on the group's last call;
  /// if that call is a rejected single record, sync.writeMeta stores it instead.
  Future<int> _applyGroup(
    List<SyncRecord> group,
    Map<String, String> meta,
    void Function(SyncRecord record, Object error) onRejected,
  ) async {
    _recorder.clear();
    final pieces = Queue<(List<SyncRecord>, Map<String, String>)>()
      ..add((group, meta));
    var steps = 0, applied = 0;
    while (pieces.isNotEmpty) {
      final (piece, pieceMeta) = pieces.removeFirst();
      final error = await _call(piece, pieceMeta);
      if (error == null) {
        applied += piece.length;
        continue;
      }
      if (piece.length == 1) {
        onRejected(piece.single, error);
        if (pieceMeta.isNotEmpty) await _writeMeta(pieceMeta);
        continue;
      }
      if (steps < config.maxBisectSteps) {
        steps++;
        final half = piece.length ~/ 2;
        pieces
          ..addFirst((piece.sublist(half), pieceMeta))
          ..addFirst((piece.sublist(0, half), const {}));
        continue;
      }
      // Budget spent: record by record, the meta on the last single call (SYNC-3-4).
      for (final (i, record) in piece.indexed) {
        final m = i == piece.length - 1 ? pieceMeta : const <String, String>{};
        final e = await _call([record], m);
        if (e == null) {
          applied++;
        } else {
          onRejected(record, e);
          if (m.isNotEmpty) await _writeMeta(m);
        }
      }
    }
    return applied;
  }

  /// One applyRemote call through the recorder. Returns the rejection (rolled back:
  /// ArgumentError, StateError, FormatException, NoteCoreException — 5.1.2 S-2·S-7) or
  /// null; any other error is a store failure and stops the batch.
  Future<Object?> _call(
    List<SyncRecord> records,
    Map<String, String> meta,
  ) async {
    _recorder.beginCall();
    try {
      await sync.applyRemote(
        [for (final r in records) _change(r)],
        policy: _recorder.wrap(SyncMergePolicy.decide),
        metaUpdates: meta,
      );
    } on Object catch (e) {
      _recorder.discardCall();
      if (_isRejection(e)) return e;
      throw _StoreFailure(e);
    }
    _recorder.commitCall();
    return null;
  }

  Future<void> _writeMeta(Map<String, String> meta) async {
    try {
      await sync.writeMeta(meta);
    } on Object catch (e) {
      throw _StoreFailure(e);
    }
  }

  static RemoteChange _change(SyncRecord record) => switch (record) {
    UpsertRecord() => record.toRemoteChange(),
    PurgeRecord() => record.toRemoteChange(),
  };

  static bool _isRejection(Object e) =>
      e is ArgumentError ||
      e is StateError ||
      e is FormatException ||
      e is NoteCoreException;

  /// Same ref twice in one batch: purge wins, upserts merge (6.6.3 step 5). False when the
  /// two cannot merge.
  static bool _mergeInto(Map<EntityRef, SyncRecord> merged, SyncRecord record) {
    final existing = merged[record.ref];
    switch ((existing, record)) {
      case (null, _):
        merged[record.ref] = record;
      case (PurgeRecord(hlc: final a), PurgeRecord(hlc: final b)):
        if (b > a) merged[record.ref] = record;
      case (PurgeRecord(), UpsertRecord()):
        break;
      case (UpsertRecord(), PurgeRecord()):
        merged[record.ref] = record;
      case (final UpsertRecord a, final UpsertRecord b):
        try {
          merged[record.ref] = FieldMerge.mergeRecords(a, b);
        } on Object {
          return false;
        }
    }
    return true;
  }

  /// Apply groups: ≤ maxRecordsPerApply records and ≤ maxBytesPerApply encoded bytes.
  List<List<SyncRecord>> _groups(List<SyncRecord> records) {
    final groups = <List<SyncRecord>>[];
    var current = <SyncRecord>[];
    var bytes = 0;
    for (final r in records) {
      final size = ChunkCodec.encodeRecord(r).length;
      if (current.isNotEmpty &&
          (current.length + 1 > config.maxRecordsPerApply ||
              bytes + size > config.maxBytesPerApply)) {
        groups.add(current);
        current = [];
        bytes = 0;
      }
      current.add(r);
      bytes += size;
    }
    if (current.isNotEmpty) groups.add(current);
    return groups;
  }

  /// Page elements whose note comes from their page (6.3.5; 2nd round 6.2.7).
  static bool _isElement(EntityKind kind) =>
      kind == EntityKind.stroke || kind == EntityKind.pageObject;

  /// Notes of 'lib'-scope strokes and (2nd round, 07-sync 6.2.7) page objects (no hint,
  /// 6.3.5): the page record in the same batch, else the local page row. Unknown pages are
  /// left out (the element is not dropped — stored as an orphan).
  Future<Map<String, String>> _libElementNotes(
    List<(RemoteChunk, List<SyncRecord>)> decoded,
  ) async {
    final pageIds = <String>{};
    final pageNotes = <String, String>{};
    for (final (c, records) in decoded) {
      for (final r in records) {
        if (r is! UpsertRecord) continue;
        final json = r.doc.json;
        if (r.doc.kind == EntityKind.page) {
          if (json['noteId'] case final String noteId) {
            pageNotes[r.doc.id] = noteId;
          }
        } else if (_isElement(r.doc.kind) && c.scope == SyncScopes.library) {
          if (json['pageId'] case final String pageId) pageIds.add(pageId);
        }
      }
    }
    pageIds.removeAll(pageNotes.keys);
    if (pageIds.isNotEmpty) {
      final ids = pageIds.toList();
      final rows = await sync.readVersioned([
        for (final id in ids) EntityRef(EntityKind.page, id),
      ]);
      for (final (i, row) in rows.indexed) {
        if (row?.entity case final Page page) pageNotes[ids[i]] = page.noteId;
      }
    }
    return pageNotes;
  }
}

/// An error the local store threw without retry: stops the batch (6.6.3 step 7).
final class _StoreFailure implements Exception {
  const _StoreFailure(this.error);
  final Object error;
}
