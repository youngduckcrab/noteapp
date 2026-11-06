// m5-7/04-editor 8.2 E2-07b, 6.7.2: the selection menu's '색 ●' → the
// recolor popup (fake CORE, R2-B3 INK). A colour tap is ONE step through
// commitInkEdit(controller, sel.recolor(argb)) — RestyleStrokes for strokes,
// UpdateObjects for shapes / text / math, their CompositeCommand for both;
// the popup closes, the selection stays, the colour goes to the front of the
// recent colours. Images are left out (INK). A rejected commit → discardEdit
// (nothing pending), the colours as they were, the selection stays.
import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/state/color_palette.dart';
import 'package:feature_editor/src/state/popup.dart';
import 'package:feature_editor/src/tools/selection.dart';
import 'package:feature_editor/src/tools/tool_controller.dart';
import 'package:feature_editor/src/tools/tool_state.dart';
import 'package:feature_editor/src/ui/color/color_picker_panel.dart';
import 'package:feature_editor/src/ui/color/hex_rgb_fields.dart';
import 'package:feature_editor/src/ui/color/recolor_panel.dart';
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:feature_editor/src/ui/overlays/selection_menu.dart';
import 'package:feature_editor/src/ui/popup_host.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

import '../helpers/pump_editor.dart';
import '../helpers/test_data.dart';

const int _red = 0xFFE53935;
const int _blue = 0xFF1E88E5;

final core.ShapeObject _shape = PageObjectFixtures.shape(
  pageId: 'x',
  id: 'shape-1',
  rect: const core.PageRect(300, 120, 420, 200),
  createdAt: 5,
);

final core.TextBoxObject _text = PageObjectFixtures.textBox(
  pageId: 'x',
  id: 'text-1',
  rect: const core.PageRect(300, 300, 480, 340),
  createdAt: 6,
);

final core.ImageObject _image = PageObjectFixtures.image(
  pageId: 'x',
  id: 'image-1',
  assetId: 'asset-7',
  rect: const core.PageRect(300, 450, 450, 560),
  createdAt: 7,
);

final core.MathObject _math = PageObjectFixtures.math(
  pageId: 'x',
  id: 'math-1',
  rect: const core.PageRect(120, 600, 220, 650),
  createdAt: 8,
);

Future<EditorTestHandles> _pump(WidgetTester tester) async {
  final h = await pumpEditor(
    tester,
    strokesByPageIndex: {
      0: [strokeA, strokeB],
    },
    objectsByPageIndex: {
      0: [_shape, _text, _image, _math],
    },
  );
  h.container.read(editorCommandsProvider).selectTool(EditorTool.lasso);
  // Two recent colours to pick from (newest first: blue, red).
  h.container.read(editorColorPaletteProvider.notifier)
    ..pushRecent(_red)
    ..pushRecent(_blue);
  await tester.pump();
  return h;
}

Future<void> _select(
  WidgetTester tester,
  EditorTestHandles h,
  Set<String> ids,
) async {
  h.container
      .read(editorSelectionProvider.notifier)
      .select(h.pageId(0), ids, origin: SelectionOrigin.lasso);
  await tester.pump();
}

List<String> _edits(EditorTestHandles h) => [
  for (final c in h.recorder!.calls)
    if (c.startsWith('execute')) c,
];

core.PageContent _page(EditorTestHandles h) =>
    h.session.pageIfLoaded(h.pageId(0))!;

int _strokeColour(EditorTestHandles h, String id) =>
    _page(h).strokeById(id)!.style.colorArgb;

int _shapeColour(EditorTestHandles h) =>
    (_page(h).objectById(_shape.id)! as core.ShapeObject).style.strokeColorArgb;

int _textColour(EditorTestHandles h) =>
    (_page(h).objectById(_text.id)! as core.TextBoxObject).style.colorArgb;

int _mathColour(EditorTestHandles h) =>
    (_page(h).objectById(_math.id)! as core.MathObject).style.colorArgb;

Future<void> _openRecolor(WidgetTester tester) async {
  await tester.tap(find.byKey(SelectionMenu.colorKey));
  await tester.pump();
  expect(find.byKey(RecolorPanel.panelKey), findsOneWidget);
}

Future<void> _pick(WidgetTester tester, int argb) async {
  await tester.tap(find.byKey(RecolorPanel.swatchKey(argb)));
  await tester.pump();
  await tester.pump();
}

int _dotColour(WidgetTester tester) {
  final box = tester.widget<Container>(find.byKey(SelectionMenu.colorDotKey));
  return (box.decoration! as BoxDecoration).color!.toARGB32();
}

