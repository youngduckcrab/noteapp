// lib/src/ui/library_scope.dart — what every part of LibraryScreen needs from
// the screen itself: the route folder, the size class and the navigation
// callbacks (6.4). Internal (not exported).
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' show FolderId, NoteId;

import 'layout/size_class.dart';

class LibraryScope extends InheritedWidget {
  const LibraryScope({
    super.key,
    required this.routeFolderId,
    required this.sizeClass,
    required this.openFolder,
    required this.openNote,
    required this.openSettings,
    required this.openDrawer,
    required this.closeDrawer,
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

  /// Closes the drawer first, then LibraryScreen.onOpenSettings.
  final VoidCallback openSettings;

  /// Opens the sidebar drawer (medium / compact).
  final VoidCallback openDrawer;

  /// Closes the drawer if it is open (sidebar 최근 / 즐겨찾기 / 휴지통).
  final VoidCallback closeDrawer;

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
      openSettings != oldWidget.openSettings ||
      openDrawer != oldWidget.openDrawer ||
      closeDrawer != oldWidget.closeDrawer;
}
