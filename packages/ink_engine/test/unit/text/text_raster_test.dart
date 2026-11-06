// T26a (m5-7/03-ink 8.1, 4.10, CP-PDF-7): InkTextLayout.rasterize — ⌈w·k⌉ × ⌈h·k⌉,
// a transparent background even when the box has a background color, the text
// clipped to the frame, a page-size box at 300 dpi stays ≤ 4 Mpx, a zero frame →
// null.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

Future<Uint8List> _files({required bool bold}) async =>
    File('assets/fonts/NoteSans-${bold ? 'Bold' : 'Regular'}.ttf')
        .readAsBytesSync();

Future<(int, int, ByteData)> _rgba(ui.Image image) async {
  final data = (await image.toByteData())!;
  return (image.width, image.height, data);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    debugSetInkFontSource(_files);
    await InkFonts.ensureLoaded();
  });
  tearDownAll(() => debugSetInkFontSource(null));

  core.TextBoxObject box(String text, core.PageRect rect, {int? background}) =>
      core.TextBoxObject(
        id: 't',
        pageId: 'p1',
        frame: core.ElementFrame(rect),
        text: text,
        style: core.TextBoxStyle(backgroundArgb: background),
        createdAt: 1,
      );

  test('frame size × k, transparent background, glyphs inside', () async {
    final image = (await InkTextLayout.rasterize(
      box(
        '안녕 hello',
        const core.PageRect(10, 20, 210, 60),
        background: 0xFF00FF00,
      ),
      pixelsPerPt: 2,
    ))!;
    final (w, h, px) = await _rgba(image);
    expect([w, h], [400, 80]);
    int alphaAt(int x, int y) => px.getUint8((y * w + x) * 4 + 3);
    expect(alphaAt(w - 2, h - 2), 0, reason: 'no background in the raster');
    var inked = 0;
    for (var i = 3; i < px.lengthInBytes; i += 4) {
      if (px.getUint8(i) > 0) inked++;
    }
    expect(inked, greaterThan(100));
    image.dispose();
  });

  test(
    'the text is clipped to the frame (a too-small frame keeps its size)',
    () async {
      final image = (await InkTextLayout.rasterize(
        box('줄 1\n줄 2\n줄 3\n줄 4', const core.PageRect(0, 0, 100, 20)),
        pixelsPerPt: 1.5,
      ))!;
      expect([image.width, image.height], [150, 30]);
      image.dispose();
    },
  );

  test('a page-size box at 300 dpi is ≤ 4 Mpx', () async {
    final page = PageObjectFixtures.textBox(
      pageId: 'p1',
      rect: const core.PageRect(0, 0, 595, 842),
    );
    final image = (await InkTextLayout.rasterize(page, pixelsPerPt: 300 / 72))!;
    expect(image.width * image.height, lessThanOrEqualTo(4194304));
    expect(image.width, greaterThan(1000));
    image.dispose();
  });

  test('a zero frame → null', () async {
    expect(
      await InkTextLayout.rasterize(
        box('x', const core.PageRect(10, 10, 10, 50)),
        pixelsPerPt: 2,
      ),
      isNull,
    );
    expect(
      await InkTextLayout.rasterize(
        box('x', const core.PageRect(10, 10, 50, 10)),
        pixelsPerPt: 2,
      ),
      isNull,
    );
  });
}
