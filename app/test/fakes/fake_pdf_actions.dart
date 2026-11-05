// Fake PDF actions (docs/plans/01-infra.md 5.7): closures in the shapes of
// pdf_io's importPdfAsNewNote / exportNotesAsPdf and PdfMenuAction lists that
// record their invocations.
import 'package:feature_library/feature_library.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf_io/pdf_io.dart';

/// One recorded PdfMenuAction.run call.
final class RecordedPdfRun {
  RecordedPdfRun(this.actionId, this.context, this.invocation);

  final String actionId;
  final BuildContext context;
  final PdfMenuInvocation invocation;
}

final class FakePdfActions {
  FakePdfActions({
    this._moreMenuIds = const ['pdf.export', 'pdf.share', 'pdf.search'],
    this._addPageIds = const ['pdf.insert'],
  });

  final List<String> _moreMenuIds;
  final List<String> _addPageIds;

  final List<String?> importFolders = [];
  final List<List<String>> exports = [];
  final List<RecordedPdfRun> runs = [];

  /// isEnabled checks (action id, invocation).
  final List<(String, PdfMenuInvocation)> enabledChecks = [];

  /// LibraryPdfImportAction shape; returns `imported-<n>`. One function
  /// object per fake (identity is checked).
  late final LibraryPdfImportAction importPdf = _import;

  /// LibraryPdfExportAction shape.
  late final LibraryPdfExportAction exportPdf = _export;

  Future<String?> _import(BuildContext context, {String? folderId}) async {
    importFolders.add(folderId);
    return 'imported-${importFolders.length}';
  }

  Future<void> _export(BuildContext context, List<String> noteIds) async {
    exports.add(noteIds);
  }

  PdfMenuAction action(String id, {bool withIsEnabled = false}) =>
      PdfMenuAction(
        id: id,
        label: 'label $id',
        icon: Icons.picture_as_pdf,
        run: (context, invocation) async {
          runs.add(RecordedPdfRun(id, context, invocation));
        },
        isEnabled: withIsEnabled
            ? (invocation) {
                enabledChecks.add((id, invocation));
                return invocation.selectedPageIds.isNotEmpty;
              }
            : null,
      );

  List<PdfMenuAction> moreMenuActions() => [
    for (final id in _moreMenuIds) action(id),
  ];

  List<PdfMenuAction> addPageActions() => [
    for (final id in _addPageIds) action(id),
  ];
}
