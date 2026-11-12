// pdfDevOverlayLinesProvider (contract v2.6 C26-02 — added only; C22-06 ②, m5-7/06-pdf 6.2.10
// ⑤): the empty list before any export, then the last note's ledger peakBytes and overBudget
// (the counts that were a debugPrint before), rebuilt after each export. The export service
// records each note's ledger after its compose loop, finished or failed.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/src/export/export_diagnostics.dart';
import 'package:pdf_io/src/export/export_memory.dart';
import 'package:pdf_io/src/providers.dart' show pdfExportDiagnosticsProvider;

import '../support/export_world.dart';

const int _mib = 1024 * 1024;

ExportMemoryLedger _ledger({required int peak, int overBy = 0}) {
  final l = ExportMemoryLedger();
  final a = l.hold(ExportMemoryKind.rgba, peak);
  if (overBy > 0) l.release(l.hold(ExportMemoryKind.encoded, overBy));
  l.release(a);
  return l;
}

void main() {
  group('PdfExportDiagnostics', () {
    test('no export → no lines', () {
      final d = PdfExportDiagnostics();
      addTearDown(d.dispose);
      expect(d.lines, isEmpty);
      expect(d.exports, 0);
    });

    test('lines = the last ledger: peak / budget, copy peak, overBudget and the total', () {
      final d = PdfExportDiagnostics();
      addTearDown(d.dispose);
      var notified = 0;
      d.addListener(() => notified++);
      d.record(_ledger(peak: 12 * _mib + _mib ~/ 4));
      expect(notified, 1);
      expect(d.lines, [
        'export: peak 12.3 / 16.0 MB · copy 0.0 MB',
        'export: over budget 0 (total 0 in 1)',
      ]);
      // M-3 outside input (CP-PDF-14 ②): the sum went over 16 MiB once
      d.record(_ledger(peak: 10 * _mib, overBy: 10 * _mib));
      expect(d.lines, [
        'export: peak 20.0 / 16.0 MB · copy 0.0 MB',
        'export: over budget 1 (total 1 in 2)',
      ]);
      d.record(_ledger(peak: _mib));
      expect(d.lines.last, 'export: over budget 0 (total 1 in 3)');
      expect(notified, 3);
      expect(() => d.lines.add('x'), throwsUnsupportedError);
    });
  });

  group('pdfDevOverlayLinesProvider', () {
    test('default: the empty list, without any store or override', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(pdfDevOverlayLinesProvider), isEmpty);
    });

    test('rebuilt after each recorded export; listeners hear it', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final seen = <List<String>>[];
      c.listen(pdfDevOverlayLinesProvider, (_, next) => seen.add(next));
      expect(c.read(pdfDevOverlayLinesProvider), isEmpty);
      final d = c.read(pdfExportDiagnosticsProvider);
      d.record(_ledger(peak: 10 * _mib, overBy: 10 * _mib));
      expect(c.read(pdfDevOverlayLinesProvider), [
        'export: peak 20.0 / 16.0 MB · copy 0.0 MB',
        'export: over budget 1 (total 1 in 1)',
      ]);
      expect(seen, hasLength(1));
      d.record(_ledger(peak: _mib));
      expect(
        c.read(pdfDevOverlayLinesProvider).last,
        'export: over budget 0 (total 1 in 2)',
      );
      expect(seen, hasLength(2));
    });

    test(
      'the export service records each note\'s ledger after its compose loop',
      () async {
        final w = ExportWorld();
        addTearDown(w.diagnostics.dispose);
        final note = await w.note('n', [blankDraft, blankDraft]);
        expect(w.diagnostics.lines, isEmpty);
        await w.service.exportNote(note.id, const PdfExportOptions());
        final ledger = w.ledgers.single;
        expect(w.diagnostics.exports, 1);
        expect(w.diagnostics.lines.first, startsWith('export: peak '));
        expect(
          w.diagnostics.lines.first,
          contains('${(ledger.peakBytes / _mib).toStringAsFixed(1)} / 16.0 MB'),
        );
        expect(
          w.diagnostics.lines.last,
          'export: over budget ${ledger.overBudget} (total 0 in 1)',
        );
      },
    );
  });
}
