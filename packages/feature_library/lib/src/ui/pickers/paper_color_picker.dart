// lib/src/ui/pickers/paper_color_picker.dart — 05-library 6.12: four round
// swatches 흰색 · 미색 · 회색 · 검정 (PaperColors.all order, CORE values).
// The template line color on dark paper is INK's choice (lineColorArgb null).
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' show PaperColors;

import '../../l10n/library_strings.dart';
import 'swatch_button.dart';

class PaperColorPicker extends StatelessWidget {
  const PaperColorPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  /// One of PaperColors.all.
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      children: [
        for (final argb in PaperColors.all)
          SwatchButton(
            color: Color(argb),
            label: LibraryStrings.paperColorName(argb),
            selected: argb == value,
            onTap: () => onChanged(argb),
          ),
      ],
    );
  }
}
