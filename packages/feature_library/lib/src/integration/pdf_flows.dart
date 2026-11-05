// lib/src/integration/pdf_flows.dart — 05-library 4.3 / 6.8 / 6.9: how the
// library calls the PDF slots (contract 7.2.18). The context handed to a
// slot is the LibraryScreen State's (LibraryScope.screenContext): the
// selection bar or a menu may be gone while the PDF flow runs. An exception
// from a slot is reported and shows errorGeneric (the slots handle
// user-level failures themselves — defensive). One call per slot at a time
// per screen: while one runs its entry points are disabled.
//
// Entry points: export — the selection bar (L14) and the note ⋯ 'PDF로
// 내보내기'; import — 새로 만들기 › 'PDF 가져오기' (L18).
import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' show FolderId, NoteId;

import '../common/report_error.dart';
import '../l10n/library_strings.dart';
import '../ui/feedback/library_snack_bar.dart';
import '../ui/library_scope.dart';
import 'pdf_slots.dart';

/// Per ProviderContainer (one per app / test): whether a slot call runs.
final Expando<ValueNotifier<bool>> _exporting = Expando(
  'feature_library pdf export',
);
final Expando<ValueNotifier<bool>> _importing = Expando(
  'feature_library pdf import',
);

ValueNotifier<bool> _flag(
  Expando<ValueNotifier<bool>> flags,
  BuildContext context,
) {
  final container = ProviderScope.containerOf(context, listen: false);
  return flags[container] ??= ValueNotifier<bool>(false);
}

/// True while an export started from this screen runs.
ValueListenable<bool> libraryPdfExportRunning(BuildContext context) =>
    _flag(_exporting, context);

/// True while an import started from this screen runs.
ValueListenable<bool> libraryPdfImportRunning(BuildContext context) =>
    _flag(_importing, context);

/// Runs [call] with the slot flag set, reporting an exception with
/// errorGeneric. false (nothing done) while the flag is already set.
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

/// `await action(screenContext, noteIds)`. Does nothing (returns false) when
/// an export from the same screen is still running; otherwise true once the
/// slot returned or failed.
Future<bool> runLibraryPdfExport(
  BuildContext context, {
  required LibraryPdfExportAction action,
  required List<NoteId> noteIds,
}) => _guarded(
  context,
  _exporting,
  'library pdf export',
  (_, screen) => action(screen, noteIds),
);

/// `await action(screenContext, folderId: folderId)` (4.3): a returned note
/// id opens that note (onOpenNote only — no markOpened); null does nothing
/// (the PDF flow showed its own cancel / error). Ignored while an import from
/// the same screen runs.
Future<void> runLibraryPdfImport(
  BuildContext context, {
  required LibraryPdfImportAction action,
  required FolderId? folderId,
}) async {
  await _guarded(context, _importing, 'library pdf import', (
    scope,
    screen,
  ) async {
    final id = await action(screen, folderId: folderId);
    if (id != null) scope.openNote(id);
  });
}
