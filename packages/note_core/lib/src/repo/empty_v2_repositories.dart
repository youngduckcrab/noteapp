// Internal: the 2nd-round repositories of a store before their CORE task (02-core 8.1
// 'B2 상태'). Reads answer as for an empty store (no drafts, no handwriting results, no
// search index; recordings are not listed — not even a row that came by the 1차 remote
// path) and every write throws UnimplementedError('CORE <task>: …').
// The real store (DriftNoteStore) passes T30 / T31 / T32 / T33a, the fake store T23b.
import 'dart:typed_data';

import '../common/ids.dart';
import '../common/pending.dart';
import '../model/asset.dart';
import '../model/handwriting.dart';
import '../search/search_types.dart';
import 'handwriting_repository.dart';
import 'recording_repository.dart';

/// A watch stream with one value that stays open, like the store's watch streams (1차 rule:
/// the current value right after listen, then every change — there is none here).
Stream<T> _holdOne<T>(T value) => Stream<T>.multi((c) => c.add(value));

final class EmptyRecordingRepository implements RecordingRepository {
  EmptyRecordingRepository(this.writeTask);

  /// The CORE task whose implementation the writes wait for.
  final String writeTask;

  @override
  Stream<List<Recording>> watchRecordings(NoteId noteId) =>
      _holdOne<List<Recording>>(const []);

  @override
  Future<List<Recording>> recordingsOf(NoteId noteId) async => const [];

  @override
  Future<Recording?> getRecording(RecordingId id) async => null;

  @override
  Future<Recording> createRecording({
    required RecordingId id,
    required NoteId noteId,
    required AssetId assetId,
    required int durationMs,
    required EpochMillis startedAt,
    String? title,
  }) async => notYet(writeTask, 'RecordingRepository.createRecording');

  @override
  Future<void> renameRecording(RecordingId id, String? title) async =>
      notYet(writeTask, 'RecordingRepository.renameRecording');

  @override
  Future<void> deleteRecording(RecordingId id) async =>
      notYet(writeTask, 'RecordingRepository.deleteRecording');

  @override
  Future<int> audioBytesOf(NoteId noteId) async => 0;
}

final class EmptyRecordingDraftStore implements RecordingDraftStore {
  EmptyRecordingDraftStore(this.writeTask);

  /// The CORE task whose implementation the writes wait for.
  final String writeTask;

  @override
  Future<RecordingDraft> begin({
    required RecordingId recordingId,
    required NoteId noteId,
    required String mimeType,
    required EpochMillis startedAt,
  }) async => notYet(writeTask, 'RecordingDraftStore.begin');

  @override
  Future<void> append(
    String draftId,
    Uint8List chunk, {
    required int activeMs,
  }) async => notYet(writeTask, 'RecordingDraftStore.append');

  @override
  Future<List<RecordingDraft>> listDrafts() async => const [];

  /// No draft exists, so every id is unknown (contract 7.2.4: StateError).
  @override
  Future<Uint8List> readAll(String draftId) async =>
      throw StateError('Unknown recording draft $draftId');

  @override
  Future<void> discard(String draftId) async =>
      notYet(writeTask, 'RecordingDraftStore.discard');
}

final class EmptyHandwritingRepository implements HandwritingRepository {
  EmptyHandwritingRepository(this.writeTask);

  /// The CORE task whose implementation the writes wait for.
  final String writeTask;

  @override
  Future<HandwritingText?> forPage(PageId pageId) async => null;

  @override
  Stream<HandwritingText?> watchPage(PageId pageId) =>
      _holdOne<HandwritingText?>(null);

  @override
  Future<void> put(HandwritingText value) async =>
      notYet(writeTask, 'HandwritingRepository.put');

  @override
  Future<HandwritingText?> update(
    PageId pageId,
    HandwritingText? Function(HandwritingText? current) transform,
  ) async => notYet(writeTask, 'HandwritingRepository.update');

  @override
  Future<void> removeForPage(PageId pageId) async =>
      notYet(writeTask, 'HandwritingRepository.removeForPage');

  @override
  Future<List<PageId>> stalePages(NoteId noteId) async => const [];

  @override
  Future<List<NoteId>> notesWithStalePages() async => const [];
}

final class EmptySearchIndex implements SearchIndex {
  EmptySearchIndex(this.writeTask);

  /// The CORE task whose implementation the writes wait for.
  final String writeTask;

  @override
  Future<String?> sourceRevOf(SearchSource source, String ownerKey) async =>
      null;

  @override
  Future<Map<String, String>> sourceRevs(SearchSource source) async => const {};

  @override
  Future<void> replaceUnits(
    SearchSource source,
    String ownerKey,
    List<SearchUnitDraft> units, {
    required String sourceRev,
  }) async => notYet(writeTask, 'SearchIndexWriter.replaceUnits');

  @override
  Future<void> removeOwner(SearchSource source, String ownerKey) async =>
      notYet(writeTask, 'SearchIndexWriter.removeOwner');

  @override
  Future<List<PageSearchHit>> searchPages(
    String query, {
    int limit = 100,
    NoteId? withinNote,
  }) async => const [];

  @override
  Stream<SearchIndexStatus> get status =>
      _holdOne<SearchIndexStatus>(const SearchIndexStatus());

  @override
  Future<void> rebuild({Set<SearchSource>? sources}) async =>
      notYet(writeTask, 'SearchIndex.rebuild');
}
