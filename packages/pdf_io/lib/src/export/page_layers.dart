// lib/src/export/page_layers.dart — m5-7/06-pdf 4.1.3, 6.2.1, 6.2.2, 6.2.9 (v2.1, PDF-M2; T24).
// Internal (not exported). No ink_engine import: the per-layer intermediate form of one page
// and the pure step that turns it into the page plan, so the L-1 order and the options are
// tested on the VM with hand-made layers (unit/page_layers_test), before INK's real export
// (INK T42). INK values become layers in ink_adapter/ink_vectorizer.dart (layersFromInk).
import 'dart:ui' as ui;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import 'vectors.dart';

/// The page background's part of the plan (L-1 1): the paper fill colour (null when white, or a
/// PDF page — the original page is the bottom), the template underlay (1차 pdfPageUnderlay items)
/// and the image background reference.
@immutable
final class PdfPageBackgroundPart {
  const PdfPageBackgroundPart({this.paperArgb, this.templateItems, this.image});

  /// A PDF background page: nothing (the original page is the bottom).
  static const PdfPageBackgroundPart none = PdfPageBackgroundPart();

  /// Paper fill ARGB, `null` when the paper is white.
  final int? paperArgb;

  /// Template lines and dots (1차 pdfTemplateItems), `null` when the page has no template.
  final List<PdfVectorItem>? templateItems;

  /// The image background (PdfAssetImageRef.background), `null` when there is none.
  final PdfAssetImageRef? image;

  /// No item at all.
  bool get isEmpty =>
      paperArgb == null && (templateItems?.isEmpty ?? true) && image == null;

  /// Same paper colour and image; template items compared by identity (vector items have no
  /// value equality — 1차).
  @override
  bool operator ==(Object other) =>
      other is PdfPageBackgroundPart &&
      other.paperArgb == paperArgb &&
      const ListEquality<PdfVectorItem>(IdentityEquality())
          .equals(other.templateItems, templateItems) &&
      other.image == image;

  @override
  int get hashCode => Object.hash(
    paperArgb,
    const ListEquality<PdfVectorItem>(IdentityEquality()).hash(templateItems),
    image,
  );

  @override
  String toString() =>
      'PdfPageBackgroundPart(paper: $paperArgb, '
      'template: ${templateItems?.length}, image: $image)';
}

/// One page in the L-1 layers (6.2.1), each list in z order.
@immutable
final class PdfPageLayers {
  const PdfPageLayers({
    required this.pageSize,
    this.background = PdfPageBackgroundPart.none,
    this.underlay = const [],
    this.highlighter = const [],
    this.ink = const [],
    this.annotations = const [],
    this.cover = const [],
  });

  /// Note pt.
  final ui.Size pageSize;

  /// Paper / template underlay / image background / none (PDF page).
  final PdfPageBackgroundPart background;

  /// L-1 2 — image objects, z order.
  final List<PdfAssetImageRef> underlay;

  /// L-1 3 — 1차 highlighterGroups conversion.
  final List<PdfStrokeItem> highlighter;

  /// L-1 4 — strokes, shape fills / borders, dash pieces, z order.
  final List<PdfFillItem> ink;

  /// L-1 5 — PdfTextBoxRef / PdfMathRef, z order.
  final List<PdfPlanItem> annotations;

  /// L-1 6 — tape, solid.
  final List<PdfFillItem> cover;

  /// Same size, background and references; vector items compared by identity.
  @override
  bool operator ==(Object other) =>
      other is PdfPageLayers &&
      other.pageSize == pageSize &&
      other.background == background &&
      const ListEquality<PdfAssetImageRef>().equals(other.underlay, underlay) &&
      const ListEquality<PdfStrokeItem>(IdentityEquality())
          .equals(other.highlighter, highlighter) &&
      const ListEquality<PdfFillItem>(IdentityEquality())
          .equals(other.ink, ink) &&
      const ListEquality<PdfPlanItem>().equals(
        other.annotations,
        annotations,
      ) &&
      const ListEquality<PdfFillItem>(IdentityEquality())
          .equals(other.cover, cover);

  @override
  int get hashCode => Object.hash(
    pageSize,
    background,
    const ListEquality<PdfAssetImageRef>().hash(underlay),
    const ListEquality<PdfStrokeItem>(IdentityEquality()).hash(highlighter),
    const ListEquality<PdfFillItem>(IdentityEquality()).hash(ink),
    const ListEquality<PdfPlanItem>().hash(annotations),
    const ListEquality<PdfFillItem>(IdentityEquality()).hash(cover),
  );

  @override
  String toString() =>
      'PdfPageLayers($pageSize, $background, underlay ${underlay.length}, '
      'highlighter ${highlighter.length}, ink ${ink.length}, '
      'annotations ${annotations.length}, cover ${cover.length})';
}

/// Pure: L-1 order (6.2.1) + options (6.2.9). [includeInk] false → background only (the image
/// background stays — it is the page's background, like a PDF page's original); [includeTemplate]
/// false → the paper fill and the template are removed, the image background is kept.
///
/// Order: paper fill (page rect) → template items → image background → image objects →
/// highlighter → ink → text boxes and formulas → tape.
PdfPagePlan planFromLayers(
  PdfPageLayers layers, {
  required bool includeInk,
  required bool includeTemplate,
}) {
  final background = layers.background;
  final paper = background.paperArgb;
  final image = background.image;
  final items = <PdfPlanItem>[
    if (includeTemplate) ...[
      if (paper != null)
        PdfFillItem(
          path: PdfVectorPath.rect(ui.Offset.zero & layers.pageSize),
          colorArgb: paper,
        ),
      ...?background.templateItems,
    ],
    ?image,
    if (includeInk) ...[
      ...layers.underlay,
      ...layers.highlighter,
      ...layers.ink,
      ...layers.annotations,
      ...layers.cover,
    ],
  ];
  return items.isEmpty
      ? PdfPagePlan.empty
      : PdfPagePlan(List.unmodifiable(items));
}
