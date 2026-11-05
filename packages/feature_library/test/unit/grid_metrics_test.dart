// GridMetrics / librarySizeClassFor / libraryContentWidth (05-library 6.2,
// 8 L8): the 8 rows of the 6.2 table.
import 'package:feature_library/src/ui/layout/grid_metrics.dart';
import 'package:feature_library/src/ui/layout/size_class.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // (screen width, sidebar shown, class, contentWidth, columns, tile width)
  const rows = <(String, double, bool, LibrarySizeClass, double, int, double)>[
    ('13" landscape', 1376, true, LibrarySizeClass.expanded, 1095, 5, 193.4),
    ('12.9" landscape', 1366, true, LibrarySizeClass.expanded, 1085, 5, 191.4),
    ('11" landscape', 1194, true, LibrarySizeClass.expanded, 913, 4, 201.25),
    (
      '13" landscape, sidebar hidden',
      1376,
      false,
      LibrarySizeClass.expanded,
      1376,
      7,
      172.5714,
    ),
    ('13" portrait', 1032, true, LibrarySizeClass.medium, 1032, 5, 180.8),
    ('11" portrait', 834, true, LibrarySizeClass.medium, 834, 4, 181.5),
    ('13" split half', 683, true, LibrarySizeClass.medium, 683, 3, 198.3333),
    ('phone', 375, true, LibrarySizeClass.compact, 375, 2, 165.5),
  ];

  for (final (name, width, sidebar, sizeClass, content, columns, tile)
      in rows) {
    test('6.2 table: $name', () {
      expect(librarySizeClassFor(width), sizeClass);
      final contentWidth = libraryContentWidth(
        width,
        sizeClass: sizeClass,
        sidebarVisible: sidebar,
      );
      expect(contentWidth, content);
      final m = GridMetrics.forWidth(contentWidth, sizeClass: sizeClass);
      expect(m.columns, columns);
      expect(m.tileWidth, closeTo(tile, 0.001));
      expect(m.coverHeight, closeTo(tile * 4 / 3, 0.001));
      expect(m.tileHeight, closeTo(tile * 4 / 3 + 64, 0.001));
      // The tiles and gaps fill the inner width exactly.
      expect(
        m.columns * m.tileWidth + (m.columns - 1) * m.gap + 2 * m.padding,
        closeTo(contentWidth, 0.001),
      );
    });
  }

  test('padding / gap / min tile by class', () {
    final compact = GridMetrics.forWidth(
      375,
      sizeClass: LibrarySizeClass.compact,
    );
    expect((compact.padding, compact.gap), (16.0, 12.0));
    final regular = GridMetrics.forWidth(
      1032,
      sizeClass: LibrarySizeClass.medium,
    );
    expect((regular.padding, regular.gap), (24.0, 20.0));
  });

  test('size class breakpoints', () {
    expect(librarySizeClassFor(1100), LibrarySizeClass.expanded);
    expect(librarySizeClassFor(1099.9), LibrarySizeClass.medium);
    expect(librarySizeClassFor(600), LibrarySizeClass.medium);
    expect(librarySizeClassFor(599.9), LibrarySizeClass.compact);
    expect(librarySizeClassFor(0), LibrarySizeClass.compact);
  });

  test('the sidebar is subtracted in the expanded class only', () {
    expect(
      libraryContentWidth(
        1032,
        sizeClass: LibrarySizeClass.medium,
        sidebarVisible: true,
      ),
      1032,
    );
  });

  test('at least 2 columns even when narrow; text scale capped at 1.3', () {
    final narrow = GridMetrics.forWidth(
      200,
      sizeClass: LibrarySizeClass.compact,
    );
    expect(narrow.columns, 2);
    expect(narrow.tileWidth, closeTo((200 - 32 - 12) / 2, 0.001));
    final big = GridMetrics.forWidth(
      1032,
      sizeClass: LibrarySizeClass.medium,
      textScale: 2,
    );
    expect(big.tileHeight - big.coverHeight, closeTo(8 + 56 * 1.3, 0.001));
    final scaled = GridMetrics.forWidth(
      1032,
      sizeClass: LibrarySizeClass.medium,
      textScale: 1.2,
    );
    expect(
      scaled.tileHeight - scaled.coverHeight,
      closeTo(8 + 56 * 1.2, 0.001),
    );
  });

  test('breadcrumb crumbs by class', () {
    expect(breadcrumbMaxVisibleFor(LibrarySizeClass.expanded), 4);
    expect(breadcrumbMaxVisibleFor(LibrarySizeClass.medium), 3);
    expect(breadcrumbMaxVisibleFor(LibrarySizeClass.compact), 2);
  });
}
