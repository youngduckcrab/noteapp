// lib/src/ui/toolbar/note_info_dialog.dart — 04-editor 6.17.4 (노트 정보);
// (v2.14-ui review — m5-7/04-editor 'UI 정리 1단계') [이름 바꾸기].
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../../scope/editor_scope.dart';
import '../editor_strings.dart';

/// Shows [NoteInfoDialog] for the open note ((v2.14-ui) from a tap on the
/// toolbar title, or ⋯ '노트 정보' while the title is hidden). (v2.14-ui
/// review) Its [이름 바꾸기] (not on a read-only note) asks for the new title
/// ([NoteRenameDialog]) and calls CORE's LibraryRepository.renameNote; the
/// toolbar title follows (editorNoteTitleProvider). A refused rename shows
/// '실행하지 못했어요'.
Future<void> showNoteInfoDialog(BuildContext context, WidgetRef ref) {
  final session = ref.read(editorSessionValueProvider);
  final readOnly = ref.read(editorReadOnlyProvider);
  final library = ref.read(core.libraryRepositoryProvider);
  final messenger = ScaffoldMessenger.maybeOf(context);
  Future<void> rename(BuildContext dialogContext) async {
    final current = ref.read(editorNoteTitleProvider);
    final title = await showDialog<String>(
      context: dialogContext,
      builder: (_) => NoteRenameDialog(initialTitle: current),
    );
    if (title == null) return;
    if (dialogContext.mounted) Navigator.of(dialogContext).pop();
    try {
      await library.renameNote(session.noteId, title);
    } on Object catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'feature_editor',
          context: ErrorDescription('while renaming the note'),
        ),
      );
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text(EditorStrings.commandFailed)),
        );
    }
  }

  return showDialog<void>(
    context: context,
    builder: (dialogContext) => NoteInfoDialog(
      note: session.note,
      title: ref.read(editorNoteTitleProvider),
      pageCount: session.pages.length,
      onRename: readOnly ? null : () => unawaited(rename(dialogContext)),
    ),
  );
}

/// (v2.14-ui review) The longest title CORE takes (C-6: trimmed,
/// String.length 1..200).
const int kMaxNoteTitleLength = 200;

/// '이름 바꾸기': the title field (focused, all selected); [바꾸기] is off for
/// an empty, too long or unchanged title; Enter saves. Pops the trimmed new
/// title, or null.
class NoteRenameDialog extends StatefulWidget {
  const NoteRenameDialog({super.key, required this.initialTitle});

  static const dialogKey = ValueKey('editor.noteRename');
  static const fieldKey = ValueKey('editor.noteRename.field');
  static const saveKey = ValueKey('editor.noteRename.save');

  final String initialTitle;

  @override
  State<NoteRenameDialog> createState() => _NoteRenameDialogState();
}

class _NoteRenameDialogState extends State<NoteRenameDialog> {
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

  bool get _canSave {
    final typed = _title.text.trim();
    return typed.isNotEmpty &&
        typed.length <= kMaxNoteTitleLength &&
        typed != widget.initialTitle;
  }

  void _save() {
    if (_canSave) Navigator.of(context).pop(_title.text.trim());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: NoteRenameDialog.dialogKey,
    title: const Text(EditorStrings.renameNote),
    content: TextField(
      key: NoteRenameDialog.fieldKey,
      controller: _title,
      autofocus: true,
      maxLength: kMaxNoteTitleLength,
      decoration: const InputDecoration(labelText: EditorStrings.noteInfoTitle),
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => _save(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text(EditorStrings.cancel),
      ),
      FilledButton(
        key: NoteRenameDialog.saveKey,
        onPressed: _canSave ? _save : null,
        child: const Text(EditorStrings.renameSave),
      ),
    ],
  );
}

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
    this.title,
    this.onRename,
  });

  static const dialogKey = ValueKey('editor.noteInfo');
  static const renameKey = ValueKey('editor.noteInfo.rename');

  final core.Note note;
  final int pageCount;

  /// The current title (after a rename in this session); null → note.title.
  final String? title;

  /// (v2.14-ui review) [이름 바꾸기]; null → no button (read-only note).
  final VoidCallback? onRename;

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
          row(EditorStrings.noteInfoTitle, title ?? note.title),
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
        if (onRename != null)
          TextButton(
            key: renameKey,
            onPressed: onRename,
            child: const Text(EditorStrings.renameNote),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(EditorStrings.close),
        ),
      ],
    );
  }
}
