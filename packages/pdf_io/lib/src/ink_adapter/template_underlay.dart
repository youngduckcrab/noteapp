// lib/src/ink_adapter/template_underlay.dart — 06-pdf 6.11.8 'underlay' (PDF T12); (2차)
// m5-7/06-pdf 6.2.1 L-1 1 (T24). Internal (not exported). With ink_vectorizer.dart the only
// place that calls INK's vector export.
//
// The underlay of a blank / template page: the paper fill when the paper is not white, then
// the template's lines and dots from ink.TemplateVectors.build (CORE PageTemplate passed as
// it is — INK applies its defaults). Lines are grouped by (color, width) into one stroked
// object each (butt caps, one subpath per segment); dots by color into one filled object of
// circle subpaths (file size, 6.11.8). (2차) pdfPageBackground gives the same parts as the
// background of the page layers, with an image background page's PdfAssetImageRef.background.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;

import '../export/page_layers.dart';
import '../export/vectors.dart';

/// Shape of ink.TemplateVectors.build (tests pass a recording builder).
typedef PdfTemplateVectorBuild = List<ink.TemplateVectorItem> Function(
  core.PageTemplate template, {
  required ui.Size pageSize,
  required int paperColorArgb,
  ui.Rect? clip,
});

/// The underlay of [page] (6.11.8): empty for a PDF page; otherwise the paper fill (only
/// when the paper is not core.PaperColors.white) and, for a template page, its lines and
/// dots. Image backgrounds get the paper only here (1차 vectorize); (2차) the image itself is
/// [pdfPageBackground]'s PdfAssetImageRef.background.
List<PdfVectorItem> pdfPageUnderlay(
  core.Page page, {
  PdfTemplateVectorBuild build = ink.TemplateVectors.build,
}) {
  final part = pdfPageBackground(page, build: build);
  final paper = part.paperArgb;
  return [
    if (paper != null)
      PdfFillItem(
        path: PdfVectorPath.rect(
          ui.Offset.zero & ui.Size(page.size.width, page.size.height),
        ),
        colorArgb: paper,
      ),
    ...?part.templateItems,
  ];
}

/// (2차, T24) The L-1 1 part of [page] (6.2.1): none for a PDF page; otherwise the paper colour
/// when it is not core.PaperColors.white, the template items of a template page, and an image
/// background page's PdfAssetImageRef.background(fit, page size).
PdfPageBackgroundPart pdfPageBackground(
  core.Page page, {
  PdfTemplateVectorBuild build = ink.TemplateVectors.build,
}) {
  final background = page.background;
  if (background is core.PdfBackground) return PdfPageBackgroundPart.none;
  final size = ui.Size(page.size.width, page.size.height);
  final paper = background.paperColorArgb;
  return PdfPageBackgroundPart(
    paperArgb: paper == core.PaperColors.white ? null : paper,
    templateItems: switch (background) {
      core.TemplateBackground(:final template) => pdfTemplateItems(
        build(template, pageSize: size, paperColorArgb: paper),
      ),
      _ => null,
    },
    image: switch (background) {
      core.ImageBackground(:final assetId, :final fit) =>
        PdfAssetImageRef.background(assetId: assetId, fit: fit, pageSize: size),
      _ => null,
    },
  );
}

/// INK template items → PDF items: one stroke item per (color, width) of the lines, one
/// fill item per color of the dots, in the order each group first appears.
List<PdfVectorItem> pdfTemplateItems(List<ink.TemplateVectorItem> items) {
  final groups = <Object, List<ink.TemplateVectorItem>>{};
  for (final item in items) {
    final key = switch (item) {
      ink.TemplateLine(:final colorArgb, :final width) => (
        'line',
        colorArgb,
        width,
      ),
      ink.TemplateDot(:final colorArgb) => ('dot', colorArgb, 0.0),
    };
    (groups[key] ??= []).add(item);
  }
  return [
    for (final group in groups.values)
      switch (group.first) {
        ink.TemplateLine(:final colorArgb, :final width) => PdfStrokeItem(
          path: _segments(group.cast<ink.TemplateLine>()),
          colorArgb: colorArgb,
          width: width,
          cap: PdfLineCap.butt,
          join: PdfLineJoin.miter,
        ),
        ink.TemplateDot(:final colorArgb) => PdfFillItem(
          path: PdfVectorPath.circles([
            for (final dot in group.cast<ink.TemplateDot>())
              (dot.center, dot.radius),
          ]),
          colorArgb: colorArgb,
        ),
      },
  ];
}

/// One moveTo + lineTo subpath per line.
PdfVectorPath _segments(List<ink.TemplateLine> lines) {
  final verbs = Uint8List(lines.length * 2);
  final coords = Float32List(lines.length * 4);
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    verbs[i * 2] = 0; // moveTo
    verbs[i * 2 + 1] = 1; // lineTo
    coords
      ..[i * 4] = line.p0.dx
      ..[i * 4 + 1] = line.p0.dy
      ..[i * 4 + 2] = line.p1.dx
      ..[i * 4 + 3] = line.p1.dy;
  }
  return PdfVectorPath(verbs, coords);
}
