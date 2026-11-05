import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'app_navigator.dart';
import 'app_routes.dart';
import 'not_found_screen.dart';
import 'screen_builders.dart';

const String _folderIdParam = 'folderId';
const String _noteIdParam = 'noteId';

/// Page types (6.6): `/` and `/folders/:folderId` →
/// NoTransitionPage(key: AppRoutes.libraryPageKey); `/notes/:noteId` →
/// NoTransitionPage(key: state.pageKey); `/settings` → default page
/// (material_ui MaterialPage); unknown → NotFoundScreen.
///
/// - Library routes share one page key and page type, so `Page.canUpdate`
///   holds and the Navigator updates the one library route on folder changes:
///   LibraryScreen keeps its State (scroll, selection, sidebar).
/// - The editor has no transition and so no edge-swipe back gesture that
///   would catch pen strokes (INFRA-M7).
/// - No redirects (M4 adds the login redirect); ids are percent-encoded by
///   [AppRoutes] and decoded by go_router.
///
/// The screens get a [GoRouterAppNavigator] over the returned router. The
/// caller owns the router and disposes it.
GoRouter createAppRouter({
  required AppScreenBuilders screens,
  String initialLocation = AppRoutes.library,
  List<NavigatorObserver>? observers,
}) {
  late final GoRouter router;
  late final AppNavigator navigator = GoRouterAppNavigator(router);

  Page<void> libraryPage(BuildContext context, GoRouterState state) =>
      NoTransitionPage<void>(
        key: AppRoutes.libraryPageKey,
        name: state.name,
        child: screens.library(
          context,
          LibraryRouteArgs(folderId: state.pathParameters[_folderIdParam]),
          navigator,
        ),
      );

  router = GoRouter(
    initialLocation: initialLocation,
    observers: observers,
    debugLogDiagnostics: kDebugMode,
    errorPageBuilder: (context, state) => NoTransitionPage<void>(
      key: state.pageKey,
      child: NotFoundScreen(
        location: state.uri.toString(),
        onGoHome: () => router.go(AppRoutes.library),
      ),
    ),
    routes: [
      GoRoute(
        path: AppRoutes.library,
        name: 'library',
        pageBuilder: libraryPage,
      ),
      GoRoute(
        path: AppRoutes.folderPattern,
        name: 'folder',
        pageBuilder: libraryPage,
      ),
      GoRoute(
        path: AppRoutes.notePattern,
        name: 'note',
        pageBuilder: (context, state) => NoTransitionPage<void>(
          key: state.pageKey,
          name: state.name,
          child: screens.editor(
            context,
            EditorRouteArgs(
              noteId: state.pathParameters[_noteIdParam]!,
              initialPageId: state.uri.queryParameters[AppRoutes.pageQueryKey],
            ),
            navigator,
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.settings,
        name: 'settings',
        builder: (context, state) => screens.settings(context, navigator),
      ),
    ],
  );
  return router;
}
