// T20 (03-ink 6.17, contract 7.2.16): the off-screen thumbnail renderer —
// a decodable PNG whose long side is maxSidePx in the page's orientation,
// pageId / contentRevision of the page, template lines and strokes drawn,
// a still renderer's background composited, the null rules (still returns
// null; pdf without a still renderer), paper color for blank pages, and the
// yields to the event loop every 4 ms on a 3,000-stroke page. Real async zone
// (no fake time); test/web/thumbnail_png_web_test.dart runs it in Chrome.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/dev_tools.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/render/thumbnail_renderer.dart'
    show thumbnailRendererYieldsOf;
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

import '../support/pixels.dart';

Future<Pixels> _decode(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  try {
    return Pixels(image.width, image.height, (await image.toByteData())!);
  } finally {
    image.dispose();
    codec.dispose();
  }
}

core.PageContent _content({
  core.PageSize size = core.PageSize.a4Portrait,
  core.PageBackground background = const core.BlankBackground(),
  List<core.Stroke> strokes = const [],
  int contentRevision = 7,
}) => core.PageContent(
  page: SyntheticInk.page(
    pageId: 'pg1',
    size: size,
    background: background,
  ).copyWith(contentRevision: contentRevision),
  strokes: strokes,
  revision: 3,
);

core.Stroke _black(ui.Offset a, ui.Offset b, {String id = 'k'}) =>
    strokeThrough(
      segment(a, b),
      core.StrokeStyle.defaultsFor(core.PenTool.marker)
          .copyWith(width: 12, colorArgb: 0xFF000000),
      id: id,
    );

const _lined = core.TemplateBackground(
  template: core.PageTemplate(kind: core.PageTemplateKind.lined),
);

const _pdf = core.PdfBackground(assetId: 'a', pdfPageIndex: 0);

