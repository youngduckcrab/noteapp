// E-13: read-only notes (04-editor 6.17.2, N-4): the banner, tools and
// undo / redo disabled, scrolling still works, and a note trashed while open
// switches at once (a running stroke is cancelled).
import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/state/panel.dart';
import 'package:feature_editor/src/state/popup.dart';
import 'package:feature_editor/src/ui/banners/read_only_banner.dart';
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:feature_editor/src/ui/toolbar/editor_toolbar.dart';
import 'package:feature_editor/src/ui/toolbar/mic_button.dart';
import 'package:feature_editor/src/ui/toolbar/tool_button.dart';
import 'package:feature_editor/src/ui/toolbar/undo_redo_buttons.dart';
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

/// (v2.15-ui) The pen and the eraser are pen tray slots: the tray ignores
/// pointers on a read-only note.
bool _toolEnabled(WidgetTester tester, Key key) {
  if (key == EditorToolbar.penKey || key == EditorToolbar.eraserKey) {
    return find
        .ancestor(
          of: find.byKey(key),
          matching: find.byWidgetPredicate(
            (w) => w is IgnorePointer && w.ignoring,
          ),
        )
        .evaluate()
        .isEmpty;
  }
  return tester.widget<ToolButton>(find.byKey(key)).onTap != null;
}

void _expectReadOnlyUi(WidgetTester tester) {
  expect(find.byKey(ReadOnlyBanner.bannerKey), findsOneWidget);
  expect(find.text(EditorStrings.readOnlyTrashed), findsOneWidget);
  for (final key in [
    EditorToolbar.penKey,
    EditorToolbar.eraserKey,
    EditorToolbar.lassoKey,
  ]) {
    expect(_toolEnabled(tester, key), isFalse, reason: '$key');
  }
  for (final key in [UndoRedoButtons.undoKey, UndoRedoButtons.redoKey]) {
    expect(tester.widget<IconButton>(find.byKey(key)).onPressed, isNull);
  }
}

void main() {
  testWidgets('a trashed note: banner, tools and undo disabled, scrolling '
      'works, the pen draws nothing', (tester) async {
    final store = createFakeNoteStore();
    addTearDown(store.close);
    final first = await pumpEditor(tester, store: store);
    await first.driver.stylusStroke(pathThrough(first, 0, _points));
    await store.library.trashItems([core.NoteRef(first.noteId)]);
    await tester.pumpWidget(const SizedBox());

    // Opened again from the trash.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [core.noteStoreProvider.overrideWithValue(store)],
        child: MaterialApp(
          home: EditorScreen(
            key: ValueKey(first.noteId),
            noteId: first.noteId,
            onClose: () {},
          ),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    final h = first; // same note: the handles read the current tree
    expect(h.container.read(editorReadOnlyProvider), isTrue);
    _expectReadOnlyUi(tester);

    final camera = h.viewport.camera;
    await h.driver.wheel(pageCenterOf(h, 0), const Offset(0, 300));
    await tester.pump(const Duration(milliseconds: 200));
    expect(h.viewport.camera.origin.dy, greaterThan(camera.origin.dy));

    final session = h.container.read(editorSessionValueProvider);
    final before = session.pageIfLoaded(h.pageId(0))!.strokes.length;
    expect(before, 1);
    await h.driver.stylusStroke(
      pathThrough(h, 0, [for (final p in _points) p + const Offset(0, 80)]),
    );
    expect(session.pageIfLoaded(h.pageId(0))!.strokes, hasLength(before));
    expect(session.history.undoDepth, 0);
  });

  testWidgets('trashed while open → read only at once; the running stroke '
      'is cancelled and the popup closes', (tester) async {
    final h = await pumpEditor(tester);
    expect(find.byKey(ReadOnlyBanner.bannerKey), findsNothing);
    expect(_toolEnabled(tester, EditorToolbar.penKey), isTrue);
    final points = pathThrough(h, 0, _points);
    await h.driver.down(1, points[0], kind: PointerDeviceKind.stylus);
    await h.driver.move(1, points[1]);
    h.container.read(editorPopupProvider.notifier).open(const QuickPenPopup());
    await tester.pump();
    expect(
      h.container.read(editorInputRouterProvider).hasActiveInteraction,
      isTrue,
    );

    await h.store.library.trashItems([core.NoteRef(h.noteId)]);
    await tester.pump();
    expect(h.container.read(editorReadOnlyProvider), isTrue);
    expect(
      h.container.read(editorInputRouterProvider).hasActiveInteraction,
      isFalse,
    );
    expect(h.container.read(editorPopupProvider), isNull);
    _expectReadOnlyUi(tester);

    await h.driver.move(1, points[2]);
    await h.driver.up(1);
    expect(h.recorder!.calls.where((c) => c.startsWith('execute')), isEmpty);

    // Restored → editable again.
    await h.store.trash.restore([core.NoteRef(h.noteId)]);
    await tester.pump();
    expect(find.byKey(ReadOnlyBanner.bannerKey), findsNothing);
    expect(_toolEnabled(tester, EditorToolbar.penKey), isTrue);
  });

  testWidgets('(v2.15-ui review) a read-only note keeps [🎤]: its '
      'recordings can be played ([+] is disabled there)', (tester) async {
    final h = await pumpEditor(
      tester,
      extensions: EditorExtensions(
        recordingPanel: (context, panel) => const SizedBox(),
      ),
    );
    expect(find.byKey(MicButton.micKey), findsNothing, reason: 'in [+]');
    await h.store.library.trashItems([core.NoteRef(h.noteId)]);
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    expect(h.container.read(editorReadOnlyProvider), isTrue);
    expect(find.byKey(MicButton.micKey).hitTestable(), findsOneWidget);
    await tester.tap(find.byKey(MicButton.micKey));
    await tester.pump();
    expect(h.container.read(editorPanelProvider), isTrue);
  });
}
