// lib/src/ui/dialogs/cover_dialog.dart — 05-library 6.11: '표지 변경' for a
// note: '첫 페이지' + the 8 CoverPalette colors; [취소] [저장]. [저장] is
// disabled while the choice equals the current cover (an AssetCover — set by
// PDF import — selects nothing until the user picks one).
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' show NoteCover;

import '../../l10n/library_strings.dart';
import '../pickers/cover_picker.dart';
import 'dialog_frame.dart';

/// Shows the dialog; the new cover, or null when cancelled.
Future<NoteCover?> showCoverDialog(
  BuildContext context, {
  required NoteCover current,
}) => showDialog<NoteCover>(
  context: context,
  builder: (_) => CoverDialog(current: current),
);

class CoverDialog extends StatefulWidget {
  const CoverDialog({super.key, required this.current});

  final NoteCover current;

  @override
  State<CoverDialog> createState() => _CoverDialogState();
}

class _CoverDialogState extends State<CoverDialog> {
  late NoteCover _value = widget.current;

  @override
  Widget build(BuildContext context) {
    final changed = _value != widget.current;
    return LibraryDialogFrame(
      title: LibraryStrings.changeCover,
      body: [
        DialogSection(
          label: LibraryStrings.fieldCover,
          child: CoverPicker(
            value: _value,
            onChanged: (cover) => setState(() => _value = cover),
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
