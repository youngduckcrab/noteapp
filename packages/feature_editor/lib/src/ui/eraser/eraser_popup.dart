// lib/src/ui/eraser/eraser_popup.dart — 04-editor 6.6.4 #5, 6.9.
//
// E-09: clearing the current page (confirmation dialog → EditorCommands).
// The eraser popup itself (mode, size, filter, return to the previous tool)
// joins with E-15; its "현재 페이지 지우기" button and the more menu item
// (E-13) both call [confirmClearCurrentPage].
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../../commands/editor_commands.dart';
import '../editor_strings.dart';

/// The confirmation title for the eraser [filter] (6.6.4 #5).
String clearPageTitleFor(core.StrokeFilter filter) => switch (filter) {
  core.StrokeFilter.all => EditorStrings.clearPageTitle,
  core.StrokeFilter.highlighterOnly =>
    EditorStrings.clearPageTitleHighlighterOnly,
  core.StrokeFilter.exceptHighlighter =>
    EditorStrings.clearPageTitleExceptHighlighter,
};

/// Asks "이 페이지의 필기를 모두 지울까요?" (worded by [filter]) and, when the
/// user confirms, runs [EditorCommands.clearCurrentPage] — one
/// core.ClearPage(current page, eraser filter) step through _runAsync. INK
/// clearPage is not used (contract 7.2.15). Returns true when the user
/// confirmed.
Future<bool> confirmClearCurrentPage(
  BuildContext context, {
  required EditorCommands commands,
  required core.StrokeFilter filter,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => ClearPageDialog(filter: filter),
  );
  if (confirmed != true) return false;
  await commands.clearCurrentPage();
  return true;
}

/// The confirmation dialog of [confirmClearCurrentPage]: pops true on
/// [EditorStrings.clearPageConfirm], false on [EditorStrings.cancel].
class ClearPageDialog extends StatelessWidget {
  const ClearPageDialog({super.key, required this.filter});

  final core.StrokeFilter filter;

  /// Key of the confirm button.
  static const confirmKey = ValueKey('editor.clearPage.confirm');

  /// Key of the cancel button.
  static const cancelKey = ValueKey('editor.clearPage.cancel');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(clearPageTitleFor(filter)),
      content: const Text(EditorStrings.clearPageBody),
      actions: [
        TextButton(
          key: cancelKey,
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(EditorStrings.cancel),
        ),
        FilledButton(
          key: confirmKey,
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text(EditorStrings.clearPageConfirm),
        ),
      ],
    );
  }
}
