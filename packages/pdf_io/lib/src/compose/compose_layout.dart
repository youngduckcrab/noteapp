// lib/src/compose/compose_layout.dart — pure parts of the compose interpreters (06-pdf
// 6.11.3 coordinate transform, 6.11.4 page assembly order). Internal (not exported), web
// safe: the native backend (T13) runs these on the pdfrx worker isolate, the tests check
// them on VM and dart2js. The web worker extension (T14) repeats the same steps in JS.
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../model/page_size_policy.dart';

/// A page box `[l b r t]` (PDF user space) and its `/Rotate` in quarter turns (0..3).
final class PdfComposePageBox {
  /// Sides are normalized (l ≤ r, b ≤ t); [rotation] is taken modulo 4.
  factory PdfComposePageBox(
    double left,
    double bottom,
    double right,
    double top, {
    int rotation = 0,
  }) => PdfComposePageBox._(
    left < right ? left : right,
    bottom < top ? bottom : top,
    left < right ? right : left,
    bottom < top ? top : bottom,
    ((rotation % 4) + 4) % 4,
  );

  const PdfComposePageBox._(
    this.left,
    this.bottom,
    this.right,
    this.top,
    this.rotation,
  );

  /// The box PDFium shows (CPDF_Page): CropBox ∩ MediaBox, the MediaBox when the CropBox is
  /// missing or the intersection is empty, `[0 0 612 792]` when the MediaBox is missing or
  /// empty too. Boxes are `[l b r t]`.
  factory PdfComposePageBox.visible({
    List<double>? mediaBox,
    List<double>? cropBox,
    int rotation = 0,
  }) {
    var media = mediaBox == null ? null : PdfComposePageBox._of(mediaBox);
    if (media == null || media.isEmpty) {
      media = PdfComposePageBox(0, 0, 612, 792);
    }
    final crop = cropBox == null ? null : PdfComposePageBox._of(cropBox);
    var box = media;
    if (crop != null && !crop.isEmpty) {
      final l = crop.left > media.left ? crop.left : media.left;
      final b = crop.bottom > media.bottom ? crop.bottom : media.bottom;
      final r = crop.right < media.right ? crop.right : media.right;
      final t = crop.top < media.top ? crop.top : media.top;
      if (l < r && b < t) box = PdfComposePageBox(l, b, r, t);
    }
    return PdfComposePageBox(
      box.left,
      box.bottom,
      box.right,
      box.top,
      rotation: rotation,
    );
  }

  static PdfComposePageBox? _of(List<double> box) {
    if (box.length != 4 || box.any((v) => !v.isFinite)) return null;
    return PdfComposePageBox(box[0], box[1], box[2], box[3]);
  }

  final double left, bottom, right, top;
  final int rotation;

  bool get isEmpty => !(right > left && top > bottom);

  /// The displayed size (dw, dh) in pt: sides swapped for 90° and 270° (6.11.3 table).
  ui.Size get displaySize => rotation.isOdd
      ? ui.Size(top - bottom, right - left)
      : ui.Size(right - left, top - bottom);

  /// D: displayed pt (y down) → PDF user space, `[a b c d e f]` (6.11.3 table).
  List<double> displayToUser() => switch (rotation) {
    0 => [1, 0, 0, -1, left, top],
    1 => [0, 1, 1, 0, left, bottom],
    2 => [-1, 0, 0, 1, right, bottom],
    _ => [0, -1, -1, 0, right, top],
  };

  /// M = D ∘ F: note page pt (y down) → PDF user space. F = [PdfPageFit.noteToPdfMatrix]
  /// of the note size against [displaySize], or the identity when the fit is one
  /// ([PdfPageFit.isIdentity]).
  List<double> noteToUser(ui.Size noteSize) {
    final d = displayToUser();
    final fit = PdfPageFit(notePageSize: noteSize, pdfPageSize: displaySize);
    if (fit.isIdentity) return d;
    final f = fit.noteToPdfMatrix();
    final s = f[0], tx = f[4], ty = f[5];
    return [
      d[0] * s,
      d[1] * s,
      d[2] * s,
      d[3] * s,
      d[0] * tx + d[2] * ty + d[4],
      d[1] * tx + d[3] * ty + d[5],
    ];
  }

