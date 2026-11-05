// test/support/test_sizes.dart — 05-library 9.1 (L0). Logical px at DPR 2.
// The 13" values are contract 00-overview 7.4.8; the rest follow 9.1.
import 'package:flutter/widgets.dart' show Size;

abstract final class TestSizes {
  /// Device pixel ratio of every widget test (iPad Retina).
  static const double devicePixelRatio = 2;

  static const Size ipad13Landscape = Size(1376, 1032);
  static const Size ipad13Portrait = Size(1032, 1376);

  /// Landscape minus Safari's address and tab bars (conservative, unmeasured).
  static const Size ipad13SafariLandscape = Size(1376, 940);
  static const Size ipad129Landscape = Size(1366, 1024);
  static const Size ipad11Landscape = Size(1194, 834);
  static const Size ipad11Portrait = Size(834, 1194);

  /// Split View, half of a 13" landscape screen.
  static const Size splitHalf = Size(683, 1032);
  static const Size compact = Size(375, 667);

  /// The 8 sizes of the layout test (8 L8), in the order of 9.1.
  static const List<Size> all = [
    ipad13Landscape,
    ipad13Portrait,
    ipad13SafariLandscape,
    ipad129Landscape,
    ipad11Landscape,
    ipad11Portrait,
    splitHalf,
    compact,
  ];
}
