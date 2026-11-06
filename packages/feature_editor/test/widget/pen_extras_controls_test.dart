// m5-7/04-editor 8.2 E2-14, 6.14.2: PenExtrasControls — the rows per pen
// follow the 6.14.2 table (in the pen settings popup '고급' and in settings
// > pen); a value goes through withInkExtras to the pen's style and the
// synced editor.penStyles; the '펜슬 돌리기로 각도 조절' row only shows with
// capabilities.barrelRoll AND a barrel roll seen on this device.
import 'dart:async';

import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/state/settings/editor_device_state.dart';
import 'package:feature_editor/src/state/settings/editor_setting_keys.dart';
import 'package:feature_editor/src/tools/tool_controller.dart';
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:feature_editor/src/ui/pen/pen_advanced_controls.dart';
import 'package:feature_editor/src/ui/pen/pen_extras_controls.dart';
import 'package:feature_editor/src/ui/pen/pen_settings_popup.dart';
import 'package:feature_editor/src/ui/toolbar/editor_toolbar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../helpers/fake_stylus_extras.dart';
import '../helpers/pump_editor.dart';

/// Opens the pen settings popup for [type] with '고급' expanded.
Future<EditorTestHandles> _open(
  WidgetTester tester,
  core.PenTool type, {
  FakeStylusExtras? stylusExtras,
}) async {
  final h = await pumpEditor(tester, stylusExtras: stylusExtras);
  h.container.read(editorToolProvider.notifier).selectPenType(type);
  await tester.pump();
  await tester.tap(find.byKey(EditorToolbar.penKey)); // the active pen
  await tester.pump();
  expect(find.byKey(PenSettingsPanel.panelKey), findsOneWidget);
  await tester.ensureVisible(find.text(EditorStrings.advanced));
  await tester.pump();
  await tester.tap(find.text(EditorStrings.advanced));
  await tester.pumpAndSettle();
  return h;
}

core.StrokeStyle _style(EditorTestHandles h, core.PenTool type) =>
    h.container.read(editorToolProvider).penStyles[type]!;

const _extrasKeys = [
  PenExtrasControls.nibAngleKey,
  PenExtrasControls.nibAspectKey,
  PenExtrasControls.followBarrelRollKey,
  PenExtrasControls.laserFadeKey,
];

Set<Key> _shownExtras(WidgetTester tester) => {
  for (final k in _extrasKeys)
    if (find.byKey(k).evaluate().isNotEmpty) k,
  for (final d in DashSpacing.values)
    if (find.byKey(PenExtrasControls.dashKey(d)).evaluate().isNotEmpty)
      PenExtrasControls.dashKey(d),
  for (final s in ink.InkTapeStyle.values)
    if (find.byKey(PenExtrasControls.tapeStyleKey(s)).evaluate().isNotEmpty)
      PenExtrasControls.tapeStyleKey(s),
};

Future<void> _tap(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pump();
  await tester.tap(find.byKey(key));
  await tester.pump();
}

void _slide(WidgetTester tester, Key key, double value) =>
    tester.widget<Slider>(find.byKey(key)).onChanged!(value);

