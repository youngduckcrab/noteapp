// Foundation step B5 smoke test (contract 00-overview 7.6 B5, 04-editor 8.1):
// the placeholder EditorScreen on CORE's shared fake store shows the note
// title, and closing it calls onClose exactly once, after session.flush().
// Also: the 6.17.1 states (opening / not found / open failed), the '설정'
// more-menu item, and the four settings sections as plain Columns.
// 2nd round R2-B5 (m5-7/04-editor 8.1): EditorScreen(initialFocusRectPt: …)
// on the fake store opens, hands the rect to the per-note scope
// (editorInitialFocusRectProvider — received only, no behaviour yet) and
// closes.
import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

/// iPad Pro 13" portrait, logical 1032 x 1376 at DPR 2 (contract 7.4.8).
void _useIpad13Portrait(WidgetTester tester) {
  tester.view.physicalSize = const Size(2064, 2752);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

final class _Calls {
  int closed = 0;
  int openedSettings = 0;
}

Future<_Calls> _pumpEditor(
  WidgetTester tester,
  core.NoteStore store,
  String noteId, {
  bool withSettings = false,
  List<Override> overrides = const [],
}) async {
  final calls = _Calls();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        core.noteStoreProvider.overrideWithValue(store),
        ...overrides,
      ],
      child: MaterialApp(
        home: EditorScreen(
          key: ValueKey(noteId),
          noteId: noteId,
          onClose: () => calls.closed++,
          onOpenSettings: withSettings ? () => calls.openedSettings++ : null,
        ),
      ),
    ),
  );
  return calls;
}

final _backButton = find.bySemanticsLabel(EditorStrings.back);

/// The innermost ProviderScope container under the screen of [noteId] (the
/// per-note scope EditorScreen creates).
ProviderContainer _noteScopeOf(WidgetTester tester, String noteId) {
  final scopes = find.descendant(
    of: find.byKey(ValueKey(noteId)),
    matching: find.byType(UncontrolledProviderScope),
  );
  return tester.widget<UncontrolledProviderScope>(scopes.last).container;
}

/// The first page of [noteId] (read through a short session).
Future<String> _firstPageId(core.NoteStore store, String noteId) async {
  final session = await store.openSession(noteId);
  final pageId = session.pages.first.id;
  await session.close();
  return pageId;
}

