// createAppRouter + AppScreenBuilders.placeholders() + GoRouterAppNavigator
// + NotFoundScreen (docs/plans/01-infra.md 4.5.5, 6.6, 9.1).
import 'package:flutter/services.dart' show SystemChannels;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:noteapp/src/app/strings.dart';
import 'package:noteapp/src/routing/app_navigator.dart';
import 'package:noteapp/src/routing/app_router.dart';
import 'package:noteapp/src/routing/app_routes.dart';
import 'package:noteapp/src/routing/not_found_screen.dart';
import 'package:noteapp/src/routing/screen_builders.dart';

/// iPad Pro 13" portrait, logical 1032×1376 at DPR 2 (contract 7.4.8).
void _useIpadPortrait(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(2064, 2752)
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

/// The placeholder screens, wrapped so the test sees what the router hands
/// to each builder.
final class _Shell {
  late final GoRouter router;
  final List<LibraryRouteArgs> libraryArgs = [];
  final List<EditorRouteArgs> editorArgs = [];
  final Set<AppNavigator> navigators = {};
  int settingsBuilds = 0;

  /// The navigator the router gave the screens (one for all of them).
  AppNavigator get navigator => navigators.single;

  String get location => router.state.uri.toString();
}

Future<_Shell> _pump(
  WidgetTester tester, {
  String initialLocation = AppRoutes.library,
  List<NavigatorObserver>? observers,
}) async {
  _useIpadPortrait(tester);
  final shell = _Shell();
  final base = AppScreenBuilders.placeholders();
  shell.router = createAppRouter(
    screens: AppScreenBuilders(
      library: (context, args, navigator) {
        shell.libraryArgs.add(args);
        shell.navigators.add(navigator);
        return base.library(context, args, navigator);
      },
      editor: (context, args, navigator) {
        shell.editorArgs.add(args);
        shell.navigators.add(navigator);
        return base.editor(context, args, navigator);
      },
      settings: (context, navigator) {
        shell.settingsBuilds++;
        shell.navigators.add(navigator);
        return base.settings(context, navigator);
      },
    ),
    initialLocation: initialLocation,
    observers: observers,
  );
  addTearDown(shell.router.dispose);
  await tester.pumpWidget(MaterialApp.router(routerConfig: shell.router));
  await tester.pumpAndSettle();
  return shell;
}

/// The router's Navigator pages, bottom first.
List<Page<Object?>> _pages(WidgetTester tester) => tester
    .widget<Navigator>(find.byType(Navigator, skipOffstage: false).first)
    .pages;

/// The visible library placeholder's title, `library #<initState serial>`.
String _libraryTitle(WidgetTester tester) =>
    tester.widget<Text>(find.textContaining('library #')).data!;

final Finder _anyLibrary = find.textContaining(
  'library #',
  skipOffstage: false,
);

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle();

final class _RecordingObserver extends NavigatorObserver {
  final List<String?> pushed = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route.settings.name);
  }
}

