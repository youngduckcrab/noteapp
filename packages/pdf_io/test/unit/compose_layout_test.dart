// Pure parts of the compose interpreters (06-pdf 6.11.3 table D, M = D ∘ F, 6.11.4 steps
// 3–5): the native backend (T13) runs exactly these on the pdfrx worker; the web worker
// extension (T14) repeats them in JS, so the expected values here are the reference.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/src/compose/compose_layout.dart';

List<double> _apply(List<double> m, double x, double y) => [
  m[0] * x + m[2] * y + m[4],
  m[1] * x + m[3] * y + m[5],
];

Matcher _closeList(List<double> expected) => pairwiseCompare<double, double>(
  expected,
  (e, a) => (e - a).abs() < 1e-9,
  'within 1e-9 of',
);

void main() {
  group('PdfComposePageBox', () {
    test('D per rotation (6.11.3 table) and displayed size', () {
      final box = [36.0, 72.0, 576.0, 756.0]; // l b r t
      PdfComposePageBox at(int rot) =>
          PdfComposePageBox(box[0], box[1], box[2], box[3], rotation: rot);
      expect(at(0).displayToUser(), [1, 0, 0, -1, 36, 756]);
      expect(at(1).displayToUser(), [0, 1, 1, 0, 36, 72]);
      expect(at(2).displayToUser(), [-1, 0, 0, 1, 576, 72]);
      expect(at(3).displayToUser(), [0, -1, -1, 0, 576, 756]);
      expect(at(0).displaySize, const ui.Size(540, 684));
      expect(at(1).displaySize, const ui.Size(684, 540));
      expect(at(2).displaySize, const ui.Size(540, 684));
      expect(at(3).displaySize, const ui.Size(684, 540));
      expect(at(5).rotation, 1);
      expect(at(-1).rotation, 3);
    });

    test('D maps the displayed corners onto the box corners', () {
      // Displayed top-left is the corner a viewer shows top-left after /Rotate.
      final cases = {
        0: [36.0, 756.0], // l t
        1: [36.0, 72.0], // l b
        2: [576.0, 72.0], // r b
        3: [576.0, 756.0], // r t
      };
      for (final MapEntry(key: rot, value: topLeft) in cases.entries) {
        final b = PdfComposePageBox(36, 72, 576, 756, rotation: rot);
        final d = b.displayToUser();
        expect(_apply(d, 0, 0), topLeft, reason: 'rot $rot');
        final s = b.displaySize;
        final far = _apply(d, s.width, s.height);
        // The opposite corner.
        expect(far[0], topLeft[0] == 36 ? 576 : 36, reason: 'rot $rot');
        expect(far[1], topLeft[1] == 72 ? 756 : 72, reason: 'rot $rot');
      }
    });

    test('visible box = CropBox ∩ MediaBox, else MediaBox, else Letter', () {
      final crop = PdfComposePageBox.visible(
        mediaBox: [-100, -50, 512, 742],
        cropBox: [-80, -30, 600, 700],
        rotation: 3,
      );
      expect(
        [crop.left, crop.bottom, crop.right, crop.top],
        [-80, -30, 512, 700],
      );
      expect(crop.rotation, 3);
      expect(crop.displaySize, const ui.Size(730, 592));
      final noCrop = PdfComposePageBox.visible(mediaBox: [0, 0, 400, 300]);
      expect(
        [noCrop.left, noCrop.bottom, noCrop.right, noCrop.top],
        [0, 0, 400, 300],
      );
      final outside = PdfComposePageBox.visible(
        mediaBox: [0, 0, 400, 300],
        cropBox: [500, 500, 600, 600],
      );
      expect(outside.right, 400);
      final reversed = PdfComposePageBox.visible(mediaBox: [400, 300, 0, 0]);
      expect(
        [reversed.left, reversed.bottom, reversed.right, reversed.top],
        [0, 0, 400, 300],
      );
      final none = PdfComposePageBox.visible();
      expect(none.displaySize, const ui.Size(612, 792));
    });

    test('M = D when the note size is the displayed size (F identity)', () {
      final b = PdfComposePageBox(0, 0, 400, 300, rotation: 1);
      expect(b.noteToUser(const ui.Size(300, 400)), b.displayToUser());
      // 0.001 pt rounding of P-1 stays the identity.
      final a4 = PdfComposePageBox(0, 0, 595.276, 841.89);
      expect(
        a4.noteToUser(const ui.Size(595.2756, 841.8898)),
        a4.displayToUser(),
      );
    });

    test('blank page FPDFPage_New(nw, nh): M = [1, 0, 0, −1, 0, nh]', () {
      final b = PdfComposePageBox(0, 0, 500, 400);
      expect(b.noteToUser(const ui.Size(500, 400)), [1, 0, 0, -1, 0, 400]);
    });

    test('M = D ∘ F with F = PdfPageFit.noteToPdfMatrix()', () {
      // Uniform: PDF 50×50, note 72×72 → note (14.4, 14.4) is PDF user (10, 40).
      final small = PdfComposePageBox(0, 0, 50, 50);
      final m = small.noteToUser(const ui.Size(72, 72));
      expect(m, _closeList([50 / 72, 0, 0, -50 / 72, 0, 50]));
      expect(_apply(m, 14.4, 14.4), _closeList([10, 40]));
      // Aspect differs: Letter PDF on an A4 note, rotated 90° (display 792 × 612).
      const note = ui.Size(595.2756, 841.8898);
      final rotated = PdfComposePageBox(0, 0, 612, 792, rotation: 1);
      final fit = PdfPageFit(
        notePageSize: note,
        pdfPageSize: rotated.displaySize,
      );
      final f = fit.noteToPdfMatrix();
      final mr = rotated.noteToUser(note);
      for (final p in const [
        ui.Offset.zero,
        ui.Offset(100, 300),
        ui.Offset(595, 841),
      ]) {
        final display = _apply(f, p.dx, p.dy);
        final user = _apply(rotated.displayToUser(), display[0], display[1]);
        expect(_apply(mr, p.dx, p.dy), _closeList(user), reason: '$p');
      }
    });
  });

  group('decodeComposePlan', () {
    test('rows of PdfComposePlan.encodePages', () {
      final plan = PdfComposePlan(
        sources: [
          PdfComposeSource(assetId: 'a', bytes: Uint8List(0)),
          PdfComposeSource(assetId: 'b', bytes: Uint8List(0)),
        ],
        pages: const [
          PdfComposeSourcePage(
            sourceIndex: 1,
            pdfPageIndex: 3,
            noteSize: ui.Size(100, 200),
          ),
          PdfComposeBlankPage(noteSize: ui.Size(300, 400)),
        ],
      );
      final rows = decodeComposePlan(plan.encodePages(), 2);
      expect(rows, [
        (
          isBlank: false,
          sourceIndex: 1,
          pdfPageIndex: 3,
          noteWidth: 100.0,
          noteHeight: 200.0,
        ),
        (
          isBlank: true,
          sourceIndex: -1,
          pdfPageIndex: -1,
          noteWidth: 300.0,
          noteHeight: 400.0,
        ),
      ]);
    });

    test('malformed plans are ArgumentErrors', () {
      Float64List row(List<double> v) => Float64List.fromList(v);
      expect(
        () => decodeComposePlan(row([0, 0, 0, 1, 1]), 1),
        throwsArgumentError,
      );
      expect(
        () => decodeComposePlan(row([0, 1, 0, 1, 1, 0]), 1),
        throwsArgumentError,
      );
      expect(
        () => decodeComposePlan(row([0, 0, -1, 1, 1, 0]), 1),
        throwsArgumentError,
      );
      expect(
        () => decodeComposePlan(row([0, 0, 0.5, 1, 1, 0]), 1),
        throwsArgumentError,
      );
      expect(
        () => decodeComposePlan(row([2, 0, 0, 1, 1, 0]), 1),
        throwsArgumentError,
      );
      expect(
        () => decodeComposePlan(row([1, -1, -1, 0, 1, 0]), 0),
        throwsArgumentError,
      );
      expect(
        () => decodeComposePlan(row([1, -1, -1, double.nan, 1, 0]), 0),
        throwsArgumentError,
      );
    });
  });

  group('PdfComposeLayout (6.11.4 steps 3–5)', () {
    PdfComposePlanRow src(int s, int i) => (
      isBlank: false,
      sourceIndex: s,
      pdfPageIndex: i,
      noteWidth: 1,
      noteHeight: 1,
    );
    const PdfComposePlanRow blank = (
      isBlank: true,
      sourceIndex: -1,
      pdfPageIndex: -1,
      noteWidth: 1,
      noteHeight: 1,
    );

    /// Replays the steps on labels and returns the final order.
    List<String> replay(PdfComposeLayout layout, List<PdfComposePlanRow> rows) {
      final doc = <String>[
        for (var s = 0; s < layout.imports.length; s++)
          for (final i in layout.imports[s]) 's$s:$i',
      ];
      for (final (from, to) in layout.moves) {
        doc.insert(to, doc.removeAt(from));
      }
      for (final index in layout.blanks) {
        doc.insert(index, 'blank');
      }
      return doc;
    }

    List<String> labels(List<PdfComposePlanRow> rows) => [
      for (final r in rows)
        r.isBlank ? 'blank' : 's${r.sourceIndex}:${r.pdfPageIndex}',
    ];

    test('A, blank, B, A: one import per source, one move, one blank', () {
      final rows = [src(0, 1), blank, src(1, 0), src(0, 0)];
      final layout = PdfComposeLayout.of(rows, 2);
      expect(layout.imports, [
        [1, 0],
        [0],
      ]);
      expect(layout.moves, [(2, 1)]);
      expect(layout.blanks, [1]);
      expect(layout.pageCount, 4);
      expect(replay(layout, rows), labels(rows));
    });

    test('one source: imports in output order (duplicates kept), no moves', () {
      final rows = [src(0, 2), src(0, 0), blank, src(0, 2), blank];
      final layout = PdfComposeLayout.of(rows, 1);
      expect(layout.imports, [
        [2, 0, 2],
      ]);
      expect(layout.moves, isEmpty);
      expect(layout.blanks, [2, 4]);
      expect(replay(layout, rows), labels(rows));
    });

    test('interleaved sources end in output order', () {
      final rows = [
        src(1, 0),
        src(0, 1),
        src(1, 0),
        src(0, 0),
        blank,
        src(0, 1),
        src(2, 4),
      ];
      final layout = PdfComposeLayout.of(rows, 3);
      expect(layout.imports, [
        [1, 0, 1],
        [0, 0],
        [4],
      ]);
      expect(replay(layout, rows), labels(rows));
      // Unused sources get no import call.
      final unused = PdfComposeLayout.of([src(1, 0), blank], 3);
      expect(unused.imports, [
        <int>[],
        [0],
        <int>[],
      ]);
      expect(unused.moves, isEmpty);
    });

    test('blank pages only', () {
      final rows = [blank, blank];
      final layout = PdfComposeLayout.of(rows, 0);
      expect(layout.imports, isEmpty);
      expect(layout.blanks, [0, 1]);
      expect(replay(layout, rows), labels(rows));
    });
  });
}
