// lib/src/ui/dialogs/folder_appearance_dialog.dart — 05-library 6.11:
// '꾸미기' for a folder: a preview, color (없음 + 10) and icon (4 × 4);
// [취소] [저장]. [저장] is disabled while nothing changed.
import 'package:material_ui/material_ui.dart';

import '../../l10n/library_strings.dart';
import '../../model/folder_appearance_value.dart';
import '../content/tile_parts.dart';
import '../pickers/folder_appearance_picker.dart';
import 'dialog_frame.dart';

/// Shows the dialog; the new appearance, or null when cancelled.
Future<FolderAppearance?> showFolderAppearanceDialog(
  BuildContext context, {
  required FolderAppearance initial,
}) => showDialog<FolderAppearance>(
  context: context,
  builder: (_) => FolderAppearanceDialog(initial: initial),
);

class FolderAppearanceDialog extends StatefulWidget {
  const FolderAppearanceDialog({super.key, required this.initial});

  final FolderAppearance initial;

  @override
  State<FolderAppearanceDialog> createState() => _FolderAppearanceDialogState();
}

class _FolderAppearanceDialogState extends State<FolderAppearanceDialog> {
  late int? _color = widget.initial.colorArgb;

  /// Kept as stored until the user picks an icon (an unknown key synced from
  /// a newer app stays when only the color changes).
  late String? _icon = widget.initial.icon;

  FolderAppearance get _value =>
      FolderAppearance(colorArgb: _color, icon: _icon);

  @override
  Widget build(BuildContext context) {
    final changed = _value != widget.initial;
    return LibraryDialogFrame(
      title: LibraryStrings.customize,
      body: [
        DialogSection(
          label: LibraryStrings.preview,
          child: Semantics(
            image: true,
            label: LibraryStrings.preview,
            child: ClipRRect(
              borderRadius: TileCoverBox.radius,
              child: SizedBox(
                width: 96,
                height: 72,
                child: FolderGlyph(
                  colorArgb: _color,
                  icon: _icon,
                  iconSize: 40,
                ),
              ),
            ),
          ),
        ),
        DialogSection(
          label: LibraryStrings.fieldColor,
          child: FolderColorPicker(
            value: _color,
            onChanged: (argb) => setState(() => _color = argb),
          ),
        ),
        DialogSection(
          label: LibraryStrings.fieldIcon,
          child: FolderIconPicker(
            value: _icon,
            colorArgb: _color,
            onChanged: (key) => setState(() => _icon = key),
          ),
        ),
      ],
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(LibraryStrings.cancel),
        ),
        FilledButton(
          onPressed: changed ? () => Navigator.of(context).pop(_value) : null,
          child: const Text(LibraryStrings.save),
        ),
      ],
    );
  }
}
