// m5-7/03-ink 8.2 T40 (6.19, K-7, K-9): the playback emphasis at layer 4′.
// - K-7: 600 frames of playback (16 ms apart) record no inkBase chunk and make
//   no raster tile; while the boundary moves inside a block a frame records at
//   most playbackVeilBlock + the writing strokes into veil pictures; a seek only
//   changes the block list.
// - dimUnwritten: an unwritten ink-layer stroke is the paper color at 0.75 over
//   the ink (0.25 of its density — white and dark paper); written strokes, other
//   recordings and strokes without one are unchanged; a writing stroke is dimmed
//   only past the points already written; highlighter and tape strokes are not
//   dimmed.
// - The recent strokes get the emphasis outline (playbackEmphasisArgb at 0.8)
//   in both styles; highlightRecent dims nothing; null → no layer 4′ drawing.
// - K-9 (a): a covered tape over unwritten recorded strokes — the pixels inside
//   the tape stay those of playback off during 600 frames, both styles; a tape
//   stroke in the recent window keeps its inside and shows the outer ring only.
// - K-9 (b): text boxes and formulas over unwritten strokes — the text box
//   (background) and the glyph pixels stay those of playback off.
// - The developer value playbackPaintUs.
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/dev_tools.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/render/cache_pool.dart' show mathRasterCacheOf;
import 'package:ink_engine/src/render/ink_page_controller.dart'
    show
        inkAnnotationCacheOf,
        inkChunkCacheOf,
        inkPageRenderOf,
        playbackIndexOf,
        playbackStatsOf;
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

import '../support/page_view.dart';
import '../support/pixels.dart';
import '../support/raster.dart';

const _pageId = 'p1';
const _blue = 0xFF0000FF;
const _red = 0xFFFF0000;
const _green = 0xFF00AA00;
const _white = 0xFFFFFFFF;
const _tape = 0xFF7E57C2;
const _frame = Duration(milliseconds: 16);

/// A segment stroke a → b (points 2 pt apart, t 10 ms apart) linked to [recording]
/// at [offset] (null recording → not linked).
core.Stroke _rec(
  String id,
  Offset a,
  Offset b, {
  String? recording = 'r',
  int offset = 0,
  core.PenTool tool = core.PenTool.ballpoint,
  int color = _blue,
  double width = 8,
  int createdAt = 1,
}) {
  final style = core.StrokeStyle.defaultsFor(tool)
      .copyWith(colorArgb: color, width: width);
  return strokeThrough(segment(a, b), style, id: id).copyWith(
    createdAt: createdAt,
    recordingId: recording,
    recordingOffsetMs: recording == null ? null : offset,
  );
}

InkPageContent _content(
  List<core.Stroke> strokes, {
  List<core.PageObject> objects = const [],
  int paper = _white,
  int revision = 1,
}) => InkPageContent.fromCore(
  page: SyntheticInk.page(
    pageId: _pageId,
    background: core.BlankBackground(paperColorArgb: paper),
  ),
  strokes: strokes,
  objects: objects,
  revision: revision,
);

/// Every layer of [c] over [paper] at 1 px per pt; [origin] is the top left page
/// point of the [w] × [h] image.
Future<Pixels> _pixelsOf(
  InkPageController c, {
  int paper = _white,
  int w = 300,
  int h = 300,
  Offset origin = Offset.zero,
}) => renderPixels(w, h, (canvas) {
  canvas.translate(-origin.dx, -origin.dy);
  paintPaper(canvas, paper);
  final render = inkPageRenderOf(c);
  for (final layer in InkRenderLayer.values) {
    render.paint(canvas, layer, 1);
  }
});

List<int> _rgba(int argb) => [
  (argb >> 16) & 0xFF,
  (argb >> 8) & 0xFF,
  argb & 0xFF,
  255,
];

/// The pixel a veil over [ink] gives on [paper]: paper × α + ink × (1 − α), α = 0.75.
List<int> _veiled(List<int> ink, int paper) {
  const a = 191 / 255; // round((1 − playbackDimOpacity) · 255)
  final p = _rgba(paper);
  return [
    for (var k = 0; k < 3; k++) (p[k] * a + ink[k] * (1 - a)).round(),
    255,
  ];
}

