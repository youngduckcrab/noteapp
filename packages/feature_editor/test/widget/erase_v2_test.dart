// E2-19 (m5-7/04-editor 6.17, 8.2 — F-09, CP-INK-2 → EDITOR-M9): the
// eraser v2 through the whole editor (PointerDriver → InputRouter →
// EraseInteraction → R2-B3 INK EraserSession → EditorCommands.commitInkEdit
// → fake CORE v2). The 1st-round cases stay in erase_test.dart.
//
// - Stroke eraser over a stroke and a shape → ONE RemoveElements with both;
//   text, image and math under the path stay (INK rule).
// - Partial eraser over a stroke and a shape → ONE CompositeCommand
//   [SplitStrokes, RemoveElements(shape)]; one undo brings back the stroke
//   (its pieces go) and the shape.
// - '도형도 지우기' off (the eraser panel switch) → the shape stays, only the
//   stroke goes; editor.eraser stores "eraseShapes": false.
// - Clear page: filter `all` shows '도형·텍스트·이미지·수식도 지우기' (on) →
//   ClearPage(includeObjects: true), one undo restores everything; unchecked
//   → objects stay; highlighter only / except highlighter → no check,
//   includeObjects false.
import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/state/popup.dart';
import 'package:feature_editor/src/state/settings/editor_setting_keys.dart';
import 'package:feature_editor/src/tools/tool_controller.dart';
import 'package:feature_editor/src/tools/tool_state.dart';
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:feature_editor/src/ui/eraser/eraser_popup.dart';
import 'package:feature_editor/src/ui/toolbar/editor_toolbar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

import '../helpers/pump_editor.dart';
import '../helpers/test_data.dart';

final core.ShapeObject _shape = PageObjectFixtures.shape(
  pageId: 'x',
  id: 'shape-1',
  rect: const core.PageRect(100, 220, 300, 280),
  createdAt: 5,
);
final core.TextBoxObject _text = PageObjectFixtures.textBox(
  pageId: 'x',
  id: 'text-1',
  rect: const core.PageRect(100, 320, 300, 360),
  createdAt: 6,
);
final core.ImageObject _image = PageObjectFixtures.image(
  pageId: 'x',
  id: 'image-1',
  assetId: 'missing-asset',
  rect: const core.PageRect(100, 400, 300, 500),
  createdAt: 7,
);
final core.MathObject _math = PageObjectFixtures.math(
  pageId: 'x',
  id: 'math-1',
  rect: const core.PageRect(100, 540, 200, 590),
  createdAt: 8,
);

const _objectIds = {'shape-1', 'text-1', 'image-1', 'math-1'};

Future<EditorTestHandles> _pump(WidgetTester tester) => pumpEditor(
  tester,
  strokesByPageIndex: {
    0: [strokeA],
  },
  objectsByPageIndex: {
    0: [_shape, _text, _image, _math],
  },
);

/// A vertical eraser path at x = 150 pt from y 100 to 620: crosses strokeA
/// (y 150), the shape, the text box, the image and the math object.
List<Offset> _acrossAll(EditorTestHandles h) =>
    pathThrough(h, 0, [for (var y = 100.0; y <= 620; y += 20) Offset(150, y)]);

List<String> _executes(EditorTestHandles h) => [
  for (final c in h.recorder!.calls)
    if (c.startsWith('execute')) c,
];

core.PageContent _page(EditorTestHandles h) =>
    h.session.pageIfLoaded(h.pageId(0))!;

Set<String> _strokeIds(EditorTestHandles h) => {
  for (final s in _page(h).strokes) s.id,
};

Set<String> _objectIdsOf(EditorTestHandles h) => {
  for (final o in _page(h).objects) o.id,
};

ToolController _tools(EditorTestHandles h) =>
    h.container.read(editorToolProvider.notifier);

void _useEraser(
  EditorTestHandles h, {
  ink.EraserMode mode = ink.EraserMode.stroke,
  core.StrokeFilter filter = core.StrokeFilter.all,
}) {
  _tools(h)
    ..selectTool(EditorTool.eraser)
    ..updateEraser((e) => e.copyWith(mode: mode, filter: filter));
}

Future<void> _undo(WidgetTester tester, EditorTestHandles h) async {
  await h.container.read(editorCommandsProvider).undo();
  await tester.pump();
}

