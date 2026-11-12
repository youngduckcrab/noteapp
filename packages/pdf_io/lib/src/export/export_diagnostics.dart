// lib/src/export/export_diagnostics.dart — the export memory ledger's developer lines (contract
// v2.6 C26-02, C22-06 ②; m5-7/06-pdf 6.2.10 ⑤). src only (not in the barrel): the barrel shows
// pdfDevOverlayLinesProvider, which reads [PdfExportDiagnostics] through an internal provider.
//
// After each note's compose loop (finished, failed or cancelled) the export service hands its
// ExportMemoryLedger to [PdfExportDiagnostics.record]. The lines (English abbreviations and
// numbers — developer use, the shape of the 1차 'pdf.render' section) are:
//   'export: peak 12.3 / 16.0 MB · copy 4.0 MB'    the last note's budget peak / budget, and the
//                                                  native worker copy peak (CP-PDF-14 ①)
//   'export: over budget 1 (total 2 in 5)'         the last note's overBudget count (CP-PDF-14 ②),
//                                                  the sum over this session and the notes counted
// No export yet → no lines (the provider's default is the empty list).
import 'package:flutter/foundation.dart';

import 'export_memory.dart';

/// The last export's memory numbers, for the developer overlay. Listenable: notifies after
/// each [record].
final class PdfExportDiagnostics extends ChangeNotifier {
  int _exports = 0, _overBudgetTotal = 0;
  int _peakBytes = 0, _budgetBytes = 0, _peakCopyBytes = 0, _overBudget = 0;

  /// Notes whose ledger was recorded.
  int get exports => _exports;

  /// overBudget summed over [exports].
  int get overBudgetTotal => _overBudgetTotal;

  /// Records [ledger] as the last export's numbers.
  void record(ExportMemoryLedger ledger) {
    _exports++;
    _peakBytes = ledger.peakBytes;
    _budgetBytes = ledger.budgetBytes;
    _peakCopyBytes = ledger.peakCopyBytes;
    _overBudget = ledger.overBudget;
    _overBudgetTotal += ledger.overBudget;
    notifyListeners();
  }

  /// The developer lines; empty before the first [record].
  List<String> get lines => _exports == 0
      ? const []
      : List.unmodifiable([
          'export: peak ${_mb(_peakBytes)} / ${_mb(_budgetBytes)} MB · copy ${_mb(_peakCopyBytes)} MB',
          'export: over budget $_overBudget (total $_overBudgetTotal in $_exports)',
        ]);

  /// Bytes as MB (1024 × 1024) with one decimal.
  static String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);
}
