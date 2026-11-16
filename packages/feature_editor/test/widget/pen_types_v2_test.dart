// m5-7/04-editor 8.2 E2-14, 6.14.1, 6.14.3; (v2.15-ui) 23.1–23.2: the pen
// picker's '무슨 펜' — every pen type as a card (pen drawing in its ink colour,
// the real stroke, the name) grouped 필기 8 / 질감 4 / 꾸미기 4 and the
// 발표·공부 도구 chips (laser, tape); a pen picked → penType, the pen active,
// the tool state stored, the tray's lifted pen is that drawing; the laser has
// no colour rows.
import 'dart:async';

import 'package:feature_editor/src/state/settings/editor_setting_keys.dart';
import 'package:feature_editor/src/tools/tool_controller.dart';
import 'package:feature_editor/src/tools/tool_state.dart';
import 'package:feature_editor/src/ui/color/basic_colors_row.dart';
import 'package:feature_editor/src/ui/color/opacity_slider.dart';
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:feature_editor/src/ui/pen/pen_art_view.dart';
import 'package:feature_editor/src/ui/pen/pen_settings_popup.dart';
import 'package:feature_editor/src/ui/pen/pen_type_selector.dart';
import 'package:feature_editor/src/ui/toolbar/editor_toolbar.dart';
import 'package:flutter_test/flutter_test.dart';
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

const _writing = [
  core.PenTool.ballpoint,
  core.PenTool.fountain,
  core.PenTool.pencil,
  core.PenTool.marker,
  core.PenTool.highlighter,
  core.PenTool.brush,
  core.PenTool.calligraphy,
  core.PenTool.dashed,
];
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
const _tools = [core.PenTool.laser, core.PenTool.tape];

void main() {
  test('the groups and names (23.1)', () {
    expect(PenTypeSelector.cardGroups, {
      PenTypeGroup.basic: _writing,
      PenTypeGroup.texture: _texture,
      PenTypeGroup.decor: _decor,
    });
    expect(PenTypeSelector.toolPens, _tools);
    expect(PenTypeSelector.types.toSet(), core.PenTool.values.toSet());
    expect(PenTypeSelector.types, hasLength(core.PenTool.values.length));
    expect(PenTypeSelector.groups.keys, PenTypeGroup.values);
    expect(
      [for (final g in PenTypeGroup.values) EditorStrings.penGroupName(g.name)],
      ['필기', '질감', '꾸미기', '발표·공부 도구'],
    );
    expect(
      [for (final t in _writing) EditorStrings.penTypeName(t)],
      ['볼펜', '만년필', '연필', '마커', '형광펜', '붓펜', '캘리그래피', '점선'],
    );
    expect(
      [
        for (final t in [..._texture, ..._decor]) EditorStrings.penTypeName(t),
      ],
      ['크레파스', '분필', '수채', '스프레이', '네온', '젤리', '무지개', '반짝이'],
    );
  });

  testWidgets('every card: the pen drawing in its ink colour, the real stroke '
      'and the name; four a row, group by group; at least 44 px', (
    tester,
  ) async {
    final h = await _open(tester);
    final styles = h.container.read(editorToolProvider).penStyles;
    for (final group in [_writing, _texture, _decor]) {
      for (var i = 0; i < group.length; i++) {
        final cell = _cell(group[i]);
        expect(cell, findsOneWidget, reason: group[i].name);
        final art = tester.widget<PenArt>(
          find.descendant(of: cell, matching: find.byType(PenArt)),
        );
        expect(art.tool, group[i]);
        expect(art.color, penArtColorOf(styles[group[i]]!));
        expect(
          find.descendant(of: cell, matching: find.byType(InkStroke)),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: cell,
            matching: find.text(EditorStrings.penTypeName(group[i])),
          ),
          findsOneWidget,
        );
        final size = tester.getSize(cell);
        expect(size.height, greaterThanOrEqualTo(44));
        expect(size.width, greaterThanOrEqualTo(44));
        if (i % 4 != 0) {
          expect(
            tester.getCenter(cell).dy,
            closeTo(tester.getCenter(_cell(group[i - 1])).dy, 0.5),
          );
          expect(
            tester.getCenter(cell).dx,
            greaterThan(tester.getCenter(_cell(group[i - 1])).dx),
          );
        }
      }
    }
    for (final t in _tools) {
      expect(_cell(t), findsOneWidget);
      expect(tester.getSize(_cell(t)).height, greaterThanOrEqualTo(44));
    }
    // One header per group, above its first card; 발표·공부 도구 last.
    for (final (g, first) in [
      (PenTypeGroup.basic, _writing.first),
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
      tester.getCenter(_cell(core.PenTool.laser)).dy,
      greaterThan(tester.getCenter(_cell(_decor.last)).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a pen picked → penType, the pen active, its style; stored in '
      'the tool state; the tray lifts its drawing', (tester) async {
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
      tester
          .widget<PenArt>(
            find.descendant(
              of: find.byKey(EditorToolbar.penKey),
              matching: find.byType(PenArt),
            ),
          )
          .tool,
      core.PenTool.calligraphy,
    );
    await tester.pump(const Duration(milliseconds: 600)); // debounced write
    final json = await _stored(tester, h, EditorSettingKeys.toolSelection);
    expect(json?['penType'], 'calligraphy');
    expect(json?['activeTool'], 'pen');
  });

  testWidgets('the laser: no colour rows; the width choices stay; another '
      'pen has them', (tester) async {
    await _open(tester);
    expect(find.byKey(BasicColorsRow.swatchKey(0)), findsOneWidget);
    await tester.tap(_cell(core.PenTool.laser));
    await tester.pump();
    expect(find.byKey(BasicColorsRow.swatchKey(0)), findsNothing);
    expect(find.byKey(PenSettingsPanel.otherColorKey), findsNothing);
    expect(find.byType(OpacitySlider), findsNothing);
    expect(find.byKey(PenSettingsPanel.widthKey(0)), findsOneWidget);
    await tester.tap(_cell(core.PenTool.highlighter));
    await tester.pump();
    expect(find.byKey(BasicColorsRow.swatchKey(0)), findsOneWidget);
    expect(find.byType(OpacitySlider), findsOneWidget);
  });
}
