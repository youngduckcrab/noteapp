// Foundation step B6 smoke test (contract 00-overview 7.6 B6, 05-library 8 B6):
// the placeholder LibraryScreen on CORE's shared fake store creates a note with
// '새 노트' and opens it with onOpenNote exactly once.
import 'package:feature_library/feature_library.dart';
import 'package:feature_library/src/l10n/library_strings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';

/// iPad Pro 13" landscape, logical 1376 x 1032 at DPR 2 (contract 7.4.8).
void _useIpad13Landscape(WidgetTester tester) {
  tester.view.physicalSize = const Size(2752, 2064);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

final class _Calls {
  final List<String?> openedFolders = [];
  final List<String> openedNotes = [];
  int openedSettings = 0;
}

Future<_Calls> _pumpLibrary(
  WidgetTester tester,
  NoteStore store, {
  String? folderId,
}) async {
  final calls = _Calls();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [noteStoreProvider.overrideWithValue(store)],
      child: MaterialApp(
        home: LibraryScreen(
          folderId: folderId,
          onOpenFolder: calls.openedFolders.add,
          onOpenNote: calls.openedNotes.add,
          onOpenSettings: () => calls.openedSettings++,
        ),
      ),
    ),
  );
  return calls;
}

void main() {
  testWidgets("'새 노트' creates an untitled note at home and opens it once", (
    tester,
  ) async {
    _useIpad13Landscape(tester);
    final store = createFakeNoteStore();
    addTearDown(store.close);
    final calls = await _pumpLibrary(tester, store);

    expect(find.text(LibraryStrings.home), findsOneWidget);
    await tester.tap(find.text(LibraryStrings.newNote));
    await tester.pump();

    expect(calls.openedNotes, hasLength(1));
    final note = await store.library.getNote(calls.openedNotes.single);
    expect(note, isNotNull);
    expect(note!.title, LibraryStrings.defaultNoteTitle);
    expect(note.folderId, isNull);
    expect(calls.openedFolders, isEmpty);
    expect(calls.openedSettings, 0);
  });

  testWidgets('a second tap while createNote is pending creates nothing', (
    tester,
  ) async {
    _useIpad13Landscape(tester);
    final faults = FakeNoteStoreFaults()
      ..commitDelay = const Duration(seconds: 1);
    final store = createFakeNoteStore(faults: faults);
    addTearDown(store.close);
    final calls = await _pumpLibrary(tester, store);

    await tester.tap(find.text(LibraryStrings.newNote));
    await tester.pump();
    await tester.tap(find.text(LibraryStrings.newNote));
    await tester.pump();
    expect(calls.openedNotes, isEmpty);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(calls.openedNotes, hasLength(1));
  });

  testWidgets('a failed createNote is reported and shows the generic error', (
    tester,
  ) async {
    _useIpad13Landscape(tester);
    final store = createFakeNoteStore();
    await tester.runAsync(store.close);
    final calls = await _pumpLibrary(tester, store);

    await tester.tap(find.text(LibraryStrings.newNote));
    await tester.pump();

    expect(tester.takeException(), isA<StateError>());
    await tester.pump(); // SnackBar entrance
    expect(find.text(LibraryStrings.errorGeneric), findsOneWidget);
    expect(calls.openedNotes, isEmpty);
  });

  testWidgets('the settings button calls onOpenSettings', (tester) async {
    _useIpad13Landscape(tester);
    final store = createFakeNoteStore();
    addTearDown(store.close);
    final calls = await _pumpLibrary(tester, store, folderId: 'folder-1');

    await tester.tap(find.byTooltip(LibraryStrings.settings));
    await tester.pump();

    expect(calls.openedSettings, 1);
    expect(calls.openedNotes, isEmpty);
  });

  testWidgets('tap targets of the placeholder meet the 44 x 44 guideline', (
    tester,
  ) async {
    _useIpad13Landscape(tester);
    final semantics = tester.ensureSemantics();
    final store = createFakeNoteStore();
    addTearDown(store.close);
    await _pumpLibrary(tester, store);

    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    semantics.dispose();
  });

  testWidgets('LibrarySettingsSection is a body without Scaffold or title', (
    tester,
  ) async {
    final store = createFakeNoteStore();
    addTearDown(store.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [noteStoreProvider.overrideWithValue(store)],
        child: const MaterialApp(
          home: Scaffold(body: LibrarySettingsSection()),
        ),
      ),
    );

    final section = find.byType(LibrarySettingsSection);
    expect(section, findsOneWidget);
    expect(
      find.descendant(of: section, matching: find.byType(Scaffold)),
      findsNothing,
    );
    expect(
      find.descendant(of: section, matching: find.byType(Column)),
      findsOneWidget,
    );
  });
}
