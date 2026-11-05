@TestOn('browser')
library;

// Pure logic that must give the same results under dart2js as on the VM (06-pdf 9.1,
// contract 7.4.8: dart2js number differences). Grows with the tasks that add pure logic
// (T8 tile math, T11 normalizer, T12 encoder bytes and alpha255).
import 'dart:ui' show Offset, Rect, Size;

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/src/model/title_policy.dart';
import 'package:pdf_io/src/render/tile_math.dart';
import 'package:pdf_io/src/text/hangul_jamo.dart';
import 'package:pdf_io/src/ui/strings_ko.dart';

import '../support/compose_fixture.dart';
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

  test('tile math (T8): buckets, preview scale, grid, tiles', () {
    expect(bucketScale(3.47), closeTo(3.8147, 1e-4));
    expect(bucketScale(1), 1.0);
    expect(bucketScale(1000), 24);
    const a4 = Size(595.276, 841.89);
    expect(previewScale(3.815, a4), closeTo(1.2163, 1e-4));
    final grid = PdfTileGrid(const Size(300, 200), 4);
    expect((grid.columns, grid.rows), (3, 2));
    final r = grid.requestRect(2, 1);
    expect((r.left, r.top, r.width, r.height), (1023, 511, 177, 289));
    final tiles = tilesFor(
      PdfTileGrid(const Size(512, 512), 8),
      const Size(512, 512),
      visiblePdfRect: const Rect.fromLTWH(128, 128, 64, 64),
    );
    expect(tiles, hasLength(9));
    expect(tiles.first, const PdfTileRef(2, 2, prefetch: false));
    expect(opaquePaperArgb(0x80FBF7EC), 0xFFFBF7EC);
    final plan = PdfRenderPlan.of(
      const PdfBackgroundParams(
        assetId: 'a',
        pdfPageIndex: 0,
        pageSize: a4,
        deviceScale: 3.47,
      ),
      a4,
    );
    expect(plan.tiles, hasLength(5 * 7));
    expect(plan.baseScale, closeTo(1.2163, 1e-4));
  });

  test('text normalizer (T11): same text and position table as on the VM', () {
    final n = PdfTextNormalizer.normalize(
      'The Con-\r\ntinue \u00A0 \u1100\u1161\u11A8\u00ADX caf\u00C9 ά-\n\u03b2',
    );
    expect(n.text, 'the continue 각x café άβ');
    expect(n.sourceStart.length, n.text.length);
    expect(n.sourceEnd.length, n.text.length);
    // '각' comes from the three jamo, the collapsed run before it from ' \u00A0 '.
    final syllable = n.text.indexOf('각');
    expect((n.sourceStart[syllable], n.sourceEnd[syllable]), (18, 21));
    expect((n.sourceStart[syllable - 1], n.sourceEnd[syllable - 1]), (15, 18));
    expect(PdfTextNormalizer.normalizeQuery('  강의\u3000NOTES '), '강의 notes');
  });

  test('compose encoder (T12): same bytes and alpha255 as on the VM', () {
    final ops = PdfComposeEncoder.encode(
      outputIndex: 2,
      vectors: composeFixtureVectors(),
    );
    expect(ops.verbs, composeFixtureVerbs);
    expect(ops.coords, composeFixtureCoords);
    expect(ops.paints, composeFixturePaints);
    expect(
      sha256.convert(composeOpsBytes(ops)).toString(),
      composeFixtureSha256,
    );
    PdfFillItem fill(int argb, double opacity) => PdfFillItem(
      path: PdfVectorPath.rect(Rect.zero),
      colorArgb: argb,
      opacity: opacity,
    );
    expect(fill(0xFFFFE600, 0.35).alpha255, 89);
    expect(fill(0x7F000000, 0.5).alpha255, 64);
    expect(fill(0x80123456, 1).alpha255, 128);
    final circle = PdfVectorPath.circles(const [(Offset(10, 20), 2)]);
    expect(circle.coords[3], closeTo(21.1046, 1e-4));
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
