// lib/src/ui/dialogs/rename_dialog.dart — 05-library 6.11: '이름 변경'. The
// field starts focused with the whole name selected; at most 200 characters
// (the counter shows from 180); [저장] is disabled for an empty or unchanged
// name (and for one CORE would refuse, C-6); Enter saves.
import 'package:material_ui/material_ui.dart';

import '../../l10n/library_strings.dart';
import '../../model/names.dart';
import 'dialog_frame.dart';

/// The rename field shows its counter from this many characters.
const int kRenameCounterFrom = 180;

/// Shows the dialog; the trimmed new name, or null when cancelled.
Future<String?> showRenameDialog(
  BuildContext context, {
  required String title,
  required String initialName,
}) => showDialog<String>(
  context: context,
  builder: (_) => RenameDialog(title: title, initialName: initialName),
);

class RenameDialog extends StatefulWidget {
  const RenameDialog({
    super.key,
    required this.title,
    required this.initialName,
  });

  final String title;
  final String initialName;

  @override
  State<RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<RenameDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.initialName)
        ..selection = TextSelection(
          baseOffset: 0,
          extentOffset: widget.initialName.length,
        );

  @override
  void initState() {
    super.initState();
    _name.addListener(_changed);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  /// Empty / too long (String.length, C-6) / unchanged → false.
  bool get _canSave {
    final typed = _name.text.trim();
    return validateItemName(typed) == null && typed != widget.initialName;
  }

  void _save() {
    if (!_canSave) return;
    Navigator.of(context).pop(_name.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return LibraryDialogFrame(
      title: widget.title,
      body: [
        DialogNameField(
          controller: _name,
          label: LibraryStrings.fieldName,
          maxLength: kMaxItemNameLength,
          counterFrom: kRenameCounterFrom,
          onSubmitted: (_) => _save(),
        ),
      ],
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(LibraryStrings.cancel),
        ),
        FilledButton(
          onPressed: _canSave ? _save : null,
          child: const Text(LibraryStrings.save),
        ),
      ],
    );
  }
}
