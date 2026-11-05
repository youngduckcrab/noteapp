// E-13: per-note provider scopes (04-editor 6.13.1 #3, #4): two editor
// screens for two notes keep their selection, popup and per-note objects
// apart. The page panel state joins with E-17.
import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/state/popup.dart';
import 'package:feature_editor/src/tools/selection.dart';
import 'package:feature_editor/src/ui/pen/quick_pen_popup.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

import '../helpers/test_data.dart';

/// The innermost ProviderScope container under the screen of [noteId].
ProviderContainer _containerOf(WidgetTester tester, String noteId) {
  final scopes = find.descendant(
    of: find.byKey(ValueKey(noteId)),
    matching: find.byType(UncontrolledProviderScope),
  );
  return tester.widget<UncontrolledProviderScope>(scopes.last).container;
}

void main() {
  testWidgets('two note screens: selection, popup, session, viewport and '
      'commands are separate', (tester) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(2752, 2064); // landscape 1376×1032
    addTearDown(tester.view.reset);
    final store = createFakeNoteStore();
    addTearDown(store.close);
    final a = await store.library.createNote(title: 'A');
    final b = await store.library.createNote(title: 'B');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [core.noteStoreProvider.overrideWithValue(store)],
        child: MaterialApp(
          home: Row(
            children: [
              for (final note in [a, b])
                Expanded(
                  child: EditorScreen(
                    key: ValueKey(note.id),
                    noteId: note.id,
                    onClose: () {},
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    final ca = _containerOf(tester, a.id);
    final cb = _containerOf(tester, b.id);
    expect(identical(ca, cb), isFalse);

    // Per-note objects are distinct.
    final sa = ca.read(editorSessionValueProvider);
    final sb = cb.read(editorSessionValueProvider);
    expect(sa.noteId, a.id);
    expect(sb.noteId, b.id);
    Object read(ProviderContainer c, int i) => switch (i) {
      0 => c.read(editorViewportProvider),
      1 => c.read(editorCommandsProvider),
      2 => c.read(editorInteractionHostProvider),
      3 => c.read(editorInputRouterProvider),
      _ => c.read(editorMountedPagesProvider),
    };
    for (var i = 0; i < 5; i++) {
      expect(identical(read(ca, i), read(cb, i)), isFalse, reason: '#$i');
    }

    // Selection in A only.
    final stroke = lineStroke(
      id: 'sa1',
      pageId: sa.pages.first.id,
      x0: 50,
      y0: 50,
      x1: 120,
      y1: 80,
    );
    sa.execute(core.AddStrokes(pageId: sa.pages.first.id, strokes: [stroke]));
    await tester.pump();
    ca.read(editorSelectionProvider.notifier).select(sa.pages.first.id, {
      stroke.id,
    });
    await tester.pump();
    expect(ca.read(editorSelectionProvider)?.strokeIds, {stroke.id});
    expect(cb.read(editorSelectionProvider), isNull);

    // Popup in B only.
    cb.read(editorPopupProvider.notifier).open(const QuickPenPopup());
    await tester.pump();
    expect(cb.read(editorPopupProvider), const QuickPenPopup());
    expect(ca.read(editorPopupProvider), isNull);
    expect(find.byKey(QuickPenPanel.panelKey), findsOneWidget);

    // Read-only state follows each note.
    await store.library.trashItems([core.NoteRef(b.id)]);
    await tester.pump();
    expect(cb.read(editorReadOnlyProvider), isTrue);
    expect(ca.read(editorReadOnlyProvider), isFalse);
    await tester.pump(const Duration(seconds: 3));
  });
}
