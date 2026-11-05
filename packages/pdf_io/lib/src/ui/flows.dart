// lib/src/ui/flows.dart — 06-pdf 4.11 (contract 7.2.19). UI flows read providers through
// ProviderScope.containerOf(context) (6.13): callers pass a BuildContext only.
//
// Foundation step B4 (T0, contract 7.6 B4): importPdfAsNewNote returned null and
// exportNotesAsPdf does nothing, so INFRA could wire both into the LIBRARY slots. The import
// flow is real from PDF T6 and the search panel from T11; the others come with T15b (bulk
// export) and T16 (export).
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../common/error_report.dart';
import '../common/job_state.dart';
import '../errors.dart';
import '../export/export_types.dart';
import '../import/import_types.dart';
import '../providers.dart';
import '../text/search_notifier.dart';
import 'import_progress_dialog.dart';
import 'import_sheet.dart';
import 'search_panel.dart';
import 'strings_ko.dart';

/// Same shape as EditorMenuContext.navigateToPage (contract 7.2.17).
typedef PdfNavigateCallback = void Function(String pageId, Rect? focusRectPt);

enum PdfExportPurpose { save, share, print }

/// Shows the import sheet ('PDF 파일 선택' button → pick → password → options → progress).
/// Returns null when cancelled, when the flow already showed its error, or when [context]
/// is unmounted midway (silently). Never throws for user-level failures.
/// Requires an ancestor ProviderScope.
/// Storage delay (6.3, contract 7.2.9 v1.2): a failed CORE commit is retried, never thrown,
/// so the progress dialog watches core.persistenceStatusProvider + core.storageInfoProvider
/// and, while core.storageWarningOf(...) == StorageWarning.writeFailing, shows the delay text
/// (6.14) and a '닫기' button ('취소' stays while the job is still cancellable). After '닫기':
/// the flow returns null at once; the job KEEPS RUNNING in pdfImportJobProvider (another
/// import / export gets busy until it ends); when CORE's retried commit succeeds the new note
/// shows up in the library list (insert: the pages show up in the editor via pagesStream),
/// with no result UI and no onNavigate; a failure after that is only reported (6.13).
Future<PdfImportResult?> runPdfImportFlow(
  BuildContext context,
  PdfImportTarget target,
) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final job = container.read(pdfImportJobProvider.notifier);
  final messenger = ScaffoldMessenger.maybeOf(context);
  void say(String text) {
    if (!context.mounted) return;
    messenger?.showSnackBar(SnackBar(content: Text(text)));
  }

  if (job.isBusy) {
    say(const PdfIoException(PdfErrorCode.busy).userMessage);
    return null;
  }
  final choice = await showPdfImportSheet(
    context,
    service: container.read(pdfImportServiceProvider),
    fileSource: container.read(pdfFileSourceProvider),
    target: target,
  );
  if (choice == null) return null;
  final session = choice.session;
  if (!context.mounted) {
    await session.dispose();
    return null;
  }
  if (session.isLargeFile &&
      !await confirmLargePdfImport(context, session.byteLength)) {
    await session.dispose();
    return null;
  }
  if (!context.mounted) {
    await session.dispose();
    return null;
  }
  if (job.isBusy) {
    // Another job started while the sheet was open.
    await session.dispose();
    say(const PdfIoException(PdfErrorCode.busy).userMessage);
    return null;
  }

  final running = job.run(session, target, range: choice.range);
  // The session lives as long as the job, whatever happens to the dialog.
  unawaited(running.whenComplete(session.dispose));

  final navigator = Navigator.of(context, rootNavigator: true);
  final closed = Completer<void>();
  final dialog = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PdfImportProgressDialog(
      onCancel: job.cancel,
      onClose: () {
        if (!closed.isCompleted) closed.complete();
      },
    ),
  );
  unawaited(navigator.push(dialog));
  void removeDialog() {
    if (navigator.mounted && dialog.isActive) navigator.removeRoute(dialog);
  }

  final ended = await Future.any<bool>([
    running.then((_) => true),
    closed.future.then((_) => false),
  ]);
  removeDialog();
  if (!ended) {
    // '닫기' during a storage delay (6.3): the job keeps running; nothing to show later.
    unawaited(
      running.then((_) {
        final state = container.read(pdfImportJobProvider);
        if (state is PdfJobFailed<PdfImportResult> &&
            state.error.code != PdfErrorCode.cancelled) {
          reportPdfError(
            state.error,
            StackTrace.current,
            'pdf import after its progress dialog was closed',
          );
        }
      }),
    );
    return null;
  }
  final result = await running;
  if (!context.mounted) return null;
  if (result != null) {
    say(PdfStringsKo.importDone(result.insertedPageIds.length));
    return result;
  }
  final state = container.read(pdfImportJobProvider);
  if (state is PdfJobFailed<PdfImportResult> &&
      state.error.code != PdfErrorCode.cancelled) {
    say(state.error.userMessage);
  }
  return null;
}

