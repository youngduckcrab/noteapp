// lib/src/import/cover_thumbnail.dart — 06-pdf 6.3 step 6, 6.9 (contract 7.2.11 thumbnail
// path: 'cover right after import').
//
// Internal (not exported).
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:note_core/note_core.dart' as core;

import '../engine/page_info.dart';
import '../model/page_size_policy.dart';
import '../render/render_service.dart';
import '../tuning.dart';

/// The cover of a freshly imported note's first page (6.3 step 6).
///
/// With [thumbnailRenderer] (core.pageThumbnailRendererProvider — INK renderer injected by
/// INFRA) the result is that renderer's, so the cover matches the ones LIBRARY's scheduler
/// makes later. Without it (foundation stage, unit tests) pdf_io draws it itself: the page
/// paper of [maxSidePx] on the long side, the PDF image from [renderer].renderThumbnail
/// placed with PdfPageFit (6.5.1), encoded as PNG. [pdfPage] is the displayed size of the
/// background's PDF page.
///
/// null = cannot draw now (not an error, nothing cached): no PDF background, bytes missing,
/// a password needed or rendering failed. Exceptions propagate (the import reports them).
Future<core.PageThumbnail?> renderImportCover({
  required core.PageContent content,
  required PdfPageInfo pdfPage,
  required PdfPageRenderer renderer,
  core.PageThumbnailRenderer? thumbnailRenderer,
  int maxSidePx = PdfTuning.coverThumbnailLongSidePx,
}) async {
  if (thumbnailRenderer != null) {
    return thumbnailRenderer.render(content, maxSidePx: maxSidePx);
  }
  final page = content.page;
  final background = page.background;
  if (background is! core.PdfBackground) return null;
  final noteSize = ui.Size(page.size.width, page.size.height);
  final fit = PdfPageFit(
    notePageSize: noteSize,
    pdfPageSize: ui.Size(pdfPage.width, pdfPage.height),
  );
  final scale = maxSidePx / math.max(noteSize.width, noteSize.height);
  final width = math.max(1, (noteSize.width * scale).round());
  final height = math.max(1, (noteSize.height * scale).round());
  final box = fit.pdfBoxInNote;
  final pdfLongSidePx = math.max(
    1,
    (math.max(box.width, box.height) * scale).round(),
  );
  final image = await renderer.renderThumbnail(
    assetId: background.assetId,
    pdfPageIndex: background.pdfPageIndex,
    longSidePx: pdfLongSidePx,
    backgroundArgb: background.paperColorArgb,
  );
  if (image == null) return null;
  ui.Image? composed;
  try {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paper = ui.Paint()..color = ui.Color(background.paperColorArgb);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      paper,
    );
    canvas.drawImageRect(
      image,
      ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      ui.Rect.fromLTWH(
        box.left * scale,
        box.top * scale,
        box.width * scale,
        box.height * scale,
      ),
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
    final picture = recorder.endRecording();
    composed = picture.toImageSync(width, height);
    picture.dispose();
    final png = await composed.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) return null;
    return core.PageThumbnail(
      pageId: page.id,
      contentRevision: page.contentRevision,
      width: width,
      height: height,
      mimeType: 'image/png',
      bytes: png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
    );
  } finally {
    image.dispose();
    composed?.dispose();
  }
}
