// lib/src/ui/dialogs/new_markdown_dialog.dart — (v2.17-md, C217M-11) '새 MD 문서': the title
// (default name, fully selected) and the location; [취소] [만들기]. An empty title uses the
// default title.
import 'package:material_ui/material_ui.dart';

import '../../l10n/library_strings.dart';
import '../../model/names.dart';
import 'dialog_frame.dart';

/// Shows the dialog; the title, or null when cancelled.
Future<String?> showNewMarkdownDialog(
  BuildContext context, {
  required String initialTitle,
  required String locationLabel,
}) => showDialog<String>(
  context: context,
  builder: (_) => NewMarkdownDialog(
    initialTitle: initialTitle,
    locationLabel: locationLabel,
  ),
);

class NewMarkdownDialog extends StatefulWidget {
  const NewMarkdownDialog({
    super.key,
    required this.initialTitle,
    required this.locationLabel,
  });

  final String initialTitle;
  final String locationLabel;

  static const Key titleFieldKey = Key('library.newMarkdown.title');

  @override
  State<NewMarkdownDialog> createState() => _NewMarkdownDialogState();
}

class _NewMarkdownDialogState extends State<NewMarkdownDialog> {
  late final TextEditingController _title =
      TextEditingController(text: widget.initialTitle)
        ..selection = TextSelection(
          baseOffset: 0,
          extentOffset: widget.initialTitle.length,
        );

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _create() {
    final typed = _title.text.trim();
    Navigator.of(context).pop(
      validateItemName(typed) == NameIssue.empty ? widget.initialTitle : typed,
    );
  }

  @override
  Widget build(BuildContext context) => LibraryDialogFrame(
    title: LibraryStrings.newMarkdown,
    body: [
      DialogNameField(
        key: NewMarkdownDialog.titleFieldKey,
        controller: _title,
        label: LibraryStrings.fieldName,
        maxLength: kMaxItemNameLength,
        onSubmitted: (_) => _create(),
      ),
      DialogLocationRow(
        label: LibraryStrings.fieldLocation,
        location: widget.locationLabel,
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
