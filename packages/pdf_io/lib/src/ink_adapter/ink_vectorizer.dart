// lib/src/ink_adapter/ink_vectorizer.dart — 06-pdf 4.9, 6.11.8 (PDF T12); (2차) planPage,
// m5-7/06-pdf 4.1.3, 6.2.1, 6.2.2 (T24 — v2.1, PDF-M2).
//
// The INK vector export adapter (with template_underlay.dart the only INK export calls):
// ink.InkVectorExport.exportPage for the strokes and (2차) the page objects,
// ink.TemplateVectors.build (through pdfPageBackground) for the paper and template.
//
// planPage = planFromLayers(layersFromInk(exportPage(…), content, background:), …): INK's
// values become the PDF intermediate form here (layersFromInk — tested with
// ink.InkVectorFixtures values), the L-1 order and the options are the pure step in
// export/page_layers.dart. The highlighter and ink conversions are the 1차 code, shared with
// vectorize.
import 'dart:ui' as ui;

import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;

import '../export/page_layers.dart';
import '../export/vectors.dart';
import 'template_underlay.dart';

/// ink.InkVectorExport.exportPage + ink.TemplateVectors.build (6.11.8).
final class InkEngineVectorizer implements PdfInkVectorizer {
  const InkEngineVectorizer();

  /// T12: underlay = pdfPageUnderlay(page) when [includeTemplate] (PDF pages: none); ink =
  /// highlighter groups split by (width, cap) into stroke items, then the fill shapes in
  /// z-order, when [includeInk] and there are strokes.
  @override
  PdfPageVectors vectorize(
    core.Page page,
    List<core.Stroke> strokes, {
    required bool includeInk,
    required bool includeTemplate,
  }) {
    final underlay = includeTemplate
        ? pdfPageUnderlay(page)
        : const <PdfVectorItem>[];
    if (!includeInk || strokes.isEmpty) {
      return PdfPageVectors(underlay: underlay);
    }
    final vectors = ink.InkVectorExport.exportPage(
      ink.InkPageContent.fromCore(page: page, strokes: strokes, revision: 0),
      options: ink.InkExportOptions(
        paperColorArgb: page.background.paperColorArgb,
      ),
    );
    return PdfPageVectors(
      underlay: underlay,
      ink: [
        ...pdfHighlighterLayer(vectors.highlighterGroups),
        ...pdfInkLayer(vectors.inkShapes),
      ],
    );
  }

  /// (2차, T24) planFromLayers(layersFromInk(exportPage(content with its objects), content,
  /// background: pdfPageBackground(page)), …) — 6.2.1 order, 6.2.9 options. With [includeInk]
  /// false (or nothing on the page) INK's export is not called: the plan is the background.
  @override
  PdfPagePlan planPage(
    core.PageContent content, {
    required bool includeInk,
    required bool includeTemplate,
  }) {
    final page = content.page;
    final background = pdfPageBackground(page);
    final PdfPageLayers layers;
    if (!includeInk || (content.strokes.isEmpty && content.objects.isEmpty)) {
      layers = PdfPageLayers(
        pageSize: ui.Size(page.size.width, page.size.height),
        background: background,
      );
    } else {
      final vectors = ink.InkVectorExport.exportPage(
        ink.InkPageContent.fromCore(
          page: page,
          strokes: content.strokes,
          objects: content.objects,
          revision: 0,
        ),
        options: ink.InkExportOptions(
          paperColorArgb: page.background.paperColorArgb,
        ),
      );
      layers = layersFromInk(vectors, content, background: background);
    }
    return planFromLayers(
      layers,
      includeInk: includeInk,
      includeTemplate: includeTemplate,
    );
  }
}

