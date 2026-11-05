// E-19: the more menu's 개발자 메뉴 (04-editor 6.12.4, EDITOR-S1): only while
// the developer overlay is visible; 합성 노트 만들기 → one more note in the
// fake store + snack bar; 합성 획 1,000 → current page +1,000 strokes as one
// undo step (one undo removes them); disabled on a read-only note; 진단
// 초기화 → the counters back to zero.
import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/ui/dev/dev_metrics.dart';
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:feature_editor/src/ui/toolbar/dev_menu.dart';
import 'package:feature_editor/src/ui/toolbar/more_menu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../helpers/pump_editor.dart';

const _devOn = EditorSettings(showDevOverlay: true);

Future<void> _openDevMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(EditorMoreMenu.buttonKey));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(EditorDevMenu.menuKey));
  await tester.pumpAndSettle();
}

/// Taps a MenuItemButton (onPressed runs after the next frame).
Future<void> _pick(WidgetTester tester, Key key) async {
  await tester.tap(find.byKey(key));
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('shown only while the overlay is visible', (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.byKey(EditorMoreMenu.buttonKey));
    await tester.pumpAndSettle();
    expect(find.byKey(EditorDevMenu.menuKey), findsNothing);
    await tester.tap(find.byKey(EditorMoreMenu.devOverlayKey));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(EditorMoreMenu.buttonKey));
    await tester.pumpAndSettle();
    expect(find.byKey(EditorDevMenu.menuKey), findsOneWidget);
    await tester.tap(find.byKey(EditorDevMenu.menuKey));
    await tester.pumpAndSettle();
    expect(find.text(EditorStrings.syntheticStrokes(1000)), findsOneWidget);
    expect(find.text('현재 페이지에 합성 획 3,000개'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('합성 노트 만들기 → a note in the store + snack bar', (tester) async {
    final h = await pumpEditor(tester, settings: _devOn);
    await _openDevMenu(tester);
    await _pick(tester, EditorDevMenu.seedNoteKey);
    for (var i = 0; i < 400; i++) {
      if (find
          .text(EditorStrings.seedSyntheticNoteDone)
          .evaluate()
          .isNotEmpty) {
        break;
      }
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(find.text(EditorStrings.seedSyntheticNoteDone), findsOneWidget);
    final found = await h.store.library.searchLibrary('perf-test');
    expect(found.notes.single.title, 'perf-test');
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(seconds: 1)); // the snack bar
    }
  });

  testWidgets('합성 획 1,000 → current page +1,000, one undo step', (
    tester,
  ) async {
    final h = await pumpEditor(tester, settings: _devOn);
    final id = h.pageId(0);
    final before = h.session.pageIfLoaded(id)!.strokeCount;
    final depth = h.session.history.undoDepth;
    h.recorder!.clearCalls();
    await _openDevMenu(tester);
    await _pick(tester, EditorDevMenu.strokesKey(1000));
    await tester.pump();
    expect(h.recorder!.calls, contains('executeAsync:add-strokes'));
    expect(h.session.pageIfLoaded(id)!.strokeCount, before + 1000);
    expect(h.session.history.undoDepth, depth + 1);

    final undo = h.container.read(editorCommandsProvider).undo();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await undo;
    expect(h.session.pageIfLoaded(id)!.strokeCount, before);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('read only: the stroke items are disabled, the others are not', (
    tester,
  ) async {
    final h = await pumpEditor(tester, settings: _devOn);
    await h.store.library.trashItems([core.NoteRef(h.noteId)]);
    await tester.pump();
    await _openDevMenu(tester);
    for (final n in EditorDevMenu.strokeCounts) {
      expect(
        tester
            .widget<MenuItemButton>(find.byKey(EditorDevMenu.strokesKey(n)))
            .onPressed,
        isNull,
      );
    }
    expect(
      tester
          .widget<MenuItemButton>(find.byKey(EditorDevMenu.seedNoteKey))
          .onPressed,
      isNotNull,
    );
    // The command refuses too.
    h.recorder!.clearCalls();
    await h.container.read(editorCommandsProvider).addSyntheticStrokes(10);
    expect(h.recorder!.calls.where((c) => c.contains('add-strokes')), isEmpty);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('진단 초기화 → the DevMetrics counters back to zero', (tester) async {
    final h = await pumpEditor(tester, settings: _devOn);
    final metrics = h.container.read(editorDevMetricsProvider)
      ..recordPalmRejected()
      ..recordStrokeCommitted(pointCount: 50);
    await tester.pump(const Duration(milliseconds: 300));
    expect(metrics.snapshot.palmRejectedCount, 1);
    await _openDevMenu(tester);
    await _pick(tester, EditorDevMenu.resetKey);
    await tester.pump(const Duration(milliseconds: 300));
    expect(metrics.snapshot.palmRejectedCount, 0);
    expect(metrics.snapshot.lastStrokePoints, 0);
  });
}
