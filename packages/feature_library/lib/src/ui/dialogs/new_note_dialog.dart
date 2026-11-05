// lib/src/ui/dialogs/new_note_dialog.dart — 05-library 6.12: title (default
// name, fully selected), location, page size + orientation, template, paper
// color, cover; [취소] [만들기]. An empty title uses the default name (not an
// error); an invalid custom size disables [만들기].
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' show FirstPageCover, NoteCover;

import '../../l10n/library_strings.dart';
import '../../model/names.dart';
import '../../model/new_note_spec.dart';
import '../pickers/cover_picker.dart';
import '../pickers/page_size_picker.dart';
import '../pickers/paper_color_picker.dart';
import '../pickers/template_picker.dart';
import 'dialog_frame.dart';

/// Shows the dialog; null when cancelled.
Future<NewNoteSpec?> showNewNoteDialog(
  BuildContext context, {
  required String initialTitle, // unique default name
  required NewNoteOptions initialOptions, // newNoteDefaultsProvider
  required String locationLabel, // '홈 › 수학'
}) => showDialog<NewNoteSpec>(
  context: context,
  builder: (_) => NewNoteDialog(
    initialTitle: initialTitle,
    initialOptions: initialOptions,
    locationLabel: locationLabel,
  ),
);

class NewNoteDialog extends StatefulWidget {
  const NewNoteDialog({
    super.key,
    required this.initialTitle,
    required this.initialOptions,
    required this.locationLabel,
  });

  final String initialTitle;
  final NewNoteOptions initialOptions;
  final String locationLabel;

  @override
  State<NewNoteDialog> createState() => _NewNoteDialogState();
}

class _NewNoteDialogState extends State<NewNoteDialog> {
  late final TextEditingController _title =
      TextEditingController(text: widget.initialTitle)
        ..selection = TextSelection(
          baseOffset: 0,
          extentOffset: widget.initialTitle.length,
        );
  late NewNoteOptions _options = widget.initialOptions;
  NoteCover _cover = const FirstPageCover();
  bool _sizeValid = true;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _create() {
    if (!_sizeValid) return;
    final typed = _title.text.trim();
    final title = validateItemName(typed) == NameIssue.empty
        ? widget.initialTitle
        : typed;
    Navigator.of(context)
        .pop(NewNoteSpec(title: title, options: _options, cover: _cover));
  }

  @override
  Widget build(BuildContext context) {
    return LibraryDialogFrame(
      title: LibraryStrings.newNote,
      body: [
        DialogNameField(
          controller: _title,
          label: LibraryStrings.fieldTitle,
          maxLength: kMaxItemNameLength,
          onSubmitted: (_) => _create(),
        ),
        DialogLocationRow(
          label: LibraryStrings.fieldLocation,
          location: widget.locationLabel,
        ),
        DialogSection(
          label: LibraryStrings.fieldPageSize,
          child: PageSizePicker(
            value: _options,
            onChanged: (o) => setState(() => _options = o),
            onValidityChanged: (ok) => setState(() => _sizeValid = ok),
          ),
        ),
        DialogSection(
          label: LibraryStrings.fieldTemplate,
          child: TemplatePicker(
            value: _options.template,
            onChanged: (kind) => setState(
              () => _options = kind == null
                  ? _options.copyWith(clearTemplate: true)
                  : _options.copyWith(template: kind),
            ),
          ),
        ),
        DialogSection(
          label: LibraryStrings.fieldPaperColor,
          child: PaperColorPicker(
            value: _options.paperColorArgb,
            onChanged: (argb) => setState(
              () => _options = _options.copyWith(paperColorArgb: argb),
            ),
          ),
        ),
        DialogSection(
          label: LibraryStrings.fieldCover,
          child: CoverPicker(
            value: _cover,
            onChanged: (c) => setState(() => _cover = c),
          ),
        ),
      ],
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(LibraryStrings.cancel),
        ),
        FilledButton(
          onPressed: _sizeValid ? _create : null,
          child: const Text(LibraryStrings.create),
        ),
      ],
    );
  }
}
