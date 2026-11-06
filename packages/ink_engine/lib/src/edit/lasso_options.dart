// lib/src/edit/lasso_options.dart — 03-ink 4.7; (v2.0) includeObjects (m5-7/03-ink 4.6).
import 'package:meta/meta.dart';

import '../tuning.dart';

/// Lasso inclusion rule — CONTRACT (00-review INK-S5, EDITOR Q9):
///  * The lasso path is closed end → start and simplified with RDP (simplifyPx / viewScale pt).
///    Fewer than 3 vertices or ∫|winding| dA < minAreaPt2 (= shoelace |area| for simple polygons;
///    a figure 8 adds its loops) → degenerate → no selection (EDITOR: tap).
///  * Inside test = NONZERO winding rule (figure-8 and doubly wound lassos select both loops).
///  * A stroke is selected iff (sum of lengths of its centerline segments whose MIDPOINT is
///    inside) / (centerline length) >= coverage (0.5). A dot (one point / zero length) is
///    selected iff its point is inside. Every tool is selectable (no StrokeFilter).
///  * (v2.0) [includeObjects] (default true): a page object is selected iff the center of its
///    frame is inside (nonzero, every object type).
@immutable
final class LassoOptions {
  const LassoOptions({
    this.coverage = InkTuning.lassoCoverage,
    this.simplifyPx = InkTuning.lassoSimplifyPx,
    this.minAreaPt2 = InkTuning.lassoMinAreaPt2,
    this.includeObjects = true,
  });

  /// fraction of centerline length that must be inside
  final double coverage;

  /// RDP tolerance in screen px
  final double simplifyPx;
  final double minAreaPt2;

  /// default true: object center inside → selected
  final bool includeObjects;

  @override
  bool operator ==(Object other) =>
      other is LassoOptions &&
      other.coverage == coverage &&
      other.simplifyPx == simplifyPx &&
      other.minAreaPt2 == minAreaPt2 &&
      other.includeObjects == includeObjects;

  @override
  int get hashCode =>
      Object.hash(coverage, simplifyPx, minAreaPt2, includeObjects);
}
