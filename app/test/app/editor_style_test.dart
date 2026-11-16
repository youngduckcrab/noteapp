// (v2.14-ui split, docs/plans/m5-7/01-infra.md 14.3) 홈 화면 스타일 vs
// 필기 화면 스타일 in the running app: the library (and settings) take the
// home style, the editor route the editor style, in the one brightness; a
// dialog, sheet or menu opened inside the editor keeps the editor style; a
// change of either setting shows at once.
import 'package:feature_editor/feature_editor.dart';
import 'package:feature_library/feature_library.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' show NoteStore, noteStoreProvider;
import 'package:note_core/testing.dart' show createFakeNoteStore;
import 'package:noteapp/src/app/appearance.dart';
import 'package:noteapp/src/app/editor_style_scope.dart';
import 'package:noteapp/src/app/note_app.dart';
import 'package:noteapp/src/bootstrap/startup_report.dart';
import 'package:noteapp/src/errors/app_error_log.dart';
import 'package:noteapp/src/providers.dart';
import 'package:noteapp/src/routing/app_navigator.dart';
import 'package:noteapp/src/routing/app_routes.dart' show EditorRouteArgs;
import 'package:noteapp/src/routing/screen_builders.dart';
import 'package:pdf_io/pdf_io.dart';
import 'package:ui_kit/ui_kit.dart';

void _useIpadPortrait(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(2064, 2752)
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

Future<void> _set(
  WidgetTester tester,
  NoteStore store,
  Map<String, String> values,
) => tester.runAsync(() async {
  for (final MapEntry(:key, :value) in values.entries) {
    final settingKey = switch (key) {
      'home' => AppearanceKeys.homeStyle,
      'editor' => AppearanceKeys.editorStyle,
      'legacy' => AppearanceKeys.legacyStyle,
      _ => AppearanceKeys.brightness,
    };
    await store.settings.set(settingKey, value);
  }
});

/// NoteApp with the production screens over a fake store.
Future<NoteStore> _pumpApp(
  WidgetTester tester, {
  Map<String, String> settings = const {},
  List<Override> extra = const [],
}) async {
  _useIpadPortrait(tester);
  final store = createFakeNoteStore();
  addTearDown(store.close);
  await _set(tester, store, settings);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        noteStoreProvider.overrideWithValue(store),
        appErrorLogProvider.overrideWithValue(AppErrorLog()),
        startupReportProvider.overrideWithValue(
          const StartupReport(steps: [], bootstrapElapsed: Duration.zero),
        ),
        ...pdfIoOverrides(),
        ...featureLibraryOverrides(),
        ...featureEditorOverrides(),
        ...extra,
      ],
      child: const NoteApp(),
    ),
  );
  await tester.pumpAndSettle();
  return store;
}

AppNavigator _navigator(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(NoteApp)))
        .read(appNavigatorProvider);

StyleTokens _tokensAt(WidgetTester tester, Finder finder) =>
    Theme.of(tester.element(finder)).extension<StyleTokens>()!;

const _more = ValueKey('editor.toolbar.more');
const _title = ValueKey('editor.toolbar.title');

