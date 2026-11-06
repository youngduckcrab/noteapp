// lib/src/ui/pen/pen_extras_controls.dart — m5-7/04-editor 6.14.2 (E2-14).
//
// The per-pen rows of the new pens, under the 1st-round PenAdvancedControls
// in the pen settings popup ('고급') and in settings > pen. Both edit the same
// editorToolProvider value through ToolController.updateStyleOf (normalized,
// 500 ms debounce, synced editor.penStyles — the 1st-round path); the values
// go to StrokeStyle.extras with INK's withInkExtras (INK owns the keys and
// reads them leniently — m5-7/03-ink 4.10).
//
// | pen         | rows                                                     |
// | brush       | — (the 1st-round sensitivity / curve / smoothing only)   |
// | calligraphy | nib angle 0–175° (5°), nib aspect 0.1–1 (0.05), '펜슬    |
// |             | 돌리기로 각도 조절' (only with capabilities.barrelRoll and |
// |             | a barrel roll seen on this device)                       |
// | dashed      | spacing 촘촘 [1, 2] · 보통 [4, 3] · 긴 파선 [8, 4]          |
// | laser       | fade time 0.3–5 s (0.1 s)                                |
// | tape        | shape 단색 / 줄무늬                                        |
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../../di/stylus_extras.dart';
import '../../state/settings/editor_device_state.dart';
import '../../tools/tool_controller.dart';
import '../editor_strings.dart';

/// The dashed pen's three spacings (6.14.2), in multiples of the width.
enum DashSpacing {
  dense([1, 2]),
  normal([4, 3]),
  long([8, 4]);

  const DashSpacing(this.pattern);
  final List<double> pattern;

  /// The spacing whose pattern [pattern] is, else null (a pattern made
  /// elsewhere — no segment is shown selected).
  static DashSpacing? of(List<double> pattern) {
    for (final d in values) {
      if (d.pattern.length == pattern.length &&
          [for (var i = 0; i < pattern.length; i++) d.pattern[i] == pattern[i]]
              .every((same) => same)) {
        return d;
      }
    }
    return null;
  }

  String get label => switch (this) {
    DashSpacing.dense => EditorStrings.dashDense,
    DashSpacing.normal => EditorStrings.dashNormal,
    DashSpacing.long => EditorStrings.dashLong,
  };
}

/// The 6.14.2 rows of [tool] (null = the current pen type); nothing for a
/// pen without extras.
class PenExtrasControls extends ConsumerWidget {
  const PenExtrasControls({super.key, this.tool});

  final core.PenTool? tool;

  static const nibAngleKey = ValueKey('editor.pen.nibAngle');
  static const nibAspectKey = ValueKey('editor.pen.nibAspect');
  static const followBarrelRollKey = ValueKey('editor.pen.rollNib');
  static const laserFadeKey = ValueKey('editor.pen.laserFade');
  static ValueKey<String> dashKey(DashSpacing spacing) =>
      ValueKey('editor.pen.dash.${spacing.name}');
  static ValueKey<String> tapeStyleKey(ink.InkTapeStyle style) =>
      ValueKey('editor.pen.tapeStyle.${style.name}');

  /// Whether [tool] has rows here (6.14.2 table).
  static bool hasControls(core.PenTool tool) => switch (tool) {
    core.PenTool.calligraphy ||
    core.PenTool.dashed ||
    core.PenTool.laser ||
    core.PenTool.tape => true,
    _ => false,
  };

  /// Slider steps (6.14.2).
  static const double nibAngleMax = 175;
  static const double nibAngleStep = 5;
  static const double nibAspectMin = 0.1;
  static const double nibAspectStep = 0.05;
  static const int laserFadeMinMs = 300;
  static const int laserFadeMaxMs = 5000;
  static const int laserFadeStepMs = 100;

