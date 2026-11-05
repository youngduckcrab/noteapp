// lib/src/scope/editor_scope.dart — 04-editor 6.13.2 (per-note providers).
//
// Every provider here lives in the nested ProviderScope that EditorScreen
// creates per note (key: ValueKey(noteId)). Each one lists the per-note
// provider(s) it watches in `dependencies`, so Riverpod creates it inside
// that scope; a missing entry would create it in the root container and mix
// state between notes (6.13.1 #3). CORE and INK providers stay in the root
// container and are watched from here (V3).
//
// E-04: note id, initial page id, session, mounted pages, viewport and the
// current page bridge. Read-only state, selection, page panel, commands,
// interaction host, input router and popup come with E-08..E-17.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_core/note_core.dart' as core;

import '../document/mounted_pages.dart';
import '../state/settings/editor_settings.dart';
import '../state/settings/editor_settings_notifier.dart';
import '../viewport/page_layout.dart';
import '../viewport/viewport_controller.dart';

/// Overridden by EditorScreen (throws elsewhere).
final editorNoteIdProvider = Provider<String>(
  (ref) => throw UnimplementedError('Overridden by EditorScreen'),
  dependencies: const [],
  name: 'editorNoteIdProvider',
);

/// Overridden by EditorScreen with EditorScreen.initialPageId (throws elsewhere).
final editorInitialPageIdProvider = Provider<String?>(
  (ref) => throw UnimplementedError('Overridden by EditorScreen'),
  dependencies: const [],
  name: 'editorInitialPageIdProvider',
);

/// The note's session, opened and closed by core.noteSessionProvider.
final editorSessionProvider = FutureProvider<core.NoteSession>(
  (ref) => ref.watch(
    core.noteSessionProvider(ref.watch(editorNoteIdProvider)).future,
  ),
  dependencies: [editorNoteIdProvider],
  retry: core.noRetry,
  name: 'editorSessionProvider',
);

/// The open session. Read only under the editor body, which is built once
/// [editorSessionProvider] has a value.
final editorSessionValueProvider = Provider<core.NoteSession>(
  (ref) => ref.watch(editorSessionProvider).requireValue,
  dependencies: [editorSessionProvider],
  name: 'editorSessionValueProvider',
);

/// Registry of the mounted pages (6.4.4).
final editorMountedPagesProvider = Provider<MountedPages>(
  (ref) {
    ref.watch(editorNoteIdProvider);
    final pages = MountedPages();
    ref.onDispose(pages.dispose);
    return pages;
  },
  dependencies: [editorNoteIdProvider],
  name: 'editorMountedPagesProvider',
);

LayoutAxis _axisOf(PageFlipMode mode) => mode == PageFlipMode.horizontalPaged
    ? LayoutAxis.horizontal
    : LayoutAxis.vertical;

/// The camera (6.3.4). Starts from session.pages and follows session.pagesStream
/// directly (synchronous — N-1, so an inserted page can be jumped to right after
/// the command; updatePages ignores lists whose ids and sizes did not change).
/// The page flip mode follows editorSettingsProvider.
final editorViewportProvider = Provider<ViewportController>(
  (ref) {
    final session = ref.watch(editorSessionValueProvider);
    final controller = ViewportController()
      ..setAxis(_axisOf(ref.read(editorSettingsProvider).pageFlipMode))
      ..updatePages(session.pages);
    final sub = session.pagesStream.listen(
      controller.updatePages,
    ); // sync (N-1)
    ref.listen(
      editorSettingsProvider.select((s) => s.pageFlipMode),
      (_, mode) => controller.setAxis(_axisOf(mode)),
    );
    ref.onDispose(() {
      sub.cancel();
      controller.dispose();
    });
    return controller;
  },
  dependencies: [editorSessionValueProvider],
  name: 'editorViewportProvider',
);

/// Mirrors ViewportController.currentPageIndex into provider state (page panel
/// highlight, add-page position). Changes only when the page changes.
class CurrentPageBridge extends Notifier<int> {
  @override
  int build() {
    final viewport = ref.watch(editorViewportProvider);
    final index = viewport.currentPageIndex;
    void changed() => state = index.value;
    index.addListener(changed);
    ref.onDispose(() => index.removeListener(changed));
    return index.value;
  }
}

final editorCurrentPageIndexProvider = NotifierProvider<CurrentPageBridge, int>(
  CurrentPageBridge.new,
  dependencies: [editorViewportProvider],
  name: 'editorCurrentPageIndexProvider',
);
