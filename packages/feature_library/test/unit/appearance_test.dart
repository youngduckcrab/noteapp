// Folder / cover appearance registry (05-library 4.4; task L2 checks, the
// registry itself is part of foundation step B6).
import 'package:feature_library/feature_library.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// 05-library 4.4: key → Icons.* and Korean label, in picker order.
const _expected = <(String, IconData, String)>[
  ('folder', Icons.folder, '폴더'),
  ('book', Icons.menu_book, '책'),
  ('school', Icons.school, '학교'),
  ('work', Icons.work, '업무'),
  ('science', Icons.science, '과학'),
  ('calculate', Icons.calculate, '계산'),
  ('language', Icons.translate, '언어'),
  ('music', Icons.music_note, '음악'),
  ('art', Icons.palette, '미술'),
  ('idea', Icons.lightbulb, '아이디어'),
  ('code', Icons.code, '코드'),
  ('travel', Icons.flight, '여행'),
  ('home', Icons.home, '집'),
  ('pet', Icons.pets, '반려동물'),
  ('star', Icons.star, '별'),
  ('heart', Icons.favorite, '하트'),
];

void main() {
  group('FolderIcons', () {
    test('16 unique keys of at most 32 characters, default first', () {
      expect(FolderIcons.keys, hasLength(16));
      expect(FolderIcons.keys.toSet(), hasLength(16));
      for (final key in FolderIcons.keys) {
        expect(key, isNotEmpty);
        expect(key.length, lessThanOrEqualTo(32), reason: key);
      }
      expect(FolderIcons.defaultKey, 'folder');
      expect(FolderIcons.keys.first, FolderIcons.defaultKey);
    });

    test('keys, icons and labels follow the 4.4 table', () {
      expect(FolderIcons.keys, [for (final (key, _, _) in _expected) key]);
      for (final (key, icon, label) in _expected) {
        expect(FolderIcons.iconFor(key), icon, reason: key);
        expect(FolderIcons.labelFor(key), label, reason: key);
      }
      final icons = {
        for (final key in FolderIcons.keys) FolderIcons.iconFor(key),
      };
      expect(icons, hasLength(16));
    });

    test('null or an unknown key falls back to the folder icon', () {
      expect(FolderIcons.iconFor(null), Icons.folder);
      expect(FolderIcons.iconFor(''), Icons.folder);
      expect(FolderIcons.iconFor('rocket-from-a-newer-app'), Icons.folder);
      expect(FolderIcons.iconFor('Book'), Icons.folder);
      expect(FolderIcons.labelFor('rocket-from-a-newer-app'), '폴더');
    });
  });

  group('palettes', () {
    test('FolderPalette: 10 unique opaque colors with a name each', () {
      expect(FolderPalette.colors, hasLength(10));
      expect(FolderPalette.names, hasLength(FolderPalette.colors.length));
      expect(FolderPalette.colors.toSet(), hasLength(10));
      expect(FolderPalette.names.toSet(), hasLength(10));
      for (final argb in FolderPalette.colors) {
        expect(argb, inInclusiveRange(0xFF000000, 0xFFFFFFFF));
      }
      expect(FolderPalette.colors.first, 0xFF5B8DEF);
      expect(FolderPalette.names.first, '파랑');
    });

    test('CoverPalette: 8 unique opaque colors with a name each', () {
      expect(CoverPalette.colors, hasLength(8));
      expect(CoverPalette.names, hasLength(CoverPalette.colors.length));
      expect(CoverPalette.colors.toSet(), hasLength(8));
      expect(CoverPalette.names.toSet(), hasLength(8));
      for (final argb in CoverPalette.colors) {
        expect(argb, inInclusiveRange(0xFF000000, 0xFFFFFFFF));
      }
      expect(CoverPalette.colors.last, 0xFF2B2B2B);
      expect(CoverPalette.names.last, '먹색');
    });
  });

  group('coverForegroundFor', () {
    const white = Color(0xFFFFFFFF);
    const black87 = Color(0xDE000000);

    test('light colors get the dark title color', () {
      expect(coverForegroundFor(0xFFFFFFFF), black87);
      expect(coverForegroundFor(0xFFFFEB3B), black87); // yellow
      expect(coverForegroundFor(0xFFE0E0E0), black87);
    });

    test('dark colors get white', () {
      expect(coverForegroundFor(0xFF000000), white);
      expect(coverForegroundFor(0xFF2B2B2B), white);
      expect(coverForegroundFor(0xFF2F4A7A), white);
    });

    test('follows Color.computeLuminance() < 0.5 for every palette color', () {
      for (final argb in [...CoverPalette.colors, ...FolderPalette.colors]) {
        final expected = Color(argb).computeLuminance() < 0.5 ? white : black87;
        expect(coverForegroundFor(argb), expected, reason: argb.toString());
      }
    });

    test('any ARGB, also unknown synced values, gives one of the two', () {
      for (final argb in [0x00000000, 0x80FFFFFF, 0xFF123456, 0x00FFFFFF]) {
        expect(coverForegroundFor(argb), anyOf(white, black87));
      }
    });
  });
}
