// E-15: the pen settings panel (04-editor 6.9.3): pen types, width (slider,
// [−]/[+] with hold-to-repeat, number input), the preview (ink.PenPreviewPainter
// with the PencilGrain object — contract 7.2.16 v1.1), opacity (5% floor) and
// '고급' (pressure sensitivity / curve, smoothing, highlighter straightening,
// disabled without pressure — 6.5.7).
import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/tools/tool_controller.dart';
import 'package:feature_editor/src/tools/tool_state.dart';
import 'package:feature_editor/src/ui/color/opacity_slider.dart';
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:feature_editor/src/ui/pen/highlighter_straightening_selector.dart';
import 'package:feature_editor/src/ui/pen/pen_advanced_controls.dart';
import 'package:feature_editor/src/ui/pen/pen_preview.dart';
import 'package:feature_editor/src/ui/pen/pen_settings_popup.dart';
import 'package:feature_editor/src/ui/pen/pen_type_selector.dart';
import 'package:feature_editor/src/ui/pen/pressure_curve_selector.dart';
import 'package:feature_editor/src/ui/pen/width_mapping.dart';
import 'package:feature_editor/src/ui/pen/width_slider.dart';
import 'package:feature_editor/src/ui/toolbar/editor_toolbar.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../helpers/pump_editor.dart';

core.StrokeStyle _pen(EditorTestHandles h) =>
    h.container.read(editorToolProvider).currentPen;

ToolController _tools(EditorTestHandles h) =>
    h.container.read(editorToolProvider.notifier);

Future<EditorTestHandles> _open(
  WidgetTester tester, {
  EditorSettings? settings,
  List<Override> overrides = const [],
}) async {
  final h = await pumpEditor(tester, settings: settings, overrides: overrides);
  await tester.tap(find.byKey(EditorToolbar.penKey)); // the active pen
  await tester.pump();
  expect(find.byKey(PenSettingsPanel.panelKey), findsOneWidget);
  return h;
}

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
}

Future<void> _expandAdvanced(WidgetTester tester) async {
  await _scrollTo(tester, find.text(EditorStrings.advanced));
  await tester.tap(find.text(EditorStrings.advanced));
  await tester.pumpAndSettle();
}

/// INK detection state fixed to [stylus] (contract 7.2.15 — INK owns it).
class _FixedCapability extends ink.PressureCapabilityNotifier {
  _FixedCapability(this._stylus);
  final ink.PressureCapability _stylus;

  @override
  ink.PressureCapabilityState build() =>
      ink.PressureCapabilityState(stylus: _stylus);
}

Override _capability(ink.PressureCapability stylus) =>
    ink.pressureCapabilityProvider.overrideWith(() => _FixedCapability(stylus));

