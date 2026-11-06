// lib/src/storage/drift_recording_draft_store.dart (internal) — RecordingDraftStore on SQLite
// + the asset blob store (m5-7/02-core 6.7, contract 7.2.4). Same meaning as the fake store's
// drafts (test/shared/recording_draft_contract.dart runs on both).
//
// Rows: recording_drafts (device-local — no versions, outbox, ChangeBatch, backup or sync),
// written by write queue jobs (the 1st-round 'every write goes through the queue'). Bytes: the
// blob store keys 'rd/<draftId>/<index, 6 digits>' (asset keys are '<sha256>/<index>') and the
// draft meta 'rd/<draftId>/meta' (UTF-8 JSON), written by begin() BEFORE the row: on the web
// the row becomes durable a few ms after its commit (6.7.3), so a lost row is rebuilt from
// the meta and the chunks (listDrafts). Orphan cleanup on first use removes only prefixes
// with neither a row nor a meta (a cut deletion).
import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

import '../assets/blob_store.dart';
import '../common/ids.dart';
import '../repo/recording_repository.dart';
import 'db/note_database.dart';
import 'drift_note_store.dart';

const int _maxChunk = 4 * 1024 * 1024;
const int _maxChunkIndex = 999999;
const String _root = 'rd/';

String _prefix(String draftId) => '$_root$draftId/';
String _chunkKey(String draftId, int i) =>
    '${_prefix(draftId)}${i.toString().padLeft(6, '0')}';
String _metaKey(String draftId) => '${_prefix(draftId)}meta';

/// The draft id of a blob key under [_root] (`rd/<draftId>/…`).
String _draftOf(String key) {
  final rest = key.substring(_root.length);
  final slash = rest.indexOf('/');
  return slash < 0 ? rest : rest.substring(0, slash);
}

/// The chunk count from index 0 without a gap, among the keys of one draft.
int _contiguous(Set<String> keys, String draftId) {
  var n = 0;
  while (keys.contains(_chunkKey(draftId, n))) {
    n++;
  }
  return n;
}

RecordingDraftsCompanion _rowOf(RecordingDraft d) =>
    RecordingDraftsCompanion.insert(
      draftId: d.draftId,
      recordingId: d.recordingId,
      noteId: d.noteId,
      mimeType: d.mimeType,
      startedAt: d.startedAt,
      chunkCount: d.chunkCount,
      bytes: d.bytes,
      activeMs: d.activeMs,
      updatedAt: d.updatedAt,
    );

final class DriftRecordingDraftStore implements RecordingDraftStore {
  DriftRecordingDraftStore(this.s, this.blobs);
  final DriftNoteStore s;

  /// The asset blob store (IndexedDB on the web, files on native — 6.15.3).
  final BlobStore blobs;

  NoteDatabase get _db => s.db;

  /// Tests: the blob keys put and the row writes (`row:<draftId>`) in the order they
  /// happened (the meta comes before the row — 6.7.2).
  @visibleForTesting
  final List<String> debugWriteOrder = [];

  /// The appends of each draft, chained in call order (6.7.2).
  final Map<String, Future<void>> _chains = {};

  /// The index of the next non-empty chunk per draft.
  final Map<String, int> _next = {};

  Future<void>? _cleaned;

  /// First use after the store opened: prefixes with neither a row nor a meta are removed
  /// (6.7.2 — a cut deletion). A failure does not fail the call (tried again next time).
  Future<void> _cleanOnce() => _cleaned ??= () async {
    try {
      final keys = await blobs.keys(_root);
      if (keys.isEmpty) return;
      final rows = {
        for (final r in await (_db.selectOnly(
          _db.recordingDrafts,
        )..addColumns([_db.recordingDrafts.draftId])).get())
          r.read(_db.recordingDrafts.draftId)!,
      };
      final prefixes = <String, bool>{}; // draft id → has a meta
      for (final k in keys) {
        final id = _draftOf(k);
        prefixes[id] = (prefixes[id] ?? false) || k == _metaKey(id);
      }
      for (final MapEntry(key: id, value: hasMeta) in prefixes.entries) {
        if (hasMeta || rows.contains(id)) continue;
        await blobs.deletePrefix(_prefix(id));
      }
    } on Object {
      _cleaned = null;
    }
  }();

