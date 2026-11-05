// lib/src/ui/menus/item_action_flows.dart — 05-library 6.11: what the item
// menus (⋯ of a tile / row, the sidebar tree row menu) and the list row ☆ do:
// dialog (if any) → LibraryActions → result snack bar. Failures show the 6.19
// snack bar; rename shows only failures.
//
// Same rules as the create flows (create_flows.dart): the container, the
// scope and the messenger are looked up before the first await, so a result
// is still shown when the widget that started the action is gone (a moved /
// trashed tile leaves the listing). The same action on the same item runs
// once at a time per screen; a repeat while it runs does nothing (6.11).
//
// The multi-item flows (move, trash, favorite) take the items in display
// order so the selection bar (L14) reuses them.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart'
    show Folder, FolderId, FolderTree, Note, NoteId, folderTreeProvider;

import '../../l10n/library_strings.dart';
import '../../model/folder_appearance_value.dart';
import '../../model/item_key.dart';
import '../../state/library_actions.dart';
import '../../state/providers.dart';
import '../dialogs/cover_dialog.dart';
import '../dialogs/folder_appearance_dialog.dart';
import '../dialogs/folder_picker_dialog.dart';
import '../dialogs/rename_dialog.dart';
import '../feedback/library_snack_bar.dart';
import '../library_scope.dart';

/// Running `'<action> <items>'` entries per container (one screen).
final Expando<Set<String>> _running = Expando('feature_library item action');

/// What a flow needs after its first await.
final class _FlowContext {
  _FlowContext(BuildContext context)
    : container = ProviderScope.containerOf(context, listen: false),
      scope = LibraryScope.read(context),
      messenger = ScaffoldMessenger.maybeOf(context);

  final ProviderContainer container;
  final LibraryScope scope;
  final ScaffoldMessengerState? messenger;

  LibraryActions get actions => container.read(libraryActionsProvider);

  void show(String message, {SnackBarAction? action}) {
    final messenger = this.messenger;
    if (messenger == null) return;
    showLibrarySnackBarOn(
      messenger,
      message: message,
      sizeClass: scope.sizeClass,
      action: action,
    );
  }

  void showFailure(LibraryFailureKind kind) =>
      show(libraryFailureMessage(kind));

  /// Shows the failure of [outcome]; true when it succeeded.
  bool check(ActionOutcome<Object?> outcome) {
    if (outcome case ActionFailure(:final kind)) {
      showFailure(kind);
      return false;
    }
    return true;
  }

  /// Runs [body] unless the same [action] on the same [items] runs already.
  Future<void> once(
    String action,
    List<LibraryItemKey> items,
    Future<void> Function() body,
  ) async {
    final running = _running[container] ??= <String>{};
    final entry = '$action ${items.map((k) => '${k.kind.name}:${k.id}')}';
    if (!running.add(entry)) return;
    try {
      await body();
    } finally {
      running.remove(entry);
    }
  }
}

/// The name a result message uses for [target] (null = 홈). Reads the latest
/// tree (a folder made inside the picker is not in an older one).
String _targetName(ProviderContainer container, FolderId? target) {
  if (target == null) return LibraryStrings.home;
  final FolderTree? tree = container.read(folderTreeProvider).value;
  return tree?.byId(target)?.name ?? LibraryStrings.home;
}

/// 이름 변경 (6.11): rename dialog → renameFolder / renameNote. Only a
/// failure shows a snack bar.
Future<void> runRenameFlow(
  BuildContext context, {
  required LibraryItemKey item,
  required String currentName,
}) {
  final flow = _FlowContext(context);
  return flow.once('rename', [item], () async {
    final name = await showRenameDialog(
      context,
      title: LibraryStrings.rename,
      initialName: currentName,
    );
    if (name == null || name == currentName) return;
    flow.check(await flow.actions.rename(item, name));
  });
}

/// 꾸미기 (folders): appearance dialog → setFolderAppearance (no color →
/// clearColor, default icon → clearIcon). Nothing shows on success.
Future<void> runFolderAppearanceFlow(BuildContext context, Folder folder) {
  final flow = _FlowContext(context);
  return flow.once('appearance', [folderKey(folder.id)], () async {
    final initial = FolderAppearance(
      colorArgb: folder.colorArgb,
      icon: folder.icon,
    );
    final chosen = await showFolderAppearanceDialog(context, initial: initial);
    if (chosen == null || chosen == initial) return;
    flow.check(await flow.actions.setFolderAppearance(folder.id, chosen));
  });
}

/// 표지 변경 (notes): cover dialog → setCover. Nothing shows on success.
Future<void> runCoverFlow(BuildContext context, Note note) {
  final flow = _FlowContext(context);
  return flow.once('cover', [noteKey(note.id)], () async {
    final cover = await showCoverDialog(context, current: note.cover);
    if (cover == null || cover == note.cover) return;
    flow.check(await flow.actions.setCover(note.id, cover));
  });
}

