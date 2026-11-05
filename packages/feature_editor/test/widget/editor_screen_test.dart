// E-13: entering and leaving the editor (04-editor 6.17.1, 6.17.4, 6.3.5,
// 4.2): opening → body, a missing note, 다시 시도, back = flushAll THEN
// onClose (with '저장하는 중…' after 300 ms), flushAll when the app is hidden,
// the last position, initialPageId and an unknown initialPageId.
import 'dart:async';

import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/ui/editor_body.dart';
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:feature_editor/src/ui/toolbar/editor_toolbar.dart';
import 'package:feature_editor/src/viewport/viewport_constants.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

import '../helpers/pump_editor.dart';
import '../helpers/test_data.dart';

const List<Offset> _points = [
  Offset(100, 150),
  Offset(140, 170),
  Offset(190, 185),
];

/// Pumps a fresh app (new root container) with EditorScreen for [noteId] on
/// [store] — "opening the note again" — and lets the viewport settle.
Future<void> _reopen(
  WidgetTester tester,
  core.NoteStore store,
  String noteId, {
  String? initialPageId,
}) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [core.noteStoreProvider.overrideWithValue(store)],
      child: MaterialApp(
        home: EditorScreen(
          key: ValueKey('again-$noteId'),
          noteId: noteId,
          initialPageId: initialPageId,
          onClose: () {},
        ),
      ),
    ),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump();
  }
}

/// Moves the camera to page [index] and lets it settle (150 ms).
Future<void> _goTo(WidgetTester tester, EditorTestHandles h, int index) async {
  await h.viewport.jumpToPage(index, animate: false);
  await tester.pump(const Duration(milliseconds: 200));
  expect(h.viewport.currentPageIndex.value, index);
}

