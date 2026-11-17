// (v2.17-md, C217M-13 — docs/plans/m5-7/08-markdown.md 11, MD-T11) The MD 문서 route: the
// library opens MD 문서 at /md/<id>[?q=][&edit=1] straight away (onOpenMarkdown → push), the
// real MarkdownScreen (deferred library — loaded at once on the VM) gets the arguments and
// closes back to the library; /notes/<MD 문서> redirects to /md/<id> with isMarkdownNote,
// an ink note stays on /notes/; the address builder encodes ids and queries.
import 'dart:async';

import 'package:feature_library/feature_library.dart';
import 'package:feature_markdown/feature_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';
import 'package:noteapp/src/app/strings.dart';
import 'package:noteapp/src/bootstrap/startup_report.dart';
import 'package:noteapp/src/errors/app_error_log.dart';
import 'package:noteapp/src/modules/feature_wiring_module.dart';
import 'package:noteapp/src/providers.dart';
import 'package:noteapp/src/routing/app_navigator.dart';
import 'package:noteapp/src/routing/app_router.dart';
import 'package:noteapp/src/routing/app_routes.dart';
import 'package:noteapp/src/routing/screen_builders.dart';
import 'package:pdf_io/pdf_io.dart';

Future<NoteStore> _pump(
  WidgetTester tester, {
  String initialLocation = AppRoutes.library,
  NoteStore? store,
  AppScreenBuilders? screens,
}) async {
  tester.view
    ..physicalSize = const Size(2064, 2752)
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final noteStore = store ?? createFakeNoteStore();
  addTearDown(noteStore.close);
  final router = createAppRouter(
    screens: screens ?? AppScreenBuilders.production(),
    initialLocation: initialLocation,
    isMarkdownNote: (id) async =>
        (await noteStore.library.getNote(id))?.isMarkdown ?? false,
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

void main() {
  test('markdownRoute: path, query, edit; ids and queries encoded', () {
    expect(markdownRoute('n1'), '/md/n1');
    expect(markdownRoute('n1', query: ''), '/md/n1');
    expect(markdownRoute('n 1/2', query: '미분 & 적분'), isNot(contains(' ')));
    expect(
      markdownRoute('n1', query: '미분 & 적분', edit: true),
      '/md/n1?q=${Uri.encodeQueryComponent('미분 & 적분')}&edit=1',
    );
    expect(markdownRoute('n1', edit: true), '/md/n1?edit=1');
    expect(
      const MarkdownRouteArgs(noteId: 'a', initialQuery: 'q'),
      const MarkdownRouteArgs(noteId: 'a', initialQuery: 'q'),
    );
  });

  testWidgets('the library opens an MD 문서 at /md/ with the query; the screen '
      'gets the arguments; onClose goes back to the library', (tester) async {
    final store = await _pump(tester);
    final note = await tester.runAsync(
      () => store.markdown.create(title: '문서', text: '# 미분'),
    );
    tester.widget<LibraryScreen>(find.byType(LibraryScreen)).onOpenMarkdown!(
      note!.id,
      query: '미분',
    );
    await tester.pumpAndSettle();
    expect(_location(tester), markdownRoute(note.id, query: '미분'));
    final screen = tester.widget<MarkdownScreen>(find.byType(MarkdownScreen));
    expect(screen.noteId, note.id);
    expect(screen.initialQuery, '미분');
    expect(screen.initialEdit, isFalse);
    expect(MarkdownScreenLoader.isLoaded, isTrue);
    screen.onClose();
    await tester.pumpAndSettle();
    expect(_location(tester), '/');
    expect(find.byType(MarkdownScreen), findsNothing);
  });

  testWidgets('[사본 열기] (onOpenMarkdown of the screen) opens the conflict '
      'copy on top; back returns to the document', (tester) async {
    final store = await _pump(tester);
    final note = await tester.runAsync(
      () => store.markdown.create(title: '문서', text: 'a'),
    );
    final copy = await tester.runAsync(
      () => store.markdown.create(title: '문서 (충돌 사본)', text: 'b'),
    );
    tester.widget<LibraryScreen>(find.byType(LibraryScreen)).onOpenMarkdown!(
      note!.id,
    );
    await tester.pumpAndSettle();
    final screen = tester.widget<MarkdownScreen>(find.byType(MarkdownScreen));
    expect(screen.onOpenMarkdown, isNotNull);
    screen.onOpenMarkdown!(copy!.id);
    await tester.pumpAndSettle();
    expect(_location(tester), markdownRoute(copy.id));
    tester.widget<MarkdownScreen>(find.byType(MarkdownScreen)).onClose();
    await tester.pumpAndSettle();
    expect(_location(tester), markdownRoute(note.id));
  });

  testWidgets('a new document opens typing in place (edit=1)', (tester) async {
    await _pump(tester);
    tester.widget<LibraryScreen>(find.byType(LibraryScreen)).onOpenMarkdown!(
      'n9',
      edit: true,
    );
    await tester.pumpAndSettle();
    expect(_location(tester), '/md/n9?edit=1');
    expect(
      tester.widget<MarkdownScreen>(find.byType(MarkdownScreen)).initialEdit,
      isTrue,
    );
  });

  testWidgets('/notes/<MD 문서> redirects to /md/<id>; an ink note stays', (
    tester,
  ) async {
    final store = createFakeNoteStore();
    final md = await store.markdown.create(title: 'md', text: 'x');
    final ink = await store.library.createNote(title: 'ink');
    await _pump(
      tester,
      store: store,
      screens: AppScreenBuilders.placeholders(),
      initialLocation: AppRoutes.note(md.id),
    );
    expect(_location(tester), markdownRoute(md.id));
    expect(find.text('markdown ${md.id}'), findsOneWidget);
    _router(tester).go(AppRoutes.note(ink.id));
    await tester.pumpAndSettle();
    expect(_location(tester), AppRoutes.note(ink.id));
    expect(find.text('noteId: ${ink.id}'), findsOneWidget);
  });

  testWidgets('an in-app open of a handwriting note does not wait for the '
      'MD redirect (no DB read, U18)', (tester) async {
    tester.view
      ..physicalSize = const Size(2064, 2752)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    var asked = 0;
    final router = createAppRouter(
      screens: AppScreenBuilders.placeholders(),
      initialLocation: AppRoutes.library,
      isMarkdownNote: (id) {
        asked++;
        return Completer<bool>().future; // a DB read that never answers
      },
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    GoRouterAppNavigator(router).openNote('ink1');
    await tester.pump();
    await tester.pump();
    expect(asked, 0);
    expect(router.state.uri.toString(), AppRoutes.note('ink1'));
    expect(find.text('noteId: ink1'), findsOneWidget);
    // A typed address still asks.
    router.go(AppRoutes.note('typed'));
    await tester.pump();
    expect(asked, 1);
  });

  testWidgets('a failed load of the screen can be retried (review finding)', (
    tester,
  ) async {
    MarkdownScreenLoader.resetForTest();
    addTearDown(MarkdownScreenLoader.resetForTest);
    var attempts = 0;
    MarkdownScreenLoader.loadLibrary = () async {
      attempts++;
      if (attempts == 1) throw StateError('part file not reachable');
    };
    final store = createFakeNoteStore();
    final note = await store.markdown.create(title: 'md', text: '# 제목');
    await _pump(tester, store: store, initialLocation: markdownRoute(note.id));
    expect(find.text(AppStrings.markdownLoadFailed), findsOneWidget);
    expect(MarkdownScreenLoader.isLoaded, isFalse);
    await tester.tap(find.byKey(const Key('md.load.retry')));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(MarkdownScreenLoader.isLoaded, isTrue);
    expect(find.byType(MarkdownScreen), findsOneWidget);
  });

  test('native builds preload the screen when idle; the web does not', () {
    expect(FeatureWiringModule(isWeb: false).idleTasks().map((t) => t.id), [
      'featureWiring.markdownScreen',
    ]);
    expect(FeatureWiringModule(isWeb: true).idleTasks(), isEmpty);
  });

  testWidgets('/md/<ink note> shows the screen (it says it is not an MD 문서)', (
    tester,
  ) async {
    final store = createFakeNoteStore();
    final ink = await store.library.createNote(title: 'ink');
    await _pump(tester, store: store, initialLocation: markdownRoute(ink.id));
    expect(find.byType(MarkdownScreen), findsOneWidget);
    expect(find.byKey(MarkdownKeys.notMarkdown), findsOneWidget);
  });
}
