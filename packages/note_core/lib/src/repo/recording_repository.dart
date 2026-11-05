// lib/src/repo/recording_repository.dart — (v2.0) 2nd-round contract 7.2.4 / 02-core 4.5,
// 6.6, 6.7: RecordingRepository, RecordingDraftStore, RecordingDraft.
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../common/ids.dart';
import '../model/asset.dart';

/// (v2.0) Local create / list API (v1.4 had only the remote-apply path).
abstract interface class RecordingRepository {
  Stream<List<Recording>> watchRecordings(
    NoteId noteId,
  ); // active, startedAt asc
  Future<List<Recording>> recordingsOf(NoteId noteId);
  Future<Recording?> getRecording(RecordingId id); // also deleted ones
  /// Called by media_io AFTER AssetStore.put(audio) returned (M-1). [id] was chosen at
  /// record start so strokes could link to it immediately. (v2.1, CP-7) Idempotent per id: a retry with the
  /// same id returns the existing row (recovery after a failed save does not duplicate).
  Future<Recording> createRecording({
    required RecordingId id,
    required NoteId noteId,
    required AssetId assetId,
    required int durationMs,
    required EpochMillis startedAt,
    String? title,
  });
  Future<void> renameRecording(RecordingId id, String? title);

  /// Soft delete; no restore UI this round. Strokes keep recordingId (R-7). Asset bytes stay
  /// until asset GC (later, 3.2).
  Future<void> deleteRecording(RecordingId id);

  /// Σ Asset.size of the note's active recordings (재생 바 '용량').
  Future<int> audioBytesOf(NoteId noteId);
}

/// (v2.0) Crash-safe staging of an in-progress recording. Device-local: never synced, never in
/// backups, not in outbox. Chunks live in the asset blob store under a private prefix.
abstract interface class RecordingDraftStore {
  Future<RecordingDraft> begin({
    required RecordingId recordingId,
    required NoteId noteId,
    required String mimeType,
    required EpochMillis startedAt,
  });

  /// Ordered append; each chunk ≤ 4 MiB; completes after the chunk is durable (write-Future rule).
  /// (v2.1) An empty chunk is allowed and only updates activeMs / updatedAt (keep-alive while
  /// paused). Unknown draftId → StateError (the draft was recovered or discarded elsewhere).
  Future<void> append(String draftId, Uint8List chunk, {required int activeMs});

  /// Leftovers after a crash / closed tab. (v2.1) A web draft whose chunks are stored but whose row
  /// was not yet durable is rebuilt from the meta the store writes next to the chunks at begin();
  /// a draft with a row and 0 chunks (native — media writes rows only) is normal and kept. Orphan
  /// cleanup removes only prefixes that have neither a row nor a meta.
  Future<List<RecordingDraft>> listDrafts();
  Future<Uint8List> readAll(String draftId);
  Future<void> discard(String draftId);
}

// CORE 4.5: the contract's draft rules, CORE side (6.7.2):
//   one draft per recordingId (a second begin → StateError); web chunks and a meta blob
//   'rd/<draftId>/meta' are written BEFORE the row is durable; listDrafts rebuilds a row-less
//   draft from its meta (activeMs 0, updatedAt = startedAt) and reconciles chunkCount / bytes
//   with the chunks; discard = chunks + meta first, then the row.
@immutable
final class RecordingDraft {
  const RecordingDraft({
    required this.draftId,
    required this.recordingId,
    required this.noteId,
    required this.mimeType,
    required this.startedAt,
    required this.chunkCount,
    required this.bytes,
    required this.activeMs,
    required this.updatedAt,
  });
  final String draftId;
  final RecordingId recordingId;
  final NoteId noteId;
  final String mimeType;
  final EpochMillis startedAt;
  final int chunkCount, bytes, activeMs;
  final EpochMillis updatedAt;

  // CORE 4.5: ==, hashCode, toString
  @override
  bool operator ==(Object other) =>
      other is RecordingDraft &&
      other.draftId == draftId &&
      other.recordingId == recordingId &&
      other.noteId == noteId &&
      other.mimeType == mimeType &&
      other.startedAt == startedAt &&
      other.chunkCount == chunkCount &&
      other.bytes == bytes &&
      other.activeMs == activeMs &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    draftId,
    recordingId,
    noteId,
    mimeType,
    startedAt,
    chunkCount,
    bytes,
    activeMs,
    updatedAt,
  );

  @override
  String toString() =>
      'RecordingDraft($draftId, recording: $recordingId, $chunkCount chunks, '
      '$bytes B, ${activeMs}ms)';
}
