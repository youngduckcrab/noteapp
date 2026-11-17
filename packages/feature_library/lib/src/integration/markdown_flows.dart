// lib/src/integration/markdown_flows.dart — (v2.17-md, C217M-11, m5-7/08-markdown 9) how the
// library runs the MD 문서 slots and '새 MD 문서'. Like pdf_flows.dart: the slot gets the
// LibraryScreen State's context, one call per slot at a time per screen (the entry is
// disabled while it runs), an exception is reported and shows errorGeneric.
import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart'
    show FolderId, NoteId, markdownRepositoryProvider, folderTreeProvider;

import '../common/report_error.dart';
import '../l10n/library_strings.dart';
import '../model/location_label.dart';
import '../state/library_actions.dart';
import '../state/providers.dart';
import '../ui/dialogs/new_markdown_dialog.dart';
import '../ui/feedback/library_snack_bar.dart';
import '../ui/library_scope.dart';
import 'markdown_slots.dart';

final Expando<ValueNotifier<bool>> _importing = Expando(
  'feature_library md import',
);
final Expando<ValueNotifier<bool>> _exporting = Expando(
  'feature_library md export',
);
final Expando<bool> _creating = Expando('feature_library md create');

ValueNotifier<bool> _flag(
  Expando<ValueNotifier<bool>> flags,
  BuildContext context,
) {
  final container = ProviderScope.containerOf(context, listen: false);
  return flags[container] ??= ValueNotifier<bool>(false);
}

/// True while an 'MD 가져오기' started from this screen runs.
ValueListenable<bool> libraryMarkdownImportRunning(BuildContext context) =>
    _flag(_importing, context);

/// True while a '.md로 내보내기' started from this screen runs.
ValueListenable<bool> libraryMarkdownExportRunning(BuildContext context) =>
    _flag(_exporting, context);

Future<bool> _guarded(
  BuildContext context,
  Expando<ValueNotifier<bool>> flags,
  String what,
  Future<void> Function(LibraryScope scope, BuildContext screen) call,
) async {
  final running = _flag(flags, context);
  if (running.value) return false;
  final scope = LibraryScope.read(context);
  final screen = scope.screenContext;
  final messenger = ScaffoldMessenger.maybeOf(screen);
  running.value = true;
  try {
    await call(scope, screen);
  } on Object catch (error, stack) {
    reportLibraryError(error, stack, what);
    if (messenger != null) {
      showLibrarySnackBarOn(
        messenger,
        message: LibraryStrings.errorGeneric,
        sizeClass: scope.sizeClass,
      );
    }
  } finally {
    running.value = false;
  }
  return true;
}

/// 'MD 가져오기' (9): a returned id opens that MD 문서 in view mode.
Future<void> runLibraryMarkdownImport(
  BuildContext context, {
  required LibraryMarkdownImportAction action,
  required FolderId? folderId,
}) => _guarded(context, _importing, 'library md import', (scope, screen) async {
  final id = await action(screen, folderId: folderId);
  if (id != null) scope.openMarkdown(id);
});

/// '.md로 내보내기' of [noteId].
Future<bool> runLibraryMarkdownExport(
  BuildContext context, {
  required LibraryMarkdownExportAction action,
  required NoteId noteId,
}) => _guarded(
  context,
  _exporting,
  'library md export',
  (_, screen) => action(screen, noteId),
);

/// '새 MD 문서' into [folderId] (9): the name dialog (default '새 MD 문서', made unique in
/// the folder) → MarkdownRepository.create → opens it in edit mode.
Future<void> runNewMarkdownFlow(
  BuildContext context, {
  required FolderId? folderId,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  if (_creating[container] ?? false) return;
  _creating[container] = true;
  try {
    final scope = LibraryScope.read(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final actions = container.read(libraryActionsProvider);
    final tree = container.read(folderTreeProvider).value;
    final initial = await actions.uniqueNoteTitle(
      folderId,
      base: LibraryStrings.defaultMarkdownTitle,
    );
    if (!context.mounted) return;
    final title = await showNewMarkdownDialog(
      context,
      initialTitle: initial,
      locationLabel: tree == null
          ? LibraryStrings.home
          : locationLabel(tree, folderId),
    );
    if (title == null) return;
    try {
      final note = await container
          .read(markdownRepositoryProvider)
          .create(folderId: folderId, title: title);
      scope.openMarkdown(note.id, edit: true);
    } on Object catch (error, stack) {
      reportLibraryError(error, stack, 'library new md');
      if (messenger != null) {
        showLibrarySnackBarOn(
          messenger,
          message: libraryFailureMessage(classifyLibraryError(error)),
          sizeClass: scope.sizeClass,
        );
      }
    }
  } finally {
    _creating[container] = null;
  }
}
