// PdfTitlePolicy.fromFileName (06-pdf 4.6, 6.3, 8 T1) — internal, imported by path.
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_io/src/model/title_policy.dart';

void main() {
  test("NFD '강의자료.PDF' → '강의자료'", () {
    // 강의자료 as conjoining jamo (macOS / iPad file names are NFD).
    const nfd = '강의자료.PDF';
    expect(PdfTitlePolicy.fromFileName(nfd), '강의자료');
  });

  test('.pdf is stripped in any case, only once and only at the end', () {
    expect(PdfTitlePolicy.fromFileName('notes.pdf'), 'notes');
    expect(PdfTitlePolicy.fromFileName('notes.Pdf'), 'notes');
    expect(PdfTitlePolicy.fromFileName('a.pdf.pdf'), 'a.pdf');
    expect(PdfTitlePolicy.fromFileName('pdf.notes'), 'pdf.notes');
    expect(PdfTitlePolicy.fromFileName('  spaced name .pdf '), 'spaced name');
  });

  test("empty name → 'PDF 문서'", () {
    expect(PdfTitlePolicy.fromFileName('.pdf'), 'PDF 문서');
    expect(PdfTitlePolicy.fromFileName(''), 'PDF 문서');
    expect(PdfTitlePolicy.fromFileName('   .PDF'), 'PDF 문서');
  });

  test('201 units cut to 200, a surrogate pair is never split', () {
    expect(PdfTitlePolicy.fromFileName('${'a' * 201}.pdf'), 'a' * 200);
    // 199 'a' + one emoji (2 units) = 201 units: the pair would straddle unit 200.
    final cut = PdfTitlePolicy.fromFileName('${'a' * 199}😀.pdf');
    expect(cut, 'a' * 199);
    // 198 'a' + one emoji = 200 units: kept whole.
    expect(
      PdfTitlePolicy.fromFileName('${'a' * 198}😀b.pdf'),
      '${'a' * 198}😀',
    );
  });

  test('no lower-casing', () {
    expect(PdfTitlePolicy.fromFileName('Calculus Ch.3.PDF'), 'Calculus Ch.3');
  });
}
