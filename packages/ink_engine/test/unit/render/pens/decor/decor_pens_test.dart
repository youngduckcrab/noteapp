// (v2.11, C211-01) The decoration pens (render/pens/decor/): neon, jelly,
// rainbow, glitter — DECOR TRACK tests next to the shared foundation test
// (pen_renderer_test.dart, K-1 + repaint determinism for every pen):
//   * screen = PDF: the committed picture and the PDF pieces painted as fills
//     give the same pixels (same layers, same colors);
//   * determinism: a stroke rebuilt from the same data and createdAt gives the
//     same pieces; glitter changes with createdAt and grows append-only;
//   * live ≈ committed: paintLive of the same centerline is (nearly) the
//     committed picture — no visible jump at the pen lift;
//   * K-1 for odd data (tiny / saturated widthQ, translucent, pale colors);
//   * PDF export: one InkFillShape per piece, same strokeId and tool, inside
//     the stroke's bounds;
//   * rainbow: the palette starts at the pen color, one piece per palette
//     step, the period does not stretch while the stroke grows, translucent
//     PDF bands do not overlap, a dot is the banded bead;
//   * live frames of a growing stroke (kept parts) = a fresh frame ≈ stored;
//   * glitter: bounded cost at thin widths, grains never move as it grows,
//     two stars on a dot; the geometry cache keeps to its budget; K-1 at the
//     thinnest widths;
//   * neon / glitter: no pressure response (widthQ fixed);
//   * cost: a 2,000-point stroke builds its layers in a few ms.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/geometry/outline_generator.dart';
import 'package:ink_engine/src/interop/core_interop.dart' as interop;
import 'package:ink_engine/src/render/pens/decor/decor_kit.dart';
import 'package:ink_engine/src/render/pens/decor/rainbow_pen.dart';
import 'package:ink_engine/src/render/pens/pen_renderer.dart';
import 'package:ink_engine/src/render/stroke_painter.dart';
import 'package:ink_engine/src/stroke/stroke_builder.dart';
import 'package:note_core/note_core.dart' as core;

import '../../../../support/pixels.dart';

const List<core.PenTool> _decor = [
  core.PenTool.neon,
  core.PenTool.jelly,
  core.PenTool.rainbow,
  core.PenTool.glitter,
];

const int _size = 200;

var _ids = 0;

/// A stroke through the real pipeline: an S curve with a pressure swell.
core.Stroke _sCurve(
  core.PenTool tool, {
  double? width,
  int? color,
  int penDown = 1000,
  int n = 90,
  double length = 150,
}) {
  final style = core.StrokeStyle.defaultsFor(tool)
      .copyWith(width: width, colorArgb: color);
  return interop.newCoreStroke(
    buildStroke(
      [
        for (var i = 0; i < n; i++)
          InkSample(
            position: ui.Offset(
              25 + length * i / (n - 1),
              100 + 40 * math.sin(i / (n - 1) * 2 * math.pi),
            ),
            timeUs: i * 8333,
            kind: InkPointerKind.stylus,
            pressure: 0.15 + 0.8 * math.sin(i / (n - 1) * math.pi),
          ),
      ],
      style: style,
      viewScale: 1,
    )!,
    id: 'decor-${_ids++}',
    pageId: 'p1',
    penDownMillis: penDown,
  );
}

/// The same CORE stroke data again (a new object: no cached geometry).
core.Stroke _copy(core.Stroke s) => interop.strokeFromData(
  Float32List.fromList(s.points.rawData),
  id: '${s.id}-copy',
  pageId: s.pageId,
  style: s.style,
  createdAt: s.createdAt,
  hasTilt: false,
  hasAzimuth: false,
);

/// The first [n] points of [s] (same id, style and createdAt: the live
/// stroke at an earlier frame).
core.Stroke _prefix(core.Stroke s, int n) => interop.strokeFromData(
  Float32List.fromList(
    s.points.rawData.sublist(0, n * core.StrokePoints.stride),
  ),
  id: s.id,
  pageId: s.pageId,
  style: s.style,
  createdAt: s.createdAt,
  hasTilt: false,
  hasAzimuth: false,
);

