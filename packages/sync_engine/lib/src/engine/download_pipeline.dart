// Internal (not exported). Receiving (6.6): fetch pages from the cursor (6.6.1–6.6.2), apply
// chunk batches (6.6.3), release held chunks (6.2.5 K2). The cursor, `sync.held`,
// `sync.scopeStats`, `sync.purged.*` and the deferred-format keys are written in the same
// transaction as the last applied records, so a crash re-receives the same page (idempotent).
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
    error: error ?? o.error,
  );

  @override
  String toString() =>
      'ApplyResult(chunks: $chunks, dup: $duplicates, applied: $applied, held: $held, '
      'dropped: $dropped, rejected: $rejected, pages: $pages, '
      'issues: ${issues.length}, error: $error)';
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
    this.afterGroup = _noChecks,
    this.codecFormat = ChunkCodec.formatVersion,
  }) : _applied = LruSet(config.appliedChunkMemory),
       _held = HeldChunks(maxEntries: config.maxHeldChunks);

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

  /// Step 8, once per apply group after all its pieces: folder cycles (6.7.2) and page
  /// resurrection (6.7.3) over the committed outcomes.
  final Future<void> Function(Map<EntityRef, MergeOutcomeKind> outcomes)
  afterGroup;

  /// Newest chunk format this app reads (6.6.5) — ChunkCodec.formatVersion.
  final int codecFormat;

  final LruSet<String> _applied;
  final MergeRecorder _recorder = MergeRecorder();

  ServerCursor? _cursor;
  ScopeStats _stats = ScopeStats();
  HeldChunks _held;
  ServerCursor? _deferredFrom;

  static int? _noSample() => null;
  static void _ignoreChunk(RemoteChunk chunk) {}
  static Future<void> _noGuard(List<PurgeRecord> purges) async {}
  static Future<void> _noChecks(Map<EntityRef, MergeOutcomeKind> o) async {}

  /// `sync.cursor`: newest serverTime of the applied chunks (6.6.2). Null before the first
  /// sync.
  ServerCursor? get cursor => _cursor;

  /// `sync.held` in memory.
  HeldChunks get held => _held.copy();

  ScopeStats get scopeStats => _stats.copy();

  /// `sync.deferredFrom` (6.6.5): a chunk in a newer format was seen.
  ServerCursor? get deferredFrom => _deferredFrom;

  /// Chunk ids applied in this session (6.6.3 step 1).
  bool wasApplied(String chunkId) => _applied.contains(chunkId);

  /// Reads the pipeline's meta. When this app reads a newer format than the one that
  /// deferred chunks, goes back to them: cursor = min(cursor, deferredFrom), keys cleared
  /// (6.6.5).
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

  /// K2 (6.2.5): with g' = min(serverNow, wall), receives the held chunks whose release
  /// time has come again (getChunks) and applies them with g' as the K1 reference; ids
  /// that did not come back (deleted by compaction) leave `sync.held`. The collapsed form
  /// moves the cursor back to its serverTime − cursorOverlap and receives everything after
  /// it again. Nothing happens without a server-time sample.
  Future<ApplyResult> releaseHeld() async {
    final serverNow = serverNowMillis();
    if (serverNow == null) return const ApplyResult();
    final wall = wallMillis();
    final g = serverNow < wall ? serverNow : wall;
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
  Future<ApplyResult> _apply(
    List<RemoteChunk> chunks, {
    int? reference,
    bool release = false,
    List<String> forgetHeld = const [],
  }) async {
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
    var deferredFrom = _deferredFrom;
    ServerCursor? latest;
    var ownSkipped = 0;
    var heldChanged = false;
    for (final id in forgetHeld) {
      heldChanged = held.release(id) || heldChanged;
    }

    // 2–3. Own chunks, format, decoding.
    final decoded = <(RemoteChunk, List<SyncRecord>)>[];
    for (final c in fresh) {
      latest = latest == null
          ? c.serverTime
          : ServerCursor.max(latest, c.serverTime);
      if (!release) {
        cursor = cursor == null
            ? c.serverTime
            : ServerCursor.max(cursor, c.serverTime);
      }
      final own = c.authorNodeId == sync.deviceNodeId;
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
        decoded.add((c, ChunkCodec.decode(c.payload)));
      } on FormatException catch (e) {
        issue(SyncIssueCode.malformedRemoteData, 'chunk ${c.id}: ${e.message}');
      }
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
    final strokeNotes = await _libStrokeNotes(decoded);
    final uid = backend.uid;
    final merged = <EntityRef, SyncRecord>{};
    var heldCount = 0, dropped = 0, rejected = 0;
    for (final (c, records) in decoded) {
      final g = reference ?? RecordGate.referenceMillis(c.serverTime, now);
      int? releaseAt;
      for (final record in records) {
        final verdict = RecordGate.check(
          record,
          scope: c.scope,
          referenceMillis: g,
          uid: uid,
          isPurged: isPurged,
          strokeNoteId:
              record is UpsertRecord && record.doc.kind == EntityKind.stroke
              ? strokeNotes[record.doc.json['pageId']]
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
            if (releaseAt == null || releaseAtMillis > releaseAt) {
              releaseAt = releaseAtMillis;
            }
        }
      }
      if (releaseAt != null) {
        held.hold(c.id, c.serverTime, releaseAt);
        heldChanged = true;
      } else if (held.release(c.id)) {
        heldChanged = true;
      }
    }
    final records = merged.values.toList(growable: false);
    final purges = [
      for (final r in records)
        if (r is PurgeRecord) r,
    ];

    // 6. PurgeGuard before the purges are applied.
    if (purges.isNotEmpty) await purgeGuard(purges);

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

    void keep() {
      _cursor = cursor;
      _stats = stats;
      _held = held;
      _deferredFrom = deferredFrom;
      purged.absorb(meta);
      for (final c in fresh) {
        _applied.add(c.id);
      }
    }

    ApplyResult result({int applied = 0, Object? error}) => ApplyResult(
      chunks: fresh.length,
      duplicates: duplicates,
      applied: applied,
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

  /// Notes of 'lib'-scope strokes (no hint, 6.3.5): the page record in the same batch, else
  /// the local page row. Unknown pages are left out (the stroke is not dropped).
  Future<Map<String, String>> _libStrokeNotes(
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
        } else if (r.doc.kind == EntityKind.stroke &&
            c.scope == SyncScopes.library) {
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
