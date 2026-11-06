// m5-7/03-ink 8.2 T41 (6.20, K-8): thumbnails with page objects.
// Renderer (InkPageThumbnailRenderer.render):
// - L-1 order (K-8) at overlapping spots: image object < highlighter < strokes
//   and shapes z-mixed (a newer stroke over an older shape and the other way
//   round) < text box (above a newer shape) < tape (always covered, above the
//   text box); the image background still below everything;
// - images, NoteSans and formulas prepared before drawing: PNG with the image
//   color, glyph ink, formula ink;
// - null when an image has no bytes (a PNG once they arrive), when the
//   preparation takes longer than InkTuning.thumbnailObjectWaitMs (fake
//   time), when a formula raster is null (the raster host's settle cap) or the
//   fonts do not load; a formula that does not parse and an image without an
//   image builder in the list are placeholders (a PNG).
// Widget (InkPageThumbnail): the placeholder first, then ONE raster again when
// this page's asset decode arrives (another asset's change: none), when
// NoteSans is loaded and when a formula raster arrives.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/image/image_cache.dart';
import 'package:ink_engine/src/math/math_renderer.dart';
import 'package:ink_engine/src/math/offscreen_host.dart';
import 'package:ink_engine/src/render/tape_painter.dart';
import 'package:ink_engine/src/render/thumbnail.dart'
    show inkThumbnailRasterCount;
import 'package:ink_engine/src/text/fonts.dart';
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

import '../support/delayed_svg_loader.dart';
import '../support/memory_asset_store.dart';
import '../support/pixels.dart';
import '../support/thumbnails.dart';

const _pageId = 'p1';
const _red = 0xFFDD0000;
const _blue = 0xFF0000FF;
const _green = 0xFF00AA00;
const _magenta = 0xFFCC00CC;
const _cyan = 0xFF00CCCC;
const _tape = 0xFF7755CC;
const _bg = 0xFF33AA55;

Future<Uint8List> _files({required bool bold}) async =>
    File('assets/fonts/NoteSans-${bold ? 'Bold' : 'Regular'}.ttf')
        .readAsBytesSync();

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

bool _is(List<int> px, int argb, {int tol = 3}) => samePixel(px, [
  (argb ~/ 0x10000) % 256,
  (argb ~/ 0x100) % 256,
  argb % 256,
  255,
], tol: tol);

String _hex(List<int> px) => px.map((c) => c.toRadixString(16)).join(',');

core.Stroke _line(
  String id,
  ui.Offset a,
  ui.Offset b,
  int createdAt, {
  core.PenTool tool = core.PenTool.ballpoint,
  int color = _blue,
  double width = 6,
}) => strokeThrough(
  segment(a, b),
  core.StrokeStyle.defaultsFor(tool).copyWith(colorArgb: color, width: width),
  id: id,
).copyWith(createdAt: createdAt);

core.ShapeObject _box(String id, core.PageRect r, int createdAt, int fill) =>
    core.ShapeObject(
      id: id,
      pageId: _pageId,
      shapeKind: core.ShapeKind.rectangle,
      geometry: core.ShapeGeometry.rectangle(r),
      style: core.ShapeStyle(
        strokeColorArgb: fill,
        strokeWidth: 1,
        fillColorArgb: fill,
      ),
      createdAt: createdAt,
    );

core.TextBoxObject _text(
  String id,
  core.PageRect r,
  int createdAt, {
  String text = '',
  int? background,
  double fontSize = 16,
}) => core.TextBoxObject(
  id: id,
  pageId: _pageId,
  frame: core.ElementFrame(r),
  text: text,
  style: core.TextBoxStyle(
    backgroundArgb: background,
    fontSizePt: fontSize,
    colorArgb: 0xFF000000,
  ),
  createdAt: createdAt,
);

core.PageContent _content({
  List<core.Stroke> strokes = const [],
  List<core.PageObject> objects = const [],
  core.PageBackground background = const core.BlankBackground(),
}) => core.PageContent(
  page: SyntheticInk.page(pageId: _pageId, background: background),
  strokes: strokes,
  objects: objects,
  revision: 1,
);

final Stopwatch _wall = Stopwatch()..start();
int _wallUs() => _wall.elapsedMicroseconds;

/// A4 portrait at 842 px high: 1 px per pt.
const _onePxPerPt = 842;

