// lib/src/ui/toolbar/note_info_dialog.dart — 04-editor 6.17.4 (노트 정보).
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../editor_strings.dart';

/// Local `yyyy-MM-dd HH:mm` (no intl — contract 7.4.5).
String formatLocalDateTime(core.EpochMillis at) {
  final t = DateTime.fromMillisecondsSinceEpoch(at);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year.toString().padLeft(4, '0')}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}';
}

/// Title, page count, created and modified dates of the open note.
class NoteInfoDialog extends StatelessWidget {
  const NoteInfoDialog({
    super.key,
    required this.note,
    required this.pageCount,
  });

  static const dialogKey = ValueKey('editor.noteInfo');

  final core.Note note;
  final int pageCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget row(String name, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              name,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
    return AlertDialog(
      key: dialogKey,
      title: const Text(EditorStrings.noteInfo),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          row(EditorStrings.noteInfoTitle, note.title),
          row(EditorStrings.noteInfoPages, '$pageCount'),
          row(
            EditorStrings.noteInfoCreated,
            formatLocalDateTime(note.createdAt),
          ),
          row(
            EditorStrings.noteInfoUpdated,
            formatLocalDateTime(note.updatedAt),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(EditorStrings.close),
        ),
      ],
    );
  }
}