  Future<void> _put(String key, Uint8List bytes) async {
    await blobs.put(key, bytes);
    debugWriteOrder.add(key);
  }

  Future<RecordingDraftRow?> _row(String draftId) => (_db.select(
    _db.recordingDrafts,
  )..where((t) => t.draftId.equals(draftId))).getSingleOrNull();

  Future<Map<String, Object?>?> _meta(String draftId) async {
    final m = await blobs.get(_metaKey(draftId));
    return m == null
        ? null
        : jsonDecode(utf8.decode(m)) as Map<String, Object?>;
  }

  /// A row, or a meta (a draft whose row was lost).
  Future<bool> _known(String draftId) async =>
      await _row(draftId) != null || await blobs.get(_metaKey(draftId)) != null;

  /// Waits for the appends queued so far (all drafts, or [draftId]'s).
  Future<void> _settled([String? draftId]) async {
    final chains = draftId == null ? [..._chains.values] : [?_chains[draftId]];
    for (final c in chains) {
      await c.then<void>((_) {}, onError: (Object _) {});
    }
  }

  @override
  Future<RecordingDraft> begin({
    required RecordingId recordingId,
    required NoteId noteId,
    required String mimeType,
    required EpochMillis startedAt,
  }) async {
    if (!isValidEntityId(recordingId)) {
      throw ArgumentError.value(recordingId, 'recordingId', 'invalid id');
    }
    if (!isValidEntityId(noteId)) {
      throw ArgumentError.value(noteId, 'noteId', 'invalid id');
    }
    if (mimeType.isEmpty) {
      throw ArgumentError.value(mimeType, 'mimeType', 'must not be empty');
    }
    await _cleanOnce();
    if (await _taken(recordingId)) {
      throw StateError('Recording $recordingId already has a draft');
    }
    final draftId = s.ids.newId();
    // ① the meta first: the row may not be durable yet on the web (6.7.3). A failure ends
    // begin() with that error and no row.
    await _put(
      _metaKey(draftId),
      Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'v': 1,
            'recordingId': recordingId,
            'noteId': noteId,
            'mimeType': mimeType,
            'startedAt': startedAt,
          }),
        ),
      ),
    );
    _next[draftId] = 0;
    // ② the row.
    try {
      return await s.queue.run((tx) async {
        final other =
            await (_db.select(_db.recordingDrafts)
                  ..where((t) => t.recordingId.equals(recordingId))
                  ..limit(1))
                .getSingleOrNull();
        if (other != null) {
          throw StateError('Recording $recordingId already has a draft');
        }
        final draft = RecordingDraft(
          draftId: draftId,
          recordingId: recordingId,
          noteId: noteId,
          mimeType: mimeType,
          startedAt: startedAt,
          chunkCount: 0,
          bytes: 0,
          activeMs: 0,
          updatedAt: tx.now,
        );
        await _db.into(_db.recordingDrafts).insert(_rowOf(draft));
        debugWriteOrder.add('row:$draftId');
        return draft;
      });
    } on StateError {
      // A begin of the same recording won meanwhile: this draft's meta must not be
      // rebuilt as a draft later.
      _next.remove(draftId);
      await blobs.deletePrefix(_prefix(draftId));
      rethrow;
    }
  }

  /// A draft of [recordingId] exists: a row, or a meta of a prefix whose row was lost.
  Future<bool> _taken(RecordingId recordingId) async {
    final row =
        await (_db.select(_db.recordingDrafts)
              ..where((t) => t.recordingId.equals(recordingId))
              ..limit(1))
            .getSingleOrNull();
    if (row != null) return true;
    final metas = [
      for (final k in await blobs.keys(_root))
        if (k == _metaKey(_draftOf(k))) _draftOf(k),
    ];
    for (final id in metas) {
      if (await _row(id) != null) continue;
      if ((await _meta(id))?['recordingId'] == recordingId) return true;
    }
    return false;
  }

  @override
  Future<void> append(
    String draftId,
    Uint8List chunk, {
    required int activeMs,
  }) {
    // Copied now: the caller may reuse its buffer before the chained write runs.
    final bytes = Uint8List.fromList(chunk);
    final previous = _chains[draftId] ?? Future<void>.value();
    final done = previous
        .then<void>((_) {}, onError: (Object _) {})
        .then((_) => _append(draftId, bytes, activeMs));
    final tail = done.then<void>((_) {}, onError: (Object _) {});
    _chains[draftId] = tail;
    unawaited(
      tail.then((_) {
        if (identical(_chains[draftId], tail)) _chains.remove(draftId);
      }),
    );
    return done;
  }

  Future<void> _append(String draftId, Uint8List chunk, int activeMs) async {
    await _cleanOnce();
    if (!await _known(draftId)) {
      throw StateError('Unknown recording draft $draftId');
    }
    if (chunk.length > _maxChunk) {
      throw ArgumentError.value(chunk.length, 'chunk', 'at most 4 MiB');
    }
    if (activeMs < 0) {
      throw ArgumentError.value(activeMs, 'activeMs', 'must be >= 0');
    }
    final empty = chunk.isEmpty;
    var index = -1;
    if (!empty) {
      index =
          _next[draftId] ??
          _contiguous((await blobs.keys(_prefix(draftId))).toSet(), draftId);
      if (index > _maxChunkIndex) {
        throw ArgumentError.value(index, 'chunk index', 'at most 999,999');
      }
      await _put(_chunkKey(draftId, index), chunk); // ①
      _next[draftId] = index + 1;
    }
    // ② the row; its Future completes after the commit (pending while it is retried).
    await s.queue.run((tx) async {
      final cur = await _row(draftId);
      // Discarded meanwhile (here or in another tab): gone.
      if (cur == null) throw StateError('Unknown recording draft $draftId');
      await (_db.update(
        _db.recordingDrafts,
      )..where((t) => t.draftId.equals(draftId))).write(
        RecordingDraftsCompanion(
          chunkCount: Value(empty ? cur.chunkCount : index + 1),
          bytes: Value(cur.bytes + chunk.length),
          activeMs: Value(activeMs),
          updatedAt: Value(tx.now),
        ),
      );
    }, bytes: chunk.length);
  }

  @override
  Future<List<RecordingDraft>> listDrafts() async {
    await _cleanOnce();
    await _settled();
    await s.queue.flush();
    final rows = await _db.select(_db.recordingDrafts).get();
    final keys = await blobs.keys(_root);
    final byDraft = <String, Set<String>>{};
    for (final k in keys) {
      (byDraft[_draftOf(k)] ??= {}).add(k);
    }
    final out = <RecordingDraft>[];
    for (final r in rows) {
      final own = byDraft[r.draftId] ?? const <String>{};
      final count = _contiguous(own, r.draftId);
      // Chunks after the row's count: cut between ① and ② — their lengths are added.
      // Fewer chunks than the row says: the stored chunks decide.
      final bytes = count >= r.chunkCount
          ? r.bytes + await _lengths(r.draftId, r.chunkCount, count)
          : await _lengths(r.draftId, 0, count);
      out.add(
        RecordingDraft(
          draftId: r.draftId,
          recordingId: r.recordingId,
          noteId: r.noteId,
          mimeType: r.mimeType,
          startedAt: r.startedAt,
          chunkCount: count,
          bytes: bytes,
          activeMs: r.activeMs,
          updatedAt: r.updatedAt,
        ),
      );
    }
    // Row-less prefixes with a meta: rebuilt (activeMs 0, updatedAt = startedAt — unknown,
    // so 'long ago' for pendingDrafts), and their rows written again.
    final withRow = {for (final r in rows) r.draftId};
    final rebuilt = <RecordingDraft>[];
    for (final MapEntry(key: id, value: own) in byDraft.entries) {
      if (withRow.contains(id) || !own.contains(_metaKey(id))) continue;
      final m = await _meta(id);
      if (m == null) continue;
      final count = _contiguous(own, id);
      final startedAt = (m['startedAt']! as num).toInt();
      rebuilt.add(
        RecordingDraft(
          draftId: id,
          recordingId: m['recordingId']! as String,
          noteId: m['noteId']! as String,
          mimeType: m['mimeType']! as String,
          startedAt: startedAt,
          chunkCount: count,
          bytes: await _lengths(id, 0, count),
          activeMs: 0,
          updatedAt: startedAt,
        ),
      );
    }
    if (rebuilt.isNotEmpty) {
      final written = await s.queue.run((tx) async {
        final kept = <RecordingDraft>[];
        for (final d in rebuilt) {
          final clash =
              await (_db.select(_db.recordingDrafts)
                    ..where(
                      (t) =>
                          t.draftId.equals(d.draftId) |
                          t.recordingId.equals(d.recordingId),
                    )
                    ..limit(1))
                  .getSingleOrNull();
          if (clash != null) continue;
          await _db.into(_db.recordingDrafts).insert(_rowOf(d));
          kept.add(d);
        }
        return kept;
      });
      out.addAll(written);
    }
    out.sort((a, b) {
      final c = a.startedAt.compareTo(b.startedAt);
      return c != 0 ? c : a.draftId.compareTo(b.draftId);
    });
    return List.unmodifiable(out);
  }

  /// The byte length of chunks [from] ≤ i < [to] of [draftId] (read one at a time).
  Future<int> _lengths(String draftId, int from, int to) async {
    var sum = 0;
    for (var i = from; i < to; i++) {
      sum += (await blobs.get(_chunkKey(draftId, i)))?.length ?? 0;
    }
    return sum;
  }

  @override
  Future<Uint8List> readAll(String draftId) async {
    await _cleanOnce();
    await _settled(draftId);
    await s.queue.flush();
    final row = await _row(draftId);
    if (row == null && await blobs.get(_metaKey(draftId)) == null) {
      throw StateError('Unknown recording draft $draftId');
    }
    final count = _contiguous(
      (await blobs.keys(_prefix(draftId))).toSet(),
      draftId,
    );
    // One result buffer plus one chunk at a time (M-4). The row's byte count sizes the
    // buffer when it agrees with the chunks; otherwise the lengths are read first.
    final size = row != null && row.chunkCount == count
        ? row.bytes
        : await _lengths(draftId, 0, count);
    var out = Uint8List(size);
    var o = 0;
    for (var i = 0; i < count; i++) {
      final c = await blobs.get(_chunkKey(draftId, i));
      if (c == null) break; // removed meanwhile (discard elsewhere)
      if (o + c.length > out.length) {
        out = Uint8List(o + c.length)..setRange(0, o, out);
      }
      out.setRange(o, o + c.length, c);
      o += c.length;
    }
    return o == out.length ? out : Uint8List.sublistView(out, 0, o);
  }

  /// After the commit that deleted the rows of [draftIds] (a purged note — 6.14.2, CORE
  /// T29): their chunks and meta. Best effort — a blob left over is an orphan for the first
  /// use after the next open (no row, no meta → removed; 6.7.2).
  Future<void> dropPurged(List<String> draftIds) async {
    for (final id in draftIds) {
      _next.remove(id);
      try {
        await blobs.deletePrefix(_prefix(id));
      } on Object {
        // Left for the orphan clean-up.
      }
    }
  }

  @override
  Future<void> discard(String draftId) async {
    await _cleanOnce();
    await _settled(draftId);
    if (!await _known(draftId)) return;
    // ① chunks + meta (one IndexedDB transaction on the web), ② the row. Cut between the
    // two, the row is left as a 0-chunk draft (6.7.2).
    await blobs.deletePrefix(_prefix(draftId));
    _next.remove(draftId);
    await s.queue.run(
      (tx) => (_db.delete(
        _db.recordingDrafts,
      )..where((t) => t.draftId.equals(draftId))).go(),
    );
  }
}
