// lib/src/search_index/unit_builder.dart — m5-7/06-pdf 4.1.1, 6.4.1 (src only). Pure, web-safe.
//
// One PDF page's text → its search units: body = PDFium's text as it is (\r\n kept), one rect
// per UTF-16 code unit as fractions [0, 1] of the displayed page (rotation applied — the engine's
// charRects are displayed page pt, y down), PageRect.zero where the position is unknown (no box,
// zero width or height), pdfPageAspect = displayed width / height. (T29) The boxes of one text
// line share one vertical band (_lineBands — CORE merges a hit's boxes per line by equal top and
// bottom). A body longer than
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
    _lineBands(body, rects);
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

  /// (T29) Gives the boxes of one text line one vertical band: a run of boxes, cut at '\n' and
  /// where a box no longer overlaps the run's band by at least half the smaller height (the
  /// 1차 per-line merge rule, 6.10.2 step 4), gets the band's top and bottom; left and right
  /// stay per character. CORE merges a hit's boxes per line as 'consecutive boxes with the same
  /// top and bottom' (02-core 6.10.4) and stores one band per such group (6.10.3 — ~12 B per
  /// line): with PDFium's tight glyph boxes ('S' taller than 'e') a line would otherwise come
  /// back as several rects. PageRect.zero boxes stay zero and do not cut a run.
  static void _lineBands(String body, List<core.PageRect> rects) {
    var runStart = 0;
    double? top, bottom;
    void close(int end) {
      if (top != null) {
        for (var i = runStart; i < end; i++) {
          final r = rects[i];
          if (r == core.PageRect.zero) continue;
          rects[i] = core.PageRect(r.left, top!, r.right, bottom!);
        }
      }
      runStart = end;
      top = bottom = null;
    }

    for (var i = 0; i < rects.length; i++) {
      if (body.codeUnitAt(i) == 0x0A) {
        close(i + 1);
        continue;
      }
      final r = rects[i];
      if (r == core.PageRect.zero) continue;
      if (top != null) {
        final overlap = math.min(bottom!, r.bottom) - math.max(top!, r.top);
        final smaller = math.min(bottom! - top!, r.bottom - r.top);
        if (overlap < 0.5 * smaller) close(i);
      }
      top = top == null ? r.top : math.min(top!, r.top);
      bottom = bottom == null ? r.bottom : math.max(bottom!, r.bottom);
    }
    close(rects.length);
  }

  static bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;
}