void main() {
  testWidgets('pen types: (v2, m5-7/04-editor 6.14.1) all ten types; '
      'switching keeps each type\'s last style and makes the pen active', (
    tester,
  ) async {
    final h = await _open(tester);
    for (final t in core.PenTool.values) {
      expect(
        find.byKey(PenTypeSelector.keyOf(t)),
        findsOneWidget,
        reason: t.name,
      );
    }
    _tools(h).setWidth(4.2);
    await tester.tap(find.byKey(PenTypeSelector.keyOf(core.PenTool.fountain)));
    await tester.pump();
    final state = h.container.read(editorToolProvider);
    expect(state.penType, core.PenTool.fountain);
    expect(state.activeTool, EditorTool.pen);
    expect(
      _pen(h),
      core.StrokeStyle.defaultsFor(core.PenTool.fountain).normalized(),
    );
    expect(find.text(EditorStrings.widthLabel(_pen(h).width)), findsOneWidget);
    await tester.tap(find.byKey(PenTypeSelector.keyOf(core.PenTool.ballpoint)));
    await tester.pump();
    expect(_pen(h).width, 4.2);
  });

  testWidgets('width slider: non-linear mapping, ends = 0.1 / 30 pt', (
    tester,
  ) async {
    final h = await _open(tester);
    final slider = find.byKey(WidthSlider.sliderKey);
    tester.widget<Slider>(slider).onChanged!(0.5);
    await tester.pump();
    expect(_pen(h).width, 7.6);
    expect(tester.widget<Slider>(slider).value, WidthMapping.positionOf(7.6));
    expect(find.text('굵기 7.6 pt'), findsOneWidget);

    final rect = tester.getRect(slider);
    await tester.tapAt(rect.centerRight - const Offset(2, 0));
    await tester.pump();
    expect(_pen(h).width, WidthMapping.max);
    await tester.tapAt(rect.centerLeft + const Offset(2, 0));
    await tester.pump();
    expect(_pen(h).width, WidthMapping.min);
  });

  testWidgets('[−] / [+] step 0.1 pt; holding repeats after 400 ms every '
      '80 ms; disabled at the ends', (tester) async {
    final h = await _open(tester);
    expect(_pen(h).width, 1.6); // ballpoint default (contract 7.2.4)
    await tester.tap(find.byKey(WidthSlider.plusKey));
    await tester.pump();
    expect(_pen(h).width, 1.7);
    await tester.tap(find.byKey(WidthSlider.minusKey));
    await tester.tap(find.byKey(WidthSlider.minusKey));
    await tester.pump();
    expect(_pen(h).width, 1.5);

    final g = await tester.startGesture(
      tester.getCenter(find.byKey(WidthSlider.plusKey)),
    );
    await tester.pump(const Duration(milliseconds: 399));
    expect(_pen(h).width, 1.5);
    await tester.pump(const Duration(milliseconds: 1));
    expect(_pen(h).width, 1.6); // first step at 400 ms
    for (var i = 0; i < 5; i++) {
      await tester.pump(WidthSlider.repeatPeriod);
    }
    expect(_pen(h).width, closeTo(2.1, 1e-9));
    await g.up();
    await tester.pump(const Duration(seconds: 1));
    expect(_pen(h).width, closeTo(2.1, 1e-9)); // stopped on release

    _tools(h).setWidth(30);
    await tester.pump();
    await tester.tap(find.byKey(WidthSlider.plusKey));
    await tester.pump();
    expect(_pen(h).width, 30);
    _tools(h).setWidth(0.1);
    await tester.pump();
    await tester.tap(find.byKey(WidthSlider.minusKey));
    await tester.pump();
    expect(_pen(h).width, 0.1);
  });

  testWidgets('number input: tap the label, 0.1–30 applied (snapped to 0.1) '
      'on submit or focus loss; anything else is dropped', (tester) async {
    final h = await _open(tester);
    await tester.tap(find.byKey(WidthSlider.labelKey));
    await tester.pump();
    final input = find.byKey(WidthSlider.inputKey);
    expect(input, findsOneWidget);
    await tester.enterText(input, '12.34');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(_pen(h).width, 12.3);
    expect(find.byKey(WidthSlider.inputKey), findsNothing);
    expect(find.text('굵기 12.3 pt'), findsOneWidget);

    for (final bad in ['50', '0', '0.05', '..']) {
      await tester.tap(find.byKey(WidthSlider.labelKey));
      await tester.pump();
      await tester.enterText(find.byKey(WidthSlider.inputKey), bad);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(_pen(h).width, 12.3, reason: bad);
    }

    await tester.tap(find.byKey(WidthSlider.labelKey));
    await tester.pump();
    await tester.enterText(find.byKey(WidthSlider.inputKey), 'x3a');
    expect(
      tester
          .widget<TextField>(find.byKey(WidthSlider.inputKey))
          .controller!
          .text,
      '3',
    ); // digits and '.' only
    await tester.tap(find.byKey(WidthSlider.plusKey)); // focus moves away
    await tester.pump();
    expect(find.byKey(WidthSlider.inputKey), findsNothing);
    expect(_pen(h).width, closeTo(3.1, 1e-9)); // 3, then [+]
  });

  testWidgets('preview: ink.PenPreviewPainter with the current style and the '
      'pencilGrainProvider object itself; "확대 n%" when cut', (tester) async {
    final h = await _open(tester);
    CustomPaint paint() =>
        tester.widget<CustomPaint>(find.byKey(PenPreview.paintKey));
    final painter = paint().painter;
    expect(painter, isA<ink.PenPreviewPainter>());
    painter as ink.PenPreviewPainter;
    expect(
      identical(painter.pencilGrain, h.container.read(ink.pencilGrainProvider)),
      isTrue,
    );
    expect(painter.style, _pen(h));
    expect(find.byKey(PenPreview.zoomLabelKey), findsNothing);

    // The canvas is scaled by the note's settled zoom (fit ≈ 168%).
    final scale = h.viewport.settledScale.value;
    expect(scale, greaterThan(1.5));
    final transform = tester.widget<Transform>(
      find
          .ancestor(
            of: find.byKey(PenPreview.paintKey),
            matching: find.byType(Transform),
          )
          .first,
    );
    expect(transform.transform.getMaxScaleOnAxis(), closeTo(scale, 1e-9));

    _tools(h).setWidth(30); // 30 × 1.68 > 48 px
    await tester.pump();
    expect((paint().painter! as ink.PenPreviewPainter).style.width, 30);
    expect(
      find.text(EditorStrings.previewZoom((scale * 100).round())),
      findsOneWidget,
    );
  });

  testWidgets('opacity: 5% at the left end, 100% at the right end', (
    tester,
  ) async {
    final h = await _open(tester);
    final slider = find.byKey(OpacitySlider.sliderKey);
    await _scrollTo(tester, slider);
    final rect = tester.getRect(slider);
    await tester.tapAt(rect.centerLeft + const Offset(1, 0));
    await tester.pump();
    expect(_pen(h).opacity, core.StrokeStyle.minOpacity);
    expect(find.text(EditorStrings.opacityLabel(5)), findsOneWidget);
    await tester.tapAt(rect.center);
    await tester.pump();
    expect(_pen(h).opacity, closeTo(0.53, 0.011)); // 0.05 + 0.95 / 2
    await tester.tapAt(rect.centerRight - const Offset(1, 0));
    await tester.pump();
    expect(_pen(h).opacity, 1);
  });

  testWidgets('advanced: curve segments set soft / linear / firm; a custom '
      'curve selects none; sensitivity and smoothing step 0.05', (
    tester,
  ) async {
    final h = await _open(tester);
    await _expandAdvanced(tester);
    Set<core.PressureCurve> selected() => tester
        .widget<SegmentedButton<core.PressureCurve>>(
          find.byKey(PressureCurveSelector.buttonKey),
        )
        .selected;
    expect(selected(), {core.PressureCurve.linear});
    for (final curve in PressureCurveSelector.presets.reversed) {
      final segment = find.byKey(PressureCurveSelector.segmentKey(curve));
      await _scrollTo(tester, segment);
      await tester.tap(segment);
      await tester.pump();
      expect(_pen(h).pressureCurve, curve);
      expect(selected(), {curve});
    }

    const custom = core.PressureCurve(x1: 0.3, y1: 0.1, x2: 0.7, y2: 0.9);
    _tools(h).updateStyleOf(
      core.PenTool.ballpoint,
      (s) => s.copyWith(pressureCurve: custom),
    );
    await tester.pump();
    expect(selected(), isEmpty);
    expect(find.byKey(PressureCurveSelector.customKey), findsOneWidget);
    expect(find.text(EditorStrings.customCurve), findsOneWidget);

    tester
        .widget<Slider>(find.byKey(PenAdvancedControls.sensitivityKey))
        .onChanged!(0.43);
    tester
        .widget<Slider>(find.byKey(PenAdvancedControls.smoothingKey))
        .onChanged!(0.12);
    await tester.pump();
    expect(_pen(h).pressureSensitivity, 0.45);
    expect(_pen(h).smoothing, 0.1);
    expect(_pen(h).pressureCurve, custom); // untouched
  });

  testWidgets('straightening: only for the highlighter, stored in the '
      'style extras through INK\'s accessor', (tester) async {
    final h = await _open(tester);
    await _expandAdvanced(tester);
    expect(
      find.byKey(HighlighterStraighteningSelector.buttonKey),
      findsNothing,
    );

    final highlighter = find.byKey(
      PenTypeSelector.keyOf(core.PenTool.highlighter),
    );
    await _scrollTo(tester, highlighter);
    await tester.tap(highlighter);
    await tester.pumpAndSettle();
    final segment = find.byKey(
      HighlighterStraighteningSelector.segmentKey(
        ink.HighlighterStraightening.snapOnLift,
      ),
    );
    await _scrollTo(tester, segment);
    await tester.tap(segment);
    await tester.pump();
    expect(_pen(h).tool, core.PenTool.highlighter);
    expect(
      ink.StrokeStyleInk(_pen(h)).highlighterStraightening,
      ink.HighlighterStraightening.snapOnLift,
    );
    expect(
      _pen(h).extras[ink.InkStyleExtras.highlighterStraightening],
      'snapOnLift',
    );
    final always = find.byKey(
      HighlighterStraighteningSelector.segmentKey(
        ink.HighlighterStraightening.alwaysStraight,
      ),
    );
    await tester.tap(always);
    await tester.pump();
    expect(
      ink.StrokeStyleInk(_pen(h)).highlighterStraightening,
      ink.HighlighterStraightening.alwaysStraight,
    );
    // The other tools keep theirs.
    expect(
      h.container
          .read(editorToolProvider)
          .penStyles[core.PenTool.ballpoint]!
          .extras,
      isNot(contains(ink.InkStyleExtras.highlighterStraightening)),
    );
  });

  group('sensitivity and curve without pressure (6.5.7)', () {
    Future<void> expectEnabled(WidgetTester tester, bool enabled) async {
      final slider = tester.widget<Slider>(
        find.byKey(PenAdvancedControls.sensitivityKey),
      );
      final curve = tester.widget<SegmentedButton<core.PressureCurve>>(
        find.byKey(PressureCurveSelector.buttonKey),
      );
      expect(slider.onChanged != null, enabled);
      expect(curve.onSelectionChanged != null, enabled);
      expect(
        find.text(EditorStrings.noPressureHint),
        enabled ? findsNothing : findsOneWidget,
      );
      // Smoothing has nothing to do with pressure.
      expect(
        tester
            .widget<Slider>(find.byKey(PenAdvancedControls.smoothingKey))
            .onChanged,
        isNotNull,
      );
    }

    testWidgets('auto + INK says unsupported → disabled', (tester) async {
      await _open(
        tester,
        overrides: [_capability(ink.PressureCapability.unsupported)],
      );
      await _expandAdvanced(tester);
      await expectEnabled(tester, false);
    });

    testWidgets('alwaysSimulated → disabled even with pressure', (
      tester,
    ) async {
      await _open(
        tester,
        settings: const EditorSettings(
          pressureMode: ink.PressureMode.alwaysSimulated,
        ),
        overrides: [_capability(ink.PressureCapability.supported)],
      );
      await _expandAdvanced(tester);
      await expectEnabled(tester, false);
    });

    testWidgets('auto + supported / unknown, alwaysReal + unsupported → '
        'enabled', (tester) async {
      await _open(
        tester,
        overrides: [_capability(ink.PressureCapability.supported)],
      );
      await _expandAdvanced(tester);
      await expectEnabled(tester, true);
    });

    testWidgets('auto + unknown → enabled', (tester) async {
      await _open(tester);
      await _expandAdvanced(tester);
      await expectEnabled(tester, true);
    });

    testWidgets('alwaysReal + unsupported → enabled', (tester) async {
      await _open(
        tester,
        settings: const EditorSettings(
          pressureMode: ink.PressureMode.alwaysReal,
        ),
        overrides: [_capability(ink.PressureCapability.unsupported)],
      );
      await _expandAdvanced(tester);
      await expectEnabled(tester, true);
    });

    test('pressureUnavailable table', () {
      for (final mode in ink.PressureMode.values) {
        for (final cap in ink.PressureCapability.values) {
          expect(
            pressureUnavailable(mode, cap),
            mode == ink.PressureMode.alwaysSimulated ||
                (mode == ink.PressureMode.auto &&
                    cap == ink.PressureCapability.unsupported),
            reason: '$mode $cap',
          );
        }
      }
    });
  });
}