  @override
  String toString() =>
      'PdfComposePageBox([$left $bottom $right $top], rotation: $rotation)';
}

/// One output page of [PdfComposePlan.encodePages]: kind 0 = source page, 1 = blank.
typedef PdfComposePlanRow = ({
  bool isBlank,
  int sourceIndex,
  int pdfPageIndex,
  double noteWidth,
  double noteHeight,
});

/// Rows of an encoded plan (stride 6). Throws ArgumentError on a malformed plan.
List<PdfComposePlanRow> decodeComposePlan(Float64List pages, int sourceCount) {
  if (pages.length % 6 != 0) {
    throw ArgumentError.value(pages.length, 'pages', 'not a multiple of 6');
  }
  final rows = <PdfComposePlanRow>[];
  for (var o = 0; o < pages.length; o += 6) {
    final kind = pages[o];
    final w = pages[o + 3], h = pages[o + 4];
    if (!(w.isFinite && h.isFinite && w > 0 && h > 0)) {
      throw ArgumentError('page ${o ~/ 6}: note size $w × $h');
    }
    if (kind == 1) {
      rows.add((
        isBlank: true,
        sourceIndex: -1,
        pdfPageIndex: -1,
        noteWidth: w,
        noteHeight: h,
      ));
      continue;
    }
    final source = pages[o + 1], index = pages[o + 2];
    final ok =
        kind == 0 &&
        source == source.roundToDouble() &&
        index == index.roundToDouble() &&
        source >= 0 &&
        source < sourceCount &&
        index >= 0;
    if (!ok) {
      throw ArgumentError(
        'page ${o ~/ 6}: kind $kind, source $source, pdf page $index',
      );
    }
    rows.add((
      isBlank: false,
      sourceIndex: source.toInt(),
      pdfPageIndex: index.toInt(),
      noteWidth: w,
      noteHeight: h,
    ));
  }
  return rows;
}

/// The page assembly steps of 6.11.4 for one plan (steps 3–5).
final class PdfComposeLayout {
  PdfComposeLayout._(this.imports, this.moves, this.blanks, this.pageCount);

  /// Step 3–5 for [rows]: per source (in source order) the PDF page indexes in output order
  /// (one import call each, duplicates kept), the single-page moves that put the source
  /// pages in output order, and the output indexes of the blank pages (ascending).
  factory PdfComposeLayout.of(List<PdfComposePlanRow> rows, int sourceCount) {
    final imports = [for (var s = 0; s < sourceCount; s++) <int>[]];
    final importedOutputs = [for (var s = 0; s < sourceCount; s++) <int>[]];
    final sourceOrder = <int>[]; // output indexes of source pages, output order
    final blanks = <int>[];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row.isBlank) {
        blanks.add(i);
        continue;
      }
      imports[row.sourceIndex].add(row.pdfPageIndex);
      importedOutputs[row.sourceIndex].add(i);
      sourceOrder.add(i);
    }
    // After the imports the document holds source 0's pages, then source 1's, ...
    final current = [for (final outputs in importedOutputs) ...outputs];
    final moves = <(int, int)>[];
    final usedSources = imports.where((list) => list.isNotEmpty).length;
    if (usedSources > 1) {
      for (var t = 0; t < sourceOrder.length; t++) {
        final p = current.indexOf(sourceOrder[t], t);
        if (p == t) continue;
        moves.add((p, t));
        current.insert(t, current.removeAt(p));
      }
    }
    return PdfComposeLayout._(imports, moves, blanks, rows.length);
  }

  /// imports[s] = PDF page indexes of source s, output order (may repeat).
  final List<List<int>> imports;

  /// (from, to): FPDF_MovePages(dst, [from], 1, to), in this order.
  final List<(int, int)> moves;

  /// Output indexes of blank pages, ascending: FPDFPage_New(dst, index, w, h).
  final List<int> blanks;

  final int pageCount;
}
