// lib/src/ui/dialogs/create_flows.dart — 05-library 6.12: what '새 노트' and
// '새 폴더' do from every control (the grid tile, the empty state, the top
// bar's '새로 만들기' menu, the sidebar's '폴더' header '+'): default name →
// dialog → CORE create → open the note / expand the parent. Failures show a
// snack bar (6.19).
//
// The result is handled even when the control that started the flow is gone
// by then (a closed menu, the empty state replaced by the new item): the
// container, the scope callbacks (they check the screen itself) and the
// messenger are looked up before the first await.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' show FolderId, folderTreeProvider;

import '../../l10n/library_strings.dart';
import '../../model/location_label.dart';
import '../../state/library_actions.dart';
import '../../state/providers.dart';
import '../feedback/library_snack_bar.dart';
import '../library_scope.dart';
import 'new_folder_dialog.dart';
import 'new_note_dialog.dart';

/// Containers with a create flow in progress: one flow at a time per screen
/// (a second tap while the default name is read or CORE writes does nothing).
final Expando<bool> _busy = Expando('feature_library create flow');

Future<void> _guarded(
  ProviderContainer container,
  Future<void> Function() flow,
) async {
  if (_busy[container] ?? false) return;
  _busy[container] = true;
  try {
    await flow();
  } finally {
    _busy[container] = null;
  }
}

void _showFailure(
  ScaffoldMessengerState? messenger,
  LibraryScope scope,
  LibraryFailureKind kind,
) {
  if (messenger == null) return;
  showLibrarySnackBarOn(
    messenger,
    message: libraryFailureMessage(kind),
    sizeClass: scope.sizeClass,
  );
}

/// '새 노트' into [folderId] (null = 홈): uniqueName('제목 없는 노트', …) →
/// new note dialog (defaults = newNoteDefaultsProvider) → createNote → open
/// it (onOpenNote only — no markOpened, N-6).
Future<void> runNewNoteFlow(
  BuildContext context, {
  required FolderId? folderId,
}) {
  final container = ProviderScope.containerOf(context, listen: false);
  return _guarded(container, () async {
    final scope = LibraryScope.read(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final actions = container.read(libraryActionsProvider);
    final tree = container.read(folderTreeProvider).value;
    final title = await actions.uniqueNoteTitle(folderId);
    if (!context.mounted) return;
    final spec = await showNewNoteDialog(
      context,
      initialTitle: title,
      initialOptions: container.read(newNoteDefaultsProvider),
      locationLabel: tree == null
          ? LibraryStrings.home
          : locationLabel(tree, folderId),
    );
    if (spec == null) return;
    final outcome = await actions.createNote(spec, folderId: folderId);
    switch (outcome) {
      case ActionSuccess(:final value):
        scope.openNote(value.id);
      case ActionFailure(:final kind):
        _showFailure(messenger, scope, kind);
    }
  });
}

/// '새 폴더' in [parentId] (null = 홈): uniqueName('새 폴더', …) → new
/// folder dialog → createFolder → the parent (and its ancestors) expanded in
/// the sidebar. Does not open the new folder.
Future<void> runNewFolderFlow(
  BuildContext context, {
  required FolderId? parentId,
}) {
  final container = ProviderScope.containerOf(context, listen: false);
  return _guarded(container, () async {
    final scope = LibraryScope.read(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final actions = container.read(libraryActionsProvider);
    final tree = container.read(folderTreeProvider).value;
    final spec = await showNewFolderDialog(
      context,
      initialName: tree == null
          ? LibraryStrings.defaultFolderName
          : actions.uniqueFolderName(parentId, tree),
      locationLabel: tree == null
          ? LibraryStrings.home
          : locationLabel(tree, parentId),
    );
    if (spec == null) return;
    final outcome = await actions.createFolder(spec, parentId: parentId);
    switch (outcome) {
      case ActionSuccess():
        if (parentId != null) {
          final path = tree?.pathTo(parentId) ?? const [];
          container.read(folderExpansionProvider.notifier).expandAll([
            for (final f in path) f.id,
            parentId,
          ]);
        }
      case ActionFailure(:final kind):
        _showFailure(messenger, scope, kind);
    }
  });
}