/// (2차, T24) INK values → PDF intermediate form (4.1.3): highlighterGroups / inkShapes by the
/// 1차 conversion code (shape pieces with an objectId are ink too), underlay →
/// PdfAssetImageRef.object(frame), annotations → PdfTextBoxRef(object, lines) /
/// PdfMathRef(object), cover → solid PdfFillItem (opacity 1 — tape always covers in exports,
/// K-9), page background → [background]. Page size from [content].
PdfPageLayers layersFromInk(
  ink.InkPageVectors vectors,
  core.PageContent content, {
  required PdfPageBackgroundPart background,
}) {
  final size = content.page.size;
  return PdfPageLayers(
    pageSize: ui.Size(size.width, size.height),
    background: background,
    underlay: List.unmodifiable([
      for (final image in vectors.underlay)
        PdfAssetImageRef.object(assetId: image.assetId, frame: image.frame),
    ]),
    highlighter: List.unmodifiable(
      pdfHighlighterLayer(vectors.highlighterGroups),
    ),
    ink: List.unmodifiable(pdfInkLayer(vectors.inkShapes)),
    annotations: List.unmodifiable([
      for (final annotation in vectors.annotations)
        switch (annotation) {
          ink.InkTextVector(:final object, :final lines) => PdfTextBoxRef(
            object,
            List.unmodifiable([
              for (final line in lines)
                (
                  text: line.text,
                  x: line.x,
                  baselineY: line.baselineY,
                  width: line.width,
                ),
            ]),
          ),
          ink.InkMathVector(:final object) => PdfMathRef(object),
        },
    ]),
    cover: List.unmodifiable([
      for (final shape in vectors.cover)
        PdfFillItem(
          path: _path(shape.path),
          colorArgb: _opaque(shape.colorArgb),
        ),
    ]),
  );
}

/// Internal: the 1차 highlighter conversion — each group (same colour, opacity, blend) through
/// [pdfHighlighterItems].
List<PdfStrokeItem> pdfHighlighterLayer(List<ink.InkHighlighterGroup> groups) =>
    [
      for (final group in groups)
        ...pdfHighlighterItems(
          colorArgb: group.colorArgb,
          opacity: group.opacity,
          blend: switch (group.blend) {
            ink.InkBlendMode.normal => PdfBlend.normal,
            ink.InkBlendMode.multiply => PdfBlend.multiply,
          },
          lines: [
            for (final line in group.lines)
              (
                centerline: _path(line.centerline),
                width: line.width,
                cap: switch (line.cap) {
                  ink.InkCap.round => PdfLineCap.round,
                  ink.InkCap.square => PdfLineCap.square,
                },
              ),
          ],
        ),
    ];

/// Internal: the 1차 fill conversion — one non-zero fill item per shape, z order.
List<PdfFillItem> pdfInkLayer(List<ink.InkFillShape> shapes) => [
  for (final shape in shapes)
    PdfFillItem(
      path: _path(shape.path),
      colorArgb: shape.colorArgb,
      opacity: shape.opacity,
    ),
];

PdfVectorPath _path(ink.InkVectorPath path) =>
    PdfVectorPath(path.verbs, path.coords);

/// Alpha 0xFF, colour kept (arithmetic — web-safe numbers).
int _opaque(int argb) => 0xFF000000 + argb % 0x1000000;

/// Internal (not exported): one highlighter group (same color, opacity, blend) → one stroke
/// item per (width, cap), in the order each pair first appears; its path = the centerlines
/// as subpaths, join round (6.11.8). Inside one item overlaps do not darken (V6); items of
/// different widths can (known difference, 11).
List<PdfStrokeItem> pdfHighlighterItems({
  required int colorArgb,
  required double opacity,
  required PdfBlend blend,
  required List<({PdfVectorPath centerline, double width, PdfLineCap cap})>
  lines,
}) {
  final groups = <(double, PdfLineCap), List<PdfVectorPath>>{};
  for (final line in lines) {
    if (line.centerline.isEmpty) continue;
    (groups[(line.width, line.cap)] ??= []).add(line.centerline);
  }
  return [
    for (final MapEntry(key: (width, cap), value: paths) in groups.entries)
      PdfStrokeItem(
        path: PdfVectorPath.concat(paths),
        colorArgb: colorArgb,
        opacity: opacity,
        blend: blend,
        width: width,
        cap: cap,
        join: PdfLineJoin.round,
      ),
  ];
}
