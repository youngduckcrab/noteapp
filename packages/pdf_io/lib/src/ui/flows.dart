// lib/src/ui/flows.dart — 06-pdf 4.11 (contract 7.2.19). UI flows read providers through
// ProviderScope.containerOf(context) (6.13): callers pass a BuildContext only.
//
// Foundation step B4 (T0, contract 7.6 B4): importPdfAsNewNote returns null and
// exportNotesAsPdf does nothing, so INFRA can wire both into the LIBRARY slots now. The
// flows come with PDF T6 (import), T11 (search), T15b (bulk export) and T16 (export).
import 'package:material_ui/material_ui.dart';

import '../export/export_types.dart';
import '../import/import_types.dart';

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
) => throw UnimplementedError('runPdfImportFlow (PDF T6)');

/// LibraryPdfImportAction shape (contract 7.2.18 / 7.2.19):
/// runPdfImportFlow(context, PdfImportAsNewNote(folderId: folderId)) → created note id or null.
/// null also when the progress dialog was closed with '닫기' during a storage delay: the job
/// keeps running and the note appears in the library once CORE commits it (runPdfImportFlow).
/// INFRA FeatureWiringModule: libraryPdfImportActionProvider.overrideWithValue(importPdfAsNewNote).
///
/// B4 (T0): always null (no flow yet).
Future<String?> importPdfAsNewNote(
  BuildContext context, {
  String? folderId,
}) async => null;

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
Future<void> showPdfSearchPanel(
  BuildContext context, {
  required String noteId,
  required PdfNavigateCallback onNavigate,
}) => throw UnimplementedError('showPdfSearchPanel (PDF T11)');
