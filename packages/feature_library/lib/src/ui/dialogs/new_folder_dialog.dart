// lib/src/ui/dialogs/new_folder_dialog.dart — 05-library 6.12: name (default
// name, fully selected), location, color (없음 + 10), icon (4 × 4);
// [취소] [만들기]. An empty name uses the default name.
import 'package:material_ui/material_ui.dart';

import '../../l10n/library_strings.dart';
import '../../model/folder_appearance_value.dart';
import '../../model/names.dart';
import '../pickers/folder_appearance_picker.dart';
import 'dialog_frame.dart';

/// Shows the dialog; null when cancelled.
Future<NewFolderSpec?> showNewFolderDialog(
  BuildContext context, {
  required String initialName,
  required String locationLabel,
}) => showDialog<NewFolderSpec>(
  context: context,
  builder: (_) =>
      NewFolderDialog(initialName: initialName, locationLabel: locationLabel),
);

class NewFolderDialog extends StatefulWidget {
  const NewFolderDialog({
    super.key,
    required this.initialName,
    required this.locationLabel,
  });

  final String initialName;
  final String locationLabel;

  @override
  State<NewFolderDialog> createState() => _NewFolderDialogState();
}

class _NewFolderDialogState extends State<NewFolderDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.initialName)
        ..selection = TextSelection(
          baseOffset: 0,
          extentOffset: widget.initialName.length,
        );
  int? _color;
  String? _icon;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _create() {
    final typed = _name.text.trim();
    final name = validateItemName(typed) == NameIssue.empty
        ? widget.initialName
        : typed;
    Navigator.of(context).pop(
      NewFolderSpec(
        name: name,
        appearance: FolderAppearance(colorArgb: _color, icon: _icon),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LibraryDialogFrame(
      title: LibraryStrings.newFolder,
      body: [
        DialogNameField(
          controller: _name,
          label: LibraryStrings.fieldName,
          maxLength: kMaxItemNameLength,
          onSubmitted: (_) => _create(),
        ),
        DialogLocationRow(
          label: LibraryStrings.fieldLocation,
          location: widget.locationLabel,
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
          onPressed: _create,
          child: const Text(LibraryStrings.create),
        ),
      ],
    );
  }
}
