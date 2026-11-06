// Internal: the 2nd-round repositories of a store before their CORE task (02-core 8.1
// 'B2 상태'). Reads answer as for an empty store (no search index) and every write throws
// UnimplementedError('CORE <task>: …').
// The real store (DriftNoteStore) passes T33a (recordings: the real repository since
// CORE T30 — storage/drift_recording_repository.dart; recording drafts since CORE T31 —
// storage/drift_recording_draft_store.dart; handwriting results since CORE T32 —
// storage/drift_handwriting_repository.dart). (The fake store used them until CORE T23b — it
// now has fake/fake_v2_repositories.dart and fake/memory_search_index.dart.)

import '../common/ids.dart';
import '../common/pending.dart';
import '../search/search_types.dart';

/// A watch stream with one value that stays open, like the store's watch streams (1차 rule:
/// the current value right after listen, then every change — there is none here).
Stream<T> _holdOne<T>(T value) => Stream<T>.multi((c) => c.add(value));

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
