@TestOn('vm')
@Tags(['golden'])
library;

// 03-ink 9.2 golden operation: every golden image lives in test/goldens/images/
// (no PNG next to the test files), is at most 400 × 400 px and is opaque
// (alpha 255 in every pixel — a fractional capture size leaves a partly
// covered last row / column; test/support/golden_frame.dart crops to whole
// pixels), and the list matches 9.2 (pens 2, templates 4 × 2, music /
// planner × 2, partial erase, thumbnail, pen preview = 17).
// v2 (m5-7/03-ink 9.4): the 17 round-1 images keep their names (and bytes —
// their tests are unchanged), plus the 2nd-round images so far.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import '../support/golden_frame.dart';

const _dir = 'test/goldens/images';

/// m5-7/03-ink 9.4 images added so far (T27: brush, preview sheet; T33: shapes).
const Set<String> _roundTwo = {
  'pens_p1_brush.png',
  'pens_p1_calligraphy.png',
  'pens_p1_dashed.png',
  'pens_p1_preview.png',
  'pens_p1_tape.png',
  'shapes_lines.png',
  'shapes_fill_arrows.png',
};

List<File> _pngs(String dir) =>
    Directory(dir)
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.png'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

void main() {
  test('no golden image outside images/', () {
    expect(_pngs('test/goldens').map((f) => f.path), isEmpty);
  });

  test('the 9.2 golden list (17 images) + the 2nd-round images', () {
    final names = {for (final f in _pngs(_dir)) f.uri.pathSegments.last};
    expect(names.difference(_roundTwo), hasLength(17), reason: 'round 1');
    expect(names.containsAll(_roundTwo), isTrue);
  });

  for (final file in _pngs(_dir)) {
    final name = file.uri.pathSegments.last;
    testWidgets('$name: ≤ 400 × 400 px, opaque', (tester) async {
      final pixels = await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(file.readAsBytesSync());
        final frame = await codec.getNextFrame();
        final image = frame.image;
        final data = await image.toByteData();
        final result = (image.width, image.height, data!.buffer.asUint8List());
        image.dispose();
        codec.dispose();
        return result;
      });
      final (w, h, rgba) = pixels!;
      expect(w, lessThanOrEqualTo(kMaxGoldenSidePx));
      expect(h, lessThanOrEqualTo(kMaxGoldenSidePx));
      var translucent = 0;
      for (var i = 3; i < rgba.length; i += 4) {
        if (rgba[i] != 255) translucent++;
      }
      expect(translucent, 0, reason: 'pixels with alpha < 255');
    });
  }
}
