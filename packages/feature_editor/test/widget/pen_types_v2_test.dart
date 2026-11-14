// m5-7/04-editor 8.2 E2-14, 6.14.1, 6.14.3: the pen picker v2 — ten cells in
// (v2.11, C211-01: + the 질감 and 꾸미기 rows, eighteen cells in three groups)
// two rows (P0 row, extra row) with the 6.14.1 names, icons and keys; a P1
// pen picked → penType, the pen active, the tool state stored; the laser has
// no colour rows in the pen settings popup.
import 'dart:async';

import 'package:feature_editor/src/state/settings/editor_setting_keys.dart';
import 'package:feature_editor/src/tools/tool_controller.dart';
import 'package:feature_editor/src/tools/tool_state.dart';
import 'package:feature_editor/src/ui/color/color_picker_panel.dart';
import 'package:feature_editor/src/ui/color/opacity_slider.dart';
import 'package:feature_editor/src/ui/color/recent_colors_row.dart';
import 'package:feature_editor/src/ui/color/user_palette_grid.dart';
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:feature_editor/src/ui/pen/pen_settings_popup.dart';
import 'package:feature_editor/src/ui/pen/pen_type_selector.dart';
import 'package:feature_editor/src/ui/pen/width_slider.dart';
import 'package:feature_editor/src/ui/toolbar/editor_toolbar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../helpers/pump_editor.dart';

Future<EditorTestHandles> _open(WidgetTester tester) async {
  final h = await pumpEditor(tester);
  await tester.tap(find.byKey(EditorToolbar.penKey)); // the active pen
  await tester.pump();
  expect(find.byKey(PenSettingsPanel.panelKey), findsOneWidget);
  return h;
}

/// The stored value of [key] (the fake store answers in a few pumps).
Future<Map<String, Object?>?> _stored(
  WidgetTester tester,
  EditorTestHandles h,
  core.SettingKey<Map<String, Object?>> key,
) async {
  Map<String, Object?>? stored;
  var done = false;
  unawaited(
    h.store.settings.get(key).then((v) {
      stored = v;
      done = true;
    }),
  );
  for (var i = 0; i < 10 && !done; i++) {
    await tester.pump();
  }
  expect(done, isTrue);
  return stored;
}

Finder _cell(core.PenTool t) => find.byKey(PenTypeSelector.keyOf(t));

const _p0 = [
  core.PenTool.ballpoint,
  core.PenTool.fountain,
  core.PenTool.highlighter,
  core.PenTool.pencil,
  core.PenTool.marker,
];
const _extra = [
  core.PenTool.brush,
  core.PenTool.calligraphy,
  core.PenTool.dashed,
  core.PenTool.laser,
  core.PenTool.tape,
];
// (C211-01) 질감 / 꾸미기 rows
const _texture = [
  core.PenTool.crayon,
  core.PenTool.chalk,
  core.PenTool.watercolor,
  core.PenTool.spray,
];
const _decor = [
  core.PenTool.neon,
  core.PenTool.jelly,
  core.PenTool.rainbow,
  core.PenTool.glitter,
];
const _rows = [_p0, _extra, _texture, _decor];

