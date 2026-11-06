// lib/src/indexer/catch_up.dart — (internal, v2.1) the indexer's catch-up
// (m5-7/05-library 6.9.5, 12.2 Q8): notesWithStalePages() — ONE query over
// CORE's pages.ink_rev cache, most recently updated note first, trash left
// out (contract 7.2.5 v2.1) — then stalePages(noteId) per note (page order).
// It replaces the draft's note walk (recent notes + a query per folder).
import 'package:note_core/note_core.dart' as core;

/// Feeds [enqueue] note by note (pages in page order), yielding to the event
/// loop after each note; stops as soon as [alive] is false.
Future<void> runCatchUp({
  required core.HandwritingRepository repo,
  required bool Function() alive,
  required void Function(core.NoteId noteId, List<core.PageId> pages) enqueue,
}) async {
  final notes = await repo.notesWithStalePages();
  for (final noteId in notes) {
    if (!alive()) return;
    final pages = await repo.stalePages(noteId);
    if (!alive()) return;
    enqueue(noteId, pages);
    await Future<void>.delayed(Duration.zero);
  }
}