/// The most 'emphasis-like' pixel (orange over white: high red, mid green, low
/// blue) among [points].
List<int> _orangest(Pixels p, Iterable<(int, int)> points) {
  List<int>? best;
  var score = -1 << 30;
  for (final (x, y) in points) {
    final c = p.at(x, y);
    final s = c[0] - c[2] - (c[1] - 161).abs();
    if (s > score) {
      score = s;
      best = c;
    }
  }
  return best!;
}

bool _sameRegion(
  Pixels a,
  Pixels b,
  bool Function(int x, int y) inside, {
  int tol = 1,
}) {
  for (var y = 0; y < a.height; y++) {
    for (var x = 0; x < a.width; x++) {
      if (!inside(x, y)) continue;
      if (!samePixel(a.at(x, y), b.at(x, y), tol: tol)) return false;
    }
  }
  return true;
}

InkPlaybackFocus _focus(
  int p, {
  InkPlaybackStyle style = InkPlaybackStyle.dimUnwritten,
  int window = 2000,
  String recording = 'r',
}) => InkPlaybackFocus(
  recordingId: recording,
  positionMs: p,
  style: style,
  recentWindowMs: window,
);

final class _TickClock implements InkClock {
  int us = 0;
  @override
  int nowUs() => us += 7;
  @override
  bool get alignedWithEventTimestamps => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('K-7: the base layers are never recorded again', () {
    testWidgets(
      '600 frames: no inkBase chunk record, no tile; a boundary inside '
      'a block records ≤ 64 + writing strokes; a seek only changes the block '
      'list',
      (tester) async {
        var n = 0;
        final synthetic = InkDevTools.syntheticStrokes(
          pageId: _pageId,
          pageSize: core.PageSize.a4Portrait,
          count: 220,
          newId: () => 'w${n++}',
          createdAt: 1000,
          seed: 40,
        );
        final strokes = [
          for (var i = 0; i < synthetic.length; i++)
            synthetic[i].copyWith(recordingId: 'r', recordingOffsetMs: i * 44),
        ];
        final c = createTestPageController(
          config: InkRenderConfig.nativeDefaults,
          services: testInkCoreServices(startMillis: 100000),
        )..updateContent(SyntheticInk.pageContent(strokes: strokes));
        addTearDown(c.dispose);
        await pumpPageView(tester, c);
        await rasterAllTiles(tester, c);
        final records = inkChunkCacheOf(c).recordCount;
        final tiles = tilesMade(c);
        expect(tiles, greaterThan(0), reason: 'the base is in tiles');
        final stats = playbackStatsOf(c);
        for (final style in InkPlaybackStyle.values) {
          for (var f = 0; f < 600; f++) {
            final p = f * 16;
            final before = stats.veilStrokes;
            final paints = stats.paints;
            c.setPlaybackFocus(_focus(p, style: style));
            await tester.pump(_frame);
            expect(stats.paints, paints + 1, reason: 'layer 4′ painted at $p');
            if (f == 0 || style == InkPlaybackStyle.highlightRecent) {
              if (style == InkPlaybackStyle.highlightRecent) {
                expect(stats.veilStrokes, before, reason: 'no veil');
              }
              continue;
            }
            final track = playbackIndexOf(c).trackOf('r')!;
            expect(
              stats.veilStrokes - before,
              lessThanOrEqualTo(
                InkTuning.playbackVeilBlock + track.writing(p).length,
              ),
              reason: 'veil strokes recorded at $p',
            );
          }
        }
        expect(inkChunkCacheOf(c).recordCount, records, reason: 'chunks');
        expect(tilesMade(c), tiles, reason: 'tiles');
        // seeks: far jumps back and forth
        final track = playbackIndexOf(c).trackOf('r')!;
        c.setPlaybackFocus(_focus(0));
        await tester.pump(_frame);
        for (final p in [9000, 100, 5003, 7777, 0, 9600, 2222]) {
          final before = stats.veilStrokes;
          c.setPlaybackFocus(_focus(p));
          await tester.pump(_frame);
          expect(
            stats.veilStrokes - before,
            lessThanOrEqualTo(
              InkTuning.playbackVeilBlock + track.writing(p).length,
            ),
            reason: 'seek to $p',
          );
        }
        c.setPlaybackFocus(null);
        await tester.pump(_frame);
        await tester.pump(const Duration(seconds: 1));
        expect(inkChunkCacheOf(c).recordCount, records);
        expect(tilesMade(c), tiles);
      },
    );

    test('setPlaybackFocus repaints inkActive only; the same focus again '
        'nothing', () {
      final c = createTestPageController()
        ..updateContent(
          _content([_rec('u', const Offset(20, 50), const Offset(280, 50))]),
        );
      addTearDown(c.dispose);
      final fired = <InkRenderLayer>[];
      for (final layer in InkRenderLayer.values) {
        c.layerRepaint(layer).addListener(() => fired.add(layer));
      }
      c.setPlaybackFocus(_focus(10));
      c.setPlaybackFocus(_focus(10));
      c.setPlaybackFocus(_focus(20));
      c.setPlaybackFocus(null);
      c.setPlaybackFocus(null);
      expect(fired, [
        InkRenderLayer.inkActive,
        InkRenderLayer.inkActive,
        InkRenderLayer.inkActive,
      ]);
    });
  });