void main() {
  group('route arguments', () {
    testWidgets('/ → LibraryRouteArgs()', (tester) async {
      final shell = await _pump(tester);
      expect(shell.libraryArgs.last, const LibraryRouteArgs());
      expect(find.text('folderId: (root)'), findsOneWidget);
    });

    testWidgets('/folders/f1 → LibraryRouteArgs(folderId: f1)', (tester) async {
      final shell = await _pump(tester, initialLocation: '/folders/f1');
      expect(shell.libraryArgs.last, const LibraryRouteArgs(folderId: 'f1'));
      expect(find.text('folderId: f1'), findsOneWidget);
    });

    testWidgets('/notes/n1?page=p3 → EditorRouteArgs(n1, p3)', (tester) async {
      final shell = await _pump(tester, initialLocation: '/notes/n1?page=p3');
      expect(
        shell.editorArgs.last,
        const EditorRouteArgs(noteId: 'n1', initialPageId: 'p3'),
      );
      expect(find.text('noteId: n1'), findsOneWidget);
      expect(find.text('pageId: p3'), findsOneWidget);
    });

    testWidgets('/notes/n1 without ?page= → initialPageId null', (
      tester,
    ) async {
      final shell = await _pump(tester, initialLocation: '/notes/n1');
      expect(shell.editorArgs.last, const EditorRouteArgs(noteId: 'n1'));
    });

    testWidgets('encoded ids and page ids are decoded', (tester) async {
      final shell = await _pump(
        tester,
        initialLocation: AppRoutes.note('a/b c', pageId: 'p 3&x'),
      );
      expect(
        shell.editorArgs.last,
        const EditorRouteArgs(noteId: 'a/b c', initialPageId: 'p 3&x'),
      );

      shell.navigator.openLibrary(folderId: '폴더/1');
      await _settle(tester);
      expect(shell.location, AppRoutes.folder('폴더/1'));
      expect(shell.libraryArgs.last, const LibraryRouteArgs(folderId: '폴더/1'));
    });

    testWidgets('every screen gets the same GoRouterAppNavigator', (
      tester,
    ) async {
      final shell = await _pump(tester);
      shell.navigator.openNote('n1');
      await _settle(tester);
      shell.navigator.openSettings();
      await _settle(tester);
      expect(shell.navigators, hasLength(1));
      expect(shell.navigator, isA<GoRouterAppNavigator>());
      expect(
        (shell.navigator as GoRouterAppNavigator).router,
        same(shell.router),
      );
    });
  });

  group('page types', () {
    testWidgets('library routes share NoTransitionPage(libraryPageKey); the '
        'note route is a NoTransitionPage; settings is a MaterialPage', (
      tester,
    ) async {
      final shell = await _pump(tester);
      expect(_pages(tester).single, isA<NoTransitionPage<Object?>>());
      expect(_pages(tester).single.key, AppRoutes.libraryPageKey);
      expect(_pages(tester).single.name, 'library');

      shell.navigator.openLibrary(folderId: 'a');
      await _settle(tester);
      expect(_pages(tester).single, isA<NoTransitionPage<Object?>>());
      expect(_pages(tester).single.key, AppRoutes.libraryPageKey);
      expect(_pages(tester).single.name, 'folder');

      shell.navigator.openNote('n1');
      await _settle(tester);
      expect(_pages(tester), hasLength(2));
      final notePage = _pages(tester).last;
      expect(notePage, isA<NoTransitionPage<Object?>>());
      expect(notePage.key, isNot(AppRoutes.libraryPageKey));
      expect(notePage.name, 'note');

      shell.navigator.openSettings();
      await _settle(tester);
      expect(_pages(tester), hasLength(3));
      expect(_pages(tester).last, isA<MaterialPage<Object?>>());
      expect(_pages(tester).last.name, 'settings');
    });

    testWidgets('a deep link to a folder also uses the shared library key', (
      tester,
    ) async {
      await _pump(tester, initialLocation: '/folders/f1');
      expect(_pages(tester).single, isA<NoTransitionPage<Object?>>());
      expect(_pages(tester).single.key, AppRoutes.libraryPageKey);
    });
  });

  group('library State is kept', () {
    testWidgets('/ → /folders/a → /folders/b → / → push /notes/n1 → pop: one '
        'initState', (tester) async {
      final shell = await _pump(tester);
      // `library #<n>`: n is the placeholder State's initState serial, so an
      // unchanged title means no new initState.
      final title = _libraryTitle(tester);
      final scaffold = tester.state(find.byType(Scaffold));

      for (final folderId in <String?>['a', 'b', null]) {
        shell.navigator.openLibrary(folderId: folderId);
        await _settle(tester);
        expect(_pages(tester), hasLength(1));
        expect(shell.libraryArgs.last, LibraryRouteArgs(folderId: folderId));
        expect(find.text('folderId: ${folderId ?? '(root)'}'), findsOneWidget);
        expect(_libraryTitle(tester), title);
      }

      shell.navigator.openNote('n1');
      await _settle(tester);
      expect(find.text('noteId: n1'), findsOneWidget);
      expect(_anyLibrary, findsOneWidget); // offstage below the editor

      shell.navigator.closeNote();
      await _settle(tester);
      expect(shell.location, '/');
      expect(_libraryTitle(tester), title);
      expect(tester.state(find.byType(Scaffold)), same(scaffold));
    });

    testWidgets('a new router builds a new library State', (tester) async {
      await _pump(tester);
      final first = _libraryTitle(tester);
      await tester.pumpWidget(const SizedBox());
      await _pump(tester);
      expect(_libraryTitle(tester), isNot(first));
    });
  });

  group('GoRouterAppNavigator', () {
    testWidgets('openNote pushes; closing returns to the previous folder', (
      tester,
    ) async {
      final shell = await _pump(tester);
      shell.navigator.openLibrary(folderId: 'f1');
      await _settle(tester);
      expect(shell.location, '/folders/f1');

      shell.navigator.openNote('n1', pageId: 'p3');
      await _settle(tester);
      expect(shell.location, '/notes/n1?page=p3');
      expect(
        shell.editorArgs.last,
        const EditorRouteArgs(noteId: 'n1', initialPageId: 'p3'),
      );
      expect(_pages(tester), hasLength(2));

      // Placeholder back button → closeNote.
      await tester.tap(find.byTooltip(AppStrings.back));
      await _settle(tester);
      expect(shell.location, '/folders/f1');
      expect(find.text('folderId: f1'), findsOneWidget);
      expect(_pages(tester), hasLength(1));
    });

    testWidgets('the reported browser address follows push and pop (6.6 — '
        'GoRouter.optionURLReflectsImperativeAPIs)', (tester) async {
      final reported = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.navigation,
        (call) async {
          if (call.method == 'routeInformationUpdated') {
            reported.add((call.arguments as Map)['uri'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.navigation,
          null,
        ),
      );
      final shell = await _pump(tester);
      shell.navigator.openLibrary(folderId: 'f1');
      await _settle(tester);
      expect(reported.last, '/folders/f1');

      shell.navigator.openNote('n1', pageId: 'p3');
      await _settle(tester);
      expect(reported.last, '/notes/n1?page=p3');

      shell.navigator.openSettings();
      await _settle(tester);
      expect(reported.last, AppRoutes.settings);

      shell.navigator.closeSettings();
      await _settle(tester);
      expect(reported.last, '/notes/n1?page=p3');

      shell.navigator.closeNote();
      await _settle(tester);
      expect(reported.last, '/folders/f1');
    });

    testWidgets('folder changes do not stack routes', (tester) async {
      final shell = await _pump(tester);
      shell.navigator.openLibrary(folderId: 'a');
      await _settle(tester);
      shell.navigator.openLibrary(folderId: 'b');
      await _settle(tester);
      expect(_pages(tester), hasLength(1));
      expect(shell.router.canPop(), isFalse);
    });

    testWidgets('reload on a note (initial /notes/n1): closeNote goes home', (
      tester,
    ) async {
      final shell = await _pump(tester, initialLocation: '/notes/n1');
      expect(find.text('noteId: n1'), findsOneWidget);
      expect(_anyLibrary, findsNothing);
      expect(shell.router.canPop(), isFalse);

      shell.navigator.closeNote();
      await _settle(tester);
      expect(shell.location, '/');
      expect(find.text('folderId: (root)'), findsOneWidget);
      expect(find.text('noteId: n1', skipOffstage: false), findsNothing);
    });

    testWidgets('settings opens over the library and the editor and closes '
        'back to them', (tester) async {
      final shell = await _pump(tester);

      // Placeholder settings button → openSettings.
      await tester.tap(find.byTooltip(AppStrings.settings));
      await _settle(tester);
      expect(shell.location, AppRoutes.settings);
      expect(find.text('settings'), findsOneWidget);

      shell.navigator.closeSettings();
      await _settle(tester);
      expect(shell.location, '/');

      shell.navigator.openNote('n1');
      await _settle(tester);
      await tester.tap(find.byTooltip(AppStrings.settings));
      await _settle(tester);
      expect(shell.location, AppRoutes.settings);
      expect(_pages(tester), hasLength(3));

      await tester.tap(find.byTooltip(AppStrings.back));
      await _settle(tester);
      expect(shell.location, '/notes/n1');
      expect(find.text('noteId: n1'), findsOneWidget);
    });

    testWidgets('reload on settings (initial /settings): closeSettings goes '
        'home', (tester) async {
      final shell = await _pump(tester, initialLocation: AppRoutes.settings);
      expect(shell.settingsBuilds, greaterThan(0));
      expect(shell.router.canPop(), isFalse);

      shell.navigator.closeSettings();
      await _settle(tester);
      expect(shell.location, '/');
      expect(find.text('folderId: (root)'), findsOneWidget);
    });

    testWidgets('openLibrary() with no folder goes to /', (tester) async {
      final shell = await _pump(tester, initialLocation: '/folders/f1');
      shell.navigator.openLibrary();
      await _settle(tester);
      expect(shell.location, '/');
      expect(shell.libraryArgs.last, const LibraryRouteArgs());
    });
  });

  group('unknown locations', () {
    for (final location in ['/nope', '/folders', '/notes', '/login']) {
      testWidgets('$location → NotFoundScreen → home', (tester) async {
        final shell = await _pump(tester, initialLocation: location);
        expect(find.byType(NotFoundScreen), findsOneWidget);
        expect(find.text(AppStrings.notFoundTitle), findsOneWidget);
        expect(
          tester.widget<NotFoundScreen>(find.byType(NotFoundScreen)).location,
          location,
        );
        expect(find.text(location), findsOneWidget);
        expect(_pages(tester).single, isA<NoTransitionPage<Object?>>());

        await tester.tap(find.text(AppStrings.goHome));
        await _settle(tester);
        expect(shell.location, '/');
        expect(find.byType(NotFoundScreen), findsNothing);
        expect(find.text('folderId: (root)'), findsOneWidget);
      });
    }

    testWidgets('going to an unknown location later also shows it', (
      tester,
    ) async {
      final shell = await _pump(tester);
      shell.router.go('/folders/f1/extra');
      await _settle(tester);
      expect(find.byType(NotFoundScreen), findsOneWidget);
      expect(find.text('/folders/f1/extra'), findsOneWidget);
    });
  });

  testWidgets('observers see the pushed routes', (tester) async {
    final observer = _RecordingObserver();
    final shell = await _pump(tester, observers: [observer]);
    expect(observer.pushed, ['library']);

    shell.navigator.openNote('n1');
    await _settle(tester);
    shell.navigator.openSettings();
    await _settle(tester);
    expect(observer.pushed, ['library', 'note', 'settings']);
  });
}
