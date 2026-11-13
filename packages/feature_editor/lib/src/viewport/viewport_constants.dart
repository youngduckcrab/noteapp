// lib/src/viewport/viewport_constants.dart — 04-editor 6.3.1.
abstract final class ViewportConstants {
  static const double minZoom = 0.5; // relative to fit
  static const double maxZoom = 8.0;
  static const double zoomSnapTolerance = 0.05; // |zoom-1| ≤ 0.05 → snap to 1
  static const double zoomStep = 1.25; // keyboard / buttons
  static const double wheelZoomDivisor = 300; // factor = exp(-dy / 300)
  static const double sideMargin = 16; // logical px, used by fit
  static const double pageGap = 24; // pt
  static const double leadingPadding = 24; // pt
  static const double trailingPadding = 120; // pt, room for "+ page" button
  static const int maxMountedPages =
      8; // = core NoteSessionOptions.maxCachedPages (E-2)
  static const Duration settleDelay = Duration(milliseconds: 150);
  static const Duration jumpDuration = Duration(milliseconds: 250);
  static const Duration snapDuration = Duration(milliseconds: 150);
  static const Duration pageSnapDuration = Duration(milliseconds: 280);
  static const double pageSnapVelocity = 300; // px/s, horizontal paged mode

  // Pull to add a page (6.11.7): a navigation drag held past the document
  // end overscrolls with resistance; released at or past the threshold it
  // adds a page like the last one.
  /// Shown pull = finger travel past the end × this (rubber band).
  static const double pullToAddResistance = 0.5;

  /// Cap of the shown pull (logical px).
  static const double pullToAddMaxExtent = 160;

  /// Shown pull (logical px) from which a release adds a page — about
  /// 2 × 96 = 192 px of finger travel past the end.
  static const double pullToAddThreshold = 96;
  static const Duration pullSpringBackDuration = Duration(milliseconds: 220);
}
