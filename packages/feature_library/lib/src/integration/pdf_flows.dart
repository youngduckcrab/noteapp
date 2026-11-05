// lib/src/integration/pdf_flows.dart — 05-library 4.3 / 6.9: how the library
// calls the PDF slots (contract 7.2.18). The context handed to the slot is
// the LibraryScreen State's (LibraryScope.screenContext): the selection bar or
// a menu may be gone while the PDF flow runs. An exception from the slot is
// reported and shows errorGeneric (the slots handle user-level failures
// themselves — defensive). One call per slot at a time per screen.
//
// The export from the selection bar is L14; the import menu and the note ⋯
// 'PDF로 내보내기' come with L18.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' show NoteId;

import '../common/report_error.dart';
import '../l10n/library_strings.dart';
import '../ui/feedback/library_snack_bar.dart';
import '../ui/library_scope.dart';
import 'pdf_slots.dart';

/// Containers with an export in progress.
final Expando<bool> _exporting = Expando('feature_library pdf export');

/// True while an export started from this screen runs.
bool isLibraryPdfExportRunning(BuildContext context) =>
    _exporting[ProviderScope.containerOf(context, listen: false)] ?? false;

/// `await action(screenContext, noteIds)`. Does nothing (returns false) when
/// an export from the same screen is still running; otherwise true once the
/// slot returned or failed.
Future<bool> runLibraryPdfExport(
  BuildContext context, {
  required LibraryPdfExportAction action,
  required List<NoteId> noteIds,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  if (_exporting[container] ?? false) return false;
  final scope = LibraryScope.read(context);
  final screen = scope.screenContext;
  final messenger = ScaffoldMessenger.maybeOf(screen);
  _exporting[container] = true;
  try {
    await action(screen, noteIds);
  } on Object catch (error, stack) {
    reportLibraryError(error, stack, 'library pdf export');
    if (messenger != null) {
      showLibrarySnackBarOn(
        messenger,
        message: LibraryStrings.errorGeneric,
        sizeClass: scope.sizeClass,
      );
    }
  } finally {
    _exporting[container] = null;
  }
  return true;
}
