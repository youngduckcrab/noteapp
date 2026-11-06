// lib/src/search_index/unit_builder.dart — m5-7/06-pdf 4.1.1, 6.4.1 (src only). Pure, web-safe.
//
// One PDF page's text → its search units: body = PDFium's text as it is (\r\n kept), one rect
// per UTF-16 code unit as fractions [0, 1] of the displayed page (rotation applied — the engine's
// charRects are displayed page pt, y down), PageRect.zero where the position is unknown (no box,
// zero width or height), pdfPageAspect = displayed width / height. A body longer than
// PdfTuning.indexMaxUnitCodeUnits is cut after the last '\n' before the limit (at the limit when
// the piece has none, never inside a surrogate pair); an empty or blank page has no units.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:note_core/note_core.dart' as core;

import '../engine/page_info.dart';
import '../tuning.dart';

abstract final class PdfSearchUnitBuilder {
  /// The units of [text] on a page shown [pageSize] pt (PdfPageInfo width × height).
  static List<core.SearchUnitDraft> build(
    PdfPageTextData text,
    ui.Size pageSize, {
    int maxCodeUnits = PdfTuning.indexMaxUnitCodeUnits,
  }) {
    final body = text.text;
    if (body.trim().isEmpty) return const [];
    final w = pageSize.width, h = pageSize.height;
    final aspect = w > 0 && h > 0 && w.isFinite && h.isFinite ? w / h : null;
    final rects = List<core.PageRect>.generate(
      body.length,
      (i) => i < text.charRects.length
          ? _fraction(text.charRects[i], w, h)
          : core.PageRect.zero,
      growable: false,
    );
    final units = <core.SearchUnitDraft>[];
    var start = 0;
    while (start < body.length) {
      var end = math.min(body.length, start + maxCodeUnits);
      if (end < body.length) {
        final lineEnd = body.lastIndexOf('\n', end - 1);
        if (lineEnd >= start) {
          end = lineEnd + 1;
        } else if (_isHighSurrogate(body.codeUnitAt(end - 1))) {
          end--; // keep the pair together
        }
      }
      units.add(
        core.SearchUnitDraft(
          body: body.substring(start, end),
          rects: List.unmodifiable(rects.sublist(start, end)),
          pdfPageAspect: aspect,
        ),
      );
      start = end;
    }
    return List.unmodifiable(units);
  }

  /// `<assetId>:<SearchText.normalizerVersion>:x<indexExtractorVersion>` (CP-PDF-2).
  static String sourceRevOf(core.AssetId assetId) =>
      '$assetId:${core.SearchText.normalizerVersion}'
      ':x${PdfTuning.indexExtractorVersion}';

  /// `<assetId>#<pdfPageIndex>` (contract 7.2.5).
  static String ownerKeyOf(core.AssetId assetId, int pdfPageIndex) =>
      '$assetId#$pdfPageIndex';

  static core.PageRect _fraction(ui.Rect r, double w, double h) {
    if (r.isEmpty || !(w > 0) || !(h > 0)) return core.PageRect.zero;
    double fx(double v) => (v / w).clamp(0.0, 1.0);
    double fy(double v) => (v / h).clamp(0.0, 1.0);
    final out = core.PageRect(fx(r.left), fy(r.top), fx(r.right), fy(r.bottom));
    return out.right > out.left || out.bottom > out.top
        ? out
        : core.PageRect.zero; // wholly outside the page
  }

  static bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;
}
