// lib/src/state/section_notifier.dart — 05-library 6.3.3 / 6.4. One instance
// per route folderId (librarySectionProvider family argument), so a route
// change starts from FolderSection(newId) without touching providers while
// building.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_core/note_core.dart' show FolderId;

import '../integration/ink_search_slot.dart';
import '../model/section.dart';

class LibrarySectionNotifier extends Notifier<LibrarySection> {
  LibrarySectionNotifier(this.routeFolderId);

  final FolderId? routeFolderId;

  /// FolderSection(routeFolderId).
  @override
  LibrarySection build() => FolderSection(routeFolderId);

  void showRouteFolder() => state = FolderSection(routeFolderId);

  void showRecent() => state = const RecentSection();

  void showFavorites() => state = const FavoritesSection();

  void showTrash() => state = const TrashSection();

  /// trimmed empty → exitSearch(); otherwise SearchSection(q, returnTo:
  /// current non-search section). Replaces the query if already searching.
  void search(String query) {
    final q = query.trim();
    if (q.isEmpty) {
      exitSearch();
      return;
    }
    final current = state;
    final returnTo = current is SearchSection ? current.returnTo : current;
    state = SearchSection(q, returnTo: returnTo);
    // (handwriting search, 6.19a) pages waiting for their quiet time are
    // recognized now, so fresh handwriting is found sooner.
    ref.read(libraryInkSearchProvider)?.searchOpened();
  }

  /// Back to returnTo (no-op otherwise).
  void exitSearch() {
    final current = state;
    if (current is SearchSection) state = current.returnTo;
  }
}
