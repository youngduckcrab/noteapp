import 'dart:async';

import 'package:feature_editor/feature_editor.dart';
import 'package:feature_library/feature_library.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../settings/settings_placeholder_screen.dart';
import 'app_routes.dart';

/// The minimal router of foundation step B8 (contract 7.6 B8): `/`,
/// `/folders/:folderId`, `/notes/:noteId` and `/settings`, wired to the B6
/// LibraryScreen, the B5 EditorScreen and the shell settings placeholder.
///
/// Page types and navigation already follow docs/plans/01-infra.md 6.6:
/// - `/` and `/folders/:folderId` share one NoTransitionPage key
///   ([AppRoutes.libraryPageKey]), so a folder change updates the library
///   route instead of recreating it;
/// - `/notes/:noteId` is a NoTransitionPage (no edge-swipe back gesture);
/// - `/settings` is the default (material_ui) page.
///
/// I6 replaces this with createAppRouter(screens: AppScreenBuilders …),
/// AppNavigator and NotFoundScreen (4.5.5). Unknown paths use go_router's
/// default error page until then.
GoRouter createFoundationRouter({String initialLocation = AppRoutes.library}) {
  late final GoRouter router;
  final nav = _FoundationNavigator(() => router);

  Page<void> libraryPage(String? folderId) => NoTransitionPage<void>(
    key: AppRoutes.libraryPageKey,
    child: LibraryScreen(
      folderId: folderId,
      onOpenFolder: nav.openLibrary,
      onOpenNote: nav.openNote,
      onOpenSettings: nav.openSettings,
    ),
  );

  router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: AppRoutes.library,
        name: 'library',
        pageBuilder: (context, state) => libraryPage(null),
      ),
      GoRoute(
        path: AppRoutes.folderPattern,
        name: 'folder',
        pageBuilder: (context, state) =>
            libraryPage(state.pathParameters[AppRoutes.folderIdParam]),
      ),
      GoRoute(
        path: AppRoutes.notePattern,
        name: 'note',
        pageBuilder: (context, state) {
          final noteId = state.pathParameters[AppRoutes.noteIdParam]!;
          return NoTransitionPage<void>(
            key: state.pageKey,
            child: EditorScreen(
              key: ValueKey<String>(noteId),
              noteId: noteId,
              initialPageId: state.uri.queryParameters[AppRoutes.pageQueryKey],
              onClose: nav.closeTop,
              onOpenSettings: nav.openSettings,
            ),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.settings,
        name: 'settings',
        builder: (context, state) =>
            SettingsPlaceholderScreen(onClose: nav.closeTop),
      ),
    ],
  );
  return router;
}

/// Navigation semantics of 6.6 (`GoRouterAppNavigator` from I6 on).
final class _FoundationNavigator {
  _FoundationNavigator(this._router);

  final GoRouter Function() _router;

  /// Folder changes do not stack routes (same page key → same screen State).
  void openLibrary(String? folderId) => _router().go(
    folderId == null ? AppRoutes.library : AppRoutes.folder(folderId),
  );

  /// Pushed, so closing the note returns to the same folder.
  void openNote(String noteId) =>
      unawaited(_router().push<void>(AppRoutes.note(noteId)));

  void openSettings() => unawaited(_router().push<void>(AppRoutes.settings));

  /// closeNote / closeSettings: back to the previous route, or home when the
  /// app was started on this route (reload / deep link).
  void closeTop() {
    final router = _router();
    if (router.canPop()) {
      router.pop();
    } else {
      router.go(AppRoutes.library);
    }
  }
}
