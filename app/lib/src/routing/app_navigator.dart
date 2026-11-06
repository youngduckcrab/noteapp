import 'dart:async';
import 'dart:ui' show Rect;

import 'package:go_router/go_router.dart';

import 'app_routes.dart';

/// Shell-internal navigation API. Feature screens get plain callbacks.
abstract interface class AppNavigator {
  void openLibrary({String? folderId});
  void openNote(String noteId, {String? pageId, Rect? focusRectPt}); // push
  void closeNote();
  void openSettings();
  void closeSettings();
}

/// [AppNavigator] over a [GoRouter] (docs/plans/01-infra.md 6.6):
///
/// | method | action | why |
/// |---|---|---|
/// | openLibrary | `go('/')` / `go('/folders/<id>')` | folder changes do not stack routes (same page key keeps the screen) |
/// | openNote | `push('/notes/<id>[?page=[&focus=]]')` | closing returns to the same folder (or the search view) |
/// | closeNote / closeSettings | `canPop() ? pop() : go('/')` | the app may have started on that route (reload, deep link) |
/// | openSettings | `push('/settings')` | |
final class GoRouterAppNavigator implements AppNavigator {
  GoRouterAppNavigator(this.router);
  final GoRouter router;

  @override
  void openLibrary({String? folderId}) => router.go(
    folderId == null ? AppRoutes.library : AppRoutes.folder(folderId),
  );

  /// A [focusRectPt] without [pageId] is dropped (S2-6).
  @override
  void openNote(String noteId, {String? pageId, Rect? focusRectPt}) =>
      unawaited(
        router.push<void>(
          AppRoutes.note(
            noteId,
            pageId: pageId,
            focus: pageId == null ? null : focusRectPt,
          ),
        ),
      );

  @override
  void closeNote() => _closeTop();

  @override
  void openSettings() => unawaited(router.push<void>(AppRoutes.settings));

  @override
  void closeSettings() => _closeTop();

  void _closeTop() {
    if (router.canPop()) {
      router.pop();
    } else {
      router.go(AppRoutes.library);
    }
  }
}