  static double _snap(double v, double step, double min, double max) =>
      ((v.clamp(min, max) - min) / step).round() * step + min;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final core.PenTool type =
        tool ?? ref.watch(editorToolProvider.select((s) => s.penType));
    if (!hasControls(type)) return const SizedBox.shrink();
    final style = ref.watch(
      editorToolProvider.select((s) => s.penStyles[type]!),
    );
    final tools = ref.read(editorToolProvider.notifier);
    void edit({
      double? nibAngleDeg,
      double? nibAspect,
      bool? followBarrelRoll,
      List<double>? dashPattern,
      int? laserFadeMs,
      ink.InkTapeStyle? tapeStyle,
    }) => tools.updateStyleOf(
      type,
      (s) => ink.StrokeStyleInk(s).withInkExtras(
        nibAngleDeg: nibAngleDeg,
        nibAspect: nibAspect,
        followBarrelRoll: followBarrelRoll,
        dashPattern: dashPattern,
        laserFadeMs: laserFadeMs,
        tapeStyle: tapeStyle,
      ),
    );
    final text = Theme.of(context).textTheme;
    Widget label(String name, [String? value]) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(child: Text(name, style: text.labelLarge)),
          if (value != null) Text(value, style: text.labelLarge),
        ],
      ),
    );

    final rows = <Widget>[];
    switch (type) {
      case core.PenTool.calligraphy:
        final angle = _snap(style.nibAngleDeg, nibAngleStep, 0, nibAngleMax);
        final aspect = _snap(style.nibAspect, nibAspectStep, nibAspectMin, 1);
        final capabilities = ref.watch(
          stylusExtrasProvider.select((s) => s.capabilities),
        );
        final seenRoll = ref.watch(
          editorDeviceStateProvider.select((s) => s.seenBarrelRoll),
        );
        rows.addAll([
          label(EditorStrings.nibAngle, '${angle.round()}°'),
          Semantics(
            label: EditorStrings.nibAngle,
            child: Slider(
              key: nibAngleKey,
              value: angle,
              max: nibAngleMax,
              divisions: (nibAngleMax / nibAngleStep).round(),
              onChanged: (v) =>
                  edit(nibAngleDeg: _snap(v, nibAngleStep, 0, nibAngleMax)),
            ),
          ),
          label(EditorStrings.nibAspect, aspect.toStringAsFixed(2)),
          Semantics(
            label: EditorStrings.nibAspect,
            child: Slider(
              key: nibAspectKey,
              value: aspect,
              min: nibAspectMin,
              divisions: ((1 - nibAspectMin) / nibAspectStep).round(),
              onChanged: (v) =>
                  edit(nibAspect: _snap(v, nibAspectStep, nibAspectMin, 1)),
            ),
          ),
          if (capabilities.barrelRoll && seenRoll)
            SwitchListTile(
              key: followBarrelRollKey,
              contentPadding: EdgeInsets.zero,
              title: const Text(EditorStrings.followBarrelRoll),
              value: style.followBarrelRoll,
              onChanged: (v) => edit(followBarrelRoll: v),
            ),
        ]);
      case core.PenTool.dashed:
        final spacing = DashSpacing.of(style.dashPattern);
        rows.addAll([
          label(EditorStrings.dashSpacing),
          const SizedBox(height: 4),
          SegmentedButton<DashSpacing>(
            showSelectedIcon: false,
            emptySelectionAllowed: true,
            segments: [
              for (final d in DashSpacing.values)
                ButtonSegment(
                  value: d,
                  label: Text(d.label, key: dashKey(d)),
                ),
            ],
            selected: {?spacing},
            onSelectionChanged: (s) {
              if (s.isNotEmpty) edit(dashPattern: s.single.pattern);
            },
          ),
        ]);
      case core.PenTool.laser:
        final fadeMs =
            (style.laserFadeMs / laserFadeStepMs).round() * laserFadeStepMs;
        rows.addAll([
          label(
            EditorStrings.laserFade,
            EditorStrings.laserFadeLabel(fadeMs / 1000),
          ),
          Semantics(
            label: EditorStrings.laserFade,
            child: Slider(
              key: laserFadeKey,
              value: fadeMs.toDouble(),
              min: laserFadeMinMs.toDouble(),
              max: laserFadeMaxMs.toDouble(),
              divisions: (laserFadeMaxMs - laserFadeMinMs) ~/ laserFadeStepMs,
              onChanged: (v) => edit(
                laserFadeMs: (v / laserFadeStepMs).round() * laserFadeStepMs,
              ),
            ),
          ),
        ]);
      case core.PenTool.tape:
        rows.addAll([
          label(EditorStrings.tapeStyle),
          const SizedBox(height: 4),
          SegmentedButton<ink.InkTapeStyle>(
            showSelectedIcon: false,
            segments: [
              for (final (value, name) in const [
                (ink.InkTapeStyle.solid, EditorStrings.tapeSolid),
                (ink.InkTapeStyle.striped, EditorStrings.tapeStriped),
              ])
                ButtonSegment(
                  value: value,
                  label: Text(name, key: tapeStyleKey(value)),
                ),
            ],
            selected: {style.tapeStyle},
            onSelectionChanged: (s) => edit(tapeStyle: s.single),
          ),
        ]);
      default:
        break;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: rows,
    );
  }
}