/// Ink (non-paper) pixels in [r] (page pt at 1 px per pt).
int _inkIn(Pixels p, ui.Rect r) {
  var n = 0;
  for (var y = r.top.round(); y < r.bottom.round(); y++) {
    for (var x = r.left.round(); x < r.right.round(); x++) {
      final c = p.at(x, y);
      if (c[0] < 160 && c[1] < 160 && c[2] < 160) n++;
    }
  }
  return n;
}

/// The thumbnail store's own slow read (the decode after the deadline).
final class _SlowStore implements core.AssetStore {
  _SlowStore(this.bytes);
  final Uint8List bytes;

  @override
  Future<Uint8List?> readBytes(core.AssetId id) async {
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    return bytes;
  }

  @override
  Future<bool> hasBytes(core.AssetId id) async => true;

  @override
  Stream<core.AssetId> get bytesArrived => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryAssetStore store;
  late InkImageCache cache;
  late List<PageBackgroundLayerBuilder> builders;
  late InkPageThumbnailRenderer renderer;
  late Uint8List redPng, bluePng, bgPng;

  setUpAll(() async {
    redPng = await testPngBytes(width: 64, height: 64, argb: _red);
    bluePng = await testPngBytes(width: 64, height: 64, argb: _blue);
    bgPng = await testPngBytes(width: 60, height: 84, argb: _bg);
  });

  setUp(() {
    store = MemoryAssetStore()
      ..bytes['red'] = redPng
      ..bytes['blue'] = bluePng
      ..bytes['bg'] = bgPng;
    cache = InkImageCache(assets: store, budgetBytes: 64 << 20);
    builders = [
      ImageBackgroundLayerBuilder(assets: store, images: cache),
      const TemplateBackgroundLayerBuilder(),
    ];
    renderer = InkPageThumbnailRenderer(backgroundBuilders: builders);
  });

  tearDown(() async {
    cache.dispose();
    await store.close();
    debugSetInkFontSource(null);
    OffscreenMathHost.debugExtraSvgLoader = null;
    OffscreenMathHost.debugNowUs = _wallUs;
  });

