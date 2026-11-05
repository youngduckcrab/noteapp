// lib/src/repo/content_reader.dart — read-only, outside sessions (PDF export, thumbnails)
// Contract 00-overview 7.2.9 / CORE 4.5.
import '../common/ids.dart';
import '../model/page.dart';
import '../session/page_content.dart';

abstract interface class NoteContentReader {
  Future<List<Page>> pagesOf(NoteId noteId); // active, ordered
  // committed state (call NoteStore.flush() first)
  Future<PageContent> loadPage(PageId pageId);
  // active page or null — cheap staleness check
  Future<Page?> getPage(PageId pageId);
}