  group('dimUnwritten (R-4)', () {
    test(
      'unwritten: paper × 0.75 over the ink (0.25 density) on white and '
      'dark paper; written, other recordings and no recording unchanged',
      () async {
        for (final paper in [_white, core.PaperColors.black]) {
          final c = createTestPageController()
            ..updateContent(
              _content(paper: paper, [
                _rec(
                  'u',
                  const Offset(20, 40),
                  const Offset(280, 40),
                  offset: 5000,
                ),
                _rec('w', const Offset(20, 80), const Offset(280, 80)),
                _rec(
                  'o',
                  const Offset(20, 120),
                  const Offset(280, 120),
                  recording: 'other',
                  offset: 5000,
                ),
                _rec(
                  'n',
                  const Offset(20, 160),
                  const Offset(280, 160),
                  recording: null,
                ),
              ]),
            );
          addTearDown(c.dispose);
          final off = await _pixelsOf(c, paper: paper);
          // 'w' runs 0..1300 ms; at 4000 it is written and outside the window
          c.setPlaybackFocus(_focus(4000));
          final on = await _pixelsOf(c, paper: paper);
          final ink = off.at(150, 40);
          expect(samePixel(ink, _rgba(_blue), tol: 2), isTrue, reason: 'ink');
          expect(
            samePixel(on.at(150, 40), _veiled(ink, paper), tol: 3),
            isTrue,
            reason: 'veiled on ${paper.toRadixString(16)}: ${on.at(150, 40)}',
          );
          for (final y in [80, 120, 160, 60]) {
            expect(
              _sameRegion(off, on, (x, yy) => yy >= y - 8 && yy <= y + 8),
              isTrue,
              reason: 'row $y unchanged',
            );
          }
        }
      },
    );

    test(
      'a writing stroke: dimmed only past the points already written',
      () async {
        // 101 points, t 0..1000 ms; at offset 1000, position 1500 → points with
        // t > 500 (x > 120) are still to be written
        final c = createTestPageController()
          ..updateContent(
            _content([
              _rec(
                's',
                const Offset(20, 50),
                const Offset(220, 50),
                offset: 1000,
              ),
            ]),
          );
        addTearDown(c.dispose);
        final off = await _pixelsOf(c);
        c.setPlaybackFocus(_focus(1500, window: 0));
        final on = await _pixelsOf(c);
        for (var x = 16; x <= 108; x += 4) {
          expect(
            samePixel(on.at(x, 50), off.at(x, 50), tol: 0),
            isTrue,
            reason: 'written part x $x',
          );
        }
        for (var x = 134; x <= 220; x += 4) {
          expect(
            samePixel(on.at(x, 50), _veiled(off.at(x, 50), _white), tol: 3),
            isTrue,
            reason: 'still to be written x $x: ${on.at(x, 50)}',
          );
        }
        // at 2000 the stroke is written: nothing dimmed
        c.setPlaybackFocus(_focus(2000, window: 0));
        expect(_sameRegion(off, await _pixelsOf(c), (x, y) => true), isTrue);
      },
    );

    test('highlighter and tape strokes are not dimmed (CP-INK-8)', () async {
      final c = createTestPageController()
        ..updateContent(
          _content([
            _rec(
              'hl',
              const Offset(20, 60),
              const Offset(280, 60),
              tool: core.PenTool.highlighter,
              color: 0xFFFFEB3B,
              width: 16,
              offset: 5000,
            ),
            _rec(
              'tape',
              const Offset(20, 140),
              const Offset(280, 140),
              tool: core.PenTool.tape,
              color: _tape,
              width: 16,
              offset: 5000,
            ),
          ]),
        );
      addTearDown(c.dispose);
      final off = await _pixelsOf(c);
      c.setPlaybackFocus(_focus(0));
      expect(_sameRegion(off, await _pixelsOf(c), (x, y) => true), isTrue);
    });

    test('highlightRecent dims nothing; null → no layer 4′ drawing', () async {
      final c = createTestPageController()
        ..updateContent(
          _content([
            _rec(
              'u',
              const Offset(20, 40),
              const Offset(280, 40),
              offset: 5000,
            ),
            _rec('n', const Offset(20, 90), const Offset(280, 90), offset: 900),
          ]),
        );
      addTearDown(c.dispose);
      final off = await _pixelsOf(c);
      c.setPlaybackFocus(
        _focus(4000, style: InkPlaybackStyle.highlightRecent, window: 100),
      );
      expect(_sameRegion(off, await _pixelsOf(c), (x, y) => true), isTrue);
      c.setPlaybackFocus(_focus(1000));
      final on = await _pixelsOf(c);
      expect(_sameRegion(off, on, (x, y) => true), isFalse, reason: 'drawn');
      c.setPlaybackFocus(null);
      expect(_sameRegion(off, await _pixelsOf(c), (x, y) => true), isTrue);
      // a recording with no stroke on the page: nothing either
      c.setPlaybackFocus(_focus(1000, recording: 'elsewhere'));
      expect(_sameRegion(off, await _pixelsOf(c), (x, y) => true), isTrue);
    });
  });