void main() {
  testWidgets('shape + text + stroke + math → ONE composite step (restyle + '
      'update-objects); the popup closes, the selection stays, the colour '
      'leads the recent colours; one undo restores all', (tester) async {
    final h = await _pump(tester);
    final ids = {strokeA.id, _shape.id, _text.id, _math.id};
    await _select(tester, h, ids);
    await _openRecolor(tester);
    // Title, the recent row (blue, red — appendix C keys), '더 보기'.
    expect(find.text(EditorStrings.selectionColor), findsWidgets);
    expect(find.byKey(RecolorPanel.swatchKey(_blue)), findsOneWidget);
    expect(find.byKey(RecolorPanel.swatchKey(_red)), findsOneWidget);
    expect(find.byKey(RecolorPanel.moreKey), findsOneWidget);
    expect(
      RecolorPanel.swatchKey(_red),
      const ValueKey('editor.recolor.swatch.ffe53935'),
    );

    await _pick(tester, _red);

    expect(_edits(h), ['execute:composite']);
    expect(h.session.history.undoDepth, 1);
    expect(_strokeColour(h, strokeA.id), _red);
    expect(_shapeColour(h), _red);
    expect(_textColour(h), _red);
    expect(_mathColour(h), _red);
    expect(_strokeColour(h, strokeB.id), strokeB.style.colorArgb); // not in it
    expect(h.container.read(editorPopupProvider), isNull);
    expect(find.byKey(RecolorPanel.panelKey), findsNothing);
    expect(h.container.read(editorSelectionProvider)!.elementIds, ids);
    expect(h.controllerOf(0).selection!.allIds, ids);
    expect(h.controllerOf(0).pendingIds, isEmpty);
    expect(h.container.read(editorColorPaletteProvider).recent.first, _red);
    expect(_dotColour(tester), _red); // the bar follows the new colour

    await h.container.read(editorCommandsProvider).undo();
    await tester.pump();
    expect(_strokeColour(h, strokeA.id), strokeA.style.colorArgb);
    expect(_shapeColour(h), _shape.style.strokeColorArgb);
    expect(_textColour(h), _text.style.colorArgb);
    expect(_mathColour(h), _math.style.colorArgb);
  });

  testWidgets('strokes only → restyle; objects only → update-objects; an '
      'image in the selection is left as it is', (tester) async {
    final h = await _pump(tester);
    final imageBefore = _page(h).objectById(_image.id);
    await _select(tester, h, {strokeA.id, strokeB.id, _image.id});
    await _openRecolor(tester);
    await _pick(tester, _blue);
    expect(_edits(h), ['execute:restyle']);
    expect(_strokeColour(h, strokeA.id), _blue);
    expect(_strokeColour(h, strokeB.id), _blue);
    expect(_page(h).objectById(_image.id), imageBefore);

    await _select(tester, h, {_shape.id, _text.id});
    await _openRecolor(tester);
    await _pick(tester, _red);
    expect(_edits(h).last, 'execute:update-objects');
    expect(_shapeColour(h), _red);
    expect(_textColour(h), _red);
    expect(h.session.history.undoDepth, 2);
  });

  testWidgets('a rejected recolor: discardEdit (nothing pending), the '
      'colours as they were, the selection stays, no undo step', (
    tester,
  ) async {
    final h = await _pump(tester);
    final ids = {strokeA.id, _shape.id, _text.id};
    await _select(tester, h, ids);
    await _openRecolor(tester);
    h.recorder!.rejectNext(const core.ReadOnlyNoteException('race'));
    await _pick(tester, _red);

    expect(_edits(h), ['execute:composite:rejected']);
    final controller = h.controllerOf(0);
    expect(controller.pendingIds, isEmpty);
    expect(_strokeColour(h, strokeA.id), strokeA.style.colorArgb);
    expect(_shapeColour(h), _shape.style.strokeColorArgb);
    expect(_textColour(h), _text.style.colorArgb);
    expect(h.session.history.undoDepth, 0);
    expect(h.container.read(editorSelectionProvider)!.elementIds, ids);
    expect(controller.selection!.allIds, ids);
    expect(h.container.read(editorPopupProvider), isNull);
    // Not pushed to the recent colours (blue still leads).
    expect(h.container.read(editorColorPaletteProvider).recent.first, _blue);
    expect(find.text(EditorStrings.readOnlyToast), findsOneWidget);
    await tester.pump(const Duration(seconds: 5)); // snackbar timer
  });

  testWidgets('더 보기 → the colour panel in the popup; a HEX colour + 적용 '
      '→ one step with that colour', (tester) async {
    final h = await _pump(tester);
    await _select(tester, h, {strokeA.id});
    await _openRecolor(tester);
    expect(find.byType(ColorPickerPanel), findsNothing);
    await tester.tap(find.byKey(RecolorPanel.moreKey));
    await tester.pump();
    expect(find.byType(ColorPickerPanel), findsOneWidget);
    // The recolor panel edits its own colour: no eyedropper.
    expect(find.byKey(ColorPickerPanel.eyedropperKey), findsNothing);
    final penBefore = h.container.read(editorToolProvider).currentPen;

    await tester.ensureVisible(find.byKey(HexRgbFields.hexKey));
    await tester.enterText(find.byKey(HexRgbFields.hexKey), '#3366cc');
    await tester.pump();
    expect(_edits(h), isEmpty); // not applied yet
    await tester.ensureVisible(find.byKey(RecolorPanel.applyKey));
    await tester.tap(find.byKey(RecolorPanel.applyKey));
    await tester.pump();
    await tester.pump();

    expect(_edits(h), ['execute:restyle']);
    expect(_strokeColour(h, strokeA.id), 0xFF3366CC);
    expect(h.container.read(editorPopupProvider), isNull);
    // The pen's colour is untouched.
    expect(h.container.read(editorToolProvider).currentPen, penBefore);
    expect(
      h.container.read(editorColorPaletteProvider).recent.first,
      0xFF3366CC,
    );
  });

  testWidgets('the popup closes when the selection ends; a down on the '
      'barrier closes it without a command', (tester) async {
    final h = await _pump(tester);
    await _select(tester, h, {strokeA.id});
    await _openRecolor(tester);
    await tester.tapAt(const Offset(5, 1300)); // the barrier, far away
    await tester.pump();
    expect(find.byKey(RecolorPanel.panelKey), findsNothing);
    expect(find.byKey(PopupHost.barrierKey), findsNothing);
    expect(_edits(h), isEmpty);
    expect(h.container.read(editorSelectionProvider), isNotNull);

    await _openRecolor(tester);
    h.container.read(editorCommandsProvider).clearSelection();
    await tester.pump();
    await tester.pump();
    expect(h.container.read(editorPopupProvider), isNull);
    expect(find.byKey(RecolorPanel.panelKey), findsNothing);
  });
}
