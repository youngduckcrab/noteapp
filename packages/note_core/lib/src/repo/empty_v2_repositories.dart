// Internal: the 2nd-round repositories of a store before their CORE task (02-core 8.1
// 'B2 상태'). Reads answer as for an empty store (no drafts, no handwriting results, no
// search index) and every write throws UnimplementedError('CORE <task>: …').
// The real store (DriftNoteStore) passes T31 / T32 / T33a (recordings: the real repository
// since CORE T30 — storage/drift_recording_repository.dart). (The fake store used them
// until CORE T23b — it now has fake/fake_v2_repositories.dart and fake/memory_search_index.dart.)
import 'dart:typed_data';

import '../common/ids.dart';
import '../common/pending.dart';
import '../model/handwriting.dart';
import '../search/search_types.dart';
import 'handwriting_repository.dart';
import 'recording_repository.dart';

/// A watch stream with one value that stays open, like the store's watch streams (1차 rule:
/// the current value right after listen, then every change — there is none here).
Stream<T> _holdOne<T>(T value) => Stream<T>.multi((c) => c.add(value));

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
