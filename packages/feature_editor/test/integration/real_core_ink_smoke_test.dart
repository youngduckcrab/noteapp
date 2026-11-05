// E-21 (integration stage, contract 7.7 step 5): real CORE + real INK smoke.
//
// Skipped by default: dart_test.yaml gives the `integration` tag a skip reason,
// so the plain `flutter test` / `ws test` run reports this suite as skipped.
// It runs only with `ws test --run-skipped -t integration` once CORE (T6,
// openTestNoteStore) and INK are merged. Until then openTestNoteStore throws
// UnimplementedError (B2), so a forced run here fails — that is expected.
//
// This file is the E-21 skeleton written during E-00. The full scenario of
// 04-editor 8.2 E-21 (3 pen strokes → partial erase → undo → lasso move →
// close → reopen) is filled in when the editor body (E-08..E-13) exists.
@Tags(['integration'])
@TestOn('vm')
library;

import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing_vm.dart';

void main() {
  testWidgets('real CORE: open a note, see the notDurable banner, close', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2064, 2752);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    // Real drift streams use real timers: open and close inside runAsync.
    final store = (await tester.runAsync(openTestNoteStore))!;
    final note = (await tester.runAsync(
      () => store.library.createNote(title: '통합 스모크'),
    ))!;

    var closed = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [core.noteStoreProvider.overrideWithValue(store)],
        child: MaterialApp(
          home: EditorScreen(noteId: note.id, onClose: () => closed++),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(find.text('통합 스모크'), findsOneWidget);
    // In-memory real CORE = nativeMemory → notDurable (contract 7.2.12).
    expect(find.text(EditorStrings.storageNotDurable), findsOneWidget);

    await tester.tap(find.bySemanticsLabel(EditorStrings.back));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(closed, 1);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(store.close);
  });
}
