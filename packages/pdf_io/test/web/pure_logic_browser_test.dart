@TestOn('browser')
library;

// Pure logic that must give the same results under dart2js as on the VM (06-pdf 9.1,
// contract 7.4.8: dart2js number differences). Grows with the tasks that add pure logic
// (T11 normalizer, T12 encoder bytes and alpha255).
import 'dart:ui' show Size;

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/src/model/title_policy.dart';
import 'package:pdf_io/src/text/hangul_jamo.dart';
import 'package:pdf_io/src/ui/strings_ko.dart';

import '../support/fixture_digest.dart';

void main() {
  test('title policy and jamo', () {
    const nfd = '강의자료.PDF';
    expect(PdfTitlePolicy.fromFileName(nfd), '강의자료');
    expect(PdfTitlePolicy.fromFileName('${'a' * 199}😀.pdf'), 'a' * 199);
    expect(HangulJamo.compose('각'), '각');
  });

  test('page range', () {
    expect(PdfPageRange.parse('1-3, 5', pageCount: 10).resolve(10), [
      0,
      1,
      2,
      4,
    ]);
    expect(PdfPageRange.parse('8-', pageCount: 10).resolve(10), [7, 8, 9]);
    expect(
      () => PdfPageRange.parse('3-1', pageCount: 10),
      throwsFormatException,
    );
  });

  test('page size policy and fit', () {
    final size = PdfPageSizePolicy.toNotePageSize(595.2755737, 841.8897705);
    expect(size.width, 595.276);
    expect(PdfPageSizePolicy.toNotePageSize(50, 50).width, 72);
    final fit = PdfPageFit(
      notePageSize: const Size(595.2756, 841.8898),
      pdfPageSize: const Size(612, 792),
    );
    expect(fit.k, closeTo(0.97267, 1e-5));
    expect(fit.oy, closeTo(35.767, 1e-3));
  });

  test('file naming and strings', () {
    expect(PdfFileNaming.deduplicate(['a.pdf', 'A.pdf', 'a.pdf']), [
      'a.pdf',
      'A (2).pdf',
      'a (3).pdf',
    ]);
    expect(PdfFileNaming.sanitize('😀' * 120), '😀' * 100);
    expect(PdfStringsKo.pageList([3, 5, 7, 8, 9]), '3, 5, 7–9');
    expect(PdfStringsKo.megabytes(300 * 1024 * 1024), '300');
  });

  test('fixture builder: same bytes as on the VM (RC4 / MD5 / numbers)', () {
    expect(
      sha256.convert(encryptedFixture()).toString(),
      encryptedFixtureSha256,
    );
  });
}