  group('emphasis', () {
    test('recent strokes get the 2 px outline in playbackEmphasisArgb at 0.8 — '
        'both styles; outside the window none', () async {
      // 'e' (11 points, 0..100 ms) at offset 800: written at 1000, recent with W 2000
      final c = createTestPageController()
        ..updateContent(
          _content([
            _rec(
              'e',
              const Offset(100, 60),
              const Offset(120, 60),
              offset: 800,
            ),
          ]),
        );
      addTearDown(c.dispose);
      final off = await _pixelsOf(c);
      // radius 4: the outline at y = 64, the outer half of the 2 px ring = row 64
      final below = [for (var x = 104; x <= 116; x++) (x, 64)];
      for (final (x, y) in below) {
        expect(samePixel(off.at(x, y), _rgba(_white), tol: 2), isTrue);
      }
      // 0.8 · orange (FF8A00) over white = (255, 161, 51)
      for (final style in InkPlaybackStyle.values) {
        c.setPlaybackFocus(_focus(1000, style: style));
        final on = await _pixelsOf(c);
        final px = _orangest(on, below);
        expect(
          samePixel(px, [255, 161, 51, 255], tol: 12),
          isTrue,
          reason: '${style.name}: $px',
        );
        // inside the ink the color stays blue-dominant (the ring's inner half
        // is 1 px wide)
        expect(on.at(110, 60)[2], greaterThan(200), reason: 'ink center');
      }
      c.setPlaybackFocus(_focus(2800, window: 2000));
      expect(
        _sameRegion(off, await _pixelsOf(c), (x, y) => true),
        isTrue,
        reason: 'offset 800 = p − W: not recent',
      );
    });
  });

