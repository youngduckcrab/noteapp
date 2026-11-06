// m5-7/04-editor 8.2 E2-09 (part 2), 6.9.1 / 6.7.5: the shape tool popup
// and a selected shape's '스타일' (fake CORE, R2-B3 INK). The popup's values
// go to editorToolOptionsProvider and, 500 ms later, to `editor.toolOptions`
// (synced); the next shape is drawn with them; 3 selected shapes recoloured
// → ONE UpdateObjects (each keeps its own width); a line has no fill row,
// only the arrowhead row; a read-only note disables '스타일'.
import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/state/popup.dart';
import 'package:feature_editor/src/state/settings/editor_setting_keys.dart';
import 'package:feature_editor/src/tools/selection.dart';
import 'package:feature_editor/src/tools/tool_controller.dart';
import 'package:feature_editor/src/tools/tool_options.dart';
import 'package:feature_editor/src/tools/tool_state.dart';
import 'package:feature_editor/src/ui/overlays/selection_menu.dart';
import 'package:feature_editor/src/ui/shape/shape_style_controls.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

import '../helpers/pump_editor.dart';

const int _red = 0xFFE53935;
const int _blue = 0xFF1E88E5;

core.ShapeObject _shape(
  String id,
  core.ShapeKind kind,
  core.PageRect rect,
  double width,
) {
  final s = PageObjectFixtures.shape(
    pageId: 'x',
    id: id,
    kind: kind,
    rect: rect,
  );
  return s.copyWith(style: s.style.copyWith(strokeWidth: width));
}

final core.ShapeObject _rect = _shape(
  'rect-1',
  core.ShapeKind.rectangle,
  const core.PageRect(100, 120, 220, 200),
  2,
);
final core.ShapeObject _ellipse = _shape(
  'ellipse-1',
  core.ShapeKind.ellipse,
  const core.PageRect(260, 120, 380, 200),
  4,
);
final core.ShapeObject _star = _shape(
  'star-1',
  core.ShapeKind.star,
  const core.PageRect(100, 240, 220, 340),
  6,
);
final core.ShapeObject _line = _shape(
  'line-1',
  core.ShapeKind.line,
  const core.PageRect(260, 260, 380, 320),
  3,
);
final core.TextBoxObject _text = PageObjectFixtures.textBox(
  pageId: 'x',
  id: 'text-1',
  rect: const core.PageRect(100, 400, 300, 440),
);

Future<EditorTestHandles> _pump(WidgetTester tester) async {
  final h = await pumpEditor(
    tester,
    objectsByPageIndex: {
      0: [_rect, _ellipse, _star, _line, _text],
    },
  );
  h.container.read(editorCommandsProvider).selectTool(EditorTool.lasso);
  await tester.pump();
  return h;
}

Future<void> _select(
  WidgetTester tester,
  EditorTestHandles h,
  Set<String> ids,
) async {
  h.container.read(editorSelectionProvider.notifier).select(h.pageId(0), ids);
  await tester.pump();
}

List<String> _edits(EditorTestHandles h) => [
  for (final c in h.recorder!.calls)
    if (c.startsWith('execute')) c,
];

core.ShapeObject _stored(EditorTestHandles h, String id) =>
    h.session.pageIfLoaded(h.pageId(0))!.objectById(id)! as core.ShapeObject;

ToolOptions _options(EditorTestHandles h) =>
    h.container.read(editorToolOptionsProvider);

Future<void> _tapKey(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pump();
  await tester.tap(find.byKey(key));
  await tester.pump();
}

Future<void> _openStyle(WidgetTester tester) async {
  await tester.tap(find.byKey(SelectionMenu.moreKey));
  await tester.pump();
  await tester.tap(find.byKey(SelectionMenu.styleKey));
  await tester.pump();
  expect(find.byKey(ShapeStylePanel.panelKey), findsOneWidget);
}

