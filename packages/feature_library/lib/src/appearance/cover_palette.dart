// lib/src/appearance/cover_palette.dart — contract 00-overview 7.2.18
// ("LIBRARY 4.4 (approved)"), 05-library 4.4. Cover colors are one of the
// palette exceptions of the no-hard-coded-colors rule (contract 7.4.11).
import 'package:material_ui/material_ui.dart' show Color;

/// Colors for ColorCover (ARGB), shown in the cover picker.
abstract final class CoverPalette {
  static const List<int> colors = [
    0xFF2F4A7A, // 남색
    0xFF2E6B4F, // 숲색
    0xFF7A2E3B, // 버건디
    0xFFC9A227, // 겨자색
    0xFF5A6773, // 슬레이트
    0xFF7FB2E5, // 하늘색
    0xFFE8A9A0, // 살구색
    0xFF2B2B2B, // 먹색
  ];
  static const List<String> names = [
    '남색', '숲색', '버건디', '겨자색', '슬레이트', '하늘색', '살구색', '먹색', //
  ];
}

/// Title color on a dark cover.
const Color _lightForeground = Color(0xFFFFFFFF);

/// Title color on a light cover (87 % black).
const Color _darkForeground = Color(0xDE000000);

/// Title color on a colored cover: white when Color(argb).computeLuminance()
/// < 0.5, otherwise 0xDE000000. Any ARGB (also unknown synced colors).
Color coverForegroundFor(int argb) =>
    Color(argb).computeLuminance() < 0.5 ? _lightForeground : _darkForeground;
