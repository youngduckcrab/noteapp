// lib/src/math/math_png.dart — (internal) m5-7/05-library 6.11.3 'pngBase64'.
//
// The image the math engine gets next to the strokes: the chosen strokes
// moved so the area's top-left sits at the margin, on a blank white page of
// the area plus a margin on each side, drawn by the app shell's
// pageThumbnailRendererProvider (INK's renderer) at maxSidePx 1024. Only
// when a renderer exists (tests and the foundation step have none — then
// MathInput.png stays null and only the strokes are sent). The base64 limit
// (2 MB) is math_payload.dart's.
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:note_core/note_core.dart' as core;

import '../common/report_error.dart';

/// White space around the strokes (pt — 6.11.3).
const double kMathPngMarginPt = 8;

/// The long side of the rendered image (px — 6.11.3).
const int kMathPngMaxSidePx = 1024;

/// A rendered engine image: the PNG bytes and its scale (px ÷ pt —
/// MathInput.pngPxPerPt).
typedef MathPng = ({Uint8List png, double pxPerPt});

/// The union of the strokes' bounds (page pt); null without strokes.
Rect? strokesAreaPt(List<core.Stroke> strokes) {
  Rect? area;
  for (final s in strokes) {
    final b = s.bounds;
    final r = Rect.fromLTRB(b.left, b.top, b.right, b.bottom);
    area = area == null ? r : area.expandToInclude(r);
  }
  return area;
}

/// [strokes] on a temporary page of [areaPt] plus [kMathPngMarginPt] on each
/// side (blank white background): copies moved by (margin − area.topLeft),
/// page id [pageId], z order. null when there is no stroke or the area is not
/// finite. The engine image (6.11.3) and recog.toMath's read-only strokes
/// view (6.15.3) both draw this page.
({core.Page page, List<core.Stroke> strokes})? mathAreaPage(
  List<core.Stroke> strokes, {
  required Rect areaPt,
  required String pageId,
  required String noteId,
  required core.EpochMillis nowMs,
}) {
  if (strokes.isEmpty) return null;
  if (!(areaPt.width >= 0 && areaPt.height >= 0) ||
      !areaPt.left.isFinite ||
      !areaPt.top.isFinite ||
      !areaPt.right.isFinite ||
      !areaPt.bottom.isFinite) {
    return null;
  }
  final move = core.Affine2.translation(
    kMathPngMarginPt - areaPt.left,
    kMathPngMarginPt - areaPt.top,
  );
  final page = core.Page(
    id: pageId,
    noteId: noteId,
    sortKey: 'a0',
    size: core.PageSize(
      areaPt.width + 2 * kMathPngMarginPt,
      areaPt.height + 2 * kMathPngMarginPt,
    ),
    background: const core.BlankBackground(),
    createdAt: nowMs,
    updatedAt: nowMs,
  );
  final moved = [
    for (final s in strokes)
      s.transformed(move, scaleWidth: false).copyWith(pageId: pageId),
  ]..sort(core.Stroke.compareOrder);
  return (page: page, strokes: moved);
}

/// The engine image of [strokes] (6.11.3), or null when there is no
/// [renderer], no stroke, the area is not finite, or the renderer gives
/// nothing. A throwing renderer is reported once and gives null (the strokes
/// are still sent). [pageId] / [noteId] name the temporary page (never
/// stored — [mathAreaPage]).
Future<MathPng?> renderMathPng(
  core.PageThumbnailRenderer? renderer,
  List<core.Stroke> strokes, {
  required Rect areaPt,
  required String pageId,
  required String noteId,
  required core.EpochMillis nowMs,
}) async {
  if (renderer == null) return null;
  final area = mathAreaPage(
    strokes,
    areaPt: areaPt,
    pageId: pageId,
    noteId: noteId,
    nowMs: nowMs,
  );
  if (area == null) return null;
  try {
    final thumb = await renderer.render(
      core.PageContent(page: area.page, strokes: area.strokes, revision: 0),
      maxSidePx: kMathPngMaxSidePx,
    );
    if (thumb == null || thumb.bytes.isEmpty || thumb.width <= 0) return null;
    return (png: thumb.bytes, pxPerPt: thumb.width / area.page.size.width);
  } catch (e, s) {
    reportRecognitionError(e, s, 'rendering the math engine image');
    return null;
  }
}