void main() {
  testWidgets('the tool popup: kind, colour, dash, fill, width, star points '
      '→ editorToolOptionsProvider → `editor.toolOptions` (synced, 500 ms); '
      'the next shape uses them', (tester) async {
    final h = await _pump(tester);
    h.container.read(editorCommandsProvider).selectTool(EditorTool.shape);
    h.container.read(editorPopupProvider.notifier).open(const ShapeToolPopup());
    await tester.pump();
    expect(find.byKey(ShapeToolPanel.panelKey), findsOneWidget);
    for (final kind in core.ShapeKind.values) {
      expect(find.byKey(ShapeToolPanel.kindKey(kind)), findsOneWidget);
    }

    await _tapKey(tester, ShapeToolPanel.kindKey(core.ShapeKind.star));
    expect(_options(h).shapeKind, core.ShapeKind.star);
    await _tapKey(tester, ShapeToolPanel.countPlusKey);
    expect(_options(h).starPoints, 6);
    await _tapKey(tester, ShapeStyleControls.strokeKey(_red));
    expect(_options(h).shapeStyle.strokeColorArgb, _red);
    await _tapKey(tester, ShapeStyleControls.dashKey(core.LineDash.dashed));
    expect(_options(h).shapeStyle.dash, core.LineDash.dashed);
    await _tapKey(tester, ShapeStyleControls.fillKey(_blue));
    expect(_options(h).shapeStyle.fillColorArgb, _blue);
    expect(find.byKey(ShapeStyleControls.arrowRowKey), findsNothing);

    // The width: applied when the slider is let go.
    await tester.ensureVisible(find.byKey(ShapeStyleControls.widthKey));
    await tester.pump();
    final slider = tester.getRect(find.byKey(ShapeStyleControls.widthKey));
    final gesture = await tester.startGesture(
      slider.centerLeft + const Offset(24, 0),
      pointer: 77,
    );
    await gesture.moveTo(slider.center);
    await tester.pump();
    expect(_options(h).shapeStyle.strokeWidth, 2); // not yet
    await gesture.up();
    await tester.pump();
    final width = _options(h).shapeStyle.strokeWidth;
    expect(width, greaterThan(10));
    expect(width, lessThan(20));

    // '펜 색 쓰기' → the current pen colour.
    await _tapKey(tester, ShapeStyleControls.penColorKey);
    final pen = h.container.read(editorToolProvider).currentPen.colorArgb;
    expect(_options(h).shapeStyle.strokeColorArgb, 0xFF000000 | pen);

    await tester.pump(const Duration(milliseconds: 600)); // 500 ms debounce
    expect(EditorSettingKeys.toolOptions.scope, core.SettingScope.synced);
    final stored = await h.store.settings.get(EditorSettingKeys.toolOptions);
    final shape = stored['shape']! as Map<String, Object?>;
    expect(shape['kind'], 'star');
    expect(shape['points'], 6);
    final style = core.ShapeStyle.fromJson(
      (shape['style']! as Map).cast<String, Object?>(),
    );
    expect(style.dash, core.LineDash.dashed);
    expect(style.fillColorArgb, _blue);
    expect(style.strokeWidth, width);

    // The next shape: a 6-point dashed star filled blue.
    h.container.read(editorPopupProvider.notifier).close();
    await tester.pump();
    final before = {
      for (final o in h.session.pageIfLoaded(h.pageId(0))!.objects) o.id,
    };
    final from = h.toGlobal(0, const Offset(300, 500));
    await h.driver.down(1, from, kind: PointerDeviceKind.stylus);
    await h.driver.move(1, from + const Offset(60, 40));
    await h.driver.move(1, from + const Offset(120, 100));
    await h.driver.up(1);
    await tester.pump();
    final drawn =
        h.session
                .pageIfLoaded(h.pageId(0))!
                .objects
                .where((o) => !before.contains(o.id))
                .single
            as core.ShapeObject;
    expect(drawn.shapeKind, core.ShapeKind.star);
    expect((drawn.geometry as core.PolylineGeometry).points, hasLength(12));
    expect(drawn.style.dash, core.LineDash.dashed);
    expect(drawn.style.fillColorArgb, _blue);
  });

  testWidgets('3 selected shapes recoloured with 스타일 → ONE UpdateObjects; '
      'each keeps its own width; a dash change → one more step', (
    tester,
  ) async {
    final h = await _pump(tester);
    await _select(tester, h, {_rect.id, _ellipse.id, _star.id});
    await _openStyle(tester);
    // Not all lines: the fill row, no arrowhead row.
    expect(find.byKey(ShapeStyleControls.fillRowKey), findsOneWidget);
    expect(find.byKey(ShapeStyleControls.arrowRowKey), findsNothing);
    expect(find.byKey(ShapeStyleControls.penColorKey), findsNothing);

    await _tapKey(tester, ShapeStyleControls.strokeKey(_red));
    expect(_edits(h), ['execute:update-objects']);
    expect(h.session.history.undoDepth, 1);
    for (final (shape, width) in [
      (_rect, 2.0),
      (_ellipse, 4.0),
      (_star, 6.0),
    ]) {
      final s = _stored(h, shape.id);
      expect(s.style.strokeColorArgb, _red, reason: shape.id);
      expect(s.style.strokeWidth, width, reason: shape.id);
      expect(s.geometry.toJson(), shape.geometry.toJson(), reason: shape.id);
    }
    // The selection and the popup stay.
    expect(h.container.read(editorSelectionProvider)!.elementIds, {
      _rect.id,
      _ellipse.id,
      _star.id,
    });
    expect(find.byKey(ShapeStylePanel.panelKey), findsOneWidget);

    await _tapKey(tester, ShapeStyleControls.dashKey(core.LineDash.dotted));
    expect(_edits(h), ['execute:update-objects', 'execute:update-objects']);
    expect(_stored(h, _ellipse.id).style.dash, core.LineDash.dotted);
    expect(_stored(h, _ellipse.id).style.strokeColorArgb, _red);

    // One undo takes back the dash only.
    await h.container.read(editorCommandsProvider).undo();
    await tester.pump();
    expect(_stored(h, _ellipse.id).style.dash, core.LineDash.solid);
    expect(_stored(h, _ellipse.id).style.strokeColorArgb, _red);
  });

  testWidgets('a line: no fill row, the arrowhead row → UpdateObjects', (
    tester,
  ) async {
    final h = await _pump(tester);
    await _select(tester, h, {_line.id});
    await _openStyle(tester);
    expect(find.byKey(ShapeStyleControls.fillRowKey), findsNothing);
    expect(find.byKey(ShapeStyleControls.fillNoneKey), findsNothing);
    expect(find.byKey(ShapeStyleControls.arrowRowKey), findsOneWidget);
    await _tapKey(tester, ShapeStyleControls.arrowKey(core.ArrowHeads.both));
    expect(_edits(h), ['execute:update-objects']);
    expect(_stored(h, _line.id).style.arrowHeads, core.ArrowHeads.both);
    expect(_stored(h, _line.id).shapeKind, core.ShapeKind.line);

    // The tool popup with the line kind: the same rule.
    h.container.read(editorPopupProvider.notifier).close();
    h.container
        .read(editorToolOptionsProvider.notifier)
        .setShapeKind(core.ShapeKind.line);
    h.container.read(editorPopupProvider.notifier).open(const ShapeToolPopup());
    await tester.pump();
    expect(find.byKey(ShapeStyleControls.fillRowKey), findsNothing);
    expect(find.byKey(ShapeStyleControls.arrowRowKey), findsOneWidget);
  });

  testWidgets("'스타일' only for shapes; a read-only note disables it", (
    tester,
  ) async {
    final h = await _pump(tester);
    await _select(tester, h, {_rect.id, _text.id}); // not shapes only
    await tester.tap(find.byKey(SelectionMenu.moreKey));
    await tester.pump();
    expect(find.byKey(SelectionMenu.styleKey), findsNothing);
    await tester.tap(find.byKey(SelectionMenu.moreKey));
    await tester.pump();

    await _select(tester, h, {_rect.id});
    await tester.tap(find.byKey(SelectionMenu.moreKey));
    await tester.pump();
    expect(find.byKey(SelectionMenu.styleKey), findsOneWidget);
    await tester.tap(find.byKey(SelectionMenu.moreKey));
    await tester.pump();

    await h.store.library.trashItems([core.NoteRef(h.noteId)]);
    await tester.pump();
    await tester.tap(find.byKey(SelectionMenu.moreKey));
    await tester.pump();
    final item = tester.widget<TextButton>(
      find.descendant(
        of: find.byKey(SelectionMenu.styleKey),
        matching: find.byType(TextButton),
      ),
    );
    expect(item.onPressed, isNull);
  });
}
