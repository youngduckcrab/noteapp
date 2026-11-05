// lib/src/library_screen.dart — contract 00-overview 7.2.18, 05-library 4.2 /
// 6.1. The screen root: one Scaffold (S-2) with the sidebar pinned in the
// expanded size class or in the drawer otherwise, and the content pane of the
// current section (6.4). LibraryDragScope above the Scaffold serves every
// drag of the screen (drawer included): edge auto scrolling and, without a
// pinned sidebar, the drawer opening at the left edge (6.10.4).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart'
    show FolderId, FolderTree, NoteId, folderTreeProvider;

import 'dnd/library_drag_scope.dart';
import 'state/providers.dart';
import 'ui/content/content_pane.dart';
import 'ui/layout/library_layout.dart';
import 'ui/layout/library_metrics.dart';
import 'ui/layout/size_class.dart';
import 'ui/library_scope.dart';
import 'ui/sidebar/library_sidebar.dart';

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

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  /// Waits for the first folder tree when the reveal ran before it loaded.
  ProviderSubscription<AsyncValue<FolderTree>>? _revealWait;

  @override
  void initState() {
    super.initState();
    _scheduleReveal();
  }

  @override
  void didUpdateWidget(LibraryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.folderId != widget.folderId) _scheduleReveal();
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

  void _closeDrawer() {
    final scaffold = _scaffoldKey.currentState;
    if (scaffold != null && scaffold.isDrawerOpen) scaffold.closeDrawer();
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

  @override
  Widget build(BuildContext context) {
    final sizeClass = librarySizeClassFor(MediaQuery.sizeOf(context).width);
    final section = ref.watch(librarySectionProvider(widget.folderId));
    final sidebarVisible = ref.watch(
      libraryPrefsProvider.select((p) => p.sidebarVisible),
    );
    final expanded = sizeClass == LibrarySizeClass.expanded;
    return LibraryScope(
      routeFolderId: widget.folderId,
      sizeClass: sizeClass,
      openFolder: _openFolder,
      openNote: _openNote,
      openSettings: _openSettings,
      openDrawer: _openDrawer,
      closeDrawer: _closeDrawer,
      screenContext: context,
      child: LibraryDragScope(
        onDrawerEdgeHold: expanded ? null : _openDrawer,
        child: Scaffold(
          key: _scaffoldKey,
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
  }
}
