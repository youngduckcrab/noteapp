// lib/src/library_screen.dart — contract 00-overview 7.2.18, 05-library 4.2 /
// 6.1; (2차) contract m5-7/00-overview 7.2.11, m5-7/05-library 4.1
// (LibraryOpenNoteAt, onOpenNoteAt). The screen root: one Scaffold (S-2)
// with the sidebar pinned in the expanded size class or in the drawer
// otherwise, and the content pane of the current section (6.4).
// LibraryDragScope above the Scaffold serves every drag of the screen (drawer
// included): edge auto scrolling and, without a pinned sidebar, the drawer
// opening at the left edge (6.10.4).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart'
    show FolderId, FolderTree, NoteId, PageId, folderTreeProvider;

import 'dnd/library_drag_scope.dart';
import 'model/section.dart';
import 'state/providers.dart';
import 'ui/content/content_pane.dart';
import 'ui/layout/library_layout.dart';
import 'ui/layout/library_metrics.dart';
import 'ui/layout/size_class.dart';
import 'ui/library_scope.dart';
import 'ui/sidebar/library_sidebar.dart';
import 'ui/top_bar/library_search_field.dart' show LibrarySearchHandle;

/// (v2.0, 2차 contract 7.2.11) Opens a note at a page; [focusRectPt] is the
/// area to bring into view in page pt (null = the page only).
typedef LibraryOpenNoteAt = void Function(
  String noteId,
  String pageId,
  Rect? focusRectPt,
);

