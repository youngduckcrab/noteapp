// Internal: the 2nd-round repositories of the fake store (m5-7/02-core 6.17) — recordings
// (6.6), recording drafts in a memory blob map with the real key layout (6.7.2) and handwriting
// results with update / stalePages / notesWithStalePages (6.9). Same validation, order and
// ChangeBatch rules as the real store; no outbox, no field versions.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:collection/collection.dart';

import '../common/errors.dart';
import '../common/ids.dart';
import '../common/source_rev.dart';
import '../common/write_guard.dart';
import '../model/asset.dart';
import '../model/handwriting.dart';
import '../model/note.dart';
import '../repo/handwriting_repository.dart';
import '../repo/recording_repository.dart';
import '../session/page_content.dart';
import 'fake_note_store.dart';

// ---- recordings (6.6) ------------------------------------------------------------------

/// Trimmed 1..100 characters (runes), empty → null; longer → ArgumentError (6.6).
String? checkRecordingTitle(String? title) {
  if (title == null) return null;
  final t = title.trim();
  if (t.isEmpty) return null;
  if (t.runes.length > 100) {
    throw ArgumentError.value(title, 'title', 'at most 100 characters');
  }
  return t;
}

int _byStart(Recording a, Recording b) {
  final c = a.startedAt.compareTo(b.startedAt);
  return c != 0 ? c : a.id.compareTo(b.id);
}

final class FakeRecordings implements RecordingRepository {
  FakeRecordings(this.s);
  final FakeNoteStore s;

  List<Recording> _active(NoteId noteId) {
    final n = s.notes[noteId];
    if (n == null || n.ownerId != s.ownerId) return const [];
    return activeOf(noteId);
  }

  /// The active recordings of [noteId] (any owner), startedAt → id.
  List<Recording> activeOf(NoteId noteId) => List.unmodifiable(
    s.recordingRows.values
        .where((r) => r.noteId == noteId && !r.isDeleted)
        .toList()
      ..sort(_byStart),
  );

  @override
  Stream<List<Recording>> watchRecordings(NoteId noteId) => s.watch(
    () => _active(noteId),
    equals: const ListEquality<Recording>().equals,
  );

  @override
  Future<List<Recording>> recordingsOf(NoteId noteId) async => _active(noteId);

  @override
  Future<Recording?> getRecording(RecordingId id) async => s.recordingRows[id];

  @override
  Future<Recording> createRecording({
    required RecordingId id,
    required NoteId noteId,
    required AssetId assetId,
    required int durationMs,
    required EpochMillis startedAt,
    String? title,
  }) => s.write(() {
    // (v2.1, CP-7) idempotent per id: the stored row, before any validation.
    final existing = s.recordingRows[id];
    if (existing != null) return existing;
    if (!isValidEntityId(id)) {
      throw ArgumentError.value(id, 'id', 'invalid entity id');
    }
    if (s.notes[noteId] == null) {
      throw EntityNotFoundException('Note $noteId does not exist');
    }
    final asset = s.assetRows[assetId];
    if (asset == null || asset.type != AssetType.audio) {
      throw ArgumentError.value(
        assetId,
        'assetId',
        'an audio asset stored first (M-1)',
      );
    }
    if (durationMs < 0) {
      throw ArgumentError.value(durationMs, 'durationMs', 'must be >= 0');
    }
    final row = Recording(
      id: id,
      noteId: noteId,
      assetId: assetId,
      durationMs: durationMs,
      startedAt: startedAt,
      createdAt: s.now,
      updatedAt: s.now,
      version: s.hlc.now(),
      title: checkRecordingTitle(title),
    );
    s.recordingRows[id] = row;
    s.record(ChangeOrigin.local, [s.changeOf(row)]);
    return row;
  });

  @override
  Future<void> renameRecording(RecordingId id, String? title) => s.write(() {
    final cur = s.recordingRows[id];
    if (cur == null || cur.isDeleted) {
      throw EntityNotFoundException('Recording $id does not exist');
    }
    final t = checkRecordingTitle(title);
    if (t == cur.title) return;
    final next = cur.copyWith(
      title: t,
      clearTitle: t == null,
      updatedAt: s.now,
      version: s.hlc.now(),
    );
    s.recordingRows[id] = next;
    s.record(ChangeOrigin.local, [s.changeOf(next)]);
  });

  @override
  Future<void> deleteRecording(RecordingId id) => s.write(() {
    final cur = s.recordingRows[id];
    if (cur == null) {
      throw EntityNotFoundException('Recording $id does not exist');
    }
    if (cur.isDeleted) return;
    final next = cur.copyWith(
      deletedAt: s.now,
      updatedAt: s.now,
      version: s.hlc.now(),
    );
    s.recordingRows[id] = next;
    s.record(ChangeOrigin.local, [s.changeOf(next)]);
  });

