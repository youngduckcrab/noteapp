// m5-7/03-ink 8.2 T32b (6.1, 6.8.1–6.8.3): the layer caches of the page
// objects.
// - L-1 order through a real InkPageView: image (underlay) < highlighter <
//   strokes and shapes z mixed by compareOrder inside the ink chunks < layer
//   4′ (the last step of inkActive) < text box (annotation). The tape above
//   the text (cover > annotation) is T31's tape_test (PenProfile.of(tape) is
//   still the ballpoint until then).
// - Counters: every layer records each chunk once; the same content again
//   (same revision, or a new revision with the same instances) records
//   nothing; one object changed → only its chunk in its layer; an object on
//   top → an appended picture; the merged ink layer appends a shape on top
//   and makes a new stroke below a kept shape dirty; hiding an object
//   re-records its chunk only; previews do not re-record the base.
// - Draw keys (6.11.3): every chunk keeps the asset / hairline keys of what it
//   drew; a key change records only those chunks (an asset, another zoom
//   octave). The cover page picture.
// - (T33, 6.9) Shapes: an arrow at opacity 0.5 is painted once where its line
//   and head overlap (S-10 — the overlap pixel = the line's middle pixel),
//   dashes leave gaps, a fill is drawn under the outline, dotted dots.
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/render/base_cache.dart';
import 'package:ink_engine/src/render/ink_page_controller.dart'
    show
        debugSetInkActiveEndStage,
        inkAnnotationCacheOf,
        inkChunkCacheOf,
        inkCoverCacheOf,
        inkPageRenderOf,
        inkUnderlayCacheOf;
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

import '../support/page_view.dart';
import '../support/pixels.dart';

const _pageId = 'p1';
const _red = 0xFFDD0000;
const _blue = 0xFF0000FF;
const _green = 0xFF00AA00;
const _magenta = 0xFFFF00FF;

core.Stroke _line(
  String id,
  Offset a,
  Offset b,
  int createdAt, {
  core.PenTool tool = core.PenTool.ballpoint,
  int color = _blue,
  double width = 4,
}) => strokeThrough(
  segment(a, b),
  core.StrokeStyle.defaultsFor(tool).copyWith(colorArgb: color, width: width),
  id: id,
).copyWith(createdAt: createdAt);

core.ShapeObject _shapeLine(
  String id,
  core.PagePoint a,
  core.PagePoint b,
  int createdAt, {
  int color = _green,
  double width = 8,
}) => core.ShapeObject(
  id: id,
  pageId: _pageId,
  shapeKind: core.ShapeKind.line,
  geometry: core.PolylineGeometry([a, b], closed: false),
  style: core.ShapeStyle(strokeColorArgb: color, strokeWidth: width),
  createdAt: createdAt,
);

core.ShapeObject _rect(
  String id,
  core.PageRect r,
  int createdAt, {
  int color = _red,
  double width = 8,
}) => core.ShapeObject(
  id: id,
  pageId: _pageId,
  shapeKind: core.ShapeKind.rectangle,
  geometry: core.ShapeGeometry.rectangle(r),
  style: core.ShapeStyle(strokeColorArgb: color, strokeWidth: width),
  createdAt: createdAt,
);

core.TextBoxObject _box(
  String id,
  core.PageRect r,
  int createdAt, {
  String text = '',
  int? background = _green,
}) => core.TextBoxObject(
  id: id,
  pageId: _pageId,
  frame: core.ElementFrame(r),
  text: text,
  style: core.TextBoxStyle(backgroundArgb: background),
  createdAt: createdAt,
);

core.ImageObject _image(String id, String assetId, core.PageRect r) =>
    PageObjectFixtures.image(
      pageId: _pageId,
      assetId: assetId,
      id: id,
      rect: r,
      createdAt: 1,
    );

InkPageContent _content(
  List<core.Stroke> strokes,
  List<core.PageObject> objects, {
  int revision = 1,
  core.PageBackground background = const core.BlankBackground(),
}) => InkPageContent.fromCore(
  page: SyntheticInk.page(pageId: _pageId, background: background),
  strokes: strokes,
  objects: objects,
  revision: revision,
);