void main() {
  test('names and icons of the ten types (6.14.1)', () {
    expect(PenTypeSelector.rows, _rows);
    expect(PenTypeSelector.types, [for (final r in _rows) ...r]);
    expect(PenTypeSelector.types.toSet(), core.PenTool.values.toSet());
    expect(PenTypeSelector.groups.keys, PenTypeGroup.values);
    expect(
      [for (final g in PenTypeGroup.values) EditorStrings.penGroupName(g.name)],
      ['기본', '질감', '꾸미기'],
    );
    expect(
      [
        for (final t in [..._texture, ..._decor]) EditorStrings.penTypeName(t),
      ],
      ['크레파스', '분필', '수채', '스프레이', '네온', '젤리', '무지개', '반짝이'],
    );
    expect(
      [
        for (final t in [..._texture, ..._decor]) penTypeIcon(t),
      ],
      [
        Icons.format_paint,
        Icons.school,
        Icons.water_drop,
        Icons.blur_on,
        Icons.lightbulb,
        Icons.bubble_chart,
        Icons.looks,
        Icons.auto_awesome,
      ],
    );
    expect(
      [for (final t in _extra) EditorStrings.penTypeName(t)],
      ['붓펜', '캘리그래피', '점선', '레이저', '암기 테이프'],
    );
    expect(
      [for (final t in _p0) EditorStrings.penTypeName(t)],
      ['볼펜', '만년필', '형광펜', '연필', '마커'],
    );
    expect(
      [
        for (final t in [..._p0, ..._extra]) penTypeIcon(t),
      ],
      [
        Icons.edit,
        Icons.history_edu,
        Icons.border_color,
        Icons.create,
        Icons.brush,
        Icons.draw,
        Icons.gesture,
        Icons.line_style,
        Icons.flare,
        Icons.visibility_off,
      ],
    );
  });

  testWidgets('every cell in its row (기본 two rows, 질감, 꾸미기), in order, '
      'each with its name, icon and '
      'key; at least 44 px', (tester) async {
    await _open(tester);
    for (final row in _rows) {
      await tester.ensureVisible(_cell(row.first));
      await tester.pump();
      final y = tester.getCenter(_cell(row.first)).dy;
      for (var i = 0; i < row.length; i++) {
        final cell = _cell(row[i]);
        expect(cell, findsOneWidget, reason: row[i].name);
        expect(tester.getCenter(cell).dy, closeTo(y, 0.5));
        if (i > 0) {
          expect(
            tester.getCenter(cell).dx,
            greaterThan(tester.getCenter(_cell(row[i - 1])).dx),
          );
        }
        final size = tester.getSize(cell);
        expect(size.height, greaterThanOrEqualTo(44));
        expect(size.width, greaterThanOrEqualTo(44));
        expect(
          find.descendant(
            of: cell,
            matching: find.text(EditorStrings.penTypeName(row[i])),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: cell, matching: find.byIcon(penTypeIcon(row[i]))),
          findsOneWidget,
        );
      }
    }
    expect(
      tester.getCenter(_cell(_extra.first)).dy,
      greaterThan(tester.getCenter(_cell(_p0.first)).dy),
    );
    // (C211-01) one header per group, above its first row
    for (final (g, first) in [
      (PenTypeGroup.basic, _p0.first),
      (PenTypeGroup.texture, _texture.first),
      (PenTypeGroup.decor, _decor.first),
    ]) {
      final header = find.byKey(PenTypeSelector.groupKeyOf(g));
      expect(header, findsOneWidget);
      expect(
        tester.getCenter(header).dy,
        lessThan(tester.getCenter(_cell(first)).dy),
      );
    }
    expect(
      tester.getCenter(_cell(_decor.first)).dy,
      greaterThan(tester.getCenter(_cell(_texture.first)).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a P1 pen picked → penType, the pen active, its style; stored '
      'in the tool state; the toolbar shows its icon', (tester) async {
    final h = await _open(tester);
    h.container.read(editorToolProvider.notifier).selectTool(EditorTool.lasso);
    await tester.pump();
    await tester.tap(_cell(core.PenTool.calligraphy));
    await tester.pump();
    final state = h.container.read(editorToolProvider);
    expect(state.penType, core.PenTool.calligraphy);
    expect(state.activeTool, EditorTool.pen);
    expect(state.currentPen.tool, core.PenTool.calligraphy);
    expect(
      find.descendant(
        of: find.byKey(EditorToolbar.penKey),
        matching: find.byIcon(Icons.gesture),
      ),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 600)); // debounced write
    final json = await _stored(tester, h, EditorSettingKeys.toolSelection);
    expect(json?['penType'], 'calligraphy');
    expect(json?['activeTool'], 'pen');
  });

  testWidgets('the laser: no colour rows (picker, opacity, recent, palette); '
      'width stays; another pen has them', (tester) async {
    await _open(tester);
    expect(find.byType(ColorPickerPanel), findsOneWidget);
    await tester.tap(_cell(core.PenTool.laser));
    await tester.pump();
    expect(find.byType(ColorPickerPanel), findsNothing);
    expect(find.byType(OpacitySlider), findsNothing);
    expect(find.byType(RecentColorsRow), findsNothing);
    expect(find.byType(UserPaletteGrid), findsNothing);
    expect(find.byType(WidthSlider), findsOneWidget);
    await tester.tap(_cell(core.PenTool.tape));
    await tester.pump();
    expect(find.byType(ColorPickerPanel), findsOneWidget);
    expect(find.byType(OpacitySlider), findsOneWidget);
  });
}