  /// Σ Asset.size of the DISTINCT assets of the note's active recordings (metadata size —
  /// counted even without local bytes).
  @override
  Future<int> audioBytesOf(NoteId noteId) async {
    final assets = {for (final r in _active(noteId)) r.assetId};
    return assets.fold<int>(0, (sum, a) => sum + (s.assetRows[a]?.size ?? 0));
  }
}

// ---- recording drafts (6.7.2) ----------------------------------------------------------

const int _maxChunk = 4 * 1024 * 1024;
const int _maxChunkIndex = 999999;

String _chunkKey(String draftId, int i) =>
    'rd/$draftId/${i.toString().padLeft(6, '0')}';
String _metaKey(String draftId) => 'rd/$draftId/meta';

final class FakeRecordingDrafts implements RecordingDraftStore {
  FakeRecordingDrafts(this.s);
  final FakeNoteStore s;

  /// The blob keys in write order (tests check that the meta comes before the row).
  final List<String> blobWrites = [];

  /// Chunk index of the next non-empty append per draft (appends run in call order).
  final Map<String, int> _next = {};
  bool _cleaned = false;

  Map<String, Uint8List> get _blobs => s.draftBlobs;

  /// Orphan cleanup on first use: prefixes with neither a row nor a meta (6.7.2).
  void _cleanOnce() {
    if (_cleaned) return;
    _cleaned = true;
    final prefixes = {
      for (final k in _blobs.keys)
        if (k.startsWith('rd/')) k.split('/')[1],
    };
    for (final id in prefixes) {
      if (s.draftRows.containsKey(id) || _blobs.containsKey(_metaKey(id))) {
        continue;
      }
      _blobs.removeWhere((k, _) => k.startsWith('rd/$id/'));
    }
  }

  void _put(String key, Uint8List bytes) {
    _blobs[key] = Uint8List.fromList(bytes);
    blobWrites.add(key);
  }

  Map<String, Object?>? _meta(String draftId) {
    final m = _blobs[_metaKey(draftId)];
    return m == null
        ? null
        : jsonDecode(utf8.decode(m)) as Map<String, Object?>;
  }

  bool _known(String draftId) =>
      s.draftRows.containsKey(draftId) || _blobs.containsKey(_metaKey(draftId));

  /// The chunks from 0 without a gap.
  List<Uint8List> _chunks(String draftId) {
    final out = <Uint8List>[];
    for (var i = 0; ; i++) {
      final c = _blobs[_chunkKey(draftId, i)];
      if (c == null) return out;
      out.add(c);
    }
  }

  @override
  Future<RecordingDraft> begin({
    required RecordingId recordingId,
    required NoteId noteId,
    required String mimeType,
    required EpochMillis startedAt,
  }) async {
    _cleanOnce();
    if (!isValidEntityId(recordingId)) {
      throw ArgumentError.value(recordingId, 'recordingId', 'invalid id');
    }
    if (!isValidEntityId(noteId)) {
      throw ArgumentError.value(noteId, 'noteId', 'invalid id');
    }
    if (mimeType.isEmpty) {
      throw ArgumentError.value(mimeType, 'mimeType', 'must not be empty');
    }
    final taken =
        s.draftRows.values.any((d) => d.recordingId == recordingId) ||
        _blobs.keys.any(
          (k) =>
              k.endsWith('/meta') &&
              _meta(k.split('/')[1])?['recordingId'] == recordingId,
        );
    if (taken) {
      throw StateError('Recording $recordingId already has a draft');
    }
    final draftId = s.ids.newId();
    // ① the meta first (the row may not be durable yet on the web — 6.7.3).
    _put(
      _metaKey(draftId),
      utf8.encode(
        jsonEncode({
          'v': 1,
          'recordingId': recordingId,
          'noteId': noteId,
          'mimeType': mimeType,
          'startedAt': startedAt,
        }),
      ),
    );
    _next[draftId] = 0;
    // ② the row.
    return s.write(() {
      final draft = RecordingDraft(
        draftId: draftId,
        recordingId: recordingId,
        noteId: noteId,
        mimeType: mimeType,
        startedAt: startedAt,
        chunkCount: 0,
        bytes: 0,
        activeMs: 0,
        updatedAt: s.now,
      );
      s.draftRows[draftId] = draft;
      blobWrites.add('row:$draftId');
      return draft;
    });
  }

