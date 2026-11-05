// lib/src/appearance/folder_appearance.dart — contract 00-overview 7.2.18
// ("LIBRARY 4.4 (approved)"), 05-library 4.4. Folder colors are one of the
// palette exceptions of the no-hard-coded-colors rule (contract 7.4.11).
import 'package:material_ui/material_ui.dart';

/// Folder icon keys stored in Folder.icon. Keys are stable wire values —
/// never rename or reuse one; only append.
abstract final class FolderIcons {
  static const String defaultKey = 'folder';

  /// Display order in the picker (4 x 4 grid).
  static const List<String> keys = [
    'folder', 'book', 'school', 'work', //
    'science', 'calculate', 'language', 'music', //
    'art', 'idea', 'code', 'travel', //
    'home', 'pet', 'star', 'heart', //
  ];

  /// Icon for a stored key. null or unknown key → Icons.folder.
  /// Every value is a const Icons.* reference (web icon tree-shaking).
  static IconData iconFor(String? key) => switch (key) {
    'folder' => Icons.folder,
    'book' => Icons.menu_book,
    'school' => Icons.school,
    'work' => Icons.work,
    'science' => Icons.science,
    'calculate' => Icons.calculate,
    'language' => Icons.translate,
    'music' => Icons.music_note,
    'art' => Icons.palette,
    'idea' => Icons.lightbulb,
    'code' => Icons.code,
    'travel' => Icons.flight,
    'home' => Icons.home,
    'pet' => Icons.pets,
    'star' => Icons.star,
    'heart' => Icons.favorite,
    _ => Icons.folder,
  };

  /// Korean semantic label for screen readers, e.g. 'book' → '책'.
  /// An unknown key (for example one synced from a newer app version) gets
  /// the label of the default icon, matching [iconFor].
  static String labelFor(String key) => switch (key) {
    'folder' => '폴더',
    'book' => '책',
    'school' => '학교',
    'work' => '업무',
    'science' => '과학',
    'calculate' => '계산',
    'language' => '언어',
    'music' => '음악',
    'art' => '미술',
    'idea' => '아이디어',
    'code' => '코드',
    'travel' => '여행',
    'home' => '집',
    'pet' => '반려동물',
    'star' => '별',
    'heart' => '하트',
    _ => '폴더',
  };
}

/// Folder colors (ARGB). null = no color (theme default).
abstract final class FolderPalette {
  static const List<int> colors = [
    0xFF5B8DEF, // 파랑
    0xFF4CAF7A, // 초록
    0xFFF2B33D, // 노랑
    0xFFF28B3D, // 주황
    0xFFE5534B, // 빨강
    0xFFE36AA7, // 분홍
    0xFF9B6BDF, // 보라
    0xFF4BB3C9, // 청록
    0xFF8D6E63, // 갈색
    0xFF78858F, // 회색
  ];

  /// Korean names in the same order (semantics, tooltips).
  static const List<String> names = [
    '파랑', '초록', '노랑', '주황', '빨강', '분홍', '보라', '청록', '갈색', '회색', //
  ];
}