  group('K-9: layer 4′ never shows over annotation / cover', () {
    test('(a) a covered tape over unwritten recorded strokes: the inside of the '
        'tape = playback off for 600 frames, both styles', () async {
      // the tape x 140..160, y 20..180 (square caps to 10..190) above 8 strokes
      final strokes = [
        for (var i = 0; i < 8; i++)
          _rec(
            's$i',
            Offset(100, 30.0 + 20 * i),
            Offset(200, 30.0 + 20 * i),
            offset: 1200 * i,
            createdAt: 1 + i,
          ),
        _rec(
          'tape',
          const Offset(150, 20),
          const Offset(150, 180),
          tool: core.PenTool.tape,
          color: _tape,
          width: 20,
          offset: 4000,
          createdAt: 100,
        ),
      ];
      final c = createTestPageController()..updateContent(_content(strokes));
      addTearDown(c.dispose);
      const origin = Offset(130, 0);
      Future<Pixels> region() => _pixelsOf(c, w: 40, h: 200, origin: origin);
      // inside the band, 2 px from its edges and the square caps
      bool inside(int x, int y) => x >= 12 && x <= 27 && y >= 14 && y <= 186;
      final off = await region();
      expect(samePixel(off.at(20, 100), _rgba(_tape), tol: 3), isTrue);
      for (final style in InkPlaybackStyle.values) {
        for (var f = 0; f < 600; f++) {
          c.setPlaybackFocus(_focus(f * 16, style: style));
          final on = await region();
          expect(
            _sameRegion(off, on, inside),
            isTrue,
            reason: '${style.name} frame $f',
          );
        }
      }
      // the veils do show outside the tape (the test sees playback)
      c.setPlaybackFocus(_focus(0));
      final full = await _pixelsOf(c);
      c.setPlaybackFocus(null);
      final fullOff = await _pixelsOf(c);
      expect(samePixel(full.at(110, 170), fullOff.at(110, 170)), isFalse);
    });

    test('a tape stroke in the recent window: the inside unchanged, the outer '
        'ring shows', () async {
      final c = createTestPageController()
        ..updateContent(
          _content([
            _rec(
              'tape',
              const Offset(150, 40),
              const Offset(150, 160),
              tool: core.PenTool.tape,
              color: _tape,
              width: 20,
              offset: 500,
            ),
          ]),
        );
      addTearDown(c.dispose);
      final off = await _pixelsOf(c);
      for (final style in InkPlaybackStyle.values) {
        c.setPlaybackFocus(_focus(1000, style: style));
        final on = await _pixelsOf(c);
        expect(
          _sameRegion(
            off,
            on,
            (x, y) => x >= 142 && x <= 157 && y >= 34 && y <= 166,
          ),
          isTrue,
          reason: '${style.name}: inside',
        );
        // the edge at x = 160: the ring's outer half is column 160
        final ring = _orangest(on, [for (var y = 60; y < 140; y++) (160, y)]);
        expect(
          samePixel(ring, [255, 161, 51, 255], tol: 16),
          isTrue,
          reason: '${style.name}: ring $ring',
        );
        expect(samePixel(off.at(160, 100), _rgba(_white), tol: 2), isTrue);
      }
    });

    group('(b) text and formulas', () {
      setUpAll(() async {
        await loadKatexFontsForTest();
        await InkFonts.ensureLoaded();
      });

      test('a text box (background and glyphs) and a formula over unwritten '
          'strokes: their pixels = playback off', () async {
        final latex = r'\frac{a}{b}+\sqrt{x}';
        final l = InkMathRenderer.layout(latex, fontSizePt: 56)!;
        final objects = <core.PageObject>[
          core.TextBoxObject(
            id: 'bg',
            pageId: _pageId,
            frame: const core.ElementFrame(core.PageRect(30, 20, 270, 70)),
            text: '가나다 ABC',
            style: const core.TextBoxStyle(
              fontSizePt: 24,
              colorArgb: _red,
              backgroundArgb: _green,
            ),
            createdAt: 50,
          ),
          core.TextBoxObject(
            id: 'plain',
            pageId: _pageId,
            frame: const core.ElementFrame(core.PageRect(30, 100, 270, 150)),
            text: 'HHH 가가가',
            style: const core.TextBoxStyle(fontSizePt: 32, colorArgb: _red),
            createdAt: 51,
          ),
          core.MathObject(
            id: 'math',
            pageId: _pageId,
            frame: core.ElementFrame(
              core.PageRect(
                60,
                180,
                60 + l.sizePt.width,
                180 + l.sizePt.height,
              ),
            ),
            latex: latex,
            style: const core.MathStyle(colorArgb: 0xFF000000, fontSizePt: 56),
            createdAt: 52,
          ),
        ];
        // unwritten strokes under everything (thick, so they run under glyphs)
        final strokes = [
          for (var i = 0; i < 14; i++)
            _rec(
              's$i',
              Offset(20, 24.0 + 16 * i),
              Offset(280, 24.0 + 16 * i),
              width: 10,
              offset: 5000 + i,
              createdAt: 1 + i,
            ),
        ];
        final c = createTestPageController()
          ..updateContent(_content(strokes, objects: objects));
        addTearDown(c.dispose);
        await _settle(c);
        final off = await _pixelsOf(c);
        for (final style in InkPlaybackStyle.values) {
          c.setPlaybackFocus(_focus(1000, style: style, window: 3000));
          final on = await _pixelsOf(c);
          // the text box with a background: all of it (1 px in)
          expect(
            _sameRegion(
              off,
              on,
              (x, y) => x >= 31 && x <= 268 && y >= 21 && y <= 68,
            ),
            isTrue,
            reason: '${style.name}: background box',
          );
          // the glyphs without a background: the pure text color pixels
          var glyphs = 0, formula = 0;
          for (var y = 100; y < 150; y++) {
            for (var x = 30; x < 270; x++) {
              final p = off.at(x, y);
              if (!samePixel(p, _rgba(_red), tol: 2)) continue;
              glyphs++;
              expect(
                samePixel(on.at(x, y), p, tol: 2),
                isTrue,
                reason: '${style.name}: glyph pixel ($x, $y)',
              );
            }
          }
          for (var y = 180; y < 180 + l.sizePt.height.floor(); y++) {
            for (var x = 60; x < 60 + l.sizePt.width.floor(); x++) {
              final p = off.at(x, y);
              // the opaque formula ink (an edge pixel mixes in the stroke under it)
              if (p[0] > 2 || p[1] > 2 || p[2] > 2) continue;
              formula++;
              expect(
                samePixel(on.at(x, y), p, tol: 2),
                isTrue,
                reason: '${style.name}: formula pixel ($x, $y)',
              );
            }
          }
          expect(glyphs, greaterThan(100), reason: 'glyph pixels seen');
          expect(formula, greaterThan(50), reason: 'formula pixels seen');
        }
        // the strokes beside the objects are dimmed (dimUnwritten)
        c.setPlaybackFocus(_focus(1000));
        final on = await _pixelsOf(c);
        expect(samePixel(on.at(25, 88), off.at(25, 88)), isFalse);
      });
    });
  });