/// ☆ 즐겨찾기 / ★ 해제: setFavorite(ids, favorite). Nothing shows on success.
Future<void> runFavoriteFlow(
  BuildContext context, {
  required List<NoteId> ids,
  required bool favorite,
  VoidCallback? onDone,
}) {
  final flow = _FlowContext(context);
  return flow.once('favorite', [for (final id in ids) noteKey(id)], () async {
    if (flow.check(await flow.actions.setFavorite(ids, favorite))) {
      onDone?.call();
    }
  });
}

/// 복사 from an item's menu: right away into the same parent with ' 사본'
/// → '복사했어요'.
Future<void> runCopyHereFlow(
  BuildContext context, {
  required LibraryItemKey item,
  required FolderId? parentId,
}) {
  final flow = _FlowContext(context);
  return flow.once('copy', [item], () async {
    final outcome = await flow.actions.copy(
      [item],
      target: parentId,
      nameSuffix: LibraryStrings.copySuffix,
    );
    if (flow.check(outcome)) flow.show(LibraryStrings.copied);
  });
}

/// 복사 from the selection bar: folder picker ('복사할 위치', starting at
/// [initialFolderId] — the current folder or 홈) → copy with ' 사본' when the
/// target is the current parent of an item (else no suffix) → '항목 n개를
/// 복사했어요'. [items] in display order, [parents] = the current parent of
/// every item (null = 홈).
Future<void> runCopyToFlow(
  BuildContext context, {
  required List<LibraryItemKey> items,
  required Map<LibraryItemKey, FolderId?> parents,
  required FolderId? initialFolderId,
  VoidCallback? onDone,
}) {
  final flow = _FlowContext(context);
  return flow.once('copyTo', items, () async {
    if (items.isEmpty) return;
    final picked = await showFolderPickerDialog(
      context,
      title: LibraryStrings.copyDestination,
      confirmLabel: LibraryStrings.copyHere,
      initialFolderId: initialFolderId,
    );
    if (picked == null) return;
    final target = picked.folderId;
    final here = items.any((k) => parents[k] == target);
    final outcome = await flow.actions.copy(
      items,
      target: target,
      nameSuffix: here ? LibraryStrings.copySuffix : '',
    );
    if (!flow.check(outcome)) return;
    onDone?.call();
    flow.show(LibraryStrings.copiedCount(items.length));
  });
}

/// 이동… : folder picker ('이동할 위치' — the moved folders and their
/// sub-folders disabled; the confirm button disabled for the one parent all
/// items share) → move → `"'<target>'(으)로 옮겼어요"` / "항목 n개를 …" +
/// [실행 취소] → undoMove. [items] in display order, [parents] = the current
/// parent of every item (null = 홈).
Future<void> runMoveFlow(
  BuildContext context, {
  required List<LibraryItemKey> items,
  required Map<LibraryItemKey, FolderId?> parents,
  VoidCallback? onDone,
}) {
  final flow = _FlowContext(context);
  return flow.once('move', items, () async {
    if (items.isEmpty) return;
    final tree = flow.container.read(folderTreeProvider).value;
    final disabled = <FolderId>{
      for (final k in items)
        if (k.isFolder) ...{k.id, ...?tree?.descendantsOf(k.id)},
    };
    final current = {for (final k in items) parents[k]};
    final picked = await showFolderPickerDialog(
      context,
      title: LibraryStrings.moveDestination,
      confirmLabel: LibraryStrings.moveHere,
      initialFolderId: current.length == 1 ? current.single : null,
      disabled: disabled,
      noOpTargets: current.length == 1 ? current : const {},
    );
    if (picked == null) return;
    final target = picked.folderId;
    final outcome = await flow.actions.move(
      items,
      target: target,
      originalParents: parents,
    );
    switch (outcome) {
      case ActionSuccess(value: final receipt):
        onDone?.call();
        final name = _targetName(flow.container, target);
        flow.show(
          items.length == 1
              ? LibraryStrings.movedTo(name)
              : LibraryStrings.movedCountTo(items.length, name),
          action: receipt.isEmpty
              ? null
              : SnackBarAction(
                  label: LibraryStrings.undo,
                  onPressed: () async =>
                      flow.check(await flow.actions.undoMove(receipt)),
                ),
        );
      case ActionFailure(:final kind):
        flow.showFailure(kind);
    }
  });
}

/// 휴지통으로 이동 (no confirmation): trash → "'<이름>'을(를) 휴지통으로
/// 옮겼어요" (one item, [singleName]) / '항목 n개를 휴지통으로 옮겼어요' +
/// [실행 취소] → restore.
Future<void> runTrashFlow(
  BuildContext context, {
  required List<LibraryItemKey> items,
  String? singleName,
  VoidCallback? onDone,
}) {
  final flow = _FlowContext(context);
  return flow.once('trash', items, () async {
    if (items.isEmpty) return;
    final outcome = await flow.actions.trash(items);
    if (!flow.check(outcome)) return;
    onDone?.call();
    flow.show(
      items.length == 1 && singleName != null
          ? LibraryStrings.trashedOne(singleName)
          : LibraryStrings.trashedCount(items.length),
      action: SnackBarAction(
        label: LibraryStrings.undo,
        onPressed: () async => flow.check(await flow.actions.restore(items)),
      ),
    );
  });
}
