// AppScreenBuilders.production() (docs/plans/01-infra.md 4.5.5, 6.6) under
// createAppRouter: the B6 LibraryScreen, the B5 EditorScreen and the shell
// settings screen over CORE's fake store. Started in foundation step B8
// (contract 00-overview 7.6 B8) and kept for the production wiring (I6).
//
// The tests drive the screens only through their contract callbacks and
// contract behaviour (7.2.17 / 7.2.18), never through placeholder body text,
// so the areas can replace their placeholders without breaking this file.
import 'package:feature_editor/feature_editor.dart';
import 'package:feature_library/feature_library.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' show NoteStore, noteStoreProvider;
import 'package:note_core/testing.dart';
import 'package:noteapp/src/app/strings.dart';
import 'package:noteapp/src/routing/app_router.dart';
import 'package:noteapp/src/routing/app_routes.dart';
import 'package:noteapp/src/routing/screen_builders.dart';
import 'package:noteapp/src/settings/settings_placeholder_screen.dart';
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
/// noteStoreProvider, pdf_io and the feature packages' own lists).
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
      expect(find.byType(SettingsPlaceholderScreen), findsOneWidget);
      expect(_pages(tester).last, isA<MaterialPage<Object?>>());

      tester
          .widget<SettingsPlaceholderScreen>(
            find.byType(SettingsPlaceholderScreen),
          )
          .onClose();
      await tester.pumpAndSettle();
      expect(_location(tester), '/');
      expect(find.byType(LibraryScreen), findsOneWidget);

      _library(tester).onOpenNote('n1');
      await tester.pumpAndSettle();
      final editorState = tester.state(find.byType(EditorScreen));
      _editor(tester).onOpenSettings!();
      await tester.pumpAndSettle();
      expect(_location(tester), AppRoutes.settings);

      await tester.tap(find.byTooltip(AppStrings.back));
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

    testWidgets('deep links to a folder and to settings', (tester) async {
      await _pumpShell(tester, initialLocation: '/folders/f9');
      expect(_library(tester).folderId, 'f9');

      _library(tester).onOpenSettings();
      await tester.pumpAndSettle();
      tester
          .widget<SettingsPlaceholderScreen>(
            find.byType(SettingsPlaceholderScreen),
          )
          .onClose();
      await tester.pumpAndSettle();
      expect(_location(tester), '/folders/f9');
    });

    testWidgets('starting on settings and closing goes home', (tester) async {
      await _pumpShell(tester, initialLocation: AppRoutes.settings);
      expect(find.byType(SettingsPlaceholderScreen), findsOneWidget);

      tester
          .widget<SettingsPlaceholderScreen>(
            find.byType(SettingsPlaceholderScreen),
          )
          .onClose();
      await tester.pumpAndSettle();
      expect(_location(tester), '/');
      expect(find.byType(LibraryScreen), findsOneWidget);
    });
  });
}
