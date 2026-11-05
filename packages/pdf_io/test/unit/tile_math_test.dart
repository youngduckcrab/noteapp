// Tile math of the page background renderer (06-pdf 6.7.1, 6.7.2; 8 T8): scale buckets, the
// preview scale, the tile grid with its 1 px overlap and edges, the 25% prefetch margin, the
// 64-tile limit and thumbnail mode.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/src/render/tile_math.dart';

const ui.Size _a4 = ui.Size(595.276, 841.89);

PdfBackgroundParams _params({
  ui.Size pageSize = _a4,
  double deviceScale = 1,
  ui.Rect? visible,
  bool isThumbnail = false,
}) => PdfBackgroundParams(
  assetId: 'a',
  pdfPageIndex: 0,
  pageSize: pageSize,
  deviceScale: deviceScale,
  visiblePageRect: visible,
  isThumbnail: isThumbnail,
);

void main() {
  group('bucketScale (6.7.1)', () {
    test('s = 3.47 → 1.25^6 ≈ 3.815; s = 1 → 1.0', () {
      expect(bucketScale(3.47), math.pow(1.25, 6));
      expect(bucketScale(3.47), closeTo(3.815, 1e-3));
      expect(bucketScale(1), 1.0);
    });

    test('over-render ≤ 25%, under-render ≤ 5%', () {
      for (var s = 0.2; s < 20; s *= 1.037) {
        final b = bucketScale(s);
        expect(b, greaterThanOrEqualTo(s * 0.95 - 1e-12), reason: 's=$s');
        expect(b, lessThanOrEqualTo(s * 0.95 * 1.25 + 1e-12), reason: 's=$s');
      }
    });

    test('clamped to [0.125, 24]', () {
      expect(bucketScale(0.01), 0.125);
      expect(bucketScale(0), 0.125);
      expect(bucketScale(-1), 0.125);
      expect(bucketScale(1000), 24);
      expect(bucketScale(double.infinity), 24);
    });

    test('a bucket value maps to itself; 5% above it takes the next', () {
      expect(bucketScale(1.25), 1.25);
      expect(bucketScale(1.32), 1.25 * 1.25); // 1.32 × 0.95 > 1.25
    });
  });

  group('preview and thumbnail scales', () {
    test('A4 preview scale = 1024 / 841.89 ≈ 1.216, capped by the bucket', () {
      expect(previewScale(3.815, _a4), closeTo(1.2163, 1e-4));
      expect(previewScale(0.8, _a4), 0.8);
    });

    test('the preview / thumbnail long side is exactly 1024 / 256 px', () {
      for (final size in [
        _a4,
        const ui.Size(612, 792),
        const ui.Size(50, 50),
      ]) {
        final preview = PdfRenderRequest(
          pageIndex: 0,
          scale: previewScale(24, size),
        );
        final page = PdfPageInfo(
          index: 0,
          width: size.width,
          height: size.height,
          rotationQuarterTurns: 0,
        );
        final (pw, ph) = preview.fullPixelSize(page);
        expect(math.max(pw, ph), 1024, reason: '$size');
        final (tw, th) = PdfRenderRequest(
          pageIndex: 0,
          scale: thumbnailScale(size),
        ).fullPixelSize(page);
        expect(math.max(tw, th), 256, reason: '$size');
      }
    });

    test('tiles only when s > pv × 1.1', () {
      expect(needsTiles(1.3, 1.2163), isFalse);
      expect(needsTiles(1.34, 1.2163), isTrue);
    });
  });

  group('PdfTileGrid', () {
    final grid = PdfTileGrid(const ui.Size(300, 200), 4); // 1200 × 800 px

    test('full size = ceil(W·b) × ceil(H·b); 512 px cells', () {
      expect((grid.fullWidth, grid.fullHeight), (1200, 800));
      expect((grid.columns, grid.rows), (3, 2));
      expect(grid.tileCount, 6);
      final a4 = PdfTileGrid(_a4, 3.815);
      expect(a4.fullWidth, (595.276 * 3.815).ceil());
      expect(a4.fullHeight, (841.89 * 3.815).ceil());
    });

    test('tile rects: 512 inside, the rest at the right / bottom edge', () {
      PdfPixelRect r(int i, int j) => grid.tileRect(i, j);
      expect(_lt(r(0, 0)), (0, 0, 512, 512));
      expect(_lt(r(1, 0)), (512, 0, 512, 512));
      expect(_lt(r(2, 0)), (1024, 0, 176, 512));
      expect(_lt(r(2, 1)), (1024, 512, 176, 288));
    });

    test('requests overlap 1 px on every side, clipped to the page', () {
      expect(_lt(grid.requestRect(0, 0)), (0, 0, 513, 513));
      expect(_lt(grid.requestRect(1, 0)), (511, 0, 514, 513));
      expect(_lt(grid.requestRect(1, 1)), (511, 511, 514, 289));
      expect(_lt(grid.requestRect(2, 1)), (1023, 511, 177, 289));
    });

    test('srcRect = the tile inside its request (overlap excluded)', () {
      expect(grid.srcRect(0, 0), const ui.Rect.fromLTWH(0, 0, 512, 512));
      expect(grid.srcRect(1, 1), const ui.Rect.fromLTWH(1, 1, 512, 288));
      expect(grid.srcRect(2, 0), const ui.Rect.fromLTWH(1, 0, 176, 512));
    });

    test('tiles cover the page exactly once (pdf rects)', () {
      var area = 0.0;
      for (var j = 0; j < grid.rows; j++) {
        for (var i = 0; i < grid.columns; i++) {
          final r = grid.pdfRect(i, j);
          area += r.width * r.height;
        }
      }
      expect(area, closeTo(300 * 200, 1e-9));
      expect(grid.pdfRect(1, 1), const ui.Rect.fromLTWH(128, 128, 128, 72));
    });
  });

  group('tilesFor (6.7.2 step 4)', () {
    final grid = PdfTileGrid(
      const ui.Size(512, 512),
      8,
    ); // 4096 px → 8 × 8 = 64

    test('null visible rect = the whole page (≤ 64 tiles)', () {
      final tiles = tilesFor(grid, const ui.Size(512, 512));
      expect(tiles, hasLength(64));
      expect(tiles.every((t) => !t.prefetch), isTrue);
    });

    test('whole page with more than 64 tiles → no tiles (preview only)', () {
      final big = PdfTileGrid(const ui.Size(520, 512), 8); // 9 × 8 = 72
      expect(tilesFor(big, const ui.Size(520, 512)), isEmpty);
    });

    test('25% margin on every side; visible tiles first, nearest first', () {
      // Visible: pdf (128, 128)–(192, 192) = px 1024–1536 → cells 2 (exactly).
      final tiles = tilesFor(
        grid,
        const ui.Size(512, 512),
        visiblePdfRect: const ui.Rect.fromLTWH(128, 128, 64, 64),
      );
      final visible = [
        for (final t in tiles)
          if (!t.prefetch) (t.column, t.row),
      ];
      expect(visible, [(2, 2)]);
      // Margin: 16 pt each side → (112, 112)–(208, 208) = px 896–1664 → cells 1..3.
      final all = {for (final t in tiles) (t.column, t.row)};
      expect(all, {
        for (var j = 1; j <= 3; j++)
          for (var i = 1; i <= 3; i++) (i, j),
      });
      expect(tiles.first, const PdfTileRef(2, 2, prefetch: false));
      expect(tiles.skip(1).every((t) => t.prefetch), isTrue);
      expect(tiles.last.renderClass, PdfRenderClass.prefetchTile);
      expect(tiles.first.renderClass, PdfRenderClass.visibleTile);
    });

    test('visible tiles sorted by distance from the visible centre', () {
      final tiles = tilesFor(
        grid,
        const ui.Size(512, 512),
        visiblePdfRect: const ui.Rect.fromLTWH(100, 100, 100, 100),
      );
      final visible = [
        for (final t in tiles)
          if (!t.prefetch) t,
      ];
      // px 800–1600 → cells 1..3; centre (150 pt = 1200 px) is in cell 2.
      expect(visible.first, const PdfTileRef(2, 2, prefetch: false));
      expect(visible, hasLength(9));
      final centre = const ui.Rect.fromLTWH(100, 100, 100, 100).center;
      final distances = [
        for (final t in visible)
          (grid.pdfRect(t.column, t.row).center - centre).distance,
      ];
      expect(distances, orderedEquals([...distances]..sort()));
    });

    test('margin clipped to the page; off-page visible rect → none', () {
      final tiles = tilesFor(
        grid,
        const ui.Size(512, 512),
        visiblePdfRect: const ui.Rect.fromLTWH(0, 0, 64, 64),
      );
      expect(
        {for (final t in tiles) (t.column, t.row)},
        {(0, 0), (1, 0), (0, 1), (1, 1)},
      );
      expect(
        tilesFor(
          grid,
          const ui.Size(512, 512),
          visiblePdfRect: const ui.Rect.fromLTWH(600, 0, 64, 64),
        ),
        isEmpty,
      );
      expect(
        tilesFor(grid, const ui.Size(512, 512), visiblePdfRect: ui.Rect.zero),
        isEmpty,
      );
    });

    test('a visible rect needing more than 64 tiles is cut at 64', () {
      final huge = PdfTileGrid(const ui.Size(512, 512), 24); // 24 × 24 cells
      final tiles = tilesFor(
        huge,
        const ui.Size(512, 512),
        visiblePdfRect: const ui.Rect.fromLTWH(100, 100, 300, 300),
      );
      expect(tiles, hasLength(64));
      expect(tiles.every((t) => !t.prefetch), isTrue);
    });
  });

  group('PdfRenderPlan.of', () {
    test(
      'iPad Pro 13 portrait A4 (s ≈ 3.47): preview 1.216 + tiles at 3.815',
      () {
        final plan = PdfRenderPlan.of(
          _params(
            deviceScale: 3.47,
            visible: const ui.Rect.fromLTWH(0, 0, 595.276, 400),
          ),
          _a4,
        );
        expect(plan.thumbnailMode, isFalse);
        expect(plan.baseKind, PdfRenderKind.preview);
        expect(plan.baseScale, closeTo(1.2163, 1e-4));
        expect(plan.tileBucket, closeTo(3.815, 1e-3));
        expect(plan.tiles, isNotEmpty);
        expect(plan.tiles.length, lessThanOrEqualTo(64));
        expect(plan.tiles.first.prefetch, isFalse);
      },
    );

    test('low zoom: preview only, no tiles', () {
      final plan = PdfRenderPlan.of(_params(deviceScale: 1), _a4);
      expect(plan.baseScale, 1.0);
      expect(plan.grid, isNull);
      expect(plan.tiles, isEmpty);
    });

    test('isThumbnail → thumbnail mode (one 256 px image, no tiles)', () {
      final plan = PdfRenderPlan.of(
        _params(deviceScale: 6, isThumbnail: true),
        _a4,
      );
      expect(plan.thumbnailMode, isTrue);
      expect(plan.baseKind, PdfRenderKind.thumbnail);
      expect(plan.baseScale, closeTo(256 / 841.89, 1e-5));
      expect(plan.tiles, isEmpty);
    });

    test('long side ≤ 320 device px → thumbnail mode', () {
      expect(
        PdfRenderPlan.of(_params(deviceScale: 319 / 841.89), _a4).thumbnailMode,
        isTrue,
      );
      expect(
        PdfRenderPlan.of(_params(deviceScale: 330 / 841.89), _a4).thumbnailMode,
        isFalse,
      );
    });

    test(
      's ≠ 1: s = deviceScale × k, tiles placed in note pt with PdfPageFit',
      () {
        // PDF 50 × 50 on a 72 × 72 note page: k = 1.44.
        final plan = PdfRenderPlan.of(
          _params(pageSize: const ui.Size(72, 72), deviceScale: 40),
          const ui.Size(50, 50),
        );
        expect(plan.fit.k, closeTo(1.44, 1e-9));
        expect(plan.scale, closeTo(57.6, 1e-9));
        expect(plan.tileBucket, 24); // clamped
        final grid = plan.grid!;
        expect((grid.fullWidth, grid.fullHeight), (1200, 1200));
        expect(plan.tilePageRect(0, 0).width, closeTo(512 / 24 * 1.44, 1e-9));
        final last = plan.tilePageRect(2, 2);
        expect(last.right, closeTo(72, 1e-9));
        expect(last.bottom, closeTo(72, 1e-9));
      },
    );

    test('visible note rect is mapped to PDF pt (letterbox offset)', () {
      // Letter PDF on an A4 note page: oy ≈ 35.767, k ≈ 0.97267.
      final fit = PdfPageFit(
        notePageSize: _a4,
        pdfPageSize: const ui.Size(612, 792),
      );
      // Only the top letterbox band and the first pt rows of the PDF are visible.
      final plan = PdfRenderPlan.of(
        _params(
          deviceScale: 8,
          visible: ui.Rect.fromLTWH(0, 0, 595.276, fit.oy + 10),
        ),
        const ui.Size(612, 792),
      );
      final rows = {
        for (final t in plan.tiles)
          if (!t.prefetch) t.row,
      };
      expect(rows, {0});
    });
  });

  test('opaquePaperArgb forces alpha without bit operations', () {
    expect(opaquePaperArgb(0x80FBF7EC), 0xFFFBF7EC);
    expect(opaquePaperArgb(0x00000000), 0xFF000000);
    expect(opaquePaperArgb(0xFFFFFFFF), 0xFFFFFFFF);
  });
}

(int, int, int, int) _lt(PdfPixelRect r) => (r.left, r.top, r.width, r.height);
