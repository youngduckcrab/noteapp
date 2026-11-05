// PdfPageFit (06-pdf 4.6, 6.5.1, 6.11.3) — real from B4 (8 T0: pure calculation).
// PdfPageSizePolicy.toNotePageSize cases join this file with PDF T1.
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_io/pdf_io.dart';

const double _eps = 1e-6;

void _rectClose(ui.Rect actual, ui.Rect expected, {double eps = _eps}) {
  expect(actual.left, closeTo(expected.left, eps));
  expect(actual.top, closeTo(expected.top, eps));
  expect(actual.width, closeTo(expected.width, eps));
  expect(actual.height, closeTo(expected.height, eps));
}

void main() {
  test('identity when the note page has the PDF size (P-1)', () {
    final fit = PdfPageFit(
      notePageSize: const ui.Size(595.276, 841.89),
      pdfPageSize: const ui.Size(595.276, 841.89),
    );
    expect(fit.k, 1);
    expect([fit.ox, fit.oy], [0, 0]);
    expect(fit.isIdentity, isTrue);
    expect(fit.pdfBoxInNote, const ui.Rect.fromLTWH(0, 0, 595.276, 841.89));
    const r = ui.Rect.fromLTWH(10, 20, 30, 40);
    expect(fit.pdfToNote(r), r);
    expect(fit.noteToPdf(r), r);
    expect(fit.noteToPdfMatrix(), [1, 0, 0, 1, 0, 0]);
  });

  test('uniform scale: PDF 50×50 → note 72×72 (6.5 s ≠ 1)', () {
    final fit = PdfPageFit(
      notePageSize: const ui.Size(72, 72),
      pdfPageSize: const ui.Size(50, 50),
    );
    expect(fit.k, closeTo(1.44, _eps));
    expect(fit.ox, closeTo(0, _eps));
    expect(fit.oy, closeTo(0, _eps));
    expect(fit.isIdentity, isFalse);
    _rectClose(
      fit.pdfToNote(const ui.Rect.fromLTWH(10, 10, 5, 5)),
      const ui.Rect.fromLTWH(14.4, 14.4, 7.2, 7.2),
    );
    _rectClose(fit.pdfBoxInNote, const ui.Rect.fromLTWH(0, 0, 72, 72));
  });

  test('different aspect: Letter PDF on an A4 note → centered letterbox', () {
    final fit = PdfPageFit(
      notePageSize: const ui.Size(595.2756, 841.8898),
      pdfPageSize: const ui.Size(612, 792),
    );
    expect(fit.k, closeTo(0.97267, 1e-5));
    expect(fit.ox, closeTo(0, _eps));
    expect(fit.oy, closeTo(35.767, 1e-3));
    final box = fit.pdfBoxInNote;
    expect(box.left, closeTo(0, _eps));
    expect(box.width, closeTo(595.2756, 1e-4));
    expect(box.top, closeTo(fit.oy, _eps));
    expect(box.top + box.height + box.top, closeTo(841.8898, 1e-4));
  });

  test('wide PDF on a tall note → letterbox left and right', () {
    final fit = PdfPageFit(
      notePageSize: const ui.Size(100, 100),
      pdfPageSize: const ui.Size(200, 400),
    );
    expect(fit.k, closeTo(0.25, _eps));
    expect(fit.ox, closeTo(25, _eps));
    expect(fit.oy, closeTo(0, _eps));
  });

  test('round trip noteToPdf(pdfToNote(r)) == r within 1e-6', () {
    final fits = [
      PdfPageFit(
        notePageSize: const ui.Size(72, 72),
        pdfPageSize: const ui.Size(50, 50),
      ),
      PdfPageFit(
        notePageSize: const ui.Size(595.2756, 841.8898),
        pdfPageSize: const ui.Size(612, 792),
      ),
      PdfPageFit(
        notePageSize: const ui.Size(100, 100),
        pdfPageSize: const ui.Size(200, 400),
      ),
    ];
    const rects = [
      ui.Rect.fromLTWH(0, 0, 1, 1),
      ui.Rect.fromLTWH(12.5, 300.25, 80, 14),
      ui.Rect.fromLTWH(-3, 5, 0, 0),
    ];
    for (final fit in fits) {
      for (final r in rects) {
        _rectClose(fit.noteToPdf(fit.pdfToNote(r)), r);
        _rectClose(fit.pdfToNote(fit.noteToPdf(r)), r);
      }
    }
  });

  test('noteToPdfMatrix() = 6.11.3 F = [1/k, 0, 0, 1/k, −ox/k, −oy/k]', () {
    final fit = PdfPageFit(
      notePageSize: const ui.Size(595.2756, 841.8898),
      pdfPageSize: const ui.Size(612, 792),
    );
    final m = fit.noteToPdfMatrix();
    expect(m, hasLength(6));
    final s = 1 / fit.k;
    expect(m[0], closeTo(s, _eps));
    expect(m[1], 0);
    expect(m[2], 0);
    expect(m[3], closeTo(s, _eps));
    expect(m[4], closeTo(-fit.ox / fit.k, _eps));
    expect(m[5], closeTo(-fit.oy / fit.k, _eps));
    // 6.11.3: s = max(dw/nw, dh/nh), tx = (dw − nw·s)/2, ty = (dh − nh·s)/2.
    const nw = 595.2756, nh = 841.8898, dw = 612.0, dh = 792.0;
    final s2 = [dw / nw, dh / nh].reduce((a, b) => a > b ? a : b);
    expect(m[0], closeTo(s2, _eps));
    expect(m[4], closeTo((dw - nw * s2) / 2, 1e-4));
    expect(m[5], closeTo((dh - nh * s2) / 2, 1e-4));
    // F maps the note point back onto the PDF display point.
    const p = ui.Offset(100, 200);
    final note = fit.pdfToNote(ui.Rect.fromLTWH(p.dx, p.dy, 0, 0)).topLeft;
    expect(m[0] * note.dx + m[2] * note.dy + m[4], closeTo(p.dx, 1e-4));
    expect(m[1] * note.dx + m[3] * note.dy + m[5], closeTo(p.dy, 1e-4));
  });

  test('isIdentity tolerances: |k − 1| < 1e-4, |ox|, |oy| < 1e-3', () {
    expect(
      PdfPageFit(
        notePageSize: const ui.Size(1000.00005, 1000),
        pdfPageSize: const ui.Size(1000, 1000),
      ).isIdentity,
      isTrue,
    );
    expect(
      PdfPageFit(
        notePageSize: const ui.Size(1000, 1000.01),
        pdfPageSize: const ui.Size(1000, 1000),
      ).isIdentity,
      isFalse,
      reason: 'oy = 0.005 ≥ 1e-3',
    );
  });

  test('sizes without positive finite sides are rejected', () {
    expect(
      () => PdfPageFit(
        notePageSize: const ui.Size(100, 100),
        pdfPageSize: ui.Size.zero,
      ),
      throwsArgumentError,
    );
    expect(
      () => PdfPageFit(
        notePageSize: const ui.Size(double.infinity, 100),
        pdfPageSize: const ui.Size(100, 100),
      ),
      throwsArgumentError,
    );
  });
}
