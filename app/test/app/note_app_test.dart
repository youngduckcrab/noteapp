// NoteApp and buildAppTheme (docs/plans/01-infra.md 4.5.6, 6.3, 9.1).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderBase;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:noteapp/src/app/note_app.dart';
import 'package:noteapp/src/app/strings.dart';
import 'package:noteapp/src/app/theme.dart';
import 'package:noteapp/src/providers.dart';
import 'package:noteapp/src/routing/app_navigator.dart';
import 'package:noteapp/src/routing/screen_builders.dart';

/// The app's seed color (4.4: Material 3, seed 0xFF3949AB).
const Color _seed = Color(0xFF3949AB);

Future<ProviderContainer> _pump(WidgetTester tester) async {
  tester.view
    ..physicalSize = const Size(2064, 2752)
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appScreenBuildersProvider.overrideWithValue(
          AppScreenBuilders.placeholders(),
        ),
      ],
      child: const NoteApp(),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(NoteApp)));
}

void main() {
  test('buildAppTheme: Material 3 from the seed, light by default', () {
    final light = buildAppTheme();
    expect(light.useMaterial3, isTrue);
    expect(light.colorScheme, ColorScheme.fromSeed(seedColor: _seed));
    expect(light.colorScheme.brightness, Brightness.light);

    final dark = buildAppTheme(brightness: Brightness.dark);
    expect(
      dark.colorScheme,
      ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.dark),
    );
  });

  testWidgets('material_ui MaterialApp.router: title, locale ko, theme, the '
      'router from appRouterProvider', (tester) async {
    final container = await _pump(tester);

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.title, AppStrings.appName);
    expect(AppStrings.appName, '필기노트');
    expect(app.locale, const Locale('ko'));
    expect(app.theme!.colorScheme, ColorScheme.fromSeed(seedColor: _seed));
    final router = container.read(appRouterProvider);
    expect(app.routerConfig, same(router));

    // Screens see the theme (placeholder library at `/`).
    final library = find.textContaining('library #');
    expect(library, findsOneWidget);
    expect(
      Theme.of(tester.element(library)).colorScheme.primary,
      ColorScheme.fromSeed(seedColor: _seed).primary,
    );
    expect(
      Localizations.localeOf(tester.element(library)).languageCode,
      isNotEmpty,
    );

    final navigator = container.read(appNavigatorProvider);
    expect(navigator, isA<GoRouterAppNavigator>());
    expect((navigator as GoRouterAppNavigator).router, same(router));
    navigator.openNote('n1');
    await tester.pumpAndSettle();
    expect(router.state.uri.toString(), '/notes/n1');
    expect(find.text('noteId: n1'), findsOneWidget);
  });

  testWidgets('no MaterialUiCompatibilityBridge in the tree (D2)', (
    tester,
  ) async {
    await _pump(tester);
    expect(
      // ignore: deprecated_member_use — absence check only (INFRA-M3, D2)
      find.byType(MaterialUiCompatibilityBridge),
      findsNothing,
    );
  });

  test('appRouterProvider builds one router per container from the screen '
      'builders and disposes it with the container', () {
    final screens = AppScreenBuilders.placeholders();
    final container = ProviderContainer.test(
      overrides: [appScreenBuildersProvider.overrideWithValue(screens)],
    );
    final router = container.read(appRouterProvider);
    expect(router, isA<GoRouter>());
    expect(container.read(appRouterProvider), same(router));
    expect(router.routeInformationProvider.value.uri.path, '/');
    container.dispose();
    // A disposed GoRouter no longer accepts listeners.
    expect(
      () => router.routerDelegate.addListener(() {}),
      throwsA(isA<AssertionError>()),
    );
  });

  test('shell providers have names (계약 7.4.4)', () {
    final providers = <ProviderBase<Object?>>[
      buildInfoProvider,
      webPlatformProvider,
      runtimeInfoProvider,
      appErrorLogProvider,
      startupReportProvider,
      appBootstrapperProvider,
      appScreenBuildersProvider,
      appRouterProvider,
      appNavigatorProvider,
    ];
    expect(providers.map((p) => p.name), [
      'buildInfoProvider',
      'webPlatformProvider',
      'runtimeInfoProvider',
      'appErrorLogProvider',
      'startupReportProvider',
      'appBootstrapperProvider',
      'appScreenBuildersProvider',
      'appRouterProvider',
      'appNavigatorProvider',
    ]);
  });
}
