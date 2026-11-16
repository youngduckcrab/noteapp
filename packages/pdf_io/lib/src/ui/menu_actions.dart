// lib/src/ui/menu_actions.dart — 06-pdf 4.11 (contract 7.2.19). INFRA turns these into
// EditorMenuItem values (editorMenuItemFromPdf / pdfMenuInvocationOf, 01-infra 4.5.9).
//
// Foundation step B4 (T0, contract 7.6 B4): both menu functions returned an empty list. The
// actions are real from PDF T17: the three export entries run runPdfExportFlow with their
// purpose, 'pdf.search' opens showPdfSearchPanel, 'pdf.insert' runs runPdfImportFlow into
// the note and then navigates to the first inserted page.
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../import/import_types.dart';
import 'flows.dart';
import 'strings_ko.dart';

@immutable
final class PdfMenuInvocation {
  const PdfMenuInvocation({
    required this.noteId,
    this.currentPageId,
    this.selectedPageIds = const [],
    this.onNavigate,
  });
  final String noteId;
  final String? currentPageId;

  /// EditorMenuContext.selectedPageIds (note order)
  final List<String> selectedPageIds;
  final PdfNavigateCallback? onNavigate; // EditorMenuContext.navigateToPage
}

@immutable
final class PdfMenuAction {
  const PdfMenuAction({
    required this.id,
    required this.label,
    required this.icon,
    required this.run,
    this.isEnabled,
  });
  final String id; // stable: 'pdf.export', 'pdf.share', 'pdf.print', 'pdf.search', 'pdf.insert'
  final String label; // Korean
  final IconData icon;
  final Future<void> Function(
    BuildContext context,
    PdfMenuInvocation invocation,
  )
  run;
  final bool Function(PdfMenuInvocation invocation)? isEnabled;
}

/// 'PDF로 내보내기', 'PDF 공유', '인쇄', 'PDF에서 찾기' (search disabled without onNavigate).
/// Export defaults to '선택한 페이지' when selectedPageIds is not empty.
///
/// T17: in this order, ids 'pdf.export' / 'pdf.share' / 'pdf.print' / 'pdf.search'. The
/// export entries pass the invocation's currentPageId and selectedPageIds to
/// runPdfExportFlow with PdfExportPurpose.save / share / print (the options sheet makes
/// '선택한 페이지' the default when a selected id is a page of the note).
List<PdfMenuAction> pdfEditorMoreMenuActions() => [
  _exportAction(
    'pdf.export',
    PdfStringsKo.exportTitle,
    Icons.picture_as_pdf_outlined,
    PdfExportPurpose.save,
  ),
  _exportAction(
    'pdf.share',
    PdfStringsKo.shareTitle,
    Icons.share_rounded, // Android share (ui_kit AppIconKind.share)
    PdfExportPurpose.share,
  ),
  _exportAction(
    'pdf.print',
    PdfStringsKo.printTitle,
    Icons.print_outlined,
    PdfExportPurpose.print,
  ),
  PdfMenuAction(
    id: 'pdf.search',
    label: PdfStringsKo.searchTitle,
    icon: Icons.search,
    isEnabled: (invocation) => invocation.onNavigate != null,
    run: (context, invocation) async {
      final onNavigate = invocation.onNavigate;
      if (onNavigate == null) return; // disabled (isEnabled)
      await showPdfSearchPanel(
        context,
        noteId: invocation.noteId,
        onNavigate: onNavigate,
      );
    },
  ),
];

PdfMenuAction _exportAction(
  String id,
  String label,
  IconData icon,
  PdfExportPurpose purpose,
) => PdfMenuAction(
  id: id,
  label: label,
  icon: icon,
  run: (context, invocation) async {
    await runPdfExportFlow(
      context,
      noteId: invocation.noteId,
      currentPageId: invocation.currentPageId,
      selectedPageIds: invocation.selectedPageIds,
      purpose: purpose,
    );
  },
);

/// 'PDF에서 페이지 삽입' (inserts after currentPageId, else at end; navigates to the first
/// inserted page with onNavigate(firstId, null) — not when the progress dialog was closed
/// with '닫기' during a storage delay, runPdfImportFlow).
///
/// T17: id 'pdf.insert'; nothing to navigate to when the import was cancelled or failed
/// (runPdfImportFlow returns null) or when onNavigate is null.
List<PdfMenuAction> pdfEditorAddPageSources() => [
  PdfMenuAction(
    id: 'pdf.insert',
    label: PdfStringsKo.importIntoNoteTitle,
    icon: Icons.note_add_outlined,
    run: (context, invocation) async {
      final current = invocation.currentPageId;
      final result = await runPdfImportFlow(
        context,
        PdfImportIntoNote(
          noteId: invocation.noteId,
          position: current == null
              ? const core.PageAtEnd()
              : core.PageAfter(current),
        ),
      );
      final pages = result?.insertedPageIds ?? const <String>[];
      if (pages.isEmpty) return;
      invocation.onNavigate?.call(pages.first, null);
    },
  ),
];