/// Paints every layer of [c] in L-1 order like InkPageView (pictures recorded lazily).
void _paintAll(InkPageController c, {double viewScale = 1}) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final render = inkPageRenderOf(c);
  for (final layer in InkRenderLayer.values) {
    render.paint(canvas, layer, viewScale);
  }
  recorder.endRecording().dispose();
}

bool _near(List<int> px, int argb, {int tol = 6}) => samePixel(px, [
  (argb ~/ 0x10000) % 256,
  (argb ~/ 0x100) % 256,
  argb % 256,
  255,
], tol: tol);

/// Paints every layer of [c] over white paper at 1 px per pt.
Future<Pixels> _pixelsOf(InkPageController c, {int w = 300, int h = 300}) =>
    renderPixels(w, h, (canvas) {
      paintPaper(canvas, 0xFFFFFFFF);
      final render = inkPageRenderOf(c);
      for (final layer in InkRenderLayer.values) {
        render.paint(canvas, layer, 1);
      }
    });

void main() {
  // text boxes draw with NoteSans from the start: no implicit load (and no
  // re-record when it arrives) in the middle of a counter test
  setUpAll(InkFonts.ensureLoaded);

  testWidgets('L-1: image < highlighter < strokes and shapes (z mixed) < 4′ < '
      'text', (tester) async {
    final c = createTestPageController();
    addTearDown(c.dispose);
    c.updateContent(
      _content(
        [
          _line(
            'hl',
            const Offset(50, 100),
            const Offset(190, 100),
            2,
            tool: core.PenTool.highlighter,
            color: 0xFFFFE600,
            width: 14,
          ),
          // over the red rectangle's left edge (x = 250), under the green line
          _line('s4', const Offset(220, 100), const Offset(300, 100), 4),
          // under the 4′ square and the text box
          _line('s6', const Offset(230, 220), const Offset(390, 220), 6),
          // newer than the green line it lies under on screen? no: older
          _line('s1', const Offset(320, 60), const Offset(320, 140), 1),
        ],
        [
          _image('im', 'a1', const core.PageRect(40, 40, 200, 200)),
          _rect('r3', const core.PageRect(250, 40, 400, 160), 3),
          _shapeLine(
            'g5',
            const core.PagePoint(280, 60),
            const core.PagePoint(280, 140),
            5,
          ),
          // over s1 (createdAt 1 < 5)
          _shapeLine(
            'g5b',
            const core.PagePoint(300, 110),
            const core.PagePoint(340, 110),
            5,
          ),
          _box('tx', const core.PageRect(300, 170, 400, 270), 7),
        ],
      ),
    );
    debugSetInkActiveEndStage(
      c,
      (canvas) => canvas.drawRect(
        const Rect.fromLTRB(230, 190, 330, 250),
        Paint()..color = const Color(_magenta),
      ),
    );
    await pumpPageView(tester, c, width: 595, surface: const Size(620, 860));
    await tester.pump();
    final px = await capturePixels(tester);

    // underlay: the image placeholder (a gray darker than the paper)
    final image = px.at(60, 60);
    expect(image[0], lessThan(250));
    expect((image[0] - image[2]).abs(), lessThanOrEqualTo(2));
    // the highlighter over the image (multiply: the blue channel drops)
    final hl = px.at(100, 100);
    expect(hl[2], lessThan(hl[0] - 40));
    // ink layer, z mixed inside the chunks: the stroke (4) over the rectangle (3)
    expect(_near(px.at(250, 100), _blue, tol: 40), isTrue, reason: 's4 > r3');
    // the green line (5) over the stroke (4)
    expect(_near(px.at(280, 100), _green, tol: 8), isTrue, reason: 'g5 > s4');
    // the green line (5) over the older stroke (1)
    expect(_near(px.at(320, 110), _green, tol: 8), isTrue, reason: 'g5b > s1');
    expect(_near(px.at(320, 80), _blue, tol: 40), isTrue, reason: 's1 drawn');
    // layer 4′ over every ink item
    expect(_near(px.at(260, 220), _magenta, tol: 2), isTrue, reason: '4′ > s6');
    // the text box over layer 4′
    expect(_near(px.at(315, 220), _green, tol: 2), isTrue, reason: 'tx > 4′');
    expect(_near(px.at(380, 220), _green, tol: 2), isTrue, reason: 'tx > s6');

    // nothing of the ink chunks is drawn after the chunks: the counters
    expect(inkChunkCacheOf(c).recordCount, inkChunkCacheOf(c).chunkCount);
    debugSetInkActiveEndStage(c, null);
    await tester.pump();
    final off = await capturePixels(tester);
    expect(_near(off.at(260, 220), _blue, tol: 40), isTrue, reason: '4′ gone');
  });

  group('layer caches (6.8.3)', () {
    // A4 at 256 pt chunks = 3 × 4: (col, row)
    final a = _line('a', const Offset(40, 40), const Offset(70, 45), 1);
    final im1 = _image('im1', 'a1', const core.PageRect(20, 20, 100, 100));
    final im2 = _image('im2', 'a2', const core.PageRect(300, 300, 400, 400));
    final sh1 = _rect('sh1', const core.PageRect(20, 300, 100, 400), 5);
    final sh2 = _rect('sh2', const core.PageRect(300, 560, 400, 700), 6);
    final tx1 = _box('tx1', const core.PageRect(20, 560, 200, 600), 7);
    final tx2 = _box(
      'tx2',
      const core.PageRect(300, 20, 500, 60),
      8,
      text: '안녕 hello',
      background: null,
    );
    final mx = PageObjectFixtures.math(
      pageId: _pageId,
      id: 'mx',
      rect: const core.PageRect(300, 780, 400, 820),
      createdAt: 9,
    );
    final un = PageObjectFixtures.unknown(
      pageId: _pageId,
      id: 'un',
      rect: const core.PageRect(520, 20, 580, 80),
    );
    final objects = <core.PageObject>[im1, im2, sh1, sh2, tx1, tx2, mx, un];

    late InkPageController c;
    late InkChunkCache ink, underlay, annotation;

    /// (ink, underlay, annotation) chunk records.
    (int, int, int) records() =>
        (ink.recordCount, underlay.recordCount, annotation.recordCount);

    setUp(() {
      c = createTestPageController()..updateContent(_content([a], objects));
      ink = inkChunkCacheOf(c);
      underlay = inkUnderlayCacheOf(c);
      annotation = inkAnnotationCacheOf(c);
      _paintAll(c);
    });
    tearDown(() => c.dispose());

    test('every chunk of every layer recorded once; then cached', () {
      expect((ink.columns, ink.rows), (3, 4));
      expect(records(), (12, 12, 12));
      expect(
        (ink.dirtyCount, underlay.dirtyCount, annotation.dirtyCount),
        (0, 0, 0),
      );
      _paintAll(c);
      expect(records(), (12, 12, 12), reason: 'cached');
      // the shapes are in the ink chunks (one item each), not drawn after them
      expect(ink.strokeCountOf(0), 1, reason: 'a');
      expect(ink.strokeCountOf(1 * 3 + 0), 1, reason: 'sh1');
      expect(underlay.strokeCountOf(0), 1, reason: 'im1');
      expect(annotation.strokeCountOf(2 * 3 + 0), 1, reason: 'tx1');
    });

    test('the same content again records nothing', () {
      c.updateContent(_content([a], objects));
      _paintAll(c);
      expect(records(), (12, 12, 12), reason: 'same revision: no-op');
      // a new revision with the same instances: no object changed
      c.updateContent(_content([a], objects, revision: 2));
      expect(
        (ink.dirtyCount, underlay.dirtyCount, annotation.dirtyCount),
        (0, 0, 0),
      );
      _paintAll(c);
      expect(records(), (12, 12, 12));
    });

    test('one object changed → only its chunk in its layer', () {
      // equal values, another instance (identity diff — K-4)
      final tx1b = _box('tx1', const core.PageRect(30, 560, 210, 600), 7);
      c.updateContent(
        _content([a], [for (final o in objects) o == tx1 ? tx1b : o]),
      );
      expect(annotation.isDirtyAt(0, 2), isTrue);
      expect(annotation.dirtyCount, 1);
      _paintAll(c);
      expect(records(), (12, 12, 13));

      final im2b = _image('im2', 'a2', const core.PageRect(310, 300, 400, 400));
      final sh2b = _rect('sh2', const core.PageRect(300, 570, 400, 700), 6);
      c.updateContent(
        _content(
          [a],
          [
            for (final o in objects)
              o == tx1
                  ? tx1b
                  : o == im2
                  ? im2b
                  : o == sh2
                  ? sh2b
                  : o,
          ],
          revision: 2,
        ),
      );
      expect(underlay.isDirtyAt(1, 1), isTrue);
      expect(ink.isDirtyAt(1, 2), isTrue);
      expect((ink.dirtyCount, underlay.dirtyCount), (1, 1));
      _paintAll(c);
      expect(records(), (13, 13, 13));
    });

    test('an object on top → appended picture, no re-record', () {
      final top = _box('top', const core.PageRect(30, 30, 90, 90), 20);
      final shTop = _rect('shTop', const core.PageRect(30, 30, 90, 90), 21);
      c.updateContent(_content([a], [...objects, top, shTop], revision: 2));
      expect(annotation.appendedCountAt(0, 0), 1);
      expect(ink.appendedCountAt(0, 0), 1, reason: 'inkAppended');
      expect(
        (ink.dirtyCount, underlay.dirtyCount, annotation.dirtyCount),
        (0, 0, 0),
      );
      _paintAll(c);
      expect(records(), (12, 12, 12));
      expect(annotation.strokeCountOf(0), 1, reason: 'the appended item');
    });

    test('the merged ink layer: a stroke under a kept shape is dirty', () {
      // createdAt 4: on top of the strokes (a = 1) but under sh1 (5)
      final under = _line('u', const Offset(30, 320), const Offset(80, 330), 4);
      c.updateContent(_content([a, under], objects, revision: 2));
      expect(ink.appendedCountAt(0, 1), 0);
      expect(ink.isDirtyAt(0, 1), isTrue);
      expect(ink.dirtyCount, 1);
      _paintAll(c);
      expect(records(), (13, 12, 12));
      expect(ink.strokeCountOf(1 * 3 + 0), 2, reason: 'u and sh1');
      // a stroke on top of everything in the chunk is appended
      final over = _line('o', const Offset(30, 340), const Offset(80, 350), 9);
      c.updateContent(_content([a, under, over], objects, revision: 3));
      expect(ink.appendedCountAt(0, 1), 1);
      expect(ink.dirtyCount, 0);
    });

    test('hiding an object re-records its chunk only; previews do not', () {
      c.setHiddenObjectIds({'tx2'});
      _paintAll(c);
      expect(records(), (12, 12, 13));
      expect(annotation.strokeCountOf(1), 0, reason: 'tx2 left out');
      c.setHiddenObjectIds({});
      _paintAll(c);
      expect(records(), (12, 12, 14), reason: 'shown again');
      // a preview with a committed id: the committed one leaves its chunk once
      for (var i = 0; i < 60; i++) {
        c.setPreviewObjects([
          _box('tx1', core.PageRect(20.0 + i, 560, 200.0 + i, 600), 7),
        ]);
        _paintAll(c);
      }
      expect(records(), (12, 12, 15));
      c.setPreviewObjects(const []);
      _paintAll(c);
      expect(records(), (12, 12, 16), reason: 'the committed one back');
    });

    test('draw keys: an asset change re-records the chunks that drew it', () {
      expect(
        underlay.drawKeysAt(0, 0),
        containsAll([InkDrawKeys.asset('a1'), InkDrawKeys.hairline]),
      );
      expect(underlay.drawKeysAt(1, 1), contains(InkDrawKeys.asset('a2')));
      expect(
        underlay.drawKeysAt(1, 1),
        isNot(contains(InkDrawKeys.asset('a1'))),
      );
      expect(underlay.drawKeysAt(2, 3), isEmpty);
      expect(annotation.drawKeysAt(2, 0), contains(InkDrawKeys.hairline));
      expect(
        annotation.drawKeysAt(0, 2),
        isNot(contains(InkDrawKeys.fonts)),
        reason: 'NoteSans was loaded',
      );
      expect(underlay.markDirtyWithKey(InkDrawKeys.asset('a1')), 1);
      expect(underlay.isDirtyAt(0, 0), isTrue);
      expect(underlay.dirtyCount, 1);
      expect(underlay.drawKeysAt(0, 0), isEmpty, reason: 'cleared');
      _paintAll(c);
      expect(records(), (12, 13, 12));
      expect(underlay.drawKeysAt(0, 0), contains(InkDrawKeys.asset('a1')));
      expect(underlay.markDirtyWithKey(InkDrawKeys.asset('none')), 0);
    });

    test('another zoom octave re-records the chunks with hairlines only', () {
      _paintAll(c, viewScale: 2);
      // the two images, the unknown object; not the text, formula, shapes, strokes
      expect(records(), (12, 14, 13));
      _paintAll(c, viewScale: 2.4);
      expect(records(), (12, 14, 13), reason: 'the same octave');
      _paintAll(c, viewScale: 1.3);
      expect(records(), (12, 16, 14), reason: 'back to octave 1');
    });

    test('a background change re-records the object chunks', () {
      c.updateContent(
        _content(
          [a],
          objects,
          revision: 2,
          background: const core.BlankBackground(
            paperColorArgb: core.PaperColors.black,
          ),
        ),
      );
      expect((underlay.dirtyCount, annotation.dirtyCount), (12, 12));
      expect(ink.dirtyCount, 0);
    });
  });

  group('shapes (T33, 6.9)', () {
    core.ShapeObject styled(
      String id,
      core.ShapeGeometry geometry, {
      core.ShapeKind kind = core.ShapeKind.line,
      double width = 6,
      double opacity = 1,
      core.LineDash dash = core.LineDash.solid,
      core.ArrowHeads heads = core.ArrowHeads.none,
      int? fill,
    }) => core.ShapeObject(
      id: id,
      pageId: _pageId,
      shapeKind: kind,
      geometry: geometry,
      style: core.ShapeStyle(
        strokeColorArgb: _red,
        strokeWidth: width,
        strokeOpacity: opacity,
        dash: dash,
        arrowHeads: heads,
        fillColorArgb: fill,
        fillOpacity: 0.5,
      ),
      createdAt: 1,
    );

    test(
      'arrow at opacity 0.5: the line / head overlap is painted once',
      () async {
        final arrow = styled(
          'ar',
          core.ShapeGeometry.line(
            const core.PagePoint(40, 100),
            const core.PagePoint(240, 100),
          ),
          kind: core.ShapeKind.arrow,
          opacity: 0.5,
          heads: core.ArrowHeads.end,
        );
        final c = createTestPageController()
          ..updateContent(_content(const [], [arrow]));
        addTearDown(c.dispose);
        final px = await _pixelsOf(c);
        final middle = px.at(140, 100);
        expect(middle[1], lessThan(200), reason: 'the line is drawn');
        expect(middle[1], greaterThan(60), reason: 'half transparent');
        // L = 18, base midpoint at 240 − 18·cos 25° ≈ 223.7; the round cap reaches 226.7
        for (final x in const [224, 226, 232]) {
          expect(
            samePixel(px.at(x, 100), middle, tol: 2),
            isTrue,
            reason: '$x',
          );
        }
        expect(samePixel(px.at(150, 100), middle, tol: 2), isTrue);
      },
    );

    test('dashes leave gaps; a fill under the outline; dotted dots', () async {
      final dashed = styled(
        'da',
        core.ShapeGeometry.line(
          const core.PagePoint(40, 40),
          const core.PagePoint(240, 40),
        ),
        width: 4,
        dash: core.LineDash.dashed,
      );
      final dotted = styled(
        'do',
        core.ShapeGeometry.line(
          const core.PagePoint(40, 80),
          const core.PagePoint(240, 80),
        ),
        width: 4,
        dash: core.LineDash.dotted,
      );
      final filled = styled(
        'fi',
        core.ShapeGeometry.rectangle(const core.PageRect(60, 140, 200, 240)),
        kind: core.ShapeKind.rectangle,
        width: 4,
        fill: _blue,
      );
      final c = createTestPageController()
        ..updateContent(_content(const [], [dashed, dotted, filled]));
      addTearDown(c.dispose);
      final px = await _pixelsOf(c);
      bool paper(List<int> p) => samePixel(p, const [255, 255, 255, 255]);
      // [4, 3] × 4: visible 16 pt from x = 40, gap 12 pt
      expect(paper(px.at(48, 40)), isFalse, reason: 'in the first dash');
      expect(paper(px.at(62, 40)), isTrue, reason: 'in the first gap');
      expect(paper(px.at(76, 40)), isFalse, reason: 'second dash');
      // [0, 2] × 4: dots of diameter 4 every 8 pt
      expect(paper(px.at(48, 80)), isFalse, reason: 'dot at 48');
      expect(paper(px.at(52, 80)), isTrue, reason: 'between two dots');
      expect(
        paper(px.at(40, 84)),
        isTrue,
        reason: 'a dot is round, 2 pt radius',
      );
      // the fill (blue × 0.5) inside, the red outline over it at the edge
      final inside = px.at(130, 190);
      expect(inside[2], greaterThan(200));
      expect(inside[0], lessThan(160));
      final edge = px.at(60, 190);
      expect(edge[0], greaterThan(180));
      expect(edge[2], lessThan(90), reason: 'outline over the fill');
    });
  });

  group('CoverPictureCache', () {
    final t1 = _line('t1', const Offset(40, 40), const Offset(90, 40), 1);
    final t2 = _line('t2', const Offset(40, 80), const Offset(90, 80), 2);
    List<InkStroke> tapes(List<core.Stroke> s) => [...s.map(InkStroke.of)];

    void paint(CoverPictureCache cache, List<InkStroke> zOrdered) {
      final recorder = ui.PictureRecorder();
      cache.paint(ui.Canvas(recorder), zOrdered, (canvas, s) {
        canvas.drawRect(s.bounds, Paint());
      });
      recorder.endRecording().dispose();
    }

    test('one page picture, recorded again only when marked dirty', () {
      final cache = CoverPictureCache();
      addTearDown(cache.dispose);
      paint(cache, const []);
      expect(cache.recordCount, 0, reason: 'no tape: nothing recorded');
      paint(cache, tapes([t1, t2]));
      paint(cache, tapes([t1, t2]));
      expect(cache.recordCount, 1);
      expect(cache.strokeCount, 2);
      cache.markDirty();
      expect(cache.isDirty, isTrue);
      paint(cache, tapes([t1]));
      expect(cache.recordCount, 2);
      expect(cache.strokeCount, 1);
    });

    test(
      'the controller: no cover strokes before T31, toggles mark it dirty',
      () {
        final tape = _line(
          'tape',
          const Offset(40, 40),
          const Offset(90, 40),
          1,
          tool: core.PenTool.tape,
        );
        final c = createTestPageController()
          ..updateContent(_content([tape], const []));
        addTearDown(c.dispose);
        _paintAll(c);
        expect(inkCoverCacheOf(c).recordCount, 0, reason: 'tape = ballpoint');
        expect(inkChunkCacheOf(c).strokeCountOf(0), 1);
        c.toggleTape('tape');
        expect(inkCoverCacheOf(c).isDirty, isTrue);
        expect(inkChunkCacheOf(c).dirtyCount, 0, reason: 'ink chunks kept');
      },
    );
  });
}
