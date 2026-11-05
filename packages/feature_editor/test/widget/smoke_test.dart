// Foundation step B5 smoke test (contract 00-overview 7.6 B5, 04-editor 8.1):
// the placeholder EditorScreen on CORE's shared fake store shows the note
// title, and closing it calls onClose exactly once, after session.flush().
// Also: the 6.17.1 states (opening / not found / open failed), the '설정'
// more-menu item, and the four settings sections as plain Columns.
import 'package:feature_editor/feature_editor.dart';
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
    expect(find.bySemanticsLabel(EditorStrings.more), findsNothing);

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
    await tester.pumpWidget(
      ProviderScope(
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
      // The B5 placeholders have no height, and the finders treat zero-extent
      // list children as offstage.
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
