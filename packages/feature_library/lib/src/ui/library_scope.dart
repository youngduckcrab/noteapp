// lib/src/ui/library_scope.dart — what every part of LibraryScreen needs from
// the screen itself: the route folder, the size class and the navigation
// callbacks (6.4). Internal (not exported).
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' show FolderId, NoteId, PageId;

import 'layout/size_class.dart';
import 'top_bar/library_search_field.dart' show LibrarySearchHandle;

class LibraryScope extends InheritedWidget {
  const LibraryScope({
    super.key,
    required this.routeFolderId,
    required this.sizeClass,
    required this.openFolder,
    required this.openNote,
    required this.openNoteAt,
    required this.openSettings,
    required this.openDrawer,
    required this.closeDrawer,
    required this.compactSearchOpen,
    required this.searchHandle,
    required this.screenContext,
    required super.child,
  });

  /// LibraryScreen.folderId (family argument of the section / selection
  /// providers).
  final FolderId? routeFolderId;
  final LibrarySizeClass sizeClass;

  /// 6.4: closes the drawer first; the route folder → showRouteFolder(),
  /// any other → LibraryScreen.onOpenFolder.
  final ValueChanged<FolderId?> openFolder;

  /// Closes the drawer first, then LibraryScreen.onOpenNote.
  final ValueChanged<NoteId> openNote;

  /// (v2, 6.1.4) Closes the drawer first, then LibraryScreen.onOpenNoteAt
  /// (page + rect, note page pt), or onOpenNote(noteId) when it is null.
  final void Function(NoteId noteId, PageId pageId, Rect? focusRectPt)
  openNoteAt;

  /// Closes the drawer first, then LibraryScreen.onOpenSettings.
  final VoidCallback openSettings;

  /// Opens the sidebar drawer (medium / compact).
  final VoidCallback openDrawer;

  /// Closes the drawer if it is open (sidebar 최근 / 즐겨찾기 / 휴지통).
  final VoidCallback closeDrawer;

  /// (v2.13-nav) The compact class's search bar is open (the search icon
  /// was pressed). Owned by the screen: system back closes the bar first,
  /// and a route change closes it.
  final ValueNotifier<bool> compactSearchOpen;

  /// (v2.13-nav) The top bar's search field reports here whether it is in
  /// use, and system back closes it through it. Owned by the screen.
  final LibrarySearchHandle searchHandle;

  /// The LibraryScreen State's context: the PDF slots get it (4.3 — the
  /// selection bar or a menu may be gone while the PDF flow runs).
  final BuildContext screenContext;

  static LibraryScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<LibraryScope>();
    assert(scope != null, 'No LibraryScope above this widget');
    return scope!;
  }

  /// Without a dependency (event handlers).
  static LibraryScope read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<LibraryScope>();
    assert(scope != null, 'No LibraryScope above this widget');
    return scope!;
  }

  @override
  bool updateShouldNotify(LibraryScope oldWidget) =>
      routeFolderId != oldWidget.routeFolderId ||
      sizeClass != oldWidget.sizeClass ||
      openFolder != oldWidget.openFolder ||
      openNote != oldWidget.openNote ||
      openNoteAt != oldWidget.openNoteAt ||
      openSettings != oldWidget.openSettings ||
      openDrawer != oldWidget.openDrawer ||
      closeDrawer != oldWidget.closeDrawer ||
      compactSearchOpen != oldWidget.compactSearchOpen ||
      searchHandle != oldWidget.searchHandle ||
      screenContext != oldWidget.screenContext;
}