  test('developer value playbackPaintUs: present once measured while '
      'enabled', () async {
    final clock = _TickClock();
    final c = createTestPageController(clock: clock)
      ..updateContent(
        _content([
          _rec('u', const Offset(20, 40), const Offset(280, 40), offset: 5000),
        ]),
      );
    addTearDown(c.dispose);
    c.setPlaybackFocus(_focus(100));
    await _pixelsOf(c);
    expect(
      c.diagnostics.developerValues.containsKey('playbackPaintUs'),
      isFalse,
      reason: 'not collected while disabled',
    );
    c.diagnostics.enabled = true;
    addTearDown(() => c.diagnostics.enabled = false);
    for (var i = 0; i < 5; i++) {
      c.setPlaybackFocus(_focus(100 + i));
      await _pixelsOf(c);
    }
    final value = c.diagnostics.developerValues['playbackPaintUs'];
    expect(value, isNotNull);
    expect(value, greaterThan(0));
    c.diagnostics.reset();
    expect(c.diagnostics.developerValues, isEmpty);
  });
}

void _paintAll(InkPageController c) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final render = inkPageRenderOf(c);
  for (final layer in InkRenderLayer.values) {
    render.paint(canvas, layer, 1);
  }
  recorder.endRecording().dispose();
}

/// Paints until the formula rasters arrived and no annotation chunk waits.
Future<void> _settle(InkPageController c) async {
  final cache = mathRasterCacheOf(c.cachePool);
  final annotation = inkAnnotationCacheOf(c);
  for (var i = 0; i < 100; i++) {
    _paintAll(c);
    for (var k = 0; k < 2000 && cache.stats.queued > 0; k++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    await pumpEventQueue();
    if (annotation.dirtyCount == 0 && cache.stats.queued == 0) return;
  }
  fail('the formula rasters did not settle');
}