  @override
  Future<void> append(
    String draftId,
    Uint8List chunk, {
    required int activeMs,
  }) async {
    _cleanOnce();
    if (!_known(draftId)) {
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
      index = _next[draftId] ??= _chunks(draftId).length;
      if (index > _maxChunkIndex) {
        throw ArgumentError.value(index, 'chunk index', 'at most 999,999');
      }
      _next[draftId] = index + 1;
      _put(_chunkKey(draftId, index), chunk); // ①
    }
    return s.write(() {
      // ② the row; a draft discarded meanwhile is gone (StateError).
      final cur = s.draftRows[draftId];
      if (cur == null) throw StateError('Unknown recording draft $draftId');
      s.draftRows[draftId] = RecordingDraft(
        draftId: draftId,
        recordingId: cur.recordingId,
        noteId: cur.noteId,
        mimeType: cur.mimeType,
        startedAt: cur.startedAt,
        chunkCount: empty ? cur.chunkCount : index + 1,
        bytes: cur.bytes + chunk.length,
        activeMs: activeMs,
        updatedAt: s.now,
      );
    });
  }

  @override
  Future<List<RecordingDraft>> listDrafts() async {
    _cleanOnce();
    await s.flush();
    final out = <RecordingDraft>[];
    final rebuilt = <RecordingDraft>[];
    for (final row in s.draftRows.values) {
      final chunks = _chunks(row.draftId);
      final bytes = chunks.length >= row.chunkCount
          ? row.bytes +
                chunks
                    .skip(row.chunkCount)
                    .fold<int>(0, (sum, c) => sum + c.length)
          : chunks.fold<int>(0, (sum, c) => sum + c.length);
      out.add(
        RecordingDraft(
          draftId: row.draftId,
          recordingId: row.recordingId,
          noteId: row.noteId,
          mimeType: row.mimeType,
          startedAt: row.startedAt,
          chunkCount: chunks.length,
          bytes: bytes,
          activeMs: row.activeMs,
          updatedAt: row.updatedAt,
        ),
      );
    }
    // Row-less drafts with a meta: rebuilt (activeMs 0, updatedAt = startedAt — 'long ago').
    for (final key in _blobs.keys.toList()) {
      if (!key.endsWith('/meta')) continue;
      final draftId = key.split('/')[1];
      if (s.draftRows.containsKey(draftId)) continue;
      final m = _meta(draftId)!;
      final chunks = _chunks(draftId);
      final startedAt = m['startedAt']! as int;
      final draft = RecordingDraft(
        draftId: draftId,
        recordingId: m['recordingId']! as String,
        noteId: m['noteId']! as String,
        mimeType: m['mimeType']! as String,
        startedAt: startedAt,
        chunkCount: chunks.length,
        bytes: chunks.fold<int>(0, (sum, c) => sum + c.length),
        activeMs: 0,
        updatedAt: startedAt,
      );
      out.add(draft);
      rebuilt.add(draft);
    }
    if (rebuilt.isNotEmpty) {
      await s.write(() {
        for (final d in rebuilt) {
          s.draftRows[d.draftId] = d;
        }
      });
    }
    out.sort((a, b) {
      final c = a.startedAt.compareTo(b.startedAt);
      return c != 0 ? c : a.draftId.compareTo(b.draftId);
    });
    return List.unmodifiable(out);
  }

  @override
  Future<Uint8List> readAll(String draftId) async {
    _cleanOnce();
    await s.flush();
    if (!_known(draftId)) {
      throw StateError('Unknown recording draft $draftId');
    }
    final chunks = _chunks(draftId);
    final out = Uint8List(chunks.fold<int>(0, (sum, c) => sum + c.length));
    var o = 0;
    for (final c in chunks) {
      out.setRange(o, o + c.length, c);
      o += c.length;
    }
    return out;
  }

  @override
  Future<void> discard(String draftId) async {
    _cleanOnce();
    if (!_known(draftId)) return;
    // ① chunks + meta, ② the row.
    _blobs.removeWhere((k, _) => k.startsWith('rd/$draftId/'));
    _next.remove(draftId);
    await s.write(() => s.draftRows.remove(draftId));
  }

  /// Drafts of purged notes go with them (6.14.2).
  void notePurged(NoteId noteId) {
    for (final d in s.draftRows.values.toList()) {
      if (d.noteId == noteId) {
        s.draftRows.remove(d.draftId);
        _blobs.removeWhere((k, _) => k.startsWith('rd/${d.draftId}/'));
      }
    }
    for (final key in _blobs.keys.toList()) {
      if (!key.endsWith('/meta')) continue;
      final id = key.split('/')[1];
      if (_meta(id)?['noteId'] == noteId) {
        _blobs.removeWhere((k, _) => k.startsWith('rd/$id/'));
      }
    }
  }
}

// ---- handwriting (6.9) -----------------------------------------------------------------

final class FakeHandwriting implements HandwritingRepository {
  FakeHandwriting(this.s);
  final FakeNoteStore s;

