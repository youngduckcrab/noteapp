// lib/src/ui/pen/highlighter_straightening_selector.dart — 04-editor 6.9.3 #7.
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:material_ui/material_ui.dart';

import '../editor_strings.dart';

/// SegmentedButton[끔 | 뗄 때 보정 | 항상 직선] =
/// ink.HighlighterStraightening.off / snapOnLift / alwaysStraight (the value
/// lives in the style's extras['hlStraight'], read and written through INK's
/// accessors only). Shown for the highlighter only.
class HighlighterStraighteningSelector extends StatelessWidget {
  const HighlighterStraighteningSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final ink.HighlighterStraightening value;
  final ValueChanged<ink.HighlighterStraightening> onChanged;

  static const buttonKey = ValueKey('editor.pen.straightening');

  static ValueKey<String> segmentKey(ink.HighlighterStraightening v) =>
      ValueKey('editor.pen.straightening.${v.name}');

  static String _label(ink.HighlighterStraightening v) => switch (v) {
    ink.HighlighterStraightening.off => EditorStrings.straighteningOff,
    ink.HighlighterStraightening.snapOnLift =>
      EditorStrings.straighteningOnLift,
    ink.HighlighterStraightening.alwaysStraight =>
      EditorStrings.straighteningAlways,
  };

  @override
  Widget build(BuildContext context) =>
      SegmentedButton<ink.HighlighterStraightening>(
        key: buttonKey,
        segments: [
          for (final v in ink.HighlighterStraightening.values)
            ButtonSegment(
              value: v,
              label: Text(_label(v), key: segmentKey(v)),
            ),
        ],
        selected: {value},
        showSelectedIcon: false,
        onSelectionChanged: (s) => onChanged(s.first),
      );
}
