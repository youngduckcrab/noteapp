// AppScreenBuilders.production() (docs/plans/01-infra.md 4.5.5, 6.6) under
// createAppRouter: the B6 LibraryScreen, the B5 EditorScreen and the shell
// settings screen over CORE's fake store. Started in foundation step B8
// (contract 00-overview 7.6 B8) and kept for the production wiring (I6).
//
// The tests drive the screens only through their contract callbacks and
// contract behaviour (7.2.17 / 7.2.18), never through placeholder body text,
// so the areas can replace their placeholders without breaking this file.
//
// 2차 (docs/plans/m5-7/01-infra.md 4.6.6, 6.8 — R2-B8b ①, J11): content
// search hits open through LibraryScreen.onOpenNoteAt → `?page=&focus=` →
// EditorScreen(initialPageId:, initialFocusRectPt:); `%2C`, unreadable focus
// and a reload on the reported address reach the real EditorScreen too.
import 'package:feature_editor/feature_editor.dart';
import 'package:feature_library/feature_library.dart';
import 'package:flutter/services.dart' show SystemChannels;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' show NoteStore, noteStoreProvider;
import 'package:note_core/testing.dart';
import 'package:noteapp/src/app/strings.dart';
import 'package:noteapp/src/bootstrap/startup_report.dart';
import 'package:noteapp/src/errors/app_error_log.dart';
import 'package:noteapp/src/providers.dart';
import 'package:noteapp/src/routing/app_router.dart';
import 'package:noteapp/src/routing/app_routes.dart';
import 'package:noteapp/src/routing/screen_builders.dart';
import 'package:noteapp/src/settings/settings_screen.dart';
import 'package:pdf_io/pdf_io.dart';

