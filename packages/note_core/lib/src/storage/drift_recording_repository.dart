// lib/src/storage/drift_recording_repository.dart (internal) — RecordingRepository on SQLite
// (m5-7/02-core 6.6, contract 7.2.4). Same meaning as the fake store's recordings
// (test/shared/recording_contract.dart runs on both).
//
// Writes go through the write queue (putLocal: field versions, outbox, ChangeBatch(local)).
// Recordings are outside undo history (R-8); strokes keep their recordingId when a recording
// is deleted (R-7) and the audio bytes stay until an asset GC (U13).
import 'package:collection/collection.dart';
import 'package:drift/drift.dart';

import '../common/errors.dart';
import '../common/ids.dart';
import '../model/asset.dart';
import '../model/sync_entity.dart';
import '../repo/recording_repository.dart';
import '../sync/outbox_types.dart';
import 'db/note_database.dart';
import 'drift_note_store.dart';
import 'row_mappers.dart';
import 'watch_hub.dart';

/// Trimmed 1..100 characters (runes), empty → null; longer → ArgumentError (6.6).
String? normalizedRecordingTitle(String? title) {
  if (title == null) return null;
  final t = title.trim();
  if (t.isEmpty) return null;
  if (t.runes.length > 100) {
    throw ArgumentError.value(title, 'title', 'at most 100 characters');
  }
  return t;
}

final class DriftRecordingRepository implements RecordingRepository {
  DriftRecordingRepository(this.s);
  final DriftNoteStore s;

  NoteDatabase get _db => s.db;

  /// Tests: createRecording calls that found the id with other arguments (the stored row
  /// won — 6.6 '개발 로그').
  int debugIdempotentMismatches = 0;

  /// The active recordings of [noteId] when the note belongs to the current owner,
  /// startedAt → id (6.6).
  Future<List<Recording>> _active(NoteId noteId) async {
    final n = _db.notes;
    final owner =
        await (_db.selectOnly(n)
              ..addColumns([n.ownerId])
              ..where(n.id.equals(noteId)))
            .getSingleOrNull();
    if (owner == null || owner.read(n.ownerId) != s.ownerId) return const [];
    final rows =
        await (_db.select(_db.recordings)
              ..where((t) => t.noteId.equals(noteId) & t.deletedAt.isNull())
              ..orderBy([
                (t) => OrderingTerm.asc(t.startedAt),
                (t) => OrderingTerm.asc(t.id),
              ]))
            .get();
    return List.unmodifiable([for (final r in rows) recordingOf(r)]);
  }

  Future<Recording?> _row(RecordingId id) async {
    final r = await (_db.select(
      _db.recordings,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return r == null ? null : recordingOf(r);
  }

  @override
  Stream<List<Recording>> watchRecordings(NoteId noteId) => s.watches.watch(
    affects: (CommitTouch t) =>
        t.kinds.contains(EntityKind.recording) ||
        t.kinds.contains(EntityKind.note),
    query: () => _active(noteId),
    equals: const ListEquality<Recording>().equals,
  );

  @override
  Future<List<Recording>> recordingsOf(NoteId noteId) => _active(noteId);

  @override
  Future<Recording?> getRecording(RecordingId id) => _row(id);

  @override
  Future<Recording> createRecording({
    required RecordingId id,
    required NoteId noteId,
    required AssetId assetId,
    required int durationMs,
    required EpochMillis startedAt,
    String? title,
  }) => s.queue.run((tx) async {
    // (v2.1, CP-7) Idempotent per id: the stored row, before any validation (deleted
    // rows too, not revived; no write, no ChangeBatch).
    final existing = await _row(id);
    if (existing != null) {
      if (existing.noteId != noteId ||
          existing.assetId != assetId ||
          existing.durationMs != durationMs ||
          existing.startedAt != startedAt) {
        debugIdempotentMismatches++;
      }
      return existing;
    }
    if (!isValidEntityId(id)) {
      throw ArgumentError.value(id, 'id', 'invalid entity id');
    }
    final note =
        await (_db.selectOnly(_db.notes)
              ..addColumns([_db.notes.id])
              ..where(_db.notes.id.equals(noteId)))
            .getSingleOrNull();
    if (note == null) {
      throw EntityNotFoundException('Note $noteId does not exist');
    }
    final a = _db.assets;
    final asset =
        await (_db.selectOnly(a)
              ..addColumns([a.type])
              ..where(a.id.equals(assetId)))
            .getSingleOrNull();
    if (asset == null || asset.read(a.type) != AssetType.audio.name) {
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
      createdAt: tx.now,
      updatedAt: tx.now,
      title: normalizedRecordingTitle(title),
    );
    final versions = await tx.putLocal(row, const {kAllFields}, isNew: true);
    return row.copyWith(version: versions.max);
  });

  @override
  Future<void> renameRecording(RecordingId id, String? title) =>
      s.queue.run((tx) async {
        final cur = await _row(id);
        if (cur == null || cur.isDeleted) {
          throw EntityNotFoundException('Recording $id does not exist');
        }
        final t = normalizedRecordingTitle(title);
        if (t == cur.title) return;
        await tx.putLocal(
          cur.copyWith(title: t, clearTitle: t == null, updatedAt: tx.now),
          const {'title', 'updatedAt'},
        );
      });

  @override
  Future<void> deleteRecording(RecordingId id) => s.queue.run((tx) async {
    final cur = await _row(id);
    if (cur == null) {
      throw EntityNotFoundException('Recording $id does not exist');
    }
    if (cur.isDeleted) return;
    await tx.putLocal(
      cur.copyWith(deletedAt: tx.now, updatedAt: tx.now),
      const {'deletedAt', 'updatedAt'},
    );
  });

  @override
  Future<int> audioBytesOf(NoteId noteId) async {
    final assets = {for (final r in await _active(noteId)) r.assetId};
    if (assets.isEmpty) return 0;
    final a = _db.assets;
    final rows =
        await (_db.selectOnly(a)
              ..addColumns([a.size])
              ..where(a.id.isIn(assets)))
            .get();
    return rows.fold<int>(0, (sum, r) => sum + r.read(a.size)!);
  }
}
