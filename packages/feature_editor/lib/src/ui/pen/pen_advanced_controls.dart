// lib/src/ui/pen/pen_advanced_controls.dart — 04-editor 6.9.3 #7 (EDITOR-S3);
// (v2, E2-15 — m5-7/04-editor 6.10) the auto shape assist toggle.
//
// Shared by the pen settings popup ('고급', folded) and settings > pen
// (EditorPenSettingsSection, E-20): both edit the same editorToolProvider
// value, so the two places always agree (contract 7.2.4 — no global
// pressure curve setting).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../../state/settings/editor_settings_notifier.dart';
import '../../tools/shape_assist_for.dart';
import '../../tools/tool_controller.dart';
import '../editor_strings.dart';
import 'highlighter_straightening_selector.dart';
import 'pressure_curve_selector.dart';

/// True when the pen has no usable pressure (6.5.7): pressure mode
/// alwaysSimulated, or auto while INK detected no stylus pressure.
bool pressureUnavailable(
  ink.PressureMode mode,
  ink.PressureCapability stylus,
) =>
    mode == ink.PressureMode.alwaysSimulated ||
    (mode == ink.PressureMode.auto &&
        stylus == ink.PressureCapability.unsupported);

/// Pressure sensitivity (0–1, 0.05), pressure curve (soft / linear / firm),
/// smoothing (0–1, 0.05) and — for the highlighter only — straightening of
/// [tool] (null = the current pen type). Sensitivity and curve are disabled
/// with "이 펜은 필압이 없어 속도로 흉내 내요" when [pressureUnavailable].
/// (v2, 6.10) '자동 도형 보정' (EditorSettings.shapeAssist — one synced
/// setting for every pen) under them, for the pens that get it
/// ([shapeAssistPen]) and only while a shape fitter is wired (hidden with
/// INK's NoShapeFitter — a build without recognition).
class PenAdvancedControls extends ConsumerWidget {
  const PenAdvancedControls({super.key, this.tool});

  final core.PenTool? tool;

  static const sensitivityKey = ValueKey('editor.pen.sensitivity');
  static const smoothingKey = ValueKey('editor.pen.smoothing');
  static const noPressureKey = ValueKey('editor.pen.noPressure');

  /// (v2, E2-15) The '자동 도형 보정' switch.
  static const shapeAssistKey = ValueKey('editor.pen.shapeAssist');

  static double _step(double v) => (v.clamp(0.0, 1.0) * 20).round() / 20;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final core.PenTool type =
        tool ?? ref.watch(editorToolProvider.select((s) => s.penType));
    final style = ref.watch(
      editorToolProvider.select((s) => s.penStyles[type]!),
    );
    final mode = ref.watch(
      editorSettingsProvider.select((s) => s.pressureMode),
    );
    final stylus = ref.watch(
      ink.pressureCapabilityProvider.select((s) => s.stylus),
    );
    final noPressure = pressureUnavailable(mode, stylus);
    final shapeAssist = ref.watch(
      editorSettingsProvider.select((s) => s.shapeAssist),
    );
    final showShapeAssist =
        shapeAssistPen(type) &&
        shapeFitterAvailable(ref.watch(ink.inkShapeFitterProvider));
    final tools = ref.read(editorToolProvider.notifier);
    void edit(core.StrokeStyle Function(core.StrokeStyle) f) =>
        tools.updateStyleOf(type, f);
    final text = Theme.of(context).textTheme;
    final sensitivity = (style.pressureSensitivity * 100).round();
    final smoothing = (style.smoothing * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          EditorStrings.pressureSensitivityLabel(sensitivity),
          style: text.labelLarge,
        ),
        Semantics(
          label: EditorStrings.pressureSensitivity,
          child: Slider(
            key: sensitivityKey,
            value: style.pressureSensitivity.clamp(0.0, 1.0),
            divisions: 20,
            onChanged: noPressure
                ? null
                : (v) => edit((s) => s.copyWith(pressureSensitivity: _step(v))),
          ),
        ),
        Text(EditorStrings.pressureCurve, style: text.labelLarge),
        const SizedBox(height: 4),
        PressureCurveSelector(
          curve: style.pressureCurve,
          enabled: !noPressure,
          onChanged: (c) => edit((s) => s.copyWith(pressureCurve: c)),
        ),
        if (noPressure)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              EditorStrings.noPressureHint,
              key: noPressureKey,
              style: text.bodySmall,
            ),
          ),
        const SizedBox(height: 8),
        Text(EditorStrings.smoothingLabel(smoothing), style: text.labelLarge),
        Semantics(
          label: EditorStrings.smoothing,
          child: Slider(
            key: smoothingKey,
            value: style.smoothing.clamp(0.0, 1.0),
            divisions: 20,
            onChanged: (v) => edit((s) => s.copyWith(smoothing: _step(v))),
          ),
        ),
        if (showShapeAssist)
          SwitchListTile(
            key: shapeAssistKey,
            contentPadding: EdgeInsets.zero,
            title: const Text(EditorStrings.shapeAssist),
            subtitle: const Text(EditorStrings.shapeAssistHint),
            value: shapeAssist,
            onChanged: (v) =>
                ref.read(editorSettingsProvider.notifier).setShapeAssist(v),
          ),
        if (type == core.PenTool.highlighter) ...[
          Text(EditorStrings.straightening, style: text.labelLarge),
          const SizedBox(height: 4),
          HighlighterStraighteningSelector(
            value: ink.StrokeStyleInk(style).highlighterStraightening,
            onChanged: (v) => edit(
              (s) => ink.StrokeStyleInk(s).withHighlighterStraightening(v),
            ),
          ),
        ],
      ],
    );
  }
}