void main() {
  test('EraserSettings.eraseShapes: default true, reaches the INK spec, '
      'JSON (missing → true)', () {
    const d = EraserSettings();
    expect(d.eraseShapes, isTrue);
    expect(d.toSpec().eraseShapes, isTrue);
    final off = d.copyWith(eraseShapes: false);
    expect(off.toSpec(), isA<ink.EraserSpec>());
    expect(off.toSpec().eraseShapes, isFalse);
    expect(off, isNot(d));
    expect(off.hashCode, isNot(d.hashCode));
    expect(off.toJson()['eraseShapes'], isFalse);
    expect(EraserSettings.fromJson(off.toJson()), off);
    // A 1st-round value has no "eraseShapes".
    final v1 = Map<String, Object?>.of(d.toJson())..remove('eraseShapes');
    final invalid = <String>[];
    expect(EraserSettings.fromJson(v1, invalidFields: invalid), d);
    expect(invalid, isEmpty);
    expect(d.toJson()['v'], 1);
  });

  testWidgets('stroke eraser over a stroke and a shape → one RemoveElements '
      'with both; text, image and math stay; one undo restores', (
    tester,
  ) async {
    final h = await _pump(tester);
    _useEraser(h);
    await h.driver.stylusStroke(_acrossAll(h));

    expect(_executes(h), ['execute:remove-elements']);
    final command = h.recorder!.commands.single as core.RemoveElements;
    expect(command.pageId, h.pageId(0));
    expect(command.elementIds.toSet(), {strokeA.id, 'shape-1'});
    expect(h.session.history.undoDepth, 1);
    expect(_strokeIds(h), isEmpty);
    expect(_objectIdsOf(h), {'text-1', 'image-1', 'math-1'});
    expect(h.controllerOf(0).pendingIds, isEmpty);

    await _undo(tester, h);
    expect(_strokeIds(h), {strokeA.id});
    expect(_objectIdsOf(h), _objectIds);
    expect(h.session.history.undoDepth, 0);
  });

  testWidgets('partial eraser over a stroke and a shape → ONE '
      'CompositeCommand [SplitStrokes, RemoveElements(shape)]; one undo '
      'brings back the stroke and the shape', (tester) async {
    final h = await _pump(tester);
    _useEraser(h, mode: ink.EraserMode.partial);
    await h.driver.stylusStroke(_acrossAll(h));

    expect(_executes(h), ['execute:composite']);
    final composite = h.recorder!.commands.single as core.CompositeCommand;
    expect(composite.commands, hasLength(2));
    final split = composite.commands[0] as core.SplitStrokes;
    expect(split.pageId, h.pageId(0));
    expect(split.removedIds, [strokeA.id]);
    expect(split.added, hasLength(2)); // the pieces left and right of x 150
    final remove = composite.commands[1] as core.RemoveElements;
    expect(remove.elementIds, ['shape-1']);
    expect(h.session.history.undoDepth, 1);
    expect(h.session.history.undoLabel, 'composite');

    final pieces = {for (final s in split.added) s.id};
    expect(_strokeIds(h), pieces);
    expect(_objectIdsOf(h), {'text-1', 'image-1', 'math-1'});
    expect(h.controllerOf(0).pendingIds, isEmpty);
    expect(h.recorder!.executeDuringDelivery, isFalse);

    await _undo(tester, h);
    expect(_strokeIds(h), {strokeA.id});
    expect(_objectIdsOf(h), _objectIds);
    expect(h.session.history.undoDepth, 0);
    expect(
      {for (final s in h.controllerOf(0).content!.strokes) s.id},
      {strokeA.id},
    );
    expect(
      {for (final o in h.controllerOf(0).content!.objects) o.id},
      {..._objectIds},
    );
  });

  testWidgets('partial eraser over a shape only → RemoveElements alone '
      '(the empty side is left out)', (tester) async {
    final h = await _pump(tester);
    _useEraser(h, mode: ink.EraserMode.partial);
    // The shape has no fill, so the eraser takes it only where the path
    // crosses its outline (03-ink 6.15, U22): a vertical path at x = 250
    // through the top (y 220) and bottom (y 280) edges, clear of strokeA
    // (y 150) and the text box (y 320).
    await h.driver.stylusStroke(
      pathThrough(h, 0, [
        for (var y = 200.0; y <= 300; y += 10) Offset(250, y),
      ]),
    );
    expect(_executes(h), ['execute:remove-elements']);
    expect((h.recorder!.commands.single as core.RemoveElements).elementIds, [
      'shape-1',
    ]);
    expect(_strokeIds(h), {strokeA.id});
  });

  for (final mode in ink.EraserMode.values) {
    testWidgets('${mode.name} mode, 도형도 지우기 off (panel switch) → the '
        'shape stays; editor.eraser stores it', (tester) async {
      final h = await _pump(tester);
      await tester.tap(find.byKey(EditorToolbar.eraserKey)); // select
      await tester.pump();
      await tester.tap(find.byKey(EditorToolbar.eraserKey)); // → popup
      await tester.pump();
      final toggle = find.byKey(EraserSettingsPanel.eraseShapesKey);
      expect(toggle, findsOneWidget);
      expect(find.text(EditorStrings.eraseShapes), findsOneWidget);
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
      await tester.ensureVisible(toggle);
      await tester.pump();
      await tester.tap(toggle);
      await tester.pump();
      final eraser = h.container.read(editorToolProvider).eraser;
      expect(eraser.eraseShapes, isFalse);
      expect(eraser.toSpec().eraseShapes, isFalse);
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);

      await tester.pump(const Duration(milliseconds: 600)); // 500 ms debounce
      final stored = await h.store.settings.get(EditorSettingKeys.eraser);
      expect(stored['eraseShapes'], isFalse);
      expect(stored['v'], 1);

      h.container.read(editorPopupProvider.notifier).close();
      _tools(h).updateEraser((e) => e.copyWith(mode: mode));
      await tester.pump();
      await h.driver.stylusStroke(_acrossAll(h));
      expect(_executes(h), [
        mode == ink.EraserMode.stroke
            ? 'execute:remove-strokes'
            : 'execute:split-strokes',
      ]);
      expect(_objectIdsOf(h), _objectIds);
      expect(_strokeIds(h), isNot(contains(strokeA.id)));
    });
  }

  group('clear the current page', () {
    /// The eraser popup's '현재 페이지 지우기' ((v2.14-ui) the more menu's copy
    /// is gone).
    Future<void> openDialog(WidgetTester tester, EditorTestHandles h) async {
      await tester.longPress(find.byKey(EditorToolbar.eraserKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(EraserSettingsPanel.clearPageKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(ClearPageDialog), findsOneWidget);
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    core.ClearPage clearPageOf(EditorTestHandles h) =>
        h.recorder!.commands.whereType<core.ClearPage>().single;

    testWidgets('filter all: the objects check is on → ClearPage('
        'includeObjects: true) one step; one undo restores everything', (
      tester,
    ) async {
      final h = await _pump(tester);
      await openDialog(tester, h);
      final check = find.byKey(ClearPageDialog.includeObjectsKey);
      expect(check, findsOneWidget);
      expect(find.text(EditorStrings.clearPageIncludeObjects), findsOneWidget);
      expect(tester.widget<CheckboxListTile>(check).value, isTrue);

      await tester.tap(find.byKey(ClearPageDialog.confirmKey));
      await settle(tester);
      expect(find.byType(ClearPageDialog), findsNothing);
      expect(_executes(h), ['executeAsync:clear-page']);
      final clear = clearPageOf(h);
      expect(clear.pageId, h.pageId(0));
      expect(clear.filter, core.StrokeFilter.all);
      expect(clear.includeObjects, isTrue);
      expect(h.session.history.undoDepth, 1);
      expect(_strokeIds(h), isEmpty);
      expect(_objectIdsOf(h), isEmpty);
      expect(h.controllerOf(0).content!.objects, isEmpty);

      await _undo(tester, h);
      expect(_strokeIds(h), {strokeA.id});
      expect(_objectIdsOf(h), _objectIds);
      expect(h.session.history.undoDepth, 0);
    });

    testWidgets('unchecked → includeObjects false: the objects stay', (
      tester,
    ) async {
      final h = await _pump(tester);
      await openDialog(tester, h);
      await tester.tap(find.byKey(ClearPageDialog.includeObjectsKey));
      await tester.pump();
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(ClearPageDialog.includeObjectsKey),
            )
            .value,
        isFalse,
      );
      await tester.tap(find.byKey(ClearPageDialog.confirmKey));
      await settle(tester);
      expect(clearPageOf(h).includeObjects, isFalse);
      expect(_strokeIds(h), isEmpty);
      expect(_objectIdsOf(h), _objectIds);
    });

    for (final filter in [
      core.StrokeFilter.highlighterOnly,
      core.StrokeFilter.exceptHighlighter,
    ]) {
      testWidgets('filter ${filter.name}: no objects check, '
          'includeObjects false', (tester) async {
        final h = await _pump(tester);
        _tools(h).updateEraser((e) => e.copyWith(filter: filter));
        await tester.pump();
        await openDialog(tester, h);
        expect(find.byType(ClearPageDialog), findsOneWidget);
        expect(find.byKey(ClearPageDialog.includeObjectsKey), findsNothing);
        expect(find.text(EditorStrings.clearPageIncludeObjects), findsNothing);
        await tester.tap(find.byKey(ClearPageDialog.confirmKey));
        await settle(tester);
        final clear = clearPageOf(h);
        expect(clear.filter, filter);
        expect(clear.includeObjects, isFalse);
        expect(_objectIdsOf(h), _objectIds);
      });
    }

    testWidgets('cancel → no command', (tester) async {
      final h = await _pump(tester);
      await openDialog(tester, h);
      await tester.tap(find.byKey(ClearPageDialog.cancelKey));
      await settle(tester);
      expect(_executes(h), isEmpty);
      expect(_objectIdsOf(h), _objectIds);
    });
  });
}