bool _isDark(List<int> p) => p[0] < 80 && p[1] < 80 && p[2] < 80;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final renderer = InkPageThumbnailRenderer(
    backgroundBuilders: const [TemplateBackgroundLayerBuilder()],
  );

  test('decodable PNG; long side = maxSidePx (512, 320) in the page\'s '
      'orientation; pageId and contentRevision of the page', () async {
    for (final (size, max, w, h) in [
      (core.PageSize.a4Portrait, 512, 362, 512),
      (core.PageSize.a4Portrait, 320, 226, 320),
      (core.PageSize.a4Portrait.landscape, 512, 512, 362),
      (core.PageSize.widescreen16x9, 512, 512, 288),
      (core.PageSize.widescreen16x9, 320, 320, 180),
    ]) {
      final t = (await renderer.render(_content(size: size), maxSidePx: max))!;
      expect((t.width, t.height), (w, h), reason: '$size @ $max');
      expect(t.pageId, 'pg1');
      expect(t.contentRevision, 7);
      expect(t.mimeType, 'image/png');
      final px = await _decode(t.bytes);
      expect((px.width, px.height), (w, h));
    }
    expect(
      () => renderer.render(_content(), maxSidePx: 0),
      throwsArgumentError,
    );
  });

  test('template lines and strokes are drawn', () async {
    final t = (await renderer.render(
      _content(
        background: _lined,
        strokes: [_black(const ui.Offset(100, 400), const ui.Offset(500, 400))],
      ),
    ))!;
    final px = await _decode(t.bytes);
    final s = t.height / core.PageSize.a4Portrait.height;
    // the stroke at y = 400 pt
    expect(_isDark(px.at((300 * s).round(), (400 * s).round())), isTrue);
    // a lined-paper line (y = 72 + 24k pt) away from the stroke, off white
    var lineRows = 0;
    for (var y = 0; y < px.height; y++) {
      final p = px.at(20, y);
      if (p[0] < 245 || p[2] < 245) lineRows++;
    }
    expect(lineRows, greaterThan(20));
    // paper elsewhere
    expect(px.at(20, 2), [255, 255, 255, 255]);
  });

  test(
    'a still renderer\'s background is composited under the strokes',
    () async {
      final pdf = InkPageThumbnailRenderer(
        backgroundBuilders: const [
          SolidBackgroundBuilder(colorArgb: 0xFF336699),
          TemplateBackgroundLayerBuilder(),
        ],
      );
      final t = (await pdf.render(
        _content(
          background: _pdf,
          strokes: [
            _black(const ui.Offset(100, 400), const ui.Offset(500, 400)),
          ],
        ),
        maxSidePx: 320,
      ))!;
      final px = await _decode(t.bytes);
      expect(px.at(5, 5), [0x33, 0x66, 0x99, 255]);
      final s = t.height / core.PageSize.a4Portrait.height;
      expect(_isDark(px.at((300 * s).round(), (400 * s).round())), isTrue);
    },
  );

  test('null rules: the still renderer returns null; pdf / image without a '
      'still renderer', () async {
    final missing = InkPageThumbnailRenderer(
      backgroundBuilders: const [
        SolidBackgroundBuilder(stillReturnsNull: true),
        TemplateBackgroundLayerBuilder(),
      ],
    );
    expect(await missing.render(_content(background: _pdf)), isNull);
    expect(await renderer.render(_content(background: _pdf)), isNull);
    expect(
      await renderer.render(
        _content(background: const core.ImageBackground(assetId: 'img')),
      ),
      isNull,
    );
  });

  test('blank page → its paper color', () async {
    for (final paper in [core.PaperColors.white, core.PaperColors.black]) {
      final t = (await renderer.render(
        _content(background: core.BlankBackground(paperColorArgb: paper)),
        maxSidePx: 64,
      ))!;
      final px = await _decode(t.bytes);
      final c = ui.Color(paper);
      expect(px.at(10, 10), [
        (c.r * 255).round(),
        (c.g * 255).round(),
        (c.b * 255).round(),
        255,
      ]);
    }
  });

  test('3,000 strokes: yields to the event loop every 4 ms', () async {
    var n = 0;
    final strokes = InkDevTools.syntheticStrokes(
      pageId: 'pg1',
      pageSize: core.PageSize.a4Portrait,
      count: 3000,
      newId: () => 't${n++}',
      createdAt: 1000,
    );
    var ticks = 0;
    var done = false;
    // another task gets the event loop while the renderer works
    Future<void> other() async {
      while (!done) {
        ticks++;
        await Future<void>.delayed(Duration.zero);
      }
    }

    final otherDone = other();
    final t = await renderer.render(_content(strokes: strokes));
    done = true;
    await otherDone;
    expect(t, isNotNull);
    expect(thumbnailRendererYieldsOf(renderer), greaterThan(0));
    expect(ticks, greaterThan(1), reason: 'the loop ran meanwhile');
  });

  test('a pencil stroke waits for the grain (textured pixels)', () async {
    final grain = PencilGrain();
    addTearDown(grain.dispose);
    // (v2.11, C211-01) the grain step also makes the texture tiles: about
    // 0.12 s on the VM and 0.19 s in Chrome (wasm), but 1.3 s under the debug
    // web compiler — past the renderer's 1 s wait. There the test waits for
    // the grain first (the textured pixels are still checked).
    if (kIsWeb && kDebugMode) await grain.ready;
    final withGrain = InkPageThumbnailRenderer(
      backgroundBuilders: const [TemplateBackgroundLayerBuilder()],
      pencilGrain: grain,
    );
    final pencil = strokeThrough(
      segment(const ui.Offset(50, 300), const ui.Offset(550, 300)),
      core.StrokeStyle.defaultsFor(core.PenTool.pencil).copyWith(width: 30),
      id: 'pc',
    );
    final t = (await withGrain.render(
      _content(strokes: [pencil]),
      maxSidePx: 512,
    ))!;
    expect(grain.value, isNotNull);
    final px = await _decode(t.bytes);
    final s = t.height / core.PageSize.a4Portrait.height;
    final y = (300 * s).round();
    final values = {
      for (var x = (100 * s).round(); x < (500 * s).round(); x++)
        px.at(x, y)[0],
    };
    expect(values.length, greaterThan(3), reason: 'grain varies the ink');
  });
}