void main() {
  for (final dark in [false, true]) {
    final b = dark ? Brightness.dark : Brightness.light;
    testWidgets('library: home style; editor: editor style — '
        '${b.name}', (tester) async {
      final store = await _pumpApp(
        tester,
        settings: {'home': 'craft', 'editor': 'studio', 'brightness': b.name},
      );
      expect(
        _tokensAt(tester, find.byType(LibraryScreen)),
        styleTokensFor(AppStyle.craft, b),
      );

      final note = await tester.runAsync(
        () => store.library.createNote(title: '분리'),
      );
      _navigator(tester).openNote(note!.id);
      await tester.pumpAndSettle();
      expect(find.byType(EditorStyleScope), findsOneWidget);
      expect(
        _tokensAt(tester, find.byType(EditorScreen)),
        styleTokensFor(AppStyle.studio, b),
      );
      // The toolbar paints with the editor style's toolbar colour.
      final toolbar = find.ancestor(
        of: find.byKey(_more),
        matching: find.byType(Material),
      );
      expect(
        tester.widgetList<Material>(toolbar).map((m) => m.color),
        contains(styleTokensFor(AppStyle.studio, b).toolbar),
      );
      // The library below (offstage) keeps the home style.
      expect(
        _tokensAt(tester, find.byType(LibraryScreen, skipOffstage: false)),
        styleTokensFor(AppStyle.craft, b),
      );

      // Settings opened from the editor: the home style.
      _navigator(tester).openSettings();
      await tester.pumpAndSettle();
      expect(
        _tokensAt(tester, find.text('홈 화면 스타일')),
        styleTokensFor(AppStyle.craft, b),
      );
    });
  }

  testWidgets('시스템 따라 + a dark platform: both routes are dark', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final store = await _pumpApp(
      tester,
      settings: {'home': 'calm', 'editor': 'craft'},
    );
    expect(
      _tokensAt(tester, find.byType(LibraryScreen)),
      styleTokensFor(AppStyle.calm, Brightness.dark),
    );
    final note = await tester.runAsync(
      () => store.library.createNote(title: '노트'),
    );
    _navigator(tester).openNote(note!.id);
    await tester.pumpAndSettle();
    expect(
      _tokensAt(tester, find.byType(EditorScreen)),
      styleTokensFor(AppStyle.craft, Brightness.dark),
    );
  });

  testWidgets('the stage-1 style alone themes both routes (migration)', (
    tester,
  ) async {
    final store = await _pumpApp(
      tester,
      settings: {'legacy': 'studio', 'brightness': 'light'},
    );
    expect(
      _tokensAt(tester, find.byType(LibraryScreen)).style,
      AppStyle.studio,
    );
    final note = await tester.runAsync(
      () => store.library.createNote(title: '노트'),
    );
    _navigator(tester).openNote(note!.id);
    await tester.pumpAndSettle();
    expect(_tokensAt(tester, find.byType(EditorScreen)).style, AppStyle.studio);
  });

  testWidgets('the editor menu ⋯ and the note-info dialog opened inside the '
      'editor get the editor style', (tester) async {
    final store = await _pumpApp(
      tester,
      settings: {'home': 'craft', 'editor': 'studio', 'brightness': 'dark'},
    );
    final note = await tester.runAsync(
      () => store.library.createNote(title: '메뉴'),
    );
    _navigator(tester).openNote(note!.id);
    await tester.pumpAndSettle();
    final studio = styleTokensFor(AppStyle.studio, Brightness.dark);

    await tester.tap(find.byKey(_more));
    await tester.pumpAndSettle();
    final item = find.byType(MenuItemButton).first;
    expect(item, findsOneWidget);
    expect(_tokensAt(tester, item), studio);
    await tester.tapAt(const Offset(500, 900));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(_title));
    await tester.pumpAndSettle();
    final dialog = find.byType(Dialog);
    expect(dialog, findsOneWidget);
    expect(_tokensAt(tester, dialog), studio);
    // The dialog's surface is the editor theme's dialog colour.
    expect(
      Theme.of(tester.element(dialog)).colorScheme,
      buildStyleTheme(AppStyle.studio, Brightness.dark).colorScheme,
    );
  });

  testWidgets('a live change of either setting applies at once, the editor '
      'staying open', (tester) async {
    final store = await _pumpApp(
      tester,
      settings: {'home': 'craft', 'editor': 'craft', 'brightness': 'light'},
    );
    final note = await tester.runAsync(
      () => store.library.createNote(title: '노트'),
    );
    _navigator(tester).openNote(note!.id);
    await tester.pumpAndSettle();
    final editorState = tester.state(find.byType(EditorScreen));

    await _set(tester, store, {'editor': 'calm'});
    await tester.pumpAndSettle();
    expect(
      _tokensAt(tester, find.byType(EditorScreen)),
      styleTokensFor(AppStyle.calm, Brightness.light),
    );
    expect(tester.state(find.byType(EditorScreen)), same(editorState));

    await _set(tester, store, {'brightness': 'dark'});
    await tester.pumpAndSettle();
    expect(
      _tokensAt(tester, find.byType(EditorScreen)),
      styleTokensFor(AppStyle.calm, Brightness.dark),
    );

    await _set(tester, store, {'home': 'studio'});
    await tester.pumpAndSettle();
    expect(
      _tokensAt(tester, find.byType(EditorScreen)),
      styleTokensFor(AppStyle.calm, Brightness.dark),
      reason: 'the home style does not touch the editor',
    );
    expect(
      _tokensAt(tester, find.byType(LibraryScreen, skipOffstage: false)),
      styleTokensFor(AppStyle.studio, Brightness.dark),
    );
  });

  group('popups opened inside the editor route carry its theme', () {
    // A stand-in editor with one button per popup kind; the router wraps it
    // in EditorStyleScope like the real one.
    late BuildContext editorContext;
    Widget editor(
      BuildContext context,
      EditorRouteArgs args,
      AppNavigator navigator,
    ) => Scaffold(
      body: Builder(
        builder: (context) {
          editorContext = context;
          return const SizedBox.expand();
        },
      ),
    );

    Future<void> openEditor(WidgetTester tester) async {
      _useIpadPortrait(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appScreenBuildersProvider.overrideWithValue(
              AppScreenBuilders(
                library: AppScreenBuilders.placeholders().library,
                editor: editor,
                settings: AppScreenBuilders.placeholders().settings,
              ),
            ),
            initialAppearanceProvider.overrideWithValue(
              const AppAppearance(
                homeStyle: AppStyle.craft,
                editorStyle: AppStyle.studio,
                brightness: AppBrightnessMode.dark,
              ),
            ),
          ],
          child: const NoteApp(),
        ),
      );
      await tester.pumpAndSettle();
      _navigator(tester).openNote('n1');
      await tester.pumpAndSettle();
    }

    final studio = styleTokensFor(AppStyle.studio, Brightness.dark);
    const probe = Text('probe');

    testWidgets('showDialog', (tester) async {
      await openEditor(tester);
      showDialog<void>(context: editorContext, builder: (_) => probe);
      await tester.pumpAndSettle();
      expect(_tokensAt(tester, find.text('probe')), studio);
    });

    testWidgets('showModalBottomSheet', (tester) async {
      await openEditor(tester);
      showModalBottomSheet<void>(context: editorContext, builder: (_) => probe);
      await tester.pumpAndSettle();
      expect(_tokensAt(tester, find.text('probe')), studio);
    });

    testWidgets('showMenu', (tester) async {
      await openEditor(tester);
      showMenu<void>(
        context: editorContext,
        position: const RelativeRect.fromLTRB(100, 100, 100, 100),
        items: const [PopupMenuItem<void>(child: probe)],
      );
      await tester.pumpAndSettle();
      expect(_tokensAt(tester, find.text('probe')), studio);
    });

    testWidgets('a DialogRoute pushed on the root navigator with captured '
        'themes (the pdf_io progress dialogs)', (tester) async {
      await openEditor(tester);
      final navigator = Navigator.of(editorContext, rootNavigator: true);
      navigator.push(
        DialogRoute<void>(
          context: editorContext,
          themes: InheritedTheme.capture(from: editorContext, to: null),
          builder: (_) => probe,
        ),
      );
      await tester.pumpAndSettle();
      expect(_tokensAt(tester, find.text('probe')), studio);
    });
  });
}
