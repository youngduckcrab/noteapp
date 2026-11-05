// lib/src/model/page_size_policy.dart — 06-pdf 4.6, 6.5, 6.5.1.
//
// Foundation step B4 (T0): PdfPageFit is real (pure calculation, 06-pdf 8 T0);
// PdfPageSizePolicy comes with PDF T1.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:note_core/note_core.dart' as core;

abstract final class PdfPageSizePolicy {
  /// PDF displayed size (pt) → CORE PageSize. Rounds to 0.001 pt; if a side is
  /// outside [core.PageSize.minSide, core.PageSize.maxSide] scales BOTH sides uniformly (6.5, P-1).
  static core.PageSize toNotePageSize(double widthPt, double heightPt) =>
      throw UnimplementedError('PdfPageSizePolicy.toNotePageSize (PDF T1)');
}

/// Where the PDF page sits on the note page (6.5.1) — the ONLY conversion between
/// "displayed PDF pt" (engine: PdfPageInfo size, charRects, render scale) and "note page pt"
/// (core.Page.size, origin top-left, y down: INK ctx, widgets, search hits, focusRectPt).
/// The displayed PDF box (dw × dh) is contain-fitted and centered in the note box (nw × nh):
///   note = k · display + (ox, oy),  k = min(nw / dw, nh / dh),
///   ox = (nw − dw · k) / 2,  oy = (nh − dh · k) / 2.
/// 6.11.3 F (note → display) is its inverse. Used by the painter, renderStill, tile
/// selection, search hits and export, so screen, highlights and the exported PDF agree.
@immutable
final class PdfPageFit {
  /// Throws ArgumentError unless both sizes have finite, positive sides.
  factory PdfPageFit({
    required ui.Size notePageSize,
    required ui.Size pdfPageSize,
  }) {
    _checkSize(notePageSize, 'notePageSize');
    _checkSize(pdfPageSize, 'pdfPageSize');
    final nw = notePageSize.width, nh = notePageSize.height;
    final dw = pdfPageSize.width, dh = pdfPageSize.height;
    final k = math.min(nw / dw, nh / dh);
    return PdfPageFit._(
      k,
      (nw - dw * k) / 2,
      (nh - dh * k) / 2,
      dw * k,
      dh * k,
    );
  }

  const PdfPageFit._(this.k, this.ox, this.oy, this._boxWidth, this._boxHeight);

  static void _checkSize(ui.Size size, String name) {
    final ok =
        size.width.isFinite &&
        size.height.isFinite &&
        size.width > 0 &&
        size.height > 0;
    if (!ok) throw ArgumentError.value(size, name, 'sides must be > 0');
  }

  final double k; // note pt per displayed PDF pt
  final double ox, oy; // note pt

  /// dw · k, dh · k (note pt)
  final double _boxWidth, _boxHeight;

  /// |k − 1| < 1e-4 and |ox|, |oy| < 1e-3 (the usual case: P-1 keeps the PDF size).
  bool get isIdentity =>
      (k - 1).abs() < 1e-4 && ox.abs() < 1e-3 && oy.abs() < 1e-3;

  /// (ox, oy, dw · k, dh · k): the note-pt box the PDF image is drawn into.
  ui.Rect get pdfBoxInNote => ui.Rect.fromLTWH(ox, oy, _boxWidth, _boxHeight);

  /// charRects → PdfSearchHit.rects (6.10.2)
  ui.Rect pdfToNote(ui.Rect displayRect) => ui.Rect.fromLTWH(
    displayRect.left * k + ox,
    displayRect.top * k + oy,
    displayRect.width * k,
    displayRect.height * k,
  );

  /// visiblePageRect → tile selection (6.7.2)
  ui.Rect noteToPdf(ui.Rect noteRect) => ui.Rect.fromLTWH(
    (noteRect.left - ox) / k,
    (noteRect.top - oy) / k,
    noteRect.width / k,
    noteRect.height / k,
  );

  /// 6.11.3 F as PDF matrix [a, b, c, d, e, f] = [1/k, 0, 0, 1/k, −ox/k, −oy/k].
  List<double> noteToPdfMatrix() => [1 / k, 0, 0, 1 / k, -ox / k, -oy / k];

  @override
  String toString() => 'PdfPageFit(k: $k, ox: $ox, oy: $oy)';
}