Future<Uint8List> _paint(void Function(ui.Canvas c) paint) async {
  final px = await renderPixels(_size, _size, (c) {
    paintPaper(c, 0xFFFFFFFF);
    paint(c);
  });
  return px.bytes.buffer.asUint8List();
}

void _paintPieces(ui.Canvas c, InkStroke s) {
  final pieces = penRendererOf(s.style.tool).vectorPieces(
    s,
    OutlineGenerator.outline(s),
    opacity: strokeOpacity(s),
    smooth: true,
  );
  for (final p in pieces) {
    c.drawPath(
      p.path.toUiPath(),
      ui.Paint()
        ..isAntiAlias = true
        ..color = inkColor(p.colorArgb, p.opacity),
    );
  }
}

void _paintLive(ui.Canvas c, InkStroke s, {bool withOutline = true}) {
  final paths = withOutline
      ? [OutlineGenerator.outline(s).toPath(), ui.Path()]
      : [ui.Path(), ui.Path()];
  penRendererOf(s.style.tool).paintLive(
    c,
    PenLiveFrame(
      style: s.style,
      paths: paths,
      centerline: [
        for (var i = 0; i < s.points.length; i++) s.points.offsetAt(i),
      ],
      bounds: s.bounds.inflate(1),
      opacity: strokeOpacity(s),
      seed: s.source.createdAt,
    ),
  );
}

/// (pixels differing by more than [tol] in some channel) / (pixels painted in a or b)
double _diffShare(Uint8List a, Uint8List b, {int tol = 24}) {
  var differ = 0, inked = 0;
  for (var i = 0; i < a.length; i += 4) {
    final paperA = a[i] == 255 && a[i + 1] == 255 && a[i + 2] == 255;
    final paperB = b[i] == 255 && b[i + 1] == 255 && b[i + 2] == 255;
    if (paperA && paperB) continue;
    inked++;
    for (var k = 0; k < 3; k++) {
      if ((a[i + k] - b[i + k]).abs() > tol) {
        differ++;
        break;
      }
    }
  }
  return inked == 0 ? 0 : differ / inked;
}

/// Pixels outside [b] (1 px anti-aliasing allowance) on a transparent canvas.
Future<int> _outside(InkStroke s) async {
  final px = await renderPixels(_size, _size, (c) {
    paintFillStroke(c, s, OutlineGenerator.outline(s));
  });
  final a = px.bytes.buffer.asUint8List();
  final b = s.bounds;
  var outside = 0;
  for (var y = 0; y < _size; y++) {
    for (var x = 0; x < _size; x++) {
      if (a[(y * _size + x) * 4 + 3] == 0) continue;
      if (x + 1 < b.left - 1 ||
          x > b.right + 1 ||
          y + 1 < b.top - 1 ||
          y > b.bottom + 1) {
        outside++;
      }
    }
  }
  return outside;
}