void main() {
  testWidgets('opening → the body with the toolbar', (tester) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(2064, 2752);
    addTearDown(tester.view.reset);
    final store = createFakeNoteStore();
    addTearDown(store.close);
    final note = await store.library.createNote(title: '여는 노트');
    final opened = Completer<void>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          core.noteStoreProvider.overrideWithValue(store),
          core.noteSessionProvider.overrideWith((ref, id) async {
            await opened.future;
            final session = await store.openSession(id);
            ref.onDispose(session.close);
            return session;
          }),
        ],
        child: MaterialApp(
          home: EditorScreen(
            key: ValueKey(note.id),
            noteId: note.id,
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text(EditorStrings.openingNote), findsOneWidget);
    expect(find.byType(EditorBody), findsNothing);

    opened.complete();
    await tester.pump();
    await tester.pump();
    expect(find.text(EditorStrings.openingNote), findsNothing);
    expect(find.byType(EditorBody), findsOneWidget);
    expect(find.byKey(EditorToolbar.titleKey), findsOneWidget);
    expect(find.text('여는 노트'), findsOneWidget);
  });

  testWidgets('a missing note: the message and a button that calls onClose', (
    tester,
  ) async {
    final store = createFakeNoteStore();
    addTearDown(store.close);
    var closed = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [core.noteStoreProvider.overrideWithValue(store)],
        child: MaterialApp(
          home: EditorScreen(
            key: const ValueKey('missing'),
            noteId: 'missing',
            onClose: () => closed++,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text(EditorStrings.noteNotFound), findsOneWidget);
    await tester.tap(find.text(EditorStrings.goBack));
    await tester.pump();
    expect(closed, 1);
  });

  testWidgets('다시 시도 creates core.noteSessionProvider again', (tester) async {
    final store = createFakeNoteStore();
    addTearDown(store.close);
    final note = await store.library.createNote(title: 'Retry');
    var attempts = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          core.noteStoreProvider.overrideWithValue(store),
          core.noteSessionProvider.overrideWith((ref, id) async {
            attempts++;
            if (attempts == 1) throw StateError('injected open failure');
            return ref.watch(core.noteStoreProvider).openSession(id);
          }),
        ],
        child: MaterialApp(
          home: EditorScreen(
            key: ValueKey(note.id),
            noteId: note.id,
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text(EditorStrings.openFailed), findsOneWidget);
    expect(tester.takeException(), isA<StateError>());

    await tester.tap(find.text(EditorStrings.retry));
    await tester.pump();
    await tester.pump();
    expect(attempts, 2);
    expect(find.byType(EditorBody), findsOneWidget);
  });

  testWidgets('back: flushAll completes BEFORE onClose; 저장하는 중… after '
      '300 ms; a second press is ignored', (tester) async {
    final faults = FakeNoteStoreFaults();
    // Closed at the end of the body (a commit waiting on fake time would
    // never finish in a tear-down).
    final store = createFakeNoteStore(faults: faults);
    final events = <String>[];
    final h = await pumpEditor(
      tester,
      store: store,
      onClose: () => events.add('onClose'),
    );
    faults.commitDelay = const Duration(seconds: 1);
    await h.driver.stylusStroke(pathThrough(h, 0, _points));
    expect(h.session.history.undoDepth, 1);

    await tester.tap(find.byKey(EditorToolbar.backKey));
    await tester.pump(const Duration(milliseconds: 200));
    expect(events, isEmpty);
    expect(h.recorder!.calls.last, 'flush');
    expect(find.text(EditorStrings.saving), findsNothing);

    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text(EditorStrings.saving), findsOneWidget);
    expect(events, isEmpty);

    // A second press while flushing is ignored.
    await tester.tap(find.byKey(EditorToolbar.backKey), warnIfMissed: false);
    await tester.pump(const Duration(seconds: 2));
    expect(events, ['onClose']);
    expect(h.recorder!.countOf('flush'), 1);
    expect(store.persistenceStatus.pendingOps, 0);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    await store.close();
  });

  testWidgets('back cancels a stroke whose pen has not lifted', (tester) async {
    final h = await pumpEditor(tester);
    final points = pathThrough(h, 0, _points);
    await h.driver.down(1, points[0], kind: PointerDeviceKind.stylus);
    await h.driver.move(1, points[1]);
    await h.driver.move(1, points[2]);

    await tester.tap(find.byKey(EditorToolbar.backKey));
    await tester.pump();
    await tester.pump();
    expect(h.closeCount, 1);
    expect(h.session.history.undoDepth, 0);
    await h.driver.up(1);
    expect(h.recorder!.calls.where((c) => c.startsWith('execute')), isEmpty);
  });

  testWidgets('the app hidden → flushAll (session.flush)', (tester) async {
    final h = await pumpEditor(tester);
    expect(h.recorder!.countOf('flush'), 0);
    final binding = tester.binding;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    expect(h.recorder!.countOf('flush'), 1);

    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(h.recorder!.countOf('flush'), 2);

    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(h.closeCount, 0);
  });

  testWidgets('the last position comes back when the note opens again', (
    tester,
  ) async {
    final store = createFakeNoteStore();
    addTearDown(store.close);
    final h = await pumpEditor(tester, store: store, pages: 6);
    await _goTo(tester, h, 4);
    final zoom = h.viewport.zoom;

    await tester.tap(find.byKey(EditorToolbar.backKey));
    await tester.pump();
    await tester.pump();
    expect(h.closeCount, 1);

    await _reopen(tester, store, h.noteId);
    expect(h.viewport.currentPageIndex.value, 4);
    expect(h.viewport.zoom, closeTo(zoom, 1e-9));
  });

  testWidgets('initialPageId wins over the last position; an unknown one is '
      'ignored', (tester) async {
    final store = createFakeNoteStore();
    addTearDown(store.close);
    final h = await pumpEditor(tester, store: store, pages: 6);
    // Without anything stored: page 0.
    expect(h.viewport.currentPageIndex.value, 0);
    await _goTo(tester, h, 4);
    await tester.tap(find.byKey(EditorToolbar.backKey));
    await tester.pump();
    await tester.pump();

    await _reopen(tester, store, h.noteId, initialPageId: h.pageId(2));
    expect(h.viewport.currentPageIndex.value, 2);
    final rect = h.viewport.layout.rectOf(2);
    expect(
      h.viewport.camera.origin.dy,
      closeTo(rect.top - ViewportConstants.pageGap / 2, 1e-6),
    );
    expect(h.viewport.zoom, closeTo(1, 1e-9));

    await _reopen(tester, store, h.noteId, initialPageId: 'no-such-page');
    expect(h.viewport.currentPageIndex.value, 4);
  });
}
