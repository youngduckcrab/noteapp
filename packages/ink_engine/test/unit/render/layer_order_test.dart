// m5-7/03-ink 9.3 K-8 (6.1 L-1, 6.20, 6.21): the drawing order is L-1 and the
// screen = the thumbnail = the vector export.
// ONE fixed page with every L-1 layer and z-mixed overlaps is drawn three ways:
// - the screen: a real InkPageView captured through a RepaintBoundary;
// - the thumbnail: the PNG of InkPageThumbnailRenderer.render, decoded;
// - the vector export: InkVectorExport.exportPage painted in its list order
//   (underlay → highlighter groups → inkShapes → annotations → cover — what PDF
//   does), the images decoded from the same bytes.
// At every overlapping spot the top element (named in the table, read from the
// vector lists by containment) has the same color in all three: an image
// object (the newest element) under everything; a highlighter (multiply) over
// it and under an older shape; strokes and shapes z-mixed (a newer stroke over
// an older shape and the other way round); a text box over a newer shape and
// over the image; a tape (the oldest element) over the text box.
// The decoder of the image cache is replaced by one that makes the asset's
// solid color at the target size at once (like image_background_test), so the
// widget test needs no real decode; the vector side decodes the real PNG.
@TestOn('vm')
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/image/image_cache.dart';
import 'package:ink_engine/src/render/tape_painter.dart' show tapeColor;
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

import '../../support/memory_asset_store.dart';
import '../../support/page_view.dart';
import '../../support/pixels.dart';

const _pageId = 'p1';
const _red = 0xFFDD0000;
const _blue = 0xFF0000FF;
const _green = 0xFF00AA00;
const _magenta = 0xFFCC00CC;
const _cyan = 0xFF00CCCC;
const _tape = 0xFF7755CC;
const _light = 0xFF0099FF;
const _paper = 0xFFFFFFFF;

/// A4 portrait 842 px high: 1 px per pt (± 0.02 %).
const _sidePx = 842;

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

/// The fixed page: createdAt is the z order inside a layer only.
final _strokes = [
  // highlighters: over the image (the oldest stroke) and the newest stroke of
  // the page, still under the older magenta shape
  _line(
    'hl',
    const ui.Offset(60, 230),
    const ui.Offset(240, 230),
    1,
    tool: core.PenTool.highlighter,
    color: _light,
    width: 12,
  ),
  _line(
    'hl2',
    const ui.Offset(100, 135),
    const ui.Offset(290, 135), // past the image's right edge (250)
    60,
    tool: core.PenTool.highlighter,
    color: _light,
    width: 8,
  ),
  // a newer stroke over the older green shape
  _line('over', const ui.Offset(110, 75), const ui.Offset(190, 75), 20),
  // an older stroke under the newer magenta shape
  _line(
    'under',
    const ui.Offset(110, 125),
    const ui.Offset(190, 125),
    5,
    color: 0xFF000000,
  ),
  // a tape — the oldest element of the page, over the text box
  _line(
    'tp',
    const ui.Offset(60, 170),
    const ui.Offset(240, 170),
    0,
    tool: core.PenTool.tape,
    color: _tape,
    width: 10,
  ),
];

final _objects = <core.PageObject>[
  // the newest element, still at the bottom (underlay)
  PageObjectFixtures.image(
    pageId: _pageId,
    assetId: 'red',
    rect: const core.PageRect(50, 50, 250, 250),
    pixelWidth: 64,
    pixelHeight: 64,
    createdAt: 100,
    id: 'img',
  ),
  _box('older', const core.PageRect(120, 60, 180, 90), 10, _green),
  _box('newer', const core.PageRect(120, 110, 180, 140), 30, _magenta),
  // a shape newer than the text box, still under it
  _box('below', const core.PageRect(100, 145, 200, 195), 50, _green),
  core.TextBoxObject(
    id: 'tx',
    pageId: _pageId,
    frame: const core.ElementFrame(core.PageRect(60, 150, 240, 190)),
    text: '',
    style: const core.TextBoxStyle(
      backgroundArgb: _cyan,
      fontSizePt: 16,
      colorArgb: 0xFF000000,
    ),
    createdAt: 0,
  ),
];

