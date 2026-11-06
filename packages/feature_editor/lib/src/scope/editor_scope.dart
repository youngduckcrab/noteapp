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
// current page bridge. E-08: read-only state, commands, interaction host and
// input router. E-10: the selection (tools/selection.dart — listed here as a
// dependency). E-13: start position and last position (ViewportMemory); the
// popup lives in state/popup.dart. E-17: the page panel state
// (state/page_panel.dart — listed here as a dependency).
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_core/note_core.dart' as core;

import '../commands/editor_commands.dart';
import '../document/mounted_pages.dart';
import '../input/input_router.dart';
import '../state/page_panel.dart';
import '../state/popup.dart';
import '../state/settings/editor_settings.dart';
import '../state/settings/editor_settings_notifier.dart';
import '../text/text_edit_session.dart';
import '../tools/interaction_host.dart';
import '../tools/selection.dart';
import '../viewport/page_layout.dart';
import '../viewport/viewport_controller.dart';
import '../viewport/viewport_memory.dart';

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

/// Overridden by EditorScreen with EditorScreen.initialFocusRectPt (throws
/// elsewhere). 2nd-round contract 7.2.10, m5-7/04-editor 6.19. Nothing reads
/// it before E2-19 (6.16), which ignores it without a known initialPageId.
final editorInitialFocusRectProvider = Provider<Rect?>(
  (ref) => throw UnimplementedError('Overridden by EditorScreen'),
  dependencies: const [],
  name: 'editorInitialFocusRectProvider',
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
///
/// Start position (6.3.5, 4.2): a known EditorScreen.initialPageId → that page
/// at fit width; else the last viewed position of the note
/// (ViewportMemory.load — a page no longer in the note → page 0), else page 0.
/// Every settle after a camera change (isInteracting → false) saves the
/// position (ViewportMemory debounces 2 s); EditorCommands.flushAll saves and
/// writes it on leaving.
final editorViewportProvider = Provider<ViewportController>(
  (ref) {
    final session = ref.watch(editorSessionValueProvider);
    final noteId = ref.watch(editorNoteIdProvider);
    final initialPageId = ref.watch(editorInitialPageIdProvider);
    final memory = ref.watch(editorViewportMemoryProvider);
    final controller = ViewportController()
      ..setAxis(_axisOf(ref.read(editorSettingsProvider).pageFlipMode))
      ..updatePages(session.pages);
    var disposed = false;
    if (initialPageId != null &&
        session.pages.any((p) => p.id == initialPageId)) {
      controller.restore(null, initialPageId: initialPageId);
    } else {
      memory
          .load(noteId)
          .then(
            (anchor) {
              if (!disposed) controller.restore(anchor);
            },
            onError: (Object error, StackTrace stack) {
              if (!disposed) controller.restore(null);
              FlutterError.reportError(
                FlutterErrorDetails(
                  exception: error,
                  stack: stack,
                  library: 'feature_editor',
                  context: ErrorDescription('while loading the last position'),
                ),
              );
            },
          );
    }
    void settled() {
      if (controller.isInteracting.value) return;
      final anchor = controller.captureAnchor();
      if (anchor != null) memory.save(noteId, anchor);
    }

    controller.isInteracting.addListener(settled);
    final sub = session.pagesStream.listen(
      controller.updatePages,
    ); // sync (N-1)
    ref.listen(
      editorSettingsProvider.select((s) => s.pageFlipMode),
      (_, mode) => controller.setAxis(_axisOf(mode)),
    );
    ref.onDispose(() {
      disposed = true;
      controller.isInteracting.removeListener(settled);
      sub.cancel();
      controller.dispose();
    });
    return controller;
  },
  dependencies: [
    editorSessionValueProvider,
    editorNoteIdProvider,
    editorInitialPageIdProvider,
  ],
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

/// Read-only state of the note (N-4, 6.17.2): session.isReadOnly at open,
/// re-read on every noteStream change (trashed / restored while open).
class ReadOnlyNotifier extends Notifier<bool> {
  @override
  bool build() {
    final session = ref.watch(editorSessionValueProvider);
    final sub = session.noteStream.listen((_) => refresh());
    ref.onDispose(sub.cancel);
    return session.isReadOnly;
  }

  /// Re-reads session.isReadOnly (also after a racing ReadOnlyNoteException).
  void refresh() {
    final value = ref.read(editorSessionValueProvider).isReadOnly;
    if (value != state) state = value;
  }
}

final editorReadOnlyProvider = NotifierProvider<ReadOnlyNotifier, bool>(
  ReadOnlyNotifier.new,
  dependencies: [editorSessionValueProvider],
  name: 'editorReadOnlyProvider',
);

/// Actions shared by toolbar, gestures, shortcuts and menus; the only place
/// that runs CORE commands (6.8, 5.1.3).
final editorCommandsProvider = Provider<EditorCommands>(
  (ref) {
    final commands = EditorCommands(
      ref,
      session: ref.watch(editorSessionValueProvider),
      viewport: ref.watch(editorViewportProvider),
      pages: ref.watch(editorMountedPagesProvider),
    );
    ref.onDispose(commands.dispose);
    return commands;
  },
  dependencies: [
    editorSessionValueProvider,
    editorViewportProvider,
    editorMountedPagesProvider,
    editorReadOnlyProvider,
    editorSelectionProvider,
    editorPopupProvider,
    editorPagePanelProvider,
  ],
  name: 'editorCommandsProvider',
);

/// Router → editor (6.6.2).
final editorInteractionHostProvider = Provider<InteractionHost>(
  (ref) {
    final commands = ref.watch(editorCommandsProvider);
    final host = InteractionHost(
      ref: ref,
      session: ref.watch(editorSessionValueProvider),
      viewport: ref.watch(editorViewportProvider),
      pages: ref.watch(editorMountedPagesProvider),
      commands: commands,
    );
    commands.bindHost(host);
    ref.onDispose(host.dispose);
    return host;
  },
  dependencies: [
    editorSessionValueProvider,
    editorViewportProvider,
    editorMountedPagesProvider,
    editorCommandsProvider,
    editorReadOnlyProvider,
    editorSelectionProvider,
    editorPopupProvider,
    editorTextEditProvider,
  ],
  name: 'editorInteractionHostProvider',
);

/// The input state machine of this note's page viewport (6.5).
final editorInputRouterProvider = Provider<InputRouter>(
  (ref) {
    final router = InputRouter(
      targets: ref.watch(editorInteractionHostProvider),
    );
    ref.watch(editorCommandsProvider).bindRouter(router);
    ref.onDispose(router.cancelAll);
    return router;
  },
  dependencies: [editorInteractionHostProvider, editorCommandsProvider],
  name: 'editorInputRouterProvider',
);
