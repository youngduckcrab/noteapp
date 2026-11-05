// lib/src/ink_adapter/ink_vectorizer.dart — 06-pdf 4.9, 6.11.8 (PDF T12).
//
// The INK vector export adapter (with template_underlay.dart the only INK export calls):
// ink.InkVectorExport.exportPage for the strokes, ink.TemplateVectors.build (through
// pdfPageUnderlay) for the paper and template.
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;

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
        for (final group in vectors.highlighterGroups)
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
        for (final shape in vectors.inkShapes)
          PdfFillItem(
            path: _path(shape.path),
            colorArgb: shape.colorArgb,
            opacity: shape.opacity,
          ),
      ],
    );
  }

  static PdfVectorPath _path(ink.InkVectorPath path) =>
      PdfVectorPath(path.verbs, path.coords);
}

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