core.PageContent _core() => core.PageContent(
  page: SyntheticInk.page(pageId: _pageId),
  strokes: _strokes,
  objects: _objects,
  revision: 1,
);

InkPageContent _ink() => InkPageContent.fromCore(
  page: SyntheticInk.page(pageId: _pageId),
  strokes: _strokes,
  objects: _objects,
  revision: 1,
);

/// A spot (page pt), the id of the element on top there, and its color when the
/// top is one opaque element (null: a blend — compared across the three only).
typedef _Spot = ({String what, ui.Offset at, String top, int? argb});

const List<_Spot> _spots = [
  (what: 'image alone', at: ui.Offset(70, 70), top: 'img', argb: _red),
  (
    what: 'an older shape over the newest image',
    at: ui.Offset(130, 65),
    top: 'older',
    argb: _green,
  ),
  (
    what: 'a highlighter over the image (multiply)',
    at: ui.Offset(100, 230),
    top: 'hl',
    argb: null,
  ),
  (
    what: 'the newest highlighter over the paper',
    at: ui.Offset(270, 135),
    top: 'hl2',
    argb: null,
  ),
  (
    what: 'an older shape over the newest highlighter',
    at: ui.Offset(150, 135),
    top: 'newer',
    argb: _magenta,
  ),
  (
    what: 'a newer stroke over an older shape',
    at: ui.Offset(150, 75),
    top: 'over',
    argb: _blue,
  ),
  (
    what: 'a newer shape over an older stroke',
    at: ui.Offset(150, 125),
    top: 'newer',
    argb: _magenta,
  ),
  (
    what: 'a text box over a newer shape',
    at: ui.Offset(150, 158),
    top: 'tx',
    argb: _cyan,
  ),
  (
    what: 'a text box over the newest image',
    at: ui.Offset(70, 156),
    top: 'tx',
    argb: _cyan,
  ),
  (
    what: 'the oldest tape over the text box',
    at: ui.Offset(80, 170),
    top: 'tp',
    argb: null, // tapeColor(_tape) — set below
  ),
  (
    what: 'the tape over a newer shape',
    at: ui.Offset(150, 170),
    top: 'tp',
    argb: null,
  ),
  (what: 'the paper', at: ui.Offset(400, 400), top: '', argb: _paper),
];

int? _expectedArgb(_Spot s) =>
    s.top == 'tp' ? tapeColor(_tape).toARGB32() : s.argb;

/// The decode stand-in: the asset's solid color at the target size.
Future<ui.Image> _decoder(
  Uint8List bytes, {
  int? targetWidth,
  int? targetHeight,
}) async {
  final w = targetWidth!, h = targetHeight ?? targetWidth;
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    ui.Paint()..color = const ui.Color(_red),
  );
  final picture = recorder.endRecording();
  try {
    return picture.toImageSync(w, h);
  } finally {
    picture.dispose();
  }
}