/// The library (home) screen. The app shell routes `/` (folderId null) and
/// `/folders/:folderId` to it; the screen knows no router and only calls the
/// callbacks below. The only provider the app shell must override is CORE's
/// noteStoreProvider (contract 7.3.3).
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({
    super.key,
    this.folderId,
    required this.onOpenFolder,
    required this.onOpenNote,
    required this.onOpenSettings,
    this.onOpenNoteAt,
  });

  /// The folder shown in the content area; null is the top level ('홈').
  final String? folderId; // null = 홈; unknown id → 'folder missing' view

  /// Navigates to a folder (null = home).
  final ValueChanged<String?> onOpenFolder; // null = 홈

  /// Opens a note in the editor. The library never calls markOpened: CORE's
  /// openSession records '최근' (contract 7.2.8 N-6).
  // also right after creating / importing a note
  final ValueChanged<String> onOpenNote;

  /// Opens the settings screen (sidebar settings button, sync status).
  final VoidCallback onOpenSettings;

  /// Content search hit → page + rect (page pt). null → onOpenNote(noteId)
  /// (page ignored).
  // (v2.0) 2차 foundation step R2-B6: stored only; the '노트 내용' search
  // results (L2-02, L2-03) call it.
  final LibraryOpenNoteAt? onOpenNoteAt;

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  /// Waits for the first folder tree when the reveal ran before it loaded.
  ProviderSubscription<AsyncValue<FolderTree>>? _revealWait;

  /// (v2.13-nav) The compact search bar is open (LibraryScope).
  final ValueNotifier<bool> _compactSearchOpen = ValueNotifier<bool>(false);

  /// (v2.13-nav) The top bar's search field: in use or not, and its close.
  final LibrarySearchHandle _searchHandle = LibrarySearchHandle();

  /// (v2.13-nav) The drawer is open (Scaffold.onDrawerChanged): back closes
  /// it, also at 홈 (canPop false, so Android 16's predictive back asks).
  bool _drawerOpen = false;

  /// (v2.13-nav) A back that waits for the first folder tree (its parent).
  bool _backWaitsForTree = false;

  @override
  void initState() {
    super.initState();
    _scheduleReveal();
  }

  @override
  void didUpdateWidget(LibraryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.folderId != widget.folderId) {
      _compactSearchOpen.value = false;
      _scheduleReveal();
    }
  }

  @override
  void dispose() {
    _revealWait?.close();
    _compactSearchOpen.dispose();
    _searchHandle.dispose();
    super.dispose();
  }

  /// 6.4 현재 폴더 드러내기: after the frame (never while building), expands
  /// the ancestors of the route folder in the sidebar tree. When the tree is
  /// still loading, once on its first value.
  void _scheduleReveal() {
    _revealWait?.close();
    _revealWait = null;
    final id = widget.folderId;
    if (id == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.folderId != id) return;
      final tree = ref.read(folderTreeProvider).value;
      if (tree != null) {
        _reveal(tree, id);
        return;
      }
      _revealWait = ref.listenManual(folderTreeProvider, (_, next) {
        final loaded = next.value;
        if (loaded == null) return;
        _revealWait?.close();
        _revealWait = null;
        if (mounted && widget.folderId == id) _reveal(loaded, id);
      });
    });
  }

  void _reveal(FolderTree tree, FolderId id) {
    final path = tree.pathTo(id);
    if (path.length < 2) return; // top level, or not in the tree
    ref.read(folderExpansionProvider.notifier).expandAll([
      for (var i = 0; i < path.length - 1; i++) path[i].id,
    ]);
  }

  /// Every move to another place (a folder, a section, a note, settings)
  /// closes the drawer and lets go of the keyboard focus (m5-7/05-library 16).
  void _closeDrawer() {
    _releaseFocus();
    final scaffold = _scaffoldKey.currentState;
    if (scaffold != null && scaffold.isDrawerOpen) scaffold.closeDrawer();
  }

  /// (v2.13-nav, m5-7/05-library 16) Unfocuses the primary focus when it is
  /// inside this screen (the search field, the drawer's focus scope).
  /// [FocusNode.unfocus] with [UnfocusDisposition.scope] also clears the route
  /// scope's focus history, so nothing hands the focus back to the search field
  /// later — the drawer closing, the editor or settings route popping — which
  /// would bring the soft keyboard up without a tap. On Android the system back
  /// that hides the keyboard leaves the field focused, which is how the field
  /// still held the focus when the user moved on.
  void _releaseFocus() {
    final focused = FocusManager.instance.primaryFocus;
    final focusedContext = focused?.context;
    if (focused == null || focusedContext == null) return;
    if (focusedContext.findAncestorStateOfType<_LibraryScreenState>() != this) {
      return;
    }
    focused.unfocus();
  }

  // The three below may run after an await in a part that is gone by then;
  // they do nothing once the screen itself is gone (6.19).

  /// 6.4: the route folder → back to its own section (from 최근 etc.);
  /// another folder → the router.
  void _openFolder(FolderId? id) {
    if (!mounted) return;
    _closeDrawer();
    if (id == widget.folderId) {
      ref
          .read(librarySectionProvider(widget.folderId).notifier)
          .showRouteFolder();
    } else {
      widget.onOpenFolder(id);
    }
  }

  void _openNote(NoteId id) {
    if (!mounted) return;
    _closeDrawer();
    widget.onOpenNote(id);
  }

  /// (v2, 6.1.4) A content hit: page + rect; the note alone without
  /// onOpenNoteAt (page ignored). LIBRARY never calls markOpened (S-5).
  void _openNoteAt(NoteId noteId, PageId pageId, Rect? focusRectPt) {
    if (!mounted) return;
    _closeDrawer();
    final openAt = widget.onOpenNoteAt;
    if (openAt != null) {
      openAt(noteId, pageId, focusRectPt);
    } else {
      widget.onOpenNote(noteId);
    }
  }

  void _openSettings() {
    if (!mounted) return;
    _closeDrawer();
    widget.onOpenSettings();
  }

  /// ☰, and a drag held at the left edge (6.10.4; the drawer stays open
  /// after the drop).
  void _openDrawer() {
    final scaffold = _scaffoldKey.currentState;
    if (scaffold != null && !scaffold.isDrawerOpen) scaffold.openDrawer();
  }

  /// (v2.13-nav, m5-7/05-library 16) System back exits the app only from 홈
  /// itself: the home route showing its folder, no selection, no search.
  /// The search counts as open while the compact bar is open or the field is
  /// in use (focused, or typed in before the 300 ms debounce applied it).
  bool _backExits(LibrarySection section, bool selecting, bool searchOpen) =>
      widget.folderId == null &&
      section == const FolderSection(null) &&
      !selecting &&
      !searchOpen &&
      !_drawerOpen;

  /// (v2.13-nav, m5-7/05-library 16) System back (Android button or gesture)
  /// when it does not exit, one step at a time: the drawer closes → selection
  /// mode ends → the search closes (back to where it started) → 최근 / 즐겨찾기 / 휴지통
  /// → 홈 → a folder → its parent folder (a top-level folder → 홈; a folder not
  /// in the tree → 홈).
  void _back() {
    if (!mounted) return;
    final scaffold = _scaffoldKey.currentState;
    if (scaffold != null && scaffold.isDrawerOpen) {
      scaffold.closeDrawer();
      return;
    }
    if (_drawerOpen) setState(() => _drawerOpen = false);
    final route = widget.folderId;
    final selection = ref.read(librarySelectionProvider(route).notifier);
    if (ref.read(librarySelectionProvider(route)).active) {
      selection.end();
      return;
    }
    final sectionNotifier = ref.read(librarySectionProvider(route).notifier);
    final section = ref.read(librarySectionProvider(route));
    if (section is SearchSection ||
        _compactSearchOpen.value ||
        _searchHandle.engaged.value) {
      _searchHandle.close();
      _releaseFocus();
      _compactSearchOpen.value = false;
      sectionNotifier.exitSearch();
      return;
    }
    switch (section) {
      case FolderSection(folderId: final id?):
        final tree = ref.read(folderTreeProvider);
        if (tree.hasValue) {
          _openFolder(_parentOf(tree.requireValue, id));
        } else if (tree.isLoading) {
          _backToParentOnceLoaded(id);
        } else {
          _openFolder(null); // the tree failed to load
        }
      case FolderSection():
        if (route != null) _openFolder(null);
      case RecentSection() || FavoritesSection() || TrashSection():
        _openFolder(null);
      case SearchSection():
        break; // handled above
    }
  }

  /// The parent folder of [id]; null (홈) for a top-level folder or one not
  /// in the tree.
  static FolderId? _parentOf(FolderTree tree, FolderId id) {
    final path = tree.pathTo(id);
    return path.length >= 2 ? path[path.length - 2].id : null;
  }

  /// Back before the first folder tree arrived (cold start or a deep link
  /// into a nested folder): go to the parent once it is known, unless the
  /// user moved on meanwhile. Further backs while waiting do nothing.
  Future<void> _backToParentOnceLoaded(FolderId id) async {
    if (_backWaitsForTree) return;
    _backWaitsForTree = true;
    FolderTree? tree;
    try {
      tree = await ref.read(folderTreeProvider.future);
    } on Object {
      tree = null; // the tree failed to load → 홈
    } finally {
      _backWaitsForTree = false;
    }
    if (!mounted) return;
    final section = ref.read(librarySectionProvider(widget.folderId));
    if (section != FolderSection(id)) return;
    _openFolder(tree == null ? null : _parentOf(tree, id));
  }

  @override
  Widget build(BuildContext context) {
    // Leaving the search for another place (not the field going back to
    // where the search started) closes the compact search bar — here, not in
    // the top bar, so it also holds in selection mode (the selection bar
    // replaces the top bar).
    ref.listen(librarySectionProvider(widget.folderId), (previous, next) {
      if (next is SearchSection || !_compactSearchOpen.value) return;
      if (previous is SearchSection && previous.returnTo == next) return;
      _compactSearchOpen.value = false;
    });
    final sizeClass = librarySizeClassFor(MediaQuery.sizeOf(context).width);
    final section = ref.watch(librarySectionProvider(widget.folderId));
    final sidebarVisible = ref.watch(
      libraryPrefsProvider.select((p) => p.sidebarVisible),
    );
    final selecting = ref.watch(
      librarySelectionProvider(widget.folderId).select((s) => s.active),
    );
    final expanded = sizeClass == LibrarySizeClass.expanded;
    // The expanded class has no drawer (one open when the window grew is
    // gone without a closing report).
    if (expanded) _drawerOpen = false;
    final screen = LibraryScope(
      routeFolderId: widget.folderId,
      sizeClass: sizeClass,
      openFolder: _openFolder,
      openNote: _openNote,
      openNoteAt: _openNoteAt,
      openSettings: _openSettings,
      openDrawer: _openDrawer,
      closeDrawer: _closeDrawer,
      compactSearchOpen: _compactSearchOpen,
      searchHandle: _searchHandle,
      screenContext: context,
      child: LibraryDragScope(
        onDrawerEdgeHold: expanded ? null : _openDrawer,
        child: Scaffold(
          key: _scaffoldKey,
          // (m5-7/05-library 16) A drawer opening (☰, edge swipe, a drag at the
          // edge) takes the focus and its closing hands it back to the route's
          // last focused node — the search field. Let go of it both times (an
          // edge swipe reports 'open' before the drawer's focus request is
          // applied, so the close matters too).
          onDrawerChanged: (open) {
            _releaseFocus();
            if (open != _drawerOpen) setState(() => _drawerOpen = open);
          },
          drawer: expanded
              ? null
              : const Drawer(
                  width: LibraryMetrics.drawerWidth,
                  child: LibrarySidebar(inDrawer: true),
                ),
          body: SafeArea(
            child: LibraryLayout(
              sizeClass: sizeClass,
              sidebarVisible: sidebarVisible,
              sidebar: const LibrarySidebar(),
              content: ContentPane(section: section),
            ),
          ),
        ),
      ),
    );
    // (v2.13-nav, m5-7/05-library 16) PopScope(canPop: false) also tells
    // Android 14+ (predictive back) that the app handles back itself.
    return ListenableBuilder(
      listenable: Listenable.merge([_compactSearchOpen, _searchHandle.engaged]),
      builder: (context, child) => PopScope<Object?>(
        canPop: _backExits(
          section,
          selecting,
          _compactSearchOpen.value || _searchHandle.engaged.value,
        ),
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _back();
        },
        child: child!,
      ),
      child: screen,
    );
  }
}
