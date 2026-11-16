// (v2.14-ui, docs/plans/m5-7/05-library.md 18) The library picks up the
// screen style: the sidebar is the style's rail, the content area its screen
// surface, in light and dark. Pixel probe on the rendered layer.
import 'dart:ui' as ui;

import 'package:feature_library/src/ui/content/note_cover_view.dart';
import 'package:feature_library/src/ui/sidebar/library_sidebar.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui_kit/ui_kit.dart';

import '../support/fake_library_backend.dart';
import '../support/library_test_harness.dart';

Future<Color> _pixelAt(WidgetTester tester, Offset logical) async {
  final view = tester.binding.renderViews.first;
  final layer = view.debugLayer! as OffsetLayer;
  final dpr = tester.view.devicePixelRatio;
  final image = (await tester.runAsync(
    () => layer.toImage(Offset.zero & (view.size * dpr), pixelRatio: 1 / dpr),
  ))!;
  final data = (await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
  ))!;
  final x = logical.dx.round(), y = logical.dy.round();
  final i = (y * image.width + x) * 4;
  final color = Color.fromARGB(
    data.getUint8(i + 3),
    data.getUint8(i),
    data.getUint8(i + 1),
    data.getUint8(i + 2),
  );
  image.dispose();
  return color;
}

bool _near(Color a, Color b) =>
    ((a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs()) < 0.03;

void main() {
  late FakeLibraryBackend backend;
  setUp(() => backend = FakeLibraryBackend());
  tearDown(() => backend.dispose());

  for (final style in AppStyle.values) {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      testWidgets('${style.wireName} ${brightness.name}: sidebar = rail, '
          'content = screen surface', (tester) async {
        await tester.runAsync(() => backend.seedNote('물리 2주차'));
        final tokens = styleTokensFor(style, brightness);
        await LibraryTestHarness(backend)
            .pump(tester, theme: buildStyleTheme(style, brightness));
        await tester.pumpAndSettle();

        final sidebar = tester.getRect(find.byType(LibrarySidebar));
        // Bottom of the sidebar, right edge: empty rail.
        final railPixel = await _pixelAt(
          tester,
          Offset(sidebar.right - 6, sidebar.center.dy + 120),
        );
        expect(
          _near(railPixel, tokens.rail),
          isTrue,
          reason: 'rail pixel $railPixel vs ${tokens.rail}',
        );
        // Bottom right corner of the content: the screen surface.
        final view = tester.view.physicalSize / tester.view.devicePixelRatio;
        final contentPixel = await _pixelAt(
          tester,
          Offset(view.width - 6, view.height - 6),
        );
        expect(
          _near(contentPixel, tokens.toolbar),
          isTrue,
          reason: 'content pixel $contentPixel vs ${tokens.toolbar}',
        );
        expect(
          (railPixel.computeLuminance() < 0.2) &&
              (contentPixel.computeLuminance() < 0.2),
          brightness == Brightness.dark,
        );
      });
    }
  }

  // (v2.14-ui review) A note placeholder is paper-coloured in dark styles,
  // like the real first-page thumbnails it stands in for.
  for (final style in AppStyle.values) {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      testWidgets('${style.wireName} ${brightness.name}: cover placeholder', (
        tester,
      ) async {
        final tokens = styleTokensFor(style, brightness);
        final theme = buildStyleTheme(style, brightness);
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: const Center(
              child: CoverPlaceholder(width: 120, height: 160),
            ),
          ),
        );
        final box = tester.widget<ColoredBox>(
          find.descendant(
            of: find.byType(CoverPlaceholder),
            matching: find.byType(ColoredBox),
          ),
        );
        // (owner review) Paper in every brightness (thumbnails are paper
        // too), with the 노트 line icon readable on it.
        expect(box.color.computeLuminance(), greaterThan(0.7));
        final icon = tester.widget<AppIcon>(
          find.byWidgetPredicate(
            (w) => w is AppIcon && w.kind == AppIconKind.note,
          ),
        );
        expect(
          contrastRatio(Color.alphaBlend(icon.color!, box.color), box.color),
          greaterThanOrEqualTo(1.8),
        );
        expect(tokens.brightness, brightness);
      });
    }
  }
}