Future<Pixels> _decodePng(Uint8List png) async {
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

/// [paint] inside [frame]'s own coordinate system (0..w × 0..h).
void _inFrame(
  ui.Canvas canvas,
  core.ElementFrame frame,
  void Function(double w, double h) paint,
) {
  final r = frame.rect;
  final c = frame.center;
  canvas
    ..save()
    ..translate(c.x, c.y)
    ..rotate(frame.rotation)
    ..translate(-r.width / 2, -r.height / 2);
  paint(r.width, r.height);
  canvas.restore();
}

/// The vector lists painted in order like PDF (6.21): paper, underlay images
/// stretched over their frames, highlighter groups (one layer each with the
/// group's opacity and blend, lines opaque), inkShapes, annotation backgrounds
/// (no lines here — empty text), cover.
void _paintVectors(
  ui.Canvas canvas,
  InkPageVectors v,
  Map<String, ui.Image> images,
) {
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 4096, 4096),
    ui.Paint()..color = const ui.Color(_paper),
  );
  for (final im in v.underlay) {
    final image = images[im.assetId]!;
    _inFrame(
      canvas,
      im.frame,
      (w, h) => canvas.drawImageRect(
        image,
        ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        ui.Rect.fromLTWH(0, 0, w, h),
        ui.Paint()..filterQuality = ui.FilterQuality.medium,
      ),
    );
  }
  for (final g in v.highlighterGroups) {
    canvas.saveLayer(
      null,
      ui.Paint()
        ..color = ui.Color.fromRGBO(0, 0, 0, g.opacity)
        ..blendMode = g.blend == InkBlendMode.multiply
            ? ui.BlendMode.multiply
            : ui.BlendMode.srcOver,
    );
    for (final l in g.lines) {
      canvas.drawPath(
        l.centerline.toUiPath(),
        ui.Paint()
          ..isAntiAlias = true
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = l.width
          ..strokeCap = l.cap == InkCap.square
              ? ui.StrokeCap.square
              : ui.StrokeCap.round
          ..strokeJoin = ui.StrokeJoin.round
          ..color = ui.Color(0xFF000000 | (g.colorArgb & 0xFFFFFF)),
      );
    }
    canvas.restore();
  }
  void fill(InkFillShape s) => canvas.drawPath(
    s.path.toUiPath(),
    ui.Paint()
      ..isAntiAlias = true
      ..color = ui.Color(s.colorArgb).withValues(alpha: s.opacity),
  );
  v.inkShapes.forEach(fill);
  for (final a in v.annotations) {
    if (a is! InkTextVector) continue;
    final bg = a.object.style.backgroundArgb;
    expect(a.lines, isEmpty, reason: 'empty text: no lines');
    if (bg == null) continue;
    _inFrame(
      canvas,
      a.frame,
      (w, h) => canvas.drawRect(
        ui.Rect.fromLTWH(0, 0, w, h),
        ui.Paint()..color = ui.Color(bg),
      ),
    );
  }
  v.cover.forEach(fill);
}

/// The id of the element on top at [p] (page pt) read from the vector lists:
/// the last element in paint order whose geometry contains [p]; '' = paper.
String _topIdAt(InkPageVectors v, ui.Offset p) {
  bool inFrame(core.ElementFrame f) {
    final c = f.center;
    final cos = math.cos(-f.rotation), sin = math.sin(-f.rotation);
    final dx = p.dx - c.x, dy = p.dy - c.y;
    final lx = c.x + cos * dx - sin * dy, ly = c.y + sin * dx + cos * dy;
    final r = f.rect;
    return lx >= r.left && lx <= r.right && ly >= r.top && ly <= r.bottom;
  }

  var top = '';
  for (final im in v.underlay) {
    if (inFrame(im.frame)) top = 'img:${im.assetId}';
  }
  for (final g in v.highlighterGroups) {
    for (final l in g.lines) {
      final b = l.centerline.toUiPath().getBounds().inflate(l.width / 2);
      if (b.contains(p)) top = l.strokeId;
    }
  }
  for (final s in v.inkShapes) {
    if (s.path.toUiPath().contains(p)) top = s.objectId ?? s.strokeId;
  }
  for (final a in v.annotations) {
    if (inFrame(a.frame)) {
      top = switch (a) {
        InkTextVector(:final object) => object.id,
        InkMathVector(:final object) => object.id,
      };
    }
  }
  for (final s in v.cover) {
    if (s.path.toUiPath().contains(p)) top = s.strokeId;
  }
  return top;
}

String _hex(List<int> px) => px.map((c) => c.toRadixString(16)).join(',');

List<int> _rgba(int argb) => [
  (argb >> 16) & 0xFF,
  (argb >> 8) & 0xFF,
  argb & 0xFF,
  0xFF,
];

