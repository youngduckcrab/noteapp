// lib/src/model/page_size_mm.dart — 05-library 6.12. The page size limits are
// CORE's (contract 7.2.5 PageSizeLimits); LIBRARY only converts to mm.
import 'package:note_core/note_core.dart' show PageSizeLimits;

/// mm <-> pt for the custom size fields. The ONLY limits are
/// core.PageSizeLimits (user input 100..3000 pt); this class just converts
/// them for display.
abstract final class PageSizeMm {
  static const double mmPerPt = 25.4 / 72;

  static double toMm(double pt) => pt * mmPerPt;

  static double toPt(double mm) => mm / mmPerPt;

  /// Input range shown and accepted by the mm fields, rounded INWARD to 0.1 mm
  /// so every accepted value converts to a pt size inside PageSizeLimits:
  ///   minInputMm = (toMm(PageSizeLimits.userMinSidePt) * 10).ceil() / 10 → 35.3
  ///   maxInputMm = (toMm(PageSizeLimits.userMaxSidePt) * 10).floor() / 10 → 1058.3
  static double get minInputMm =>
      (toMm(PageSizeLimits.userMinSidePt) * 10).ceil() / 10;

  static double get maxInputMm =>
      (toMm(PageSizeLimits.userMaxSidePt) * 10).floor() / 10;

  /// PageSizeLimits.userMinSidePt <= toPt(mm) <= PageSizeLimits.userMaxSidePt.
  /// For 0.1 mm steps this equals minInputMm <= mm <= maxInputMm (35.2 → 99.8
  /// pt ✗, 35.3 → 100.06 pt ✓, 1058.3 → 2999.9 pt ✓, 1058.4 → 3000.2 pt ✗).
  /// NaN and infinities are invalid.
  static bool isValidInput(double mm) {
    if (!mm.isFinite) return false;
    final pt = toPt(mm);
    return pt >= PageSizeLimits.userMinSidePt &&
        pt <= PageSizeLimits.userMaxSidePt;
  }

  /// Value clamped into [minInputMm, maxInputMm] (used by fromJson
  /// tolerance). NaN → minInputMm.
  static double clampInput(double mm) =>
      mm.isNaN ? minInputMm : mm.clamp(minInputMm, maxInputMm).toDouble();
}