void main() {
  group('screen = PDF pieces', () {
    for (final tool in _decor) {
      test(tool.name, () async {
        for (final color in [null, 0xFFFFFFFF, 0xFF1A1A1A]) {
          final s = InkStroke.of(_sCurve(tool, width: 8, color: color));
          final screen = await _paint(
            (c) => paintFillStroke(c, s, OutlineGenerator.outline(s)),
          );
          final pdf = await _paint((c) => _paintPieces(c, s));
          // the screen draws the outlines' quadratics, the PDF the equal
          // cubics: only anti-aliasing differs (a few levels at edges)
          expect(
            _diffShare(screen, pdf),
            lessThan(0.002),
            reason: '${tool.name} $color',
          );
        }
      });
    }
  });

  group('determinism', () {
    for (final tool in _decor) {
      test('${tool.name}: rebuilt stroke → the same pieces', () {
        final a = _sCurve(tool, width: 6);
        final sa = InkStroke.of(a), sb = InkStroke.of(_copy(a));
        final r = penRendererOf(tool);
        final pa = r.vectorPieces(
          sa,
          OutlineGenerator.outline(sa),
          opacity: 1,
          smooth: true,
        );
        final pb = r.vectorPieces(
          sb,
          OutlineGenerator.outline(sb),
          opacity: 1,
          smooth: true,
        );
        expect(pa.length, pb.length);
        for (var i = 0; i < pa.length; i++) {
          expect(pa[i].colorArgb, pb[i].colorArgb);
          expect(pa[i].opacity, pb[i].opacity);
          expect(pa[i].path.verbs, pb[i].path.verbs);
          expect(pa[i].path.coords, pb[i].path.coords);
        }
      });
    }

    List<double> sparkleStarts(core.Stroke s) =>
        sparkleStartsOf(InkStroke.of(s));

    test('glitter: createdAt seeds the sparkles; they grow append-only', () {
      final a = _sCurve(core.PenTool.glitter, penDown: 5000);
      final b = _sCurve(core.PenTool.glitter, penDown: 5001);
      expect(sparkleStarts(a), isNot(sparkleStarts(b)));
      // the first 60 % of the same stroke: its grains are the long stroke's
      final full = _sCurve(core.PenTool.glitter, penDown: 7000, n: 100);
      final m = 60;
      final raw = full.points.rawData;
      final part = interop.strokeFromData(
        Float32List.fromList(raw.sublist(0, m * core.StrokePoints.stride)),
        id: 'part',
        pageId: 'p1',
        style: full.style,
        createdAt: full.createdAt,
        hasTilt: false,
        hasAzimuth: false,
      );
      final big = sparkleStarts(full);
      final small = sparkleStarts(part);
      final keys = <String>{
        for (var i = 0; i + 1 < big.length; i += 2)
          '${big[i].toStringAsFixed(2)},${big[i + 1].toStringAsFixed(2)}',
      };
      var found = 0;
      for (var i = 0; i + 1 < small.length; i += 2) {
        if (keys.contains(
          '${small[i].toStringAsFixed(2)},${small[i + 1].toStringAsFixed(2)}',
        )) {
          found++;
        }
      }
      expect(small.length, greaterThan(100));
      expect(found / (small.length / 2), greaterThan(0.9));
    });
  });

  group('live ≈ committed (no jump at the pen lift)', () {
    for (final tool in _decor) {
      test(tool.name, () async {
        final s = InkStroke.of(_sCurve(tool, width: 8));
        final committed = await _paint(
          (c) => paintFillStroke(c, s, OutlineGenerator.outline(s)),
        );
        final live = await _paint((c) => _paintLive(c, s));
        // neon and glitter have no pressure: the same tubes; jelly differs
        // only in tube joins; the live rainbow's bands are clipped to the live
        // outline (its stored bands have their own radius: a step of the
        // color ramp at the edges — hence the wider tolerance); live glitter
        // grains are round points, stored ones octagons
        final rainbow = tool == core.PenTool.rainbow;
        expect(
          _diffShare(committed, live, tol: rainbow ? 40 : 24),
          lessThan(tool == core.PenTool.glitter ? 0.04 : 0.03),
          reason: tool.name,
        );
      });
    }
  });

  group('K-1 for odd data', () {
    for (final tool in _decor) {
      test(tool.name, () async {
        for (final q in [0.02, 0.25, 1.0]) {
          for (final (color, opacity) in [
            (0xFFFFFFFF, 1.0),
            (0xFF000000, 0.4),
            (0xFF2F80ED, 0.7),
          ]) {
            final style = core.StrokeStyle.defaultsFor(tool)
                .copyWith(width: 6, colorArgb: color, opacity: opacity);
            for (final pts in [
              segment(const ui.Offset(60, 100), const ui.Offset(140, 100)),
              [
                for (var i = 0; i <= 30; i++)
                  ui.Offset(
                    60 + 80 * i / 30,
                    100 + 30 * math.sin(i / 30 * 3 * math.pi),
                  ),
              ],
              [const ui.Offset(100, 100)],
            ]) {
              final s = InkStroke.of(strokeThrough(pts, style, widthQ: q));
              expect(
                await _outside(s),
                0,
                reason: '${tool.name} q=$q $color $opacity ${pts.length}',
              );
              for (final p in penRendererOf(tool).vectorPieces(
                s,
                OutlineGenerator.outline(s),
                opacity: opacity,
                smooth: false,
              )) {
                final pb = p.path.bounds;
                expect(
                  s.bounds.inflate(0.01).contains(pb.topLeft) &&
                      s.bounds.inflate(0.01).contains(pb.bottomRight),
                  isTrue,
                  reason: '${tool.name} q=$q: $pb outside ${s.bounds}',
                );
                expect(p.opacity, inInclusiveRange(0.0, 1.0));
              }
            }
          }
        }
      });
    }
  });

  group('PDF export (exportStrokes)', () {
    for (final tool in _decor) {
      test(tool.name, () {
        final s = InkStroke.of(_sCurve(tool));
        final v = InkVectorExport.exportStrokes([s]);
        final pieces = penRendererOf(tool).vectorPieces(
          s,
          OutlineGenerator.outline(s),
          opacity: 1,
          smooth: true,
        );
        expect(v.inkShapes, hasLength(pieces.length));
        expect(v.inkShapes.length, greaterThan(1), reason: 'layered');
        for (var i = 0; i < pieces.length; i++) {
          final shape = v.inkShapes[i];
          expect(shape.strokeId, s.id);
          expect(shape.tool, tool);
          expect(shape.colorArgb ~/ 0x1000000, 0xFF, reason: 'K-5');
          expect(shape.colorArgb, pieces[i].colorArgb);
          expect(shape.opacity, pieces[i].opacity);
          final pb = shape.path.bounds;
          expect(
            s.bounds.inflate(0.01).contains(pb.topLeft) &&
                s.bounds.inflate(0.01).contains(pb.bottomRight),
            isTrue,
          );
        }
      });
    }
  });

  group('rainbow', () {
    test('the palette starts at the pen color; gray starts at red', () {
      expect(rainbowStart(0xFF808080), 0);
      expect(rainbowStart(0xFFFF4D6D), 0);
      final (blueHue, _, _) = hsvOf(rainbowAt(rainbowStart(0xFF2F80ED)));
      expect(blueHue, closeTo(210, 25));
      final (greenHue, _, _) = hsvOf(rainbowAt(rainbowStart(0xFF00C853)));
      expect(greenHue, closeTo(145, 25));
      // the first band of a blue stroke is blue
      final s = InkStroke.of(_sCurve(core.PenTool.rainbow, color: 0xFF2F80ED));
      final first = penRendererOf(core.PenTool.rainbow)
          .vectorPieces(
            s,
            OutlineGenerator.outline(s),
            opacity: 1,
            smooth: true,
          )
          .first;
      final (h, _, _) = hsvOf(first.colorArgb);
      expect(h, closeTo(210, 30));
    });

    test('pieces: one per palette step (+ 2 gloss lines), whatever the length; '
        'a round keeps ≥ 36 steps from 1 pt', () {
      final s = InkStroke.of(
        strokeThrough(
          segment(const ui.Offset(0, 50), const ui.Offset(6000, 50), step: 4),
          core.StrokeStyle.defaultsFor(core.PenTool.rainbow),
        ),
      );
      final pieces = penRendererOf(
        core.PenTool.rainbow,
      ).vectorPieces(s, OutlineGenerator.outline(s), opacity: 1, smooth: true);
      final (nc, _) = rainbowBands(s.style.width);
      expect(pieces.length, lessThanOrEqualTo(nc + 2));
      for (final w in [1.0, 2.0, 6.0, 30.0]) {
        expect(rainbowBands(w).$1, greaterThanOrEqualTo(36), reason: '$w');
      }
    });

    test('the period does not depend on the length: the colors of a stroke\'s '
        'start stay put while it grows (stored and live)', () async {
      final full = _sCurve(core.PenTool.rainbow, width: 6, n: 80);
      final short = _prefix(full, 40);
      final xEnd = short.points.x(30);
      for (final live in [false, true]) {
        Future<Uint8List> draw(core.Stroke cs) => _paint((c) {
          c.clipRect(ui.Rect.fromLTRB(0, 0, xEnd, _size.toDouble()));
          final s = InkStroke.of(cs);
          if (live) {
            _paintLive(c, s);
          } else {
            paintFillStroke(c, s, OutlineGenerator.outline(s));
          }
        });
        expect(
          _diffShare(await draw(short), await draw(full), tol: 40),
          lessThan(0.02),
          reason: live ? 'live' : 'stored',
        );
      }
    });

    test('translucent: the PDF pieces do not overlap (same mean color as the '
        'screen layer)', () async {
      for (final paper in [0xFFFFFFFF, 0xFF202124]) {
        final s = InkStroke.of(
          _sCurve(core.PenTool.rainbow, width: 6).copyWith(
            style: core.StrokeStyle.defaultsFor(core.PenTool.rainbow)
                .copyWith(width: 6, opacity: 0.5),
          ),
        );
        Future<List<double>> mean(void Function(ui.Canvas) paint) async {
          final px = await renderPixels(_size, _size, (c) {
            paintPaper(c, paper);
            paint(c);
          });
          final a = px.bytes.buffer.asUint8List();
          final sum = [0.0, 0.0, 0.0];
          var n = 0;
          final b = s.bounds;
          for (var y = b.top.floor(); y < b.bottom.ceil(); y++) {
            for (var x = b.left.floor(); x < b.right.ceil(); x++) {
              final i = (y * _size + x) * 4;
              for (var k = 0; k < 3; k++) {
                sum[k] += a[i + k];
              }
              n++;
            }
          }
          return [for (final v in sum) v / n];
        }

        final screen = await mean(
          (c) => paintFillStroke(c, s, OutlineGenerator.outline(s)),
        );
        final pdf = await mean((c) => _paintPieces(c, s));
        for (var k = 0; k < 3; k++) {
          expect(pdf[k], closeTo(screen[k], 1.5), reason: '$paper ch$k');
        }
      }
    });

    test('a dot is the banded bead (no color wheel), the same live and '
        'stored', () async {
      final s = InkStroke.of(
        strokeThrough(
          [const ui.Offset(100, 100)],
          core.StrokeStyle.defaultsFor(core.PenTool.rainbow)
              .copyWith(width: 30),
        ),
      );
      final pieces = penRendererOf(
        core.PenTool.rainbow,
      ).vectorPieces(s, OutlineGenerator.outline(s), opacity: 1, smooth: true);
      // ≥ 10 bands + rim + gloss + specular; no wedge reaches the center
      expect(pieces.length, greaterThan(13));
      final stored = await _paint(
        (c) => paintFillStroke(c, s, OutlineGenerator.outline(s)),
      );
      final live = await _paint((c) => _paintLive(c, s));
      expect(_diffShare(stored, live), lessThan(0.01));
    });
  });

  group('live frames as the stroke grows = the stored stroke', () {
    for (final tool in _decor) {
      test(tool.name, () async {
        final full = _sCurve(tool, width: 6, n: 120, length: 170);
        final s = InkStroke.of(full);
        // frames of a growing stroke (the kept parts carry over), then the
        // last frame is painted
        final rec = ui.PictureRecorder();
        final scratch = ui.Canvas(rec);
        for (var n = 2; n < full.points.length; n += 7) {
          _paintLive(scratch, InkStroke.of(_prefix(full, n)));
        }
        rec.endRecording().dispose();
        final live = await _paint((c) => _paintLive(c, s));
        final fresh = await _paint((c) {
          // the same frame without kept parts: another seed key first
          _paintLive(
            ui.Canvas(ui.PictureRecorder()),
            InkStroke.of(_copy(full)),
          );
          _paintLive(c, s);
        });
        expect(_diffShare(live, fresh, tol: 8), lessThan(0.002));
        final committed = await _paint(
          (c) => paintFillStroke(c, s, OutlineGenerator.outline(s)),
        );
        expect(_diffShare(committed, live, tol: 40), lessThan(0.04));
      });
    }
  });

  group('glitter cost and growth', () {
    test('a thin, long stroke: bounded pieces and live frames', () {
      for (final w in [0.1, 0.3, 1.0]) {
        final cs = strokeThrough(
          [
            for (var i = 0; i <= 1500; i++)
              ui.Offset(10 + i * 2.0, 100 + 30 * math.sin(i / 40)),
          ],
          core.StrokeStyle.defaultsFor(core.PenTool.glitter).copyWith(width: w),
        );
        final s = InkStroke.of(cs);
        final pieces = glitterPieces(s);
        var coords = 0;
        for (final p in pieces) {
          coords += p.path.coords.length;
        }
        // ~3,000 pt: the grain and star spacing has a floor in pt and thins
        // out in blocks, so the size per pt stays small at every width
        expect(coords, lessThan(400000), reason: 'w=$w coords $coords');
        // live: 40 frames of the growing stroke; the last ones stay cheap
        final rec = ui.PictureRecorder();
        final canvas = ui.Canvas(rec);
        var worst = 0;
        for (var n = 1300; n <= 1500; n += 5) {
          final f = InkStroke.of(_prefix(cs, n));
          final sw = Stopwatch()..start();
          _paintLive(canvas, f, withOutline: false);
          sw.stop();
          if (n > 1310) worst = math.max(worst, sw.elapsedMicroseconds);
        }
        rec.endRecording().dispose();
        // ignore: avoid_print
        print(
          'glitter w=$w: $coords coords, worst live frame ${worst / 1000} ms',
        );
        expect(worst, lessThan(30000), reason: 'w=$w');
      }
    });

    test('grains are never moved as the stroke grows (past the first block)', () {
      final full = _sCurve(
        core.PenTool.glitter,
        width: 6,
        penDown: 9000,
        n: 700,
        length: 900,
      );
      final part = _prefix(full, full.points.length * 7 ~/ 10);
      final big = <String>{};
      final starts = sparkleStartsOf(InkStroke.of(full));
      for (var i = 0; i + 1 < starts.length; i += 2) {
        big.add(
          '${starts[i].toStringAsFixed(2)},${starts[i + 1].toStringAsFixed(2)}',
        );
      }
      final small = sparkleStartsOf(InkStroke.of(part));
      var found = 0;
      for (var i = 0; i + 1 < small.length; i += 2) {
        if (big.contains(
          '${small[i].toStringAsFixed(2)},${small[i + 1].toStringAsFixed(2)}',
        )) {
          found++;
        }
      }
      expect(small.length / 2, greaterThan(2600), reason: 'past one block');
      expect(found / (small.length / 2), greaterThan(0.98));
    });

    test('a dot has at most two stars', () {
      final s = InkStroke.of(
        strokeThrough([
          const ui.Offset(100, 100),
        ], core.StrokeStyle.defaultsFor(core.PenTool.glitter)),
      );
      final centers = penRendererOf(core.PenTool.glitter)
          .vectorPieces(
            s,
            OutlineGenerator.outline(s),
            opacity: 1,
            smooth: true,
          )
          .where((p) => p.colorArgb == 0xFFFFFFFF && p.opacity == 0.9)
          .single;
      final stars = centers.path.verbs
          .where((v) => v == InkPathVerb.moveTo.index)
          .length;
      expect(stars, inInclusiveRange(1, 2));
    });
  });

  test('the geometry cache keeps to its budget', () {
    clearDecorGeometry();
    for (var i = 0; i < 300; i++) {
      for (final tool in [core.PenTool.glitter, core.PenTool.rainbow]) {
        final s = InkStroke.of(
          strokeThrough(
            segment(ui.Offset(10, 10.0 + i), ui.Offset(310, 10.0 + i), step: 1),
            core.StrokeStyle.defaultsFor(tool).copyWith(width: 4),
          ),
        );
        penRendererOf(tool).vectorPieces(
          s,
          OutlineGenerator.outline(s),
          opacity: 1,
          smooth: true,
        );
      }
    }
    final stats = decorGeometryStats;
    expect(stats.bytes, lessThanOrEqualTo(kDecorGeometryBudgetBytes));
    expect(stats.entries, lessThan(600), reason: 'old strokes were dropped');
    clearDecorGeometry();
  });

  test('K-1 at the thinnest widths', () {
    for (final tool in _decor) {
      for (final w in [0.1, 0.15, 0.3]) {
        final style = core.StrokeStyle.defaultsFor(tool).copyWith(width: w);
        for (final pts in [
          segment(const ui.Offset(60, 100), const ui.Offset(140, 120)),
          [const ui.Offset(100, 100)],
        ]) {
          final s = InkStroke.of(strokeThrough(pts, style));
          for (final p in penRendererOf(tool).vectorPieces(
            s,
            OutlineGenerator.outline(s),
            opacity: 1,
            smooth: false,
          )) {
            final pb = p.path.bounds;
            expect(
              s.bounds.inflate(0.001).contains(pb.topLeft) &&
                  s.bounds.inflate(0.001).contains(pb.bottomRight),
              isTrue,
              reason: '${tool.name} w=$w: $pb outside ${s.bounds}',
            );
          }
        }
      }
    }
  });

  test('neon and glitter: no pressure response (widthQ fixed)', () {
    for (final tool in [core.PenTool.neon, core.PenTool.glitter]) {
      final s = _sCurve(tool);
      final p = s.points;
      for (var i = 0; i < p.length; i++) {
        expect(p.widthQ(i), core.kNominalWidthQ, reason: tool.name);
      }
    }
  });

  test('cost: layers of a 2,000-point stroke (record time)', () {
    for (final tool in _decor) {
      final s = InkStroke.of(_sCurve(tool, n: 2000, length: 1800, width: 6));
      final sw = Stopwatch()..start();
      final pieces = penRendererOf(
        tool,
      ).vectorPieces(s, OutlineGenerator.outline(s), opacity: 1, smooth: true);
      sw.stop();
      // ignore: avoid_print
      print(
        '${tool.name}: ${pieces.length} pieces, '
        '${sw.elapsedMicroseconds / 1000} ms',
      );
      // a loose bound (CI machines vary): the budget is ~8 ms
      expect(sw.elapsedMilliseconds, lessThan(250), reason: tool.name);
    }
  });

  test('cost: one live frame of a 500-point stroke (recording)', () {
    for (final tool in _decor) {
      final s = InkStroke.of(_sCurve(tool, n: 500, length: 450, width: 6));
      final rec = ui.PictureRecorder();
      final canvas = ui.Canvas(rec);
      _paintLive(canvas, s); // warm-up
      final sw = Stopwatch()..start();
      for (var i = 0; i < 10; i++) {
        _paintLive(canvas, s);
      }
      sw.stop();
      rec.endRecording().dispose();
      // ignore: avoid_print
      print('${tool.name} live: ${sw.elapsedMicroseconds / 10000} ms / frame');
      expect(sw.elapsedMilliseconds / 10, lessThan(50), reason: tool.name);
    }
  });
}

/// The glitter pieces of [s] (body first).
List<PenVectorPiece> glitterPieces(InkStroke s) =>
    penRendererOf(core.PenTool.glitter)
        .vectorPieces(s, OutlineGenerator.outline(s), opacity: 1, smooth: true)
        .where((p) => p.colorArgb != opaqueArgb(kRimArgb))
        .toList();

/// The start point of every contour of the grain and star pieces.
List<double> sparkleStartsOf(InkStroke s) {
  final out = <double>[];
  for (final p in glitterPieces(s).skip(1)) {
    var c = 0;
    for (final v in p.path.verbs) {
      if (v == InkPathVerb.moveTo.index) {
        out
          ..add(p.path.coords[c])
          ..add(p.path.coords[c + 1]);
        c += 2;
      } else if (v == InkPathVerb.lineTo.index) {
        c += 2;
      } else if (v == InkPathVerb.cubicTo.index) {
        c += 6;
      }
    }
  }
  return out;
}