  group('renderer', () {
    test('L-1 order (K-8) at overlapping spots; the image background still '
        'below everything', () async {
      final image = PageObjectFixtures.image(
        pageId: _pageId,
        assetId: 'red',
        rect: const core.PageRect(50, 50, 250, 250),
        pixelWidth: 64,
        pixelHeight: 64,
        createdAt: 100, // the newest element, still at the bottom
        id: 'img',
      );
      final content = _content(
        background: const core.ImageBackground(
          assetId: 'bg',
          fit: core.ImageFit.fill,
        ),
        strokes: [
          _line(
            'hl',
            const ui.Offset(60, 230),
            const ui.Offset(240, 230),
            1,
            tool: core.PenTool.highlighter,
            color: 0xFF0099FF,
            width: 12,
          ),
          // a newer stroke over an older shape
          _line('over', const ui.Offset(110, 75), const ui.Offset(190, 75), 20),
          // an older stroke under a newer shape
          _line(
            'under',
            const ui.Offset(110, 125),
            const ui.Offset(190, 125),
            5,
            color: 0xFF000000,
          ),
          // a tape — the oldest element, on top of the text box
          _line(
            'tp',
            const ui.Offset(60, 170),
            const ui.Offset(240, 170),
            0,
            tool: core.PenTool.tape,
            color: _tape,
            width: 10,
          ),
        ],
        objects: [
          image,
          _box('older', const core.PageRect(120, 60, 180, 90), 10, _green),
          _box('newer', const core.PageRect(120, 110, 180, 140), 30, _magenta),
          // a shape newer than the text box, still below it
          _box('below', const core.PageRect(100, 145, 200, 195), 50, _green),
          _text(
            'tx',
            const core.PageRect(60, 150, 240, 190),
            0,
            background: _cyan,
          ),
        ],
      );
      final t = (await renderer.render(content, maxSidePx: _onePxPerPt))!;
      expect((t.width, t.height), (595, 842));
      final p = await _decode(t.bytes);
      expect(_is(p.at(70, 70), _red), isTrue, reason: _hex(p.at(70, 70)));
      expect(_is(p.at(150, 75), _blue), isTrue, reason: 'stroke over shape');
      expect(
        _is(p.at(150, 125), _magenta),
        isTrue,
        reason: 'shape over stroke',
      );
      expect(_is(p.at(150, 160), _cyan), isTrue, reason: 'text over shape');
      expect(
        _is(p.at(80, 170), tapeColor(_tape).toARGB32()),
        isTrue,
        reason: 'tape over the text box: ${_hex(p.at(80, 170))}',
      );
      // the highlighter over the image (multiply: the red channel drops)
      final hl = p.at(100, 230);
      expect(hl[0], lessThan(0xDD - 40), reason: _hex(hl));
      // the background image away from the objects
      expect(_is(p.at(100, 700), _bg), isTrue, reason: _hex(p.at(100, 700)));
    });

    test('images, NoteSans and formulas are prepared before drawing', () async {
      debugSetInkFontSource(_files);
      expect(InkFontsDebug.isLoaded, isFalse);
      final content = _content(
        objects: [
          PageObjectFixtures.image(
            pageId: _pageId,
            assetId: 'blue',
            rect: const core.PageRect(300, 50, 500, 250),
            pixelWidth: 64,
            pixelHeight: 64,
            id: 'img',
          ),
          _text(
            'tx',
            const core.PageRect(50, 300, 450, 360),
            1,
            text: '가나다 Hello',
            fontSize: 28,
          ),
          PageObjectFixtures.math(
            pageId: _pageId,
            latex: r'\sqrt{x} + \frac{a}{b}',
            rect: const core.PageRect(50, 450, 300, 550),
            createdAt: 2,
            id: 'mx',
          ),
        ],
      );
      final t = (await renderer.render(content, maxSidePx: _onePxPerPt))!;
      expect(InkFontsDebug.isLoaded, isTrue, reason: 'the thumbnail loaded it');
      final p = await _decode(t.bytes);
      expect(_is(p.at(350, 100), _blue), isTrue, reason: _hex(p.at(350, 100)));
      expect(
        _inkIn(p, const ui.Rect.fromLTRB(50, 300, 450, 360)),
        greaterThan(100),
        reason: 'glyphs',
      );
      expect(
        _inkIn(p, const ui.Rect.fromLTRB(50, 450, 300, 550)),
        greaterThan(50),
        reason: 'the formula raster',
      );
      // nothing pinned after the render
      expect(cache.stats.pinnedBytes, 0);
    });

    test('an image without bytes → null; once they arrive → a PNG', () async {
      final content = _content(
        objects: [
          PageObjectFixtures.image(
            pageId: _pageId,
            assetId: 'late',
            pixelWidth: 64,
            pixelHeight: 64,
          ),
        ],
      );
      expect(await renderer.render(content), isNull);
      store.arrive('late', redPng);
      await Future<void>.delayed(Duration.zero);
      expect(await renderer.render(content), isNotNull);
    });

    test('the preparation longer than thumbnailObjectWaitMs → null (fake '
        'time; nothing drawn)', () {
      final slow = _SlowStore(redPng);
      final slowCache = InkImageCache(assets: slow, budgetBytes: 16 << 20);
      final slowRenderer = InkPageThumbnailRenderer(
        backgroundBuilders: [
          ImageBackgroundLayerBuilder(assets: slow, images: slowCache),
          const TemplateBackgroundLayerBuilder(),
        ],
      );
      fakeAsync((async) {
        var done = false;
        core.PageThumbnail? result;
        unawaited(
          slowRenderer
              .render(
                _content(
                  objects: [
                    PageObjectFixtures.image(
                      pageId: _pageId,
                      assetId: 'slow',
                      pixelWidth: 64,
                      pixelHeight: 64,
                    ),
                  ],
                ),
              )
              .then((t) {
                done = true;
                result = t;
              }),
        );
        async.elapse(
          const Duration(milliseconds: InkTuning.thumbnailObjectWaitMs - 1),
        );
        expect(done, isFalse, reason: 'still waiting');
        async.elapse(const Duration(milliseconds: 2));
        expect(done, isTrue);
        expect(result, isNull);
        slowCache.dispose();
      });
    });

    test('a formula raster null (the glyph pictures did not settle) → null; a '
        'formula that does not parse → its placeholder (a PNG)', () async {
      var looks = 0;
      // every look at the settle clock is 2 s later: the cap is passed at once
      OffscreenMathHost.debugNowUs = () => (looks++) * 2000000;
      OffscreenMathHost.debugExtraSvgLoader = DelayedSvgLoader(
        const Duration(milliseconds: 50),
      );
      final formula = PageObjectFixtures.math(pageId: _pageId, id: 'mx');
      expect(await renderer.render(_content(objects: [formula])), isNull);
      OffscreenMathHost.debugExtraSvgLoader = null;
      OffscreenMathHost.debugNowUs = _wallUs;
      final bad = PageObjectFixtures.math(
        pageId: _pageId,
        latex: r'\frac{a',
        rect: const core.PageRect(100, 600, 300, 700),
        id: 'bad',
      );
      final t = await renderer.render(
        _content(objects: [bad]),
        maxSidePx: _onePxPerPt,
      );
      expect(t, isNotNull);
      final p = await _decode(t!.bytes);
      expect(
        _inkIn(p, const ui.Rect.fromLTRB(100, 600, 300, 700)) +
            [
              for (var x = 100; x < 300; x += 7)
                if (!_is(p.at(x, 650), 0xFFFFFFFF)) x,
            ].length,
        greaterThan(0),
        reason: 'the hatched placeholder',
      );
    });

    test('fonts that do not load → null; no image builder in the list → the '
        'placeholder (a PNG, no image color)', () async {
      debugSetInkFontSource(
        ({required bool bold}) async => throw StateError('no font'),
      );
      expect(
        await renderer.render(
          _content(
            objects: [
              _text('tx', const core.PageRect(50, 50, 250, 100), 1, text: 'a'),
            ],
          ),
        ),
        isNull,
      );
      debugSetInkFontSource(null);
      final plain = InkPageThumbnailRenderer(
        backgroundBuilders: const [TemplateBackgroundLayerBuilder()],
      );
      final t = await plain.render(
        _content(
          objects: [
            PageObjectFixtures.image(
              pageId: _pageId,
              assetId: 'red',
              rect: const core.PageRect(50, 50, 250, 250),
              pixelWidth: 64,
              pixelHeight: 64,
            ),
          ],
        ),
        maxSidePx: _onePxPerPt,
      );
      final p = await _decode(t!.bytes);
      final c = p.at(100, 120);
      expect(_is(c, _red), isFalse, reason: _hex(c));
      expect(_is(c, 0xFFFFFFFF), isFalse, reason: 'the placeholder box');
    });
  });

