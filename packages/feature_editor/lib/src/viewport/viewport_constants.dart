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
}