Future<Map<String, Object?>?> _stored(
  WidgetTester tester,
  EditorTestHandles h,
) async {
  Map<String, Object?>? stored;
  var done = false;
  unawaited(
    h.store.settings.get(EditorSettingKeys.penStyles).then((v) {
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

void main() {
  test('dash spacings (6.14.2)', () {
    expect(DashSpacing.dense.pattern, [1, 2]);
    expect(DashSpacing.normal.pattern, [4, 3]);
    expect(DashSpacing.long.pattern, [8, 4]);
    expect(DashSpacing.of(const [4, 3]), DashSpacing.normal);
    expect(DashSpacing.of(const [1, 2]), DashSpacing.dense);
    expect(DashSpacing.of(const [2, 2]), isNull);
    expect(DashSpacing.of(const [8, 4, 1, 1]), isNull);
    for (final t in core.PenTool.values) {
      expect(
        PenExtrasControls.hasControls(t),
        const {
          core.PenTool.calligraphy,
          core.PenTool.dashed,
          core.PenTool.laser,
          core.PenTool.tape,
        }.contains(t),
        reason: t.name,
      );
    }
  });

  for (final (type, expected) in <(core.PenTool, Set<Key>)>[
    (core.PenTool.ballpoint, {}),
    (core.PenTool.brush, {}),
    (
      core.PenTool.calligraphy,
      {PenExtrasControls.nibAngleKey, PenExtrasControls.nibAspectKey},
    ),
    (
      core.PenTool.dashed,
      {for (final d in DashSpacing.values) PenExtrasControls.dashKey(d)},
    ),
    (core.PenTool.laser, {PenExtrasControls.laserFadeKey}),
    (
      core.PenTool.tape,
      {
        for (final s in ink.InkTapeStyle.values)
          PenExtrasControls.tapeStyleKey(s),
      },
    ),
  ]) {
    testWidgets('${type.name}: the 6.14.2 rows under the 1st-round ones', (
      tester,
    ) async {
      await _open(tester, type);
      expect(find.byType(PenAdvancedControls), findsOneWidget);
      expect(_shownExtras(tester), expected);
    });
  }

  testWidgets('calligraphy: angle 0–175 (5°) and aspect 0.1–1 (0.05) → '
      'withInkExtras, then the synced editor.penStyles', (tester) async {
    final h = await _open(tester, core.PenTool.calligraphy);
    expect(_style(h, core.PenTool.calligraphy).nibAngleDeg, 45);
    expect(find.text('45°'), findsOneWidget);
    final angle = tester.widget<Slider>(
      find.byKey(PenExtrasControls.nibAngleKey),
    );
    expect(angle.min, 0);
    expect(angle.max, 175);
    expect(angle.divisions, 35);
    final aspect = tester.widget<Slider>(
      find.byKey(PenExtrasControls.nibAspectKey),
    );
    expect(aspect.min, 0.1);
    expect(aspect.max, 1);
    expect(aspect.divisions, 18);

    _slide(tester, PenExtrasControls.nibAngleKey, 92.4); // → 90
    await tester.pump();
    _slide(tester, PenExtrasControls.nibAspectKey, 0.52); // → 0.5
    await tester.pump();
    final style = _style(h, core.PenTool.calligraphy);
    expect(style.nibAngleDeg, 90);
    expect(style.nibAspect, closeTo(0.5, 1e-9));
    expect(find.text('90°'), findsOneWidget);
    expect(find.text('0.50'), findsOneWidget);
    // Other pens are untouched.
    expect(
      h.container.read(editorToolProvider).penStyles[core.PenTool.ballpoint],
      core.StrokeStyle.defaultsFor(core.PenTool.ballpoint).normalized(),
    );

    await tester.pump(const Duration(milliseconds: 600)); // debounced write
    final stored = await _stored(tester, h);
    final styles = stored?['styles'] as Map<String, Object?>?;
    final calligraphy = styles?['calligraphy'] as Map<String, Object?>?;
    final extras = calligraphy?['extras'] as Map<String, Object?>?;
    expect(extras?[ink.InkStyleExtras.nibAngleDeg], 90);
    expect(extras?[ink.InkStyleExtras.nibAspect], closeTo(0.5, 1e-9));
  });

  testWidgets('dashed: 촘촘 / 보통 / 긴 파선 → the dash pattern; the default is '
      '보통', (tester) async {
    final h = await _open(tester, core.PenTool.dashed);
    final segmented = tester.widget<SegmentedButton<DashSpacing>>(
      find.byType(SegmentedButton<DashSpacing>),
    );
    expect(segmented.selected, {DashSpacing.normal});
    await _tap(tester, PenExtrasControls.dashKey(DashSpacing.dense));
    expect(_style(h, core.PenTool.dashed).dashPattern, [1, 2]);
    await _tap(tester, PenExtrasControls.dashKey(DashSpacing.long));
    expect(_style(h, core.PenTool.dashed).dashPattern, [8, 4]);
    expect(
      tester
          .widget<SegmentedButton<DashSpacing>>(
            find.byType(SegmentedButton<DashSpacing>),
          )
          .selected,
      {DashSpacing.long},
    );
  });

  testWidgets('laser: fade 0.3–5 s in 0.1 s steps (default 1.5 s)', (
    tester,
  ) async {
    final h = await _open(tester, core.PenTool.laser);
    expect(find.text(EditorStrings.laserFadeLabel(1.5)), findsOneWidget);
    final slider = tester.widget<Slider>(
      find.byKey(PenExtrasControls.laserFadeKey),
    );
    expect(slider.min, 300);
    expect(slider.max, 5000);
    expect(slider.divisions, 47);
    _slide(tester, PenExtrasControls.laserFadeKey, 2340); // → 2300
    await tester.pump();
    expect(_style(h, core.PenTool.laser).laserFadeMs, 2300);
    expect(find.text(EditorStrings.laserFadeLabel(2.3)), findsOneWidget);
  });

  testWidgets('tape: 단색 / 줄무늬', (tester) async {
    final h = await _open(tester, core.PenTool.tape);
    expect(_style(h, core.PenTool.tape).tapeStyle, ink.InkTapeStyle.solid);
    await _tap(
      tester,
      PenExtrasControls.tapeStyleKey(ink.InkTapeStyle.striped),
    );
    expect(_style(h, core.PenTool.tape).tapeStyle, ink.InkTapeStyle.striped);
  });

  testWidgets('the barrel roll row: only with capabilities.barrelRoll and a '
      'barrel roll seen; on by default, off → rollNib false', (tester) async {
    final h = await _open(
      tester,
      core.PenTool.calligraphy,
      stylusExtras: FakeStylusExtras(),
    );
    // Capable, not seen yet → hidden.
    expect(find.byKey(PenExtrasControls.followBarrelRollKey), findsNothing);
    h.container.read(editorDeviceStateProvider.notifier).markSeenBarrelRoll();
    await tester.pump();
    final row = find.byKey(PenExtrasControls.followBarrelRollKey);
    expect(row, findsOneWidget);
    expect(find.text(EditorStrings.followBarrelRoll), findsOneWidget);
    expect(tester.widget<SwitchListTile>(row).value, isTrue);
    await tester.ensureVisible(row);
    await tester.pump();
    await tester.tap(row);
    await tester.pump();
    expect(_style(h, core.PenTool.calligraphy).followBarrelRoll, isFalse);
  });

  testWidgets('seen but not capable → no barrel roll row', (tester) async {
    final h = await pumpEditor(
      tester,
      stylusExtras: FakeStylusExtras(
        capabilities: const StylusCapabilities(
          doubleTap: true,
          squeeze: true,
          hoverPose: true,
        ),
      ),
    );
    h.container.read(editorDeviceStateProvider.notifier).markSeenBarrelRoll();
    h.container
        .read(editorToolProvider.notifier)
        .selectPenType(core.PenTool.calligraphy);
    await tester.pump();
    await tester.tap(find.byKey(EditorToolbar.penKey));
    await tester.pump();
    await tester.ensureVisible(find.text(EditorStrings.advanced));
    await tester.pump();
    await tester.tap(find.text(EditorStrings.advanced));
    await tester.pumpAndSettle();
    expect(find.byKey(PenExtrasControls.nibAngleKey), findsOneWidget);
    expect(find.byKey(PenExtrasControls.followBarrelRollKey), findsNothing);
  });
}