  test('the formula raster host after a fonts change (NoteSans arriving): '
      'the next rasters are the new formulas and still wait for their SVG '
      'pictures', () async {
    final before = await rasterizeFormula(
      r'\sqrt{x} + \frac{a}{b}',
      colorArgb: 0xFF000000,
      fontSizePt: 20,
      pixelsPerPt: 1,
    );
    expect(before, isNotNull);
    debugSetInkFontSource(_files); // a new load: a system fonts change
    await InkFonts.ensureLoaded();
    final small = await rasterizeFormula(
      'x',
      colorArgb: 0xFF000000,
      fontSizePt: 20,
      pixelsPerPt: 1,
    );
    final wide = await rasterizeFormula(
      r'\int_0^1 f(x)\,dx = F(1) - F(0)',
      colorArgb: 0xFF000000,
      fontSizePt: 20,
      pixelsPerPt: 1,
    );
    expect(small!.size.width, lessThan(before!.size.width / 2));
    expect(wide!.size.width, greaterThan(before.size.width * 2));
    for (final r in [before, small, wide]) {
      r.image.dispose();
    }
    var looks = 0;
    OffscreenMathHost.debugNowUs = () => (looks++) * 2000000;
    OffscreenMathHost.debugExtraSvgLoader = DelayedSvgLoader(
      const Duration(milliseconds: 50),
    );
    final waited = await rasterizeFormula(
      r'\frac{a}{b}',
      colorArgb: 0xFF000000,
      fontSizePt: 20,
      pixelsPerPt: 1,
    );
    expect(waited, isNull, reason: 'it waited for the picture (and gave up)');
    expect(looks, greaterThan(1));
  });

  group('InkPageThumbnail', () {
    Future<Pixels> shown(WidgetTester tester) async {
      await tester.pump(); // the RawImage of the latest raster
      final raw = tester.widget<RawImage>(find.byType(RawImage));
      final image = raw.image!;
      final data = await tester.runAsync(image.toByteData);
      return Pixels(image.width, image.height, data!);
    }

    Widget thumb(InkPageContent content) => Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: InkPageThumbnail(
          content: content,
          width: 595,
          backgroundBuilders: builders,
        ),
      ),
    );

