// lib/src/ui/pickers/folder_appearance_picker.dart — 05-library 6.12: folder
// color (없음 + the 10 FolderPalette colors) and folder icon (the 16
// FolderIcons keys, 4 × 4). Used by the new folder dialog and (L13) the
// folder appearance dialog.
import 'package:material_ui/material_ui.dart';

import '../../appearance/folder_appearance.dart';
import '../../l10n/library_strings.dart';
import '../layout/library_metrics.dart';
import 'swatch_button.dart';

class FolderColorPicker extends StatelessWidget {
  const FolderColorPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  /// null = no color (theme default).
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ChoiceChip(
          label: const Text(LibraryStrings.colorNone),
          selected: value == null,
          onSelected: (_) => onChanged(null),
        ),
        for (var i = 0; i < FolderPalette.colors.length; i++)
          SwatchButton(
            color: Color(FolderPalette.colors[i]),
            label: FolderPalette.names[i],
            selected: value == FolderPalette.colors[i],
            onTap: () => onChanged(FolderPalette.colors[i]),
          ),
      ],
    );
  }
}

class FolderIconPicker extends StatelessWidget {
  const FolderIconPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.colorArgb,
  });

  /// A FolderIcons key; null (or an unknown key) = the default folder icon.
  final String? value;

  /// The default key is reported as null (nothing stored = default).
  final ValueChanged<String?> onChanged;

  /// Icons are drawn in this folder color (null = onSurfaceVariant).
  final int? colorArgb;

  static const int columns = 4;
  static const double cell = 48;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selectedKey = FolderIcons.keys.contains(value)
        ? value!
        : FolderIcons.defaultKey;
    final argb = colorArgb;
    final iconColor = argb != null ? Color(argb) : scheme.onSurfaceVariant;
    return SizedBox(
      width: columns * cell,
      child: Wrap(
        children: [
          for (final key in FolderIcons.keys)
            SizedBox(
              width: cell,
              height: cell,
              child: Center(
                child: IconButton(
                  constraints: const BoxConstraints.tightFor(
                    width: LibraryMetrics.minTapTarget,
                    height: LibraryMetrics.minTapTarget,
                  ),
                  padding: EdgeInsets.zero,
                  isSelected: key == selectedKey,
                  style: IconButton.styleFrom(
                    backgroundColor: key == selectedKey
                        ? scheme.secondaryContainer
                        : null,
                  ),
                  icon: Icon(FolderIcons.iconFor(key), color: iconColor),
                  tooltip: FolderIcons.labelFor(key),
                  onPressed: () =>
                      onChanged(key == FolderIcons.defaultKey ? null : key),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
