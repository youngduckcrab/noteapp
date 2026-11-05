// PdfFileNaming (06-pdf 4.9, 6.11.10, 8 T1).
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_io/pdf_io.dart';

void main() {
  group('sanitize', () {
    test('forbidden characters and control characters become _', () {
      expect(
        PdfFileNaming.sanitize(r'a\b/c:d*e?f"g<h>i|j'),
        'a_b_c_d_e_f_g_h_i_j',
      );
      expect(PdfFileNaming.sanitize('a\u0000b\u001Fc'), 'a_b_c');
      expect(PdfFileNaming.sanitize('tab\there'), 'tab_here');
    });

    test('space runs collapse, leading / trailing spaces and dots go', () {
      expect(PdfFileNaming.sanitize('  미적분   3강 . '), '미적분 3강');
      expect(PdfFileNaming.sanitize('..hidden..'), 'hidden');
      expect(PdfFileNaming.sanitize('a  b'), 'a b');
    });

    test('cut to 100 runes without splitting a surrogate pair', () {
      final long = '가' * 150;
      expect(PdfFileNaming.sanitize(long).runes.length, 100);
      final emoji = '😀' * 120; // two UTF-16 units each
      final cut = PdfFileNaming.sanitize(emoji);
      expect(cut.runes.length, 100);
      expect(cut, '😀' * 100);
      // A cut that ends in a space is trimmed again.
      expect(PdfFileNaming.sanitize('${'a' * 99} b'), 'a' * 99);
    });

    test("empty → '노트'", () {
      expect(PdfFileNaming.sanitize(''), '노트');
      expect(PdfFileNaming.sanitize(' . . '), '노트');
    });
  });

  group('forExport', () {
    test('suffix by range, .pdf extension', () {
      expect(
        PdfFileNaming.forExport('미적분 3강', const PdfExportAllPages()),
        '미적분 3강.pdf',
      );
      expect(
        PdfFileNaming.forExport(
          '미적분 3강',
          const PdfExportCurrentPage('p12'),
          currentPageNumber: 12,
        ),
        '미적분 3강 (p12).pdf',
      );
      expect(
        PdfFileNaming.forExport(
          '미적분 3강',
          const PdfExportSelectedPages(['a', 'b']),
        ),
        '미적분 3강 (선택 2쪽).pdf',
      );
      expect(
        PdfFileNaming.forExport(
          '미적분 3강',
          const PdfExportSelectedPages(['a']),
          selectedCount: 4,
        ),
        '미적분 3강 (선택 4쪽).pdf',
      );
    });

    test('the title is sanitized, empty title → 노트.pdf', () {
      expect(
        PdfFileNaming.forExport('a/b: c?', const PdfExportAllPages()),
        'a_b_ c_.pdf',
      );
      expect(
        PdfFileNaming.forExport('  ', const PdfExportAllPages()),
        '노트.pdf',
      );
    });
  });

  group('deduplicate', () {
    test("second → ' (2)', third → ' (3)'", () {
      expect(PdfFileNaming.deduplicate(['a.pdf', 'b.pdf', 'a.pdf', 'a.pdf']), [
        'a.pdf',
        'b.pdf',
        'a (2).pdf',
        'a (3).pdf',
      ]);
    });

    test('case-insensitive compare, original spelling kept', () {
      expect(PdfFileNaming.deduplicate(['Note.pdf', 'note.PDF', 'NOTE.pdf']), [
        'Note.pdf',
        'note (2).PDF',
        'NOTE (3).pdf',
      ]);
    });

    test('a generated name never repeats an earlier name', () {
      expect(PdfFileNaming.deduplicate(['a.pdf', 'a (2).pdf', 'a.pdf']), [
        'a.pdf',
        'a (2).pdf',
        'a (3).pdf',
      ]);
    });

    test('unique names unchanged, names without extension', () {
      expect(PdfFileNaming.deduplicate(['x.pdf', 'y.pdf']), ['x.pdf', 'y.pdf']);
      expect(PdfFileNaming.deduplicate(['x', 'x']), ['x', 'x (2)']);
      expect(PdfFileNaming.deduplicate([]), isEmpty);
    });
  });
}
