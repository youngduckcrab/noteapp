// lib/src/model/page_size.dart — contract 00-overview 7.2.5 / CORE 4.2.3, 6.2.6.
import 'package:meta/meta.dart';

import '../common/json_read.dart';

/// CORE 4.2: each side in [72, 14400] (storage / PDF import).
@immutable
final class PageSize {
  const PageSize(this.width, this.height); // pt

  static const PageSize a4Portrait = PageSize(595.2756, 841.8898);
  static const PageSize letterPortrait = PageSize(612, 792);

  /// Landscape form (960×540) == PageSizePreset.widescreen16x9.portrait.landscape.
  static const PageSize widescreen16x9 = PageSize(960, 540);
  static const double minSide = 72, maxSide = 14400;

  final double width, height;

  bool get isLandscape => width > height;

  /// Longer side horizontal
  PageSize get landscape => width >= height ? this : PageSize(height, width);
  PageSize get portrait => height >= width ? this : PageSize(height, width);

  /// Each side clamped to [minSide, maxSide] (aspect not kept — PDF C-2)
  PageSize clamped() => PageSize(_clampSide(width), _clampSide(height));

  static double _clampSide(double v) =>
      v.isNaN ? minSide : v.clamp(minSide, maxSide).toDouble();

  /// JSON form `[w, h]` (one key, merged as one unit — CORE 6.3).
  List<double> toJson() => [width, height];

  static PageSize fromJson(Object? json) {
    final list = asList(json, 'size');
    if (list.length != 2) {
      throw FormatException('size needs [w, h], got ${list.length} values');
    }
    return PageSize(asDouble(list[0], 'size'), asDouble(list[1], 'size'));
  }

  @override
  bool operator ==(Object other) =>
      other is PageSize && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'PageSize($width × $height)';
}

enum PageSizePreset {
  a4,
  letter,
  widescreen16x9;

  /// a4 595.2756×841.8898, letter 612×792, widescreen16x9 540×960 (portrait form).
  PageSize get portrait => switch (this) {
    PageSizePreset.a4 => PageSize.a4Portrait,
    PageSizePreset.letter => PageSize.letterPortrait,
    PageSizePreset.widescreen16x9 => const PageSize(540, 960),
  };

  /// Either orientation within ±0.5 pt; null = custom.
  static PageSizePreset? match(PageSize size) {
    bool near(double a, double b) => (a - b).abs() <= 0.5;
    for (final preset in PageSizePreset.values) {
      final p = preset.portrait;
      if ((near(size.width, p.width) && near(size.height, p.height)) ||
          (near(size.width, p.height) && near(size.height, p.width))) {
        return preset;
      }
    }
    return null;
  }
}

abstract final class PageSizeLimits {
  /// Custom sizes typed by the user (EDITOR add-page sheet, LIBRARY new-note dialog).
  /// LIBRARY shows mm: 100 pt ≈ 35.3 mm, 3000 pt ≈ 1058.3 mm.
  static const double userMinSidePt = 100;
  static const double userMaxSidePt = 3000;
}
