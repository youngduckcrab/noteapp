// test/helpers/pump_editor.dart — 04-editor 9.1 (E-01).
//
// E-01 state: the handles cover the store, the seeded note, the session (and
// its recorder), the provider container and the pointer driver. `viewport`
// (ViewportController) and `controllerOf` (mounted INK page controllers) are
// added with E-03/E-04, and `settings` (written to the CORE keys) with E-06.
import 'dart:async';

import 'package:feature_editor/feature_editor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

import 'pointer_driver.dart';
import 'recording_note_session.dart';

/// Page id of page [index] of the note seeded with [seedKey] (unique per
/// pumpEditor call, so one store can hold several seeded notes).
core.PageId seededPageId(String seedKey, int index) => '$seedKey-p$index';

int _seedCount = 0;

/// Pumps EditorScreen inside material_ui MaterialApp + ProviderScope with
/// core.noteStoreProvider = createFakeNoteStore() (or [store]) and a seeded note.
/// Default view: iPad Pro 13" portrait, logical 1032×1376 at DPR 2 (contract 7.4.8);
/// resets the view in addTearDown.
///
/// The note has [pages] blank A4 pages with ids [seededPageId]; the strokes of
/// [strokesByPageIndex] are added through the session with their page id set
/// to that page (ids kept), then the history is cleared, so the screen opens
/// with `undoDepth == 0`. A store created here is closed in a tear-down; a
/// store passed in is the caller's to close.
Future<EditorTestHandles> pumpEditor(
  WidgetTester tester, {
  core.NoteStore? store, // default: core.createFakeNoteStore()
  String title = '테스트 노트',
  int pages = 3, // A4 blank pages of the seeded note
  Map<int, List<core.Stroke>> strokesByPageIndex = const {},
  List<Override> overrides = const [], // e.g. syncBadgeProvider
  Size logicalSize = const Size(1032, 1376),
  String? initialPageId,
  VoidCallback? onClose,
  VoidCallback? onOpenSettings,
  bool recordSession = true, // wrap the CORE session in RecordingNoteSession
}) async {
  if (pages < 1) throw ArgumentError.value(pages, 'pages', 'must be >= 1');
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = logicalSize * 2;
  addTearDown(tester.view.reset);

  final ownStore = store == null;
  final s = store ?? createFakeNoteStore();
  if (ownStore) addTearDown(s.close);

  final seedKey = 'seed${++_seedCount}';
  final noteId = await _seedNote(s, seedKey, title, pages, strokesByPageIndex);

  RecordingNoteSession? recorder;
  final handles = EditorTestHandles._(
    tester,
    () => recorder,
    store: s,
    noteId: noteId,
    seedKey: seedKey,
    driver: PointerDriver(tester),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        core.noteStoreProvider.overrideWithValue(s),
        if (recordSession)
          core.noteSessionProvider.overrideWith((ref, id) async {
            // Same life cycle as CORE's provider: open on first listen,
            // close (one reference) on dispose.
            var disposed = false;
            core.NoteSession? opened;
            ref.onDispose(() {
              disposed = true;
              final o = opened;
              if (o != null) unawaited(o.close());
            });
            final inner = await s.openSession(id);
            if (disposed) {
              unawaited(inner.close());
            } else {
              opened = inner;
            }
            final wrapped = RecordingNoteSession(inner);
            if (id == noteId) recorder = wrapped;
            return wrapped;
          }),
        ...overrides,
      ],
      child: MaterialApp(
        home: EditorScreen(
          key: ValueKey(noteId),
          noteId: noteId,
          initialPageId: initialPageId,
          onClose: () {
            handles.closeCount++;
            onClose?.call();
          },
          onOpenSettings: onOpenSettings,
        ),
      ),
    ),
  );
  // The fake store opens the session after a microtask; one pump shows it.
  await tester.pump();
  return handles;
}

Future<core.NoteId> _seedNote(
  core.NoteStore store,
  String key,
  String title,
  int pages,
  Map<int, List<core.Stroke>> strokesByPageIndex,
) async {
  for (final index in strokesByPageIndex.keys) {
    if (index < 0 || index >= pages) {
      throw ArgumentError.value(index, 'strokesByPageIndex', 'no such page');
    }
  }
  final note = await store.library.createNote(
    title: title,
    pages: [
      for (var i = 0; i < pages; i++)
        core.PageDraft(
          id: seededPageId(key, i),
          size: core.PageSize.a4Portrait,
          background: const core.BlankBackground(),
        ),
    ],
  );
  if (strokesByPageIndex.values.every((s) => s.isEmpty)) return note.id;

  final session = await store.openSession(note.id);
  try {
    for (final MapEntry(key: index, value: strokes)
        in strokesByPageIndex.entries) {
      if (strokes.isEmpty) continue;
      final pageId = seededPageId(key, index);
      await session.openPage(pageId);
      session.execute(
        core.AddStrokes(
          pageId: pageId,
          strokes: [for (final s in strokes) s.copyWith(pageId: pageId)],
        ),
      );
      session.closePage(pageId);
    }
    session.clearHistory();
    await session.flush();
  } finally {
    await session.close();
  }
  return note.id;
}

class EditorTestHandles {
  EditorTestHandles._(
    this._tester,
    this._recorderOf, {
    required this.store,
    required this.noteId,
    required this.seedKey,
    required this.driver,
  });

  final core.NoteStore store;
  final String noteId;

  /// Prefix of the seeded page ids ([seededPageId]).
  final String seedKey;
  final PointerDriver driver;
  final WidgetTester _tester;
  final RecordingNoteSession? Function() _recorderOf;

  /// How often EditorScreen.onClose ran.
  int closeCount = 0;

  /// The id of page [index] of the seeded note.
  core.PageId pageId(int index) => seededPageId(seedKey, index);

  /// The editor's provider container: the innermost ProviderScope at or under
  /// EditorScreen, else the root scope.
  ProviderContainer get container {
    final screen = find.byType(EditorScreen);
    final scopes = find.descendant(
      of: screen,
      matching: find.byWidgetPredicate(
        (w) => w is ProviderScope || w is UncontrolledProviderScope,
      ),
    );
    final context = scopes.evaluate().isNotEmpty
        ? _tester.element(scopes.last)
        : _tester.element(screen);
    return ProviderScope.containerOf(context, listen: false);
  }

  /// The real (fake-store) session; throws while the note is still opening.
  core.NoteSession get session {
    final rec = recorder;
    if (rec != null) return rec.inner;
    final open = container.read(core.noteSessionProvider(noteId)).value;
    return open ?? (throw StateError('the note session is not open yet'));
  }

  /// The recording wrapper (null with recordSession: false or before open).
  RecordingNoteSession? get recorder => _recorderOf();
}