  HandwritingText? _active(PageId pageId) {
    final h = s.handwritingRows[pageId];
    return h == null || h.isDeleted ? null : h;
  }

  /// put / update validation (6.9.4).
  void _check(HandwritingText value) {
    final page = s.pages[value.pageId];
    if (page == null) {
      throw EntityNotFoundException('Page ${value.pageId} does not exist');
    }
    if (page.noteId != value.noteId) {
      throw ArgumentError.value(
        value.noteId,
        'noteId',
        'page ${value.pageId} belongs to note ${page.noteId}',
      );
    }
    for (final l in value.lines) {
      if (l.alternatives.length > 5) {
        throw ArgumentError.value(
          l.alternatives.length,
          'alternatives',
          'at most 5',
        );
      }
      if (l.languageTag.isEmpty) {
        throw ArgumentError.value(l.languageTag, 'languageTag', 'empty');
      }
    }
  }

  /// Stores [value] (deletedAt cleared, updatedAt / version filled, an existing row's
  /// createdAt kept) and re-indexes the page. No synced key differs from the active row →
  /// nothing is written and the stored value is returned (as the SQLite store).
  HandwritingText _store(HandwritingText value) {
    final prev = s.handwritingRows[value.pageId];
    final candidate = HandwritingText(
      noteId: value.noteId,
      pageId: value.pageId,
      engineId: value.engineId,
      sourceRev: value.sourceRev,
      lines: value.lines,
      createdAt: prev?.createdAt ?? value.createdAt,
    );
    if (prev != null && !prev.isDeleted && _sameContent(prev, candidate)) {
      return prev;
    }
    final stored = candidate.copyWith(updatedAt: s.now, version: s.hlc.now());
    s.handwritingRows[value.pageId] = stored;
    s.search.handwritingWritten(stored);
    s.record(ChangeOrigin.local, [s.changeOf(stored)]);
    return stored;
  }

  static bool _sameContent(HandwritingText a, HandwritingText b) =>
      a.noteId == b.noteId &&
      a.engineId == b.engineId &&
      a.sourceRev == b.sourceRev &&
      const ListEquality<HandwritingLine>().equals(a.lines, b.lines);

  @override
  Future<HandwritingText?> forPage(PageId pageId) async => _active(pageId);

  @override
  Stream<HandwritingText?> watchPage(PageId pageId) =>
      s.watch(() => _active(pageId));

  @override
  Future<void> put(HandwritingText value) => s.write(() {
    _check(value);
    _store(value);
  });

  @override
  Future<HandwritingText?> update(
    PageId pageId,
    HandwritingText? Function(HandwritingText? current) transform,
  ) => s.write(() {
    if (s.pages[pageId] == null) {
      throw EntityNotFoundException('Page $pageId does not exist');
    }
    final current = _active(pageId);
    final next = runUpdateTransform(() => transform(current));
    if (next == null) return current;
    if (next.pageId != pageId) {
      throw ArgumentError.value(next.pageId, 'pageId', 'must be $pageId');
    }
    _check(next);
    return _store(next);
  });

  @override
  Future<void> removeForPage(PageId pageId) => s.write(() {
    final cur = _active(pageId);
    if (cur == null) return;
    final next = cur.copyWith(
      deletedAt: s.now,
      updatedAt: s.now,
      version: s.hlc.now(),
    );
    s.handwritingRows[pageId] = next;
    s.search.handwritingWritten(next);
    s.record(ChangeOrigin.local, [s.changeOf(next)]);
  });

  /// sourceRevOf of the page's active recognition-input strokes.
  String _inkRev(PageId pageId) => HandwritingText.sourceRevOf(
    s.activeStrokesOf(pageId).where(HandwritingText.isRecognitionInput),
  );

  bool _stale(PageId pageId) {
    final rev = _inkRev(pageId);
    final h = _active(pageId);
    return h == null ? rev != kEmptySourceRev : h.sourceRev != rev;
  }

  @override
  Future<List<PageId>> stalePages(NoteId noteId) async {
    await s.flush();
    final n = s.notes[noteId];
    if (n == null || n.ownerId != s.ownerId) return const [];
    return List.unmodifiable([
      for (final p in s.activePagesOf(noteId))
        if (_stale(p.id)) p.id,
    ]);
  }

  @override
  Future<List<NoteId>> notesWithStalePages() async {
    await s.flush();
    final notes = [
      for (final n in s.ownNotes)
        if (!n.isDeleted && s.activePagesOf(n.id).any((p) => _stale(p.id))) n,
    ]..sort(_newestFirst);
    return List.unmodifiable([for (final n in notes) n.id]);
  }

  static int _newestFirst(Note a, Note b) {
    final c = b.updatedAt.compareTo(a.updatedAt);
    return c != 0 ? c : a.id.compareTo(b.id);
  }
}
