// lib/src/ui/pen/pressure_curve_selector.dart — 04-editor 6.9.3 #7.
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../editor_strings.dart';

/// SegmentedButton[부드럽게 | 보통 | 단단하게] = core.PressureCurve.soft /
/// linear / firm. A [curve] equal to none of them (a synced custom value)
/// selects no segment and shows "사용자 지정 곡선" under the buttons.
class PressureCurveSelector extends StatelessWidget {
  const PressureCurveSelector({
    super.key,
    required this.curve,
    required this.onChanged,
    this.enabled = true,
  });

  final core.PressureCurve curve;
  final ValueChanged<core.PressureCurve> onChanged;
  final bool enabled;

  static const buttonKey = ValueKey('editor.pen.curve');
  static const customKey = ValueKey('editor.pen.curve.custom');

  static ValueKey<String> segmentKey(core.PressureCurve preset) =>
      ValueKey('editor.pen.curve.${_name(preset)}');

  static const presets = [
    core.PressureCurve.soft,
    core.PressureCurve.linear,
    core.PressureCurve.firm,
  ];

  static String _name(core.PressureCurve c) => c == core.PressureCurve.soft
      ? 'soft'
      : c == core.PressureCurve.firm
      ? 'firm'
      : 'linear';

  static String _label(core.PressureCurve c) => c == core.PressureCurve.soft
      ? EditorStrings.curveSoft
      : c == core.PressureCurve.firm
      ? EditorStrings.curveFirm
      : EditorStrings.curveLinear;

  @override
  Widget build(BuildContext context) {
    final preset = presets.where((p) => p == curve).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SegmentedButton<core.PressureCurve>(
          key: buttonKey,
          segments: [
            for (final p in presets)
              ButtonSegment(
                value: p,
                label: Text(_label(p), key: segmentKey(p)),
              ),
          ],
          selected: {?preset},
          emptySelectionAllowed: true,
          showSelectedIcon: false,
          onSelectionChanged: enabled
              ? (s) {
                  if (s.isNotEmpty) onChanged(s.first);
                }
              : null,
        ),
        if (preset == null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              EditorStrings.customCurve,
              key: customKey,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}