/// iPad Pro 13" portrait, logical 1032×1376 at DPR 2 (contract 7.4.8).
void _useIpadPortrait(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(2064, 2752)
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

/// Pumps the production screens over [store] (a fresh fake store by
/// default) with the root overrides the screens need (contract 7.3.3:
/// noteStoreProvider, pdf_io and the feature packages' own lists; the
/// settings screen's about section also reads the shell's error log and
/// startup report).
Future<NoteStore> _pumpShell(
  WidgetTester tester, {
  String initialLocation = AppRoutes.library,
  NoteStore? store,
}) async {
  _useIpadPortrait(tester);
  final noteStore = store ?? createFakeNoteStore();
  addTearDown(noteStore.close);
  final router = createAppRouter(
    screens: AppScreenBuilders.production(),
    initialLocation: initialLocation,
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        noteStoreProvider.overrideWithValue(noteStore),
        appErrorLogProvider.overrideWithValue(AppErrorLog()),
        startupReportProvider.overrideWithValue(
          const StartupReport(steps: [], bootstrapElapsed: Duration.zero),
        ),
        ...pdfIoOverrides(),
        ...featureLibraryOverrides(),
        ...featureEditorOverrides(),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return noteStore;
}

GoRouter _router(WidgetTester tester) =>
    tester.widget<MaterialApp>(find.byType(MaterialApp)).routerConfig!
        as GoRouter;

String _location(WidgetTester tester) => _router(tester).state.uri.toString();

/// The router's Navigator pages, bottom first.
List<Page<Object?>> _pages(WidgetTester tester) => tester
    .widget<Navigator>(find.byType(Navigator, skipOffstage: false).first)
    .pages;

LibraryScreen _library(WidgetTester tester) =>
    tester.widget<LibraryScreen>(find.byType(LibraryScreen));

EditorScreen _editor(WidgetTester tester) =>
    tester.widget<EditorScreen>(find.byType(EditorScreen));

final Finder _anyLibrary = find.byType(LibraryScreen, skipOffstage: false);
final Finder _anyEditor = find.byType(EditorScreen, skipOffstage: false);

void main() {
  group('production screens', () {
    testWidgets('library → onOpenNote → editor → onClose → library', (
      tester,
    ) async {
      await _pumpShell(tester);

      expect(_location(tester), '/');
      expect(find.byType(LibraryScreen), findsOneWidget);
      expect(_library(tester).folderId, isNull);
      expect(_anyEditor, findsNothing);

      _library(tester).onOpenNote('n1');
      await tester.pumpAndSettle();

      expect(_location(tester), '/notes/n1');
      expect(find.byType(EditorScreen), findsOneWidget);
      expect(_editor(tester).noteId, 'n1');
      expect(_editor(tester).initialPageId, isNull);
      expect(_editor(tester).onOpenSettings, isNotNull);
      // Pushed: the library route stays below (offstage) for the way back.
      expect(find.byType(LibraryScreen), findsNothing);
      expect(_anyLibrary, findsOneWidget);

      _editor(tester).onClose();
      await tester.pumpAndSettle();

      expect(_location(tester), '/');
      expect(find.byType(LibraryScreen), findsOneWidget);
      expect(_anyEditor, findsNothing);
    });

    testWidgets('a created note opens, and system back closes the editor '
        'after the session flush', (tester) async {
      final store = createFakeNoteStore();
      final note = await store.library.createNote(title: 'B8');
      await _pumpShell(tester, store: store);

      _library(tester).onOpenNote(note.id);
      await tester.pumpAndSettle();
      expect(_location(tester), AppRoutes.note(note.id));
      expect(_editor(tester).noteId, note.id);

      // System back reaches EditorScreen's PopScope (canPop: false); the
      // screen flushes its session and then calls onClose (contract 7.2.17),
      // which pops the route.
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();

      expect(_location(tester), '/');
      expect(find.byType(LibraryScreen), findsOneWidget);
      expect(_anyEditor, findsNothing);
    });

    testWidgets('folders share one library route; its State is kept', (
      tester,
    ) async {
      await _pumpShell(tester);
      final state = tester.state(find.byType(LibraryScreen));

      Page<Object?> libraryPage() => _pages(tester).first;
      expect(libraryPage(), isA<NoTransitionPage<Object?>>());
      expect(libraryPage().key, AppRoutes.libraryPageKey);

      _library(tester).onOpenFolder('f1');
      await tester.pumpAndSettle();
      expect(_location(tester), '/folders/f1');
      expect(_library(tester).folderId, 'f1');
      expect(_pages(tester), hasLength(1));
      expect(libraryPage(), isA<NoTransitionPage<Object?>>());
      expect(libraryPage().key, AppRoutes.libraryPageKey);
      expect(tester.state(find.byType(LibraryScreen)), same(state));

      _library(tester).onOpenFolder('a/b c');
      await tester.pumpAndSettle();
      expect(_location(tester), AppRoutes.folder('a/b c'));
      expect(_library(tester).folderId, 'a/b c');
      expect(tester.state(find.byType(LibraryScreen)), same(state));

      _library(tester).onOpenNote('n1');
      await tester.pumpAndSettle();
      expect(_pages(tester).last, isA<NoTransitionPage<Object?>>());
      _editor(tester).onClose();
      await tester.pumpAndSettle();
      // Closing the note returns to the same folder.
      expect(_location(tester), AppRoutes.folder('a/b c'));
      expect(tester.state(find.byType(LibraryScreen)), same(state));

      _library(tester).onOpenFolder(null);
      await tester.pumpAndSettle();
      expect(_location(tester), '/');
      expect(_library(tester).folderId, isNull);
      expect(tester.state(find.byType(LibraryScreen)), same(state));
    });

    testWidgets('settings opens from the library and the editor', (
      tester,
    ) async {
      await _pumpShell(tester);

      _library(tester).onOpenSettings();
      await tester.pumpAndSettle();
      expect(_location(tester), AppRoutes.settings);
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(_pages(tester).last, isA<MaterialPage<Object?>>());

      tester.widget<SettingsScreen>(find.byType(SettingsScreen)).onClose();
      await tester.pumpAndSettle();
      expect(_location(tester), '/');
      expect(find.byType(LibraryScreen), findsOneWidget);

      _library(tester).onOpenNote('n1');
      await tester.pumpAndSettle();
      final editorState = tester.state(find.byType(EditorScreen));
      _editor(tester).onOpenSettings!();
      await tester.pumpAndSettle();
      expect(_location(tester), AppRoutes.settings);

      await tester.tap(find.byTooltip(AppStrings.close));
      await tester.pumpAndSettle();
      expect(_location(tester), '/notes/n1');
      expect(tester.state(find.byType(EditorScreen)), same(editorState));
    });

    testWidgets('a deep link to a note opens the editor; closing goes home', (
      tester,
    ) async {
      await _pumpShell(
        tester,
        initialLocation: AppRoutes.note('a/b c', pageId: 'p 3'),
      );

      expect(find.byType(EditorScreen), findsOneWidget);
      expect(_editor(tester).noteId, 'a/b c');
      expect(_editor(tester).initialPageId, 'p 3');
      expect(_anyLibrary, findsNothing);

      // Nothing to pop (started on the note, e.g. after a reload) → home.
      _editor(tester).onClose();
      await tester.pumpAndSettle();
      expect(_location(tester), '/');
      expect(find.byType(LibraryScreen), findsOneWidget);
      expect(_anyEditor, findsNothing);
    });

    testWidgets('onOpenNoteAt(noteId, pageId, rect) → the editor gets the '
        'page and the focus rect; closing returns to the library', (
      tester,
    ) async {
      await _pumpShell(tester);
      expect(_library(tester).onOpenNoteAt, isNotNull);

      const rect = Rect.fromLTRB(120, 80, 320.5, 200);
      _library(tester).onOpenNoteAt!('n1', 'p3', rect);
      await tester.pumpAndSettle();

      expect(_location(tester), '/notes/n1?page=p3&focus=120,80,320.5,200');
      expect(_editor(tester).noteId, 'n1');
      expect(_editor(tester).initialPageId, 'p3');
      expect(_editor(tester).initialFocusRectPt, rect);
      // Pushed over the library (the search view stays below).
      expect(_anyLibrary, findsOneWidget);

      _editor(tester).onClose();
      await tester.pumpAndSettle();
      expect(_location(tester), '/');
      expect(find.byType(LibraryScreen), findsOneWidget);
    });

    testWidgets('onOpenNoteAt without a rect opens the page only', (
      tester,
    ) async {
      await _pumpShell(tester);
      _library(tester).onOpenNoteAt!('n1', 'p 3', null);
      await tester.pumpAndSettle();

      expect(_location(tester), AppRoutes.note('n1', pageId: 'p 3'));
      expect(_editor(tester).initialPageId, 'p 3');
      expect(_editor(tester).initialFocusRectPt, isNull);
    });

    testWidgets('a deep link with ?page=&focus= reaches EditorScreen', (
      tester,
    ) async {
      await _pumpShell(
        tester,
        initialLocation: '/notes/n1?page=p3&focus=-1.5,0,36,72.8',
      );
      expect(_editor(tester).initialPageId, 'p3');
      expect(
        _editor(tester).initialFocusRectPt,
        const Rect.fromLTRB(-1.5, 0, 36, 72.8),
      );
    });

    // J11 (6.8): the same three cases as the placeholder screens in
    // app_router_test, now through the real LibraryScreen / EditorScreen.
    testWidgets('%2C between the focus values reaches EditorScreen the same', (
      tester,
    ) async {
      await _pumpShell(
        tester,
        initialLocation: '/notes/n1?page=p3&focus=120%2C80%2C320.5%2C200',
      );
      expect(_editor(tester).noteId, 'n1');
      expect(_editor(tester).initialPageId, 'p3');
      expect(
        _editor(tester).initialFocusRectPt,
        const Rect.fromLTRB(120, 80, 320.5, 200),
      );
    });

    testWidgets('an unreadable focus is dropped; EditorScreen still opens the '
        'page', (tester) async {
      for (final bad in [
        '10,0,5,5', // l > r
        '0,10,5,5', // t > b
        '1,2,3',
        '1,2,3,4,5',
        'x,1,2,3',
        '',
        '1,2,3,1e9',
        '1,2,3,100001',
        'NaN,0,1,1',
      ]) {
        await _pumpShell(
          tester,
          initialLocation: '/notes/n1?page=p3&focus=$bad',
        );
        expect(find.byType(EditorScreen), findsOneWidget, reason: bad);
        expect(_editor(tester).noteId, 'n1', reason: bad);
        expect(_editor(tester).initialPageId, 'p3', reason: bad);
        expect(_editor(tester).initialFocusRectPt, isNull, reason: bad);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('focus without page is dropped at EditorScreen', (
      tester,
    ) async {
      await _pumpShell(tester, initialLocation: '/notes/n1?focus=1,2,3,4');
      expect(_editor(tester).noteId, 'n1');
      expect(_editor(tester).initialPageId, isNull);
      expect(_editor(tester).initialFocusRectPt, isNull);
    });

    testWidgets('search hit in a folder → reload on the reported address '
        'opens the same page and rect; closing then goes home', (tester) async {
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
      const hit = Rect.fromLTRB(-1.25, 0, 36.04, 72.75);
      // What the address keeps: each value rounded to 0.1 pt.
      const rect = Rect.fromLTRB(-1.3, 0, 36, 72.8);

      await _pumpShell(tester, initialLocation: '/folders/f9');
      expect(_library(tester).folderId, 'f9');
      expect(_library(tester).onOpenNoteAt, isNotNull);
      _library(tester).onOpenNoteAt!('a/b c', 'p 3', hit);
      await tester.pumpAndSettle();

      final address = reported.last;
      expect(address, AppRoutes.note('a/b c', pageId: 'p 3', focus: rect));
      expect(address, contains('focus=-1.3,0,36,72.8'));
      expect(_editor(tester).noteId, 'a/b c');
      expect(_editor(tester).initialPageId, 'p 3');
      expect(_editor(tester).initialFocusRectPt, rect);

      // Closing before a reload returns to the folder the search ran in.
      _editor(tester).onClose();
      await tester.pumpAndSettle();
      expect(_location(tester), '/folders/f9');

      // Open again, then reload: a new app starts on the browser's address.
      _library(tester).onOpenNoteAt!('a/b c', 'p 3', hit);
      await tester.pumpAndSettle();
      expect(reported.last, address);
      await tester.pumpWidget(const SizedBox());
      await _pumpShell(tester, initialLocation: address);

      expect(_location(tester), address);
      expect(_editor(tester).noteId, 'a/b c');
      expect(_editor(tester).initialPageId, 'p 3');
      expect(_editor(tester).initialFocusRectPt, rect);
      expect(_anyLibrary, findsNothing);

      // After a reload nothing is below the editor → home.
      _editor(tester).onClose();
      await tester.pumpAndSettle();
      expect(_location(tester), '/');
      expect(find.byType(LibraryScreen), findsOneWidget);
    });

    testWidgets('deep links to a folder and to settings', (tester) async {
      await _pumpShell(tester, initialLocation: '/folders/f9');
      expect(_library(tester).folderId, 'f9');

      _library(tester).onOpenSettings();
      await tester.pumpAndSettle();
      tester.widget<SettingsScreen>(find.byType(SettingsScreen)).onClose();
      await tester.pumpAndSettle();
      expect(_location(tester), '/folders/f9');
    });

    testWidgets('starting on settings and closing goes home', (tester) async {
      await _pumpShell(tester, initialLocation: AppRoutes.settings);
      expect(find.byType(SettingsScreen), findsOneWidget);

      tester.widget<SettingsScreen>(find.byType(SettingsScreen)).onClose();
      await tester.pumpAndSettle();
      expect(_location(tester), '/');
      expect(find.byType(LibraryScreen), findsOneWidget);
    });
  });
}
