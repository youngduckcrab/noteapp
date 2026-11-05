// lib/src/ui/menu_actions.dart — 06-pdf 4.11 (contract 7.2.19). INFRA turns these into
// EditorMenuItem values (editorMenuItemFromPdf / pdfMenuInvocationOf, 01-infra 4.5.9).
//
// Foundation step B4 (T0, contract 7.6 B4): both menu functions return an empty list. The
// actions come with PDF T17.
import 'package:material_ui/material_ui.dart';

import 'flows.dart';

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
/// B4 (T0): empty list.
List<PdfMenuAction> pdfEditorMoreMenuActions() =>
    const []; // pdf.export, pdf.share, pdf.print, pdf.search

/// 'PDF에서 페이지 삽입' (inserts after currentPageId, else at end; navigates to the first
/// inserted page with onNavigate(firstId, null) — not when the progress dialog was closed
/// with '닫기' during a storage delay, runPdfImportFlow).
///
/// B4 (T0): empty list.
List<PdfMenuAction> pdfEditorAddPageSources() => const []; // pdf.insert