/// LibraryPdfImportAction shape (contract 7.2.18 / 7.2.19):
/// runPdfImportFlow(context, PdfImportAsNewNote(folderId: folderId)) → created note id or null.
/// null also when the progress dialog was closed with '닫기' during a storage delay: the job
/// keeps running and the note appears in the library once CORE commits it (runPdfImportFlow).
/// INFRA FeatureWiringModule: libraryPdfImportActionProvider.overrideWithValue(importPdfAsNewNote).
Future<String?> importPdfAsNewNote(
  BuildContext context, {
  String? folderId,
}) async {
  final result = await runPdfImportFlow(
    context,
    PdfImportAsNewNote(folderId: folderId),
  );
  return result?.noteId;
}

/// Options sheet → progress dialog (cancellable; shows the storage-delay text while
/// writeFailing — 6.11.2 step 1, '취소' ends a pending flush at once) → result sheet
/// (share/download/open).
Future<PdfExportResult?> runPdfExportFlow(
  BuildContext context, {
  required String noteId,
  String? currentPageId,
  List<String> selectedPageIds = const [],
  PdfExportPurpose purpose = PdfExportPurpose.save,
}) => throw UnimplementedError('runPdfExportFlow (PDF T16)');

/// LibraryPdfExportAction shape (contract 7.2.18 / 7.2.19), F-01 bulk export (6.12.1):
/// options sheet (필기·속지 포함) → one PDF per note in [noteIds] order with a cancellable overall
/// progress (storage-delay text while writeFailing, 6.12.1) → result sheet (share all when
/// possible, else per-file download). Empty list → no-op.
/// Errors are shown inside the flow; never throws for user-level failures.
/// INFRA FeatureWiringModule: libraryPdfExportActionProvider.overrideWithValue(exportNotesAsPdf).
///
/// Contract 7.2.19: LibraryPdfExportAction shape: one PDF per note, then the result sheet
/// (share all / download).
/// B4 (T0): does nothing (no flow yet).
Future<void> exportNotesAsPdf(
  BuildContext context,
  List<String> noteIds,
) async {}

/// Search sheet (query field, progress, hit list). Tapping a hit selects it and calls [onNavigate].
///
/// T11: a modal bottom sheet (search_panel.dart) on the container of [context]; completes
/// when it closes. Closing it cancels a running search (6.10.2 step 0); the hits found stay
/// highlighted until a new query or PdfSearchNotifier.clear(), and reopening the panel for
/// the same note shows them again (a search stopped midway runs again).
Future<void> showPdfSearchPanel(
  BuildContext context, {
  required String noteId,
  required PdfNavigateCallback onNavigate,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  try {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => UncontrolledProviderScope(
        container: container,
        child: PdfSearchPanel(noteId: noteId, onNavigate: onNavigate),
      ),
    );
  } finally {
    stopPdfSearch(container.read(pdfActiveSearchProvider.notifier));
  }
}
