// lib/src/ui/pickers/cover_picker.dart — 05-library 6.12: '첫 페이지' + the 8
// CoverPalette colors (ColorCover).
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart'
    show ColorCover, FirstPageCover, NoteCover;

import '../../appearance/cover_palette.dart';
import '../../l10n/library_strings.dart';
import 'swatch_button.dart';

class CoverPicker extends StatelessWidget {
  const CoverPicker({super.key, required this.value, required this.onChanged});

  /// FirstPageCover or a ColorCover (an AssetCover selects nothing here).
  final NoteCover value;
  final ValueChanged<NoteCover> onChanged;

  @override
  Widget build(BuildContext context) {
    final value = this.value;
    return Wrap(
      spacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ChoiceChip(
          label: const Text(LibraryStrings.coverFirstPage),
          selected: value is FirstPageCover,
          onSelected: (_) => onChanged(const FirstPageCover()),
        ),
        for (var i = 0; i < CoverPalette.colors.length; i++)
          SwatchButton(
            color: Color(CoverPalette.colors[i]),
            label: CoverPalette.names[i],
            circle: false,
            swatchSize: const Size(21, 28),
            selected:
                value is ColorCover &&
                value.colorArgb == CoverPalette.colors[i],
            onTap: () => onChanged(ColorCover(CoverPalette.colors[i])),
          ),
      ],
    );
  }
}