    InkPageContent ink(List<core.PageObject> objects) =>
        SyntheticInk.pageContentWith(objects: objects);

    testWidgets('an image: the placeholder, then ONE raster again when this '
        'asset arrives (another asset: none)', (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      final gate = Completer<void>();
      debugSetImageDecoder(cache, (
        bytes, {
        int? targetWidth,
        int? targetHeight,
      }) async {
        if (identical(bytes, redPng)) await gate.future;
        final w = targetWidth ?? 64, h = targetHeight ?? w;
        final recorder = ui.PictureRecorder();
        ui.Canvas(recorder).drawRect(
          ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
          ui.Paint()..color = ui.Color(identical(bytes, redPng) ? _red : _blue),
        );
        final picture = recorder.endRecording();
        try {
          return picture.toImageSync(w, h);
        } finally {
          picture.dispose();
        }
      });
      final content = ink([
        PageObjectFixtures.image(
          pageId: _pageId,
          assetId: 'red',
          rect: const core.PageRect(50, 50, 250, 250),
          pixelWidth: 64,
          pixelHeight: 64,
        ),
      ]);
      final before = inkThumbnailRasterCount;
      await tester.pumpWidget(thumb(content));
      await settleThumbnails(tester);
      expect(inkThumbnailRasterCount - before, 1);
      var p = await shown(tester);
      expect(_is(p.at(100, 120), _red), isFalse, reason: 'the placeholder');
      expect(_is(p.at(100, 120), 0xFFFFFFFF), isFalse);
      // another asset's decode: no raster
      await tester.runAsync(() => cache.load('blue', longSidePx: 64));
      await tester.pump();
      await settleThumbnails(tester);
      expect(inkThumbnailRasterCount - before, 1);
      // this asset arrives: one raster again
      gate.complete();
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
      }
      await settleThumbnails(tester);
      expect(inkThumbnailRasterCount - before, 2);
      p = await shown(tester);
      expect(_is(p.at(100, 120), _red), isTrue, reason: _hex(p.at(100, 120)));
      await tester.pump(const Duration(seconds: 1));
      await settleThumbnails(tester);
      expect(inkThumbnailRasterCount - before, 2, reason: 'no more');
    });

    testWidgets('text: the system font first, ONE raster again once NoteSans '
        'is loaded', (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      final gate = Completer<void>();
      debugSetInkFontSource(({required bool bold}) async {
        await gate.future;
        return _files(bold: bold);
      });
      final content = ink([
        _text(
          'tx',
          const core.PageRect(50, 50, 450, 120),
          1,
          text: '가나다 Hello',
          fontSize: 28,
        ),
      ]);
      final before = inkThumbnailRasterCount;
      await tester.pumpWidget(thumb(content));
      await settleThumbnails(tester);
      expect(inkThumbnailRasterCount - before, 1);
      expect(InkFontsDebug.isLoading, isTrue, reason: 'the raster started it');
      gate.complete();
      await tester.runAsync(InkFonts.ensureLoaded);
      await tester.pump();
      await settleThumbnails(tester);
      expect(InkFontsDebug.isLoaded, isTrue);
      expect(inkThumbnailRasterCount - before, 2);
      final p = await shown(tester);
      expect(
        _inkIn(p, const ui.Rect.fromLTRB(50, 50, 450, 120)),
        greaterThan(100),
      );
    });

    testWidgets('a formula: the light box first, ONE raster again when its '
        'raster arrives', (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      final content = ink([
        PageObjectFixtures.math(
          pageId: _pageId,
          latex: r'\sqrt{x} + \frac{a}{b}',
          rect: const core.PageRect(50, 50, 300, 150),
        ),
      ]);
      final before = inkThumbnailRasterCount;
      await tester.pumpWidget(thumb(content));
      expect(inkThumbnailRasterCount - before, 1, reason: 'the light box');
      for (var i = 0; i < 40 && inkThumbnailRasterCount - before < 2; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      await settleThumbnails(tester);
      expect(inkThumbnailRasterCount - before, 2);
      final p = await shown(tester);
      expect(
        _inkIn(p, const ui.Rect.fromLTRB(50, 50, 300, 150)),
        greaterThan(50),
      );
    });
  });
}