void main() {
  // the text box draws with NoteSans from the start (no implicit load)
  setUpAll(InkFonts.ensureLoaded);

  late Uint8List redPng;
  late MemoryAssetStore store;
  late InkImageCache cache;
  late List<PageBackgroundLayerBuilder> builders;

  setUpAll(() async {
    redPng = await testPngBytes(width: 64, height: 64, argb: _red);
  });

  setUp(() {
    store = MemoryAssetStore()..bytes['red'] = redPng;
    cache = InkImageCache(assets: store, budgetBytes: 64 << 20);
    debugSetImageDecoder(cache, _decoder);
    builders = [
      ImageBackgroundLayerBuilder(assets: store, images: cache),
      const TemplateBackgroundLayerBuilder(),
    ];
  });

  tearDown(() async {
    cache.dispose();
    await store.close();
  });

  testWidgets('K-8: the top element at every overlapping spot has the same '
      'color on the screen, in the thumbnail and in the vector export', (
    tester,
  ) async {
    // the vector lists: the top element per spot is the table's (L-1 order)
    final vectors = InkVectorExport.exportPage(_ink());
    expect(vectors.underlay.map((i) => i.assetId), ['red']);
    expect(vectors.cover.map((s) => s.strokeId), ['tp']);
    for (final s in _spots) {
      final top = _topIdAt(vectors, s.at);
      expect(
        top,
        s.top == 'img' ? 'img:red' : s.top,
        reason: '${s.what}: the vector lists',
      );
    }

    // 1. the screen: a real InkPageView, the image decoded through the cache
    final c = createTestPageController(backgroundBuilders: builders);
    addTearDown(c.dispose);
    c.updateContent(_ink());
    await pumpPageView(tester, c, width: 595, surface: const Size(620, 860));
    for (var i = 0; i < 20 && cache.stats.queued > 0; i++) {
      await tester.pump();
    }
    await tester.pump();
    final screen = await capturePixels(tester);

    // 2. the thumbnail PNG (the same cache: the stand-in decoder too)
    final renderer = InkPageThumbnailRenderer(backgroundBuilders: builders);
    final thumbnail = (await tester.runAsync(() async {
      final t = await renderer.render(_core(), maxSidePx: _sidePx);
      return t == null ? null : _decodePng(t.bytes);
    }))!;
    expect((thumbnail.width, thumbnail.height), (595, 842));

    // 3. the vector export painted in list order (the real PNG decode)
    final exported = (await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(redPng);
      final image = (await codec.getNextFrame()).image;
      codec.dispose();
      try {
        return await renderPixels(
          595,
          842,
          (canvas) => _paintVectors(canvas, vectors, {'red': image}),
        );
      } finally {
        image.dispose();
      }
    }))!;

    for (final s in _spots) {
      final x = s.at.dx.round(), y = s.at.dy.round();
      final a = screen.at(x, y), b = thumbnail.at(x, y), v = exported.at(x, y);
      final why =
          '${s.what} at (${s.at.dx}, ${s.at.dy}): screen ${_hex(a)} · '
          'thumbnail ${_hex(b)} · vector ${_hex(v)}';
      expect(
        samePixel(a, b, tol: 4),
        isTrue,
        reason: 'screen = thumbnail: $why',
      );
      expect(samePixel(a, v, tol: 4), isTrue, reason: 'screen = vector: $why');
      final argb = _expectedArgb(s);
      if (argb != null) {
        expect(samePixel(a, _rgba(argb), tol: 3), isTrue, reason: why);
      }
    }
    // the blends are blends: the highlighter darkened what it lies on
    final overImage = screen.at(100, 230), overPaper = screen.at(270, 135);
    expect(overImage[0], lessThan(0xDD - 40), reason: _hex(overImage));
    expect(overPaper[0], lessThan(0xFF - 40), reason: _hex(overPaper));
    expect(
      overPaper[2],
      greaterThan(0xF0),
      reason: 'multiply keeps the blue: ${_hex(overPaper)}',
    );
  });
}
