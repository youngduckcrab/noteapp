// T13 (03-ink 8, 4.10, 6.16): TemplateBackgroundLayerBuilder.renderStill —
// the image has pixelSize, the opaque paper color and the template lines
// (thumbnails / InkPageThumbnailRenderer use it).
import 'dart:ui' as ui;
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:note_core/note_core.dart' as core;

import '../support/pixels.dart';

const _a4 = Size(595.2756, 841.8898);

Future<Pixels> _still(
  core.PageBackground bg, {
  Size pixelSize = const Size(298, 421),
  Size pageSize = _a4,
}) async {
  final image = (await const TemplateBackgroundLayerBuilder().renderStill(
    InkBackgroundSpec.fromCore(bg),
    pageSize: pageSize,
    pixelSize: pixelSize,
  ))!;
  try {
    return Pixels(image.width, image.height, (await image.toByteData())!);
  } finally {
    image.dispose();
  }
}

core.TemplateBackground _template(
  core.PageTemplateKind kind, {
  int paper = core.PaperColors.white,
}) => core.TemplateBackground(
  template: core.PageTemplate.defaults(kind),
  paperColorArgb: paper,
);

int _inkPixels(Pixels px, List<int> paper) {
  var n = 0;
  for (var y = 0; y < px.height; y++) {
    for (var x = 0; x < px.width; x++) {
      final p = px.at(x, y);
      if (p[0] != paper[0] || p[1] != paper[1] || p[2] != paper[2]) n++;
    }
  }
  return n;
}

void main() {
  const white = [255, 255, 255, 255];
  const black = [0x20, 0x21, 0x24, 255];

  test('size = pixelSize; opaque paper; blank = paper only', () async {
    final px = await _still(
      const core.BlankBackground(paperColorArgb: core.PaperColors.ivory),
      pixelSize: const Size(120.4, 169.6),
    );
    expect((px.width, px.height), (120, 170));
    expect(px.at(0, 0), [0xFB, 0xF7, 0xEC, 255]);
    expect(_inkPixels(px, [0xFB, 0xF7, 0xEC]), 0);
    // a translucent paper color is drawn opaque
    final translucent = await _still(
      const core.BlankBackground(paperColorArgb: 0x80FF0000),
      pixelSize: const Size(10, 10),
    );
    expect(translucent.at(5, 5), [255, 0, 0, 255]);
  });

  test('lined: ruled lines and the margin line at the page scale', () async {
    final px = await _still(_template(core.PageTemplateKind.lined));
    const s = 298 / 595.2756; // ≈ 0.5
    final lineRow = ((72 + 24 * 5) * s).floor(); // ruled line k = 5
    var hit = false;
    for (final y in [lineRow - 1, lineRow, lineRow + 1]) {
      if (px.at(200, y)[2] != 255 || px.at(200, y)[0] != 255) hit = true;
    }
    expect(hit, isTrue, reason: 'a ruled line near row $lineRow');
    expect(px.at(200, ((72 + 24 * 5 + 12) * s).round()), white); // between
    expect(px.at((72 * s).round(), 10), isNot(white)); // margin line
    expect(px.at(5, 5), white); // above the first line, left of the margin
  });

  test('every kind draws lines; dark paper keeps its color', () async {
    for (final kind in core.PageTemplateKind.values) {
      final light = await _still(_template(kind));
      expect(light.at(0, light.height - 1)[3], 255);
      expect(
        _inkPixels(light, [255, 255, 255]),
        greaterThan(100),
        reason: '$kind',
      );
      final dark = await _still(_template(kind, paper: core.PaperColors.black));
      expect(_inkPixels(dark, black.sublist(0, 3)), greaterThan(100));
      // lines are lighter than the black paper
      var lighter = 0;
      for (var y = 0; y < dark.height; y += 3) {
        for (var x = 0; x < dark.width; x += 3) {
          if (dark.at(x, y)[0] > black[0] + 8) lighter++;
        }
      }
      expect(lighter, greaterThan(0), reason: '$kind on black');
    }
  });

  test('lines stay at least one pixel wide on a small still', () async {
    final px = await _still(
      _template(core.PageTemplateKind.grid),
      pixelSize: const Size(60, 85), // 0.1 px per pt
    );
    expect(_inkPixels(px, [255, 255, 255]), greaterThan(60));
  });

  test(
    'pdf / image specs: paper only (the template builder is the fallback)',
    () async {
      final px = await _still(
        const core.PdfBackground(
          assetId: 'a',
          pdfPageIndex: 0,
          paperColorArgb: core.PaperColors.gray,
        ),
        pixelSize: const Size(40, 56),
      );
      expect(_inkPixels(px, [0xF1, 0xF3, 0xF4]), 0);
      expect(px.at(20, 20), [0xF1, 0xF3, 0xF4, 255]);
    },
  );

  test('a ui.Image is returned for every template kind', () async {
    for (final kind in core.PageTemplateKind.values) {
      final image = await const TemplateBackgroundLayerBuilder().renderStill(
        InkBackgroundSpec.fromCore(_template(kind)),
        pageSize: _a4,
        pixelSize: const Size(30, 42),
      );
      expect(image, isA<ui.Image>());
      image!.dispose();
    }
  });
}