void main() {
  testWidgets('shows the note title; back calls onClose once after flush', (
    tester,
  ) async {
    _useIpad13Portrait(tester);
    final faults = FakeNoteStoreFaults();
    // Closed at the end of the body, not in a tear-down: close() flushes, and
    // a commit still waiting on fake time would never finish after a failure.
    final store = createFakeNoteStore(faults: faults);
    final note = await store.library.createNote(title: '수학 노트');
    // From here on every commit takes 1 s. Opening the session queues CORE's
    // markOpened write (N-6), so session.flush() stays pending for 1 s.
    faults.commitDelay = const Duration(seconds: 1);

    final calls = await _pumpEditor(tester, store, note.id);
    expect(find.text(EditorStrings.openingNote), findsOneWidget);
    await tester.pump();
    expect(find.text('수학 노트'), findsOneWidget);
    expect(find.text(EditorStrings.openingNote), findsNothing);

    await tester.tap(_backButton);
    await tester.pump(const Duration(milliseconds: 900));
    expect(calls.closed, 0, reason: 'session.flush() has not completed yet');

    // A second press while flushing is ignored.
    await tester.tap(_backButton);
    await tester.pump(const Duration(milliseconds: 200));
    expect(calls.closed, 1);
    final opened = await store.library.getNote(note.id);
    expect(opened!.lastOpenedAt, isNotNull, reason: 'flushed before onClose');

    await tester.tap(_backButton);
    await tester.pump(const Duration(seconds: 2));
    expect(calls.closed, 1);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    await store.close();
  });

  testWidgets('(R2-B5) EditorScreen(initialFocusRectPt: …) shows the note, '
      'keeps the rect in the note scope and closes', (tester) async {
    _useIpad13Portrait(tester);
    final store = createFakeNoteStore();
    addTearDown(store.close);
    final note = await store.library.createNote(title: '검색 결과');
    final pageId = await _firstPageId(store, note.id);
    const focus = Rect.fromLTWH(120, 340, 200, 48);
    var closed = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [core.noteStoreProvider.overrideWithValue(store)],
        child: MaterialApp(
          home: EditorScreen(
            key: ValueKey(note.id),
            noteId: note.id,
            initialPageId: pageId,
            initialFocusRectPt: focus,
            onClose: () => closed++,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('검색 결과'), findsOneWidget);
    final scope = _noteScopeOf(tester, note.id);
    expect(scope.read(editorInitialFocusRectProvider), focus);
    expect(scope.read(editorInitialPageIdProvider), pageId);
    expect(tester.takeException(), isNull);

    await tester.tap(_backButton);
    await tester.pump();
    await tester.pump();
    expect(closed, 1);

    // Without the argument the scope holds null; an unknown page with a
    // rect still opens normally (the rect is only received in R2-B5).
    for (final (initialPageId, rect) in <(String?, Rect?)>[
      (pageId, null),
      ('no-such-page', focus),
      (null, focus),
    ]) {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [core.noteStoreProvider.overrideWithValue(store)],
          child: MaterialApp(
            home: EditorScreen(
              key: ValueKey(note.id),
              noteId: note.id,
              initialPageId: initialPageId,
              initialFocusRectPt: rect,
              onClose: () => closed++,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('검색 결과'), findsOneWidget);
      expect(
        _noteScopeOf(tester, note.id).read(editorInitialFocusRectProvider),
        rect,
      );
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('system back goes through the same path (PopScope)', (
    tester,
  ) async {
    _useIpad13Portrait(tester);
    final store = createFakeNoteStore();
    addTearDown(store.close);
    final note = await store.library.createNote(title: 'Back');
    final calls = await _pumpEditor(tester, store, note.id);
    await tester.pump();

    final NavigatorState navigator = tester.state(find.byType(Navigator));
    expect(await navigator.maybePop(), isTrue);
    await tester.pump();
    expect(calls.closed, 1);
    expect(find.text('Back'), findsOneWidget, reason: 'the route stays');
  });

  testWidgets('the session closes when the screen goes away', (tester) async {
    _useIpad13Portrait(tester);
    final store = createFakeNoteStore();
    addTearDown(store.close);
    final note = await store.library.createNote(title: 'Close');
    await _pumpEditor(tester, store, note.id);
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(EditorScreen)),
    );
    final session = container
        .read(core.noteSessionProvider(note.id))
        .requireValue;
    expect(session.isClosed, isFalse);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(session.isClosed, isTrue);
  });

  testWidgets("a missing note shows '노트를 찾을 수 없어요' and a button that "
      'calls onClose', (tester) async {
    _useIpad13Portrait(tester);
    final store = createFakeNoteStore();
    addTearDown(store.close);
    final calls = await _pumpEditor(tester, store, 'no-such-note');
    await tester.pump();

    expect(find.text(EditorStrings.noteNotFound), findsOneWidget);
    await tester.tap(find.text(EditorStrings.goBack));
    await tester.pump();
    expect(calls.closed, 1);
  });

  testWidgets('an open failure is reported, and 다시 시도 opens the note', (
    tester,
  ) async {
    _useIpad13Portrait(tester);
    final store = createFakeNoteStore();
    addTearDown(store.close);
    final note = await store.library.createNote(title: 'Retry');
    var attempts = 0;
    final calls = await _pumpEditor(
      tester,
      store,
      note.id,
      overrides: [
        core.noteSessionProvider.overrideWith((ref, id) async {
          attempts++;
          if (attempts == 1) throw StateError('injected open failure');
          return ref.watch(core.noteStoreProvider).openSession(id);
        }),
      ],
    );
    await tester.pump();

    expect(find.text(EditorStrings.openFailed), findsOneWidget);
    final reported = tester.takeException();
    expect(reported, isA<StateError>());

    await tester.tap(find.text(EditorStrings.retry));
    await tester.pump();
    await tester.pump();
    expect(attempts, 2);
    expect(find.text('Retry'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(calls.closed, 0);
  });

  testWidgets("'설정' is in the more menu only when onOpenSettings is given", (
    tester,
  ) async {
    _useIpad13Portrait(tester);
    final store = createFakeNoteStore();
    addTearDown(store.close);
    final note = await store.library.createNote(title: 'Menu');

    await _pumpEditor(tester, store, note.id);
    await tester.pump();
    // E-13: the more menu is always there; '설정' only with onOpenSettings.
    await tester.tap(find.bySemanticsLabel(EditorStrings.more));
    await tester.pumpAndSettle();
    expect(find.text(EditorStrings.noteInfo), findsOneWidget);
    expect(find.text(EditorStrings.settings), findsNothing);
    await tester.tap(find.bySemanticsLabel(EditorStrings.more)); // closes it
    await tester.pumpAndSettle();

    final calls = await _pumpEditor(tester, store, note.id, withSettings: true);
    await tester.pump();
    await tester.tap(find.bySemanticsLabel(EditorStrings.more));
    await tester.pumpAndSettle();
    await tester.tap(find.text(EditorStrings.settings));
    await tester.pumpAndSettle();
    expect(calls.openedSettings, 1);
    expect(calls.closed, 0);
  });

  testWidgets('buttons meet the tap-target and label guidelines (7.4.8)', (
    tester,
  ) async {
    _useIpad13Portrait(tester);
    final handle = tester.ensureSemantics();
    final store = createFakeNoteStore();
    addTearDown(store.close);
    final note = await store.library.createNote(title: 'A11y');
    await _pumpEditor(tester, store, note.id, withSettings: true);
    await tester.pump();

    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('the four settings sections are Columns without a Scaffold', (
    tester,
  ) async {
    // The sections read editorSettingsProvider / editorToolProvider, which
    // store through CORE: the settings screen's container has the store (app
    // root), like every container that reads them.
    final store = createFakeNoteStore();
    addTearDown(store.close);
    // Tall enough for the ListView to build all four.
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1032, 6000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [core.noteStoreProvider.overrideWithValue(store)],
        child: MaterialApp(
          home: Material(
            child: ListView(
              children: const [
                EditorInputSettingsSection(),
                EditorPenSettingsSection(),
                EditorPageSettingsSection(),
                EditorDeveloperSettingsSection(),
              ],
            ),
          ),
        ),
      ),
    );
    for (final type in [
      EditorInputSettingsSection,
      EditorPenSettingsSection,
      EditorPageSettingsSection,
      EditorDeveloperSettingsSection,
    ]) {
      // Sections below the fold are offstage for the default finders.
      final section = find.byType(type, skipOffstage: false);
      expect(section, findsOneWidget);
      expect(
        find.descendant(
          of: section,
          matching: find.byType(Column, skipOffstage: false),
          skipOffstage: false,
        ),
        findsWidgets,
      );
      expect(
        find.descendant(
          of: section,
          matching: find.byType(Scaffold, skipOffstage: false),
          skipOffstage: false,
        ),
        findsNothing,
      );
    }
    expect(tester.takeException(), isNull);
  });
}
