// lib/src/ui/pages/page_panel_selection_bar.dart — 04-editor 6.11.2.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../../scope/editor_scope.dart';
import '../../state/page_panel.dart';
import '../editor_strings.dart';

/// Under the panel header in the selection mode: "n쪽 선택됨" [완료] /
/// [모두 선택] [복제] [삭제]. [복제]·[삭제] are disabled while nothing is
/// selected and on a read-only note; [삭제] also when every page is selected
/// (nothing would remain — contract 7.2.6). Both act on the selection in note
/// order, one undo step each.
class PagePanelSelectionBar extends ConsumerWidget {
  const PagePanelSelectionBar({super.key, required this.pages});

  /// The panel's page list (note order).
  final List<core.Page> pages;

  static const barKey = ValueKey('editor.pagePanel.selectionBar');
  static const selectAllKey = ValueKey('editor.pagePanel.selectAll');
  static const duplicateKey = ValueKey('editor.pagePanel.duplicateSelected');
  static const deleteKey = ValueKey('editor.pagePanel.deleteSelected');
  static const doneKey = ValueKey('editor.pagePanel.done');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final panel = ref.watch(editorPagePanelProvider);
    final readOnly = ref.watch(editorReadOnlyProvider);
    final commands = ref.watch(editorCommandsProvider);
    final notifier = ref.read(editorPagePanelProvider.notifier);
    final ids = [for (final p in pages) p.id];
    final selected = panel.orderedSelection(ids);
    final canAct = selected.isNotEmpty && !readOnly;
    final canDelete = canAct && selected.length < ids.length;
    final theme = Theme.of(context);
    return Padding(
      key: barKey,
      padding: const EdgeInsets.fromLTRB(12, 0, 4, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  EditorStrings.pagesSelected(selected.length),
                  style: theme.textTheme.labelLarge,
                ),
              ),
              TextButton(
                key: doneKey,
                style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                onPressed: () => notifier.setSelecting(false),
                child: const Text(EditorStrings.done),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                key: selectAllKey,
                onPressed: () => notifier.selectAll(ids),
                icon: const Icon(
                  Icons.select_all,
                  semanticLabel: EditorStrings.selectAll,
                ),
              ),
              IconButton(
                key: duplicateKey,
                onPressed: canAct
                    ? () => unawaited(commands.duplicatePages(selected))
                    : null,
                icon: const Icon(
                  Icons.copy,
                  semanticLabel: EditorStrings.duplicatePage,
                ),
              ),
              IconButton(
                key: deleteKey,
                onPressed: canDelete
                    ? () => commands.deletePages(selected)
                    : null,
                icon: const Icon(
                  Icons.delete_outline,
                  semanticLabel: EditorStrings.deletePage,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
