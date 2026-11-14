// (v2.11, C211-01) Regressions from the texture track review:
//   * cost: the spine stays near the input points (no 6× oversampling), and a
//     page's PDF stays within a fixed multiple of the plain outline coordinates;
//   * memory: the geometry cache stays inside its budget (least recently used out);
//   * the PDF tone matches the screen (ink coverage within ±15 %), the live
//     stroke matches the committed one, and the live chunks' joints are not darker;
//   * short strokes: the brush does not fork, the watercolor is not a diamond;
//   * the watercolor's recolor preview uses the preview color's light boost.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/geometry/outline_generator.dart';
import 'package:ink_engine/src/render/pens/pen_renderer.dart';
import 'package:ink_engine/src/render/pens/texture/texture_geometry.dart';
import 'package:ink_engine/src/render/stroke_painter.dart';
import 'package:note_core/note_core.dart' as core;

import '../../../../support/pixels.dart';

const int _n = 220;

double _coverage(ByteData b) {
  var s = 0;
  for (var i = 3; i < b.lengthInBytes; i += 4) {
    s += b.getUint8(i);
  }
  return s / 255;
}

InkStroke _wave(core.PenTool tool, double widthQ, {double width = 6}) {
  final style = core.StrokeStyle.defaultsFor(tool).copyWith(width: width);
  final pts = [
    for (var i = 0; i <= 80; i++)
      ui.Offset(20 + 2.2 * i, 110 + 50 * math.sin(i / 13)),
  ];
  return InkStroke.of(
    strokeThrough(pts, style, widthQ: widthQ, id: '${tool.name}-$widthQ'),
  );
}

Future<double> _screen(InkStroke s, ui.Image? grain) async => _coverage(
  (await renderPixels(_n, _n, (c) {
    paintFillStroke(c, s, OutlineGenerator.outline(s), grain: grain);
  })).bytes,
);

Future<double> _pdf(InkStroke s) async {
  // what vector_export does: the pencil grain factor for the pencil only
  final factor = s.style.tool == core.PenTool.pencil
      ? InkTuning.exportPencilOpacityFactor
      : 1.0;
  final pieces = penRendererOf(s.style.tool).vectorPieces(
    s,
    OutlineGenerator.outline(s),
    opacity: strokeOpacity(s) * factor,
    smooth: true,
  );
  return _coverage(
    (await renderPixels(_n, _n, (c) {
      for (final p in pieces) {
        c.drawPath(
          p.path.toUiPath()..fillType = ui.PathFillType.nonZero,
          ui.Paint()..color = inkColor(p.colorArgb, p.opacity),
        );
      }
    })).bytes,
  );
}

const List<core.PenTool> _pens = [
  core.PenTool.pencil,
  core.PenTool.brush,
  core.PenTool.crayon,
  core.PenTool.chalk,
  core.PenTool.watercolor,
  core.PenTool.spray,
];

void main() {
  late PencilGrain grainSource;
  late ui.Image grain;

  setUpAll(() async {
    grainSource = PencilGrain();
    grain = await grainSource.ready;
  });
  tearDownAll(() => grainSource.dispose());

  group('cost', () {
    test('the spine: about one sample per 0.4 width, at most 2 per input '
        'point, at least one per width', () {
      final style = core.StrokeStyle.defaultsFor(core.PenTool.crayon)
          .copyWith(width: 1.4);
      // dense input: 150 points 0.3 pt apart
      final dense = InkStroke.of(
        strokeThrough([
          for (var i = 0; i < 150; i++)
            ui.Offset(10 + 0.3 * i, 10 + 3 * math.sin(i / 9)),
        ], style),
      );
      expect(Spine.of(dense).n, lessThanOrEqualTo(2 * 150 + 2));
      // sparse input: a 300 pt line from 2 points keeps its ragged edge
      final sparse = InkStroke.of(
        strokeThrough(const [ui.Offset(10, 10), ui.Offset(310, 10)], style),
      );
      expect(Spine.of(sparse).n, greaterThanOrEqualTo(300 ~/ 1.4));
    });

    test('a page of short strokes exports within a fixed multiple of the '
        'plain outline coordinates', () {
      int coords(core.PenTool tool) {
        final style = core.StrokeStyle.defaultsFor(tool);
        var sum = 0;
        for (var k = 0; k < 120; k++) {
          final ox = (k % 12) * 40.0, oy = (k ~/ 12) * 50.0;
          final s = InkStroke.of(
            strokeThrough(
              [
                for (var i = 0; i <= 40; i++)
                  ui.Offset(
                    ox + 10 + i * 0.9,
                    oy + 20 + 10 * math.sin(i / 6 + k),
                  ),
              ],
              style,
              widthQ: 0.2 + 0.1 * math.sin(k.toDouble()),
              id: '${tool.name}-$k',
            ),
          );
          for (final p in penRendererOf(tool).vectorPieces(
            s,
            OutlineGenerator.outline(s),
            opacity: 1,
            smooth: true,
          )) {
            sum += p.path.coords.length;
          }
        }
        return sum;
      }

      final plain = coords(core.PenTool.ballpoint);
      // measured after the review: brush 1.35, crayon 4.0, chalk 7.4,
      // watercolor 8.8, spray 13.5 (the original track: 2.7 … 17)
      const limits = {
        core.PenTool.pencil: 1.05,
        core.PenTool.brush: 1.6,
        core.PenTool.crayon: 4.6,
        core.PenTool.chalk: 8.5,
        core.PenTool.watercolor: 10.0,
        core.PenTool.spray: 15.5,
      };
      for (final MapEntry(key: tool, value: limit) in limits.entries) {
        expect(
          coords(tool) / plain,
          lessThanOrEqualTo(limit),
          reason: tool.name,
        );
      }
    });

    test('the geometry cache stays inside its budget', () {
      TextureGeometryCache.clear();
      final style = core.StrokeStyle.defaultsFor(core.PenTool.chalk);
      final strokes = [
        for (var k = 0; k < 160; k++)
          InkStroke.of(
            strokeThrough(
              [
                for (var i = 0; i <= 600; i++)
                  ui.Offset(
                    300 + (40 + i * 0.4) * math.cos(i / 15 + k),
                    300 + (40 + i * 0.4) * math.sin(i / 15 + k),
                  ),
              ],
              style,
              id: 'spiral-$k',
            ),
          ),
      ];
      for (final s in strokes) {
        penRendererOf(core.PenTool.chalk).vectorPieces(
          s,
          OutlineGenerator.outline(s),
          opacity: 1,
          smooth: false,
        );
        expect(
          TextureGeometryCache.bytes,
          lessThanOrEqualTo(InkTuning.textureGeometryBudgetBytes),
        );
      }
      expect(TextureGeometryCache.length, lessThan(strokes.length));
      // the most recent strokes are kept: the same pieces again
      final last = strokes.last;
      List<Float32List> pieces() => [
        for (final p in penRendererOf(core.PenTool.chalk).vectorPieces(
          last,
          OutlineGenerator.outline(last),
          opacity: 1,
          smooth: false,
        ))
          p.path.coords,
      ];
      expect(pieces(), pieces());
      TextureGeometryCache.clear();
    });
  });

  group('tone', () {
    for (final tool in _pens) {
      test('${tool.name}: PDF ≈ screen, live ≈ committed', () async {
        for (final wq in [0.1, 0.25, 0.4]) {
          final s = _wave(tool, wq);
          final screen = await _screen(s, grain);
          final pdf = await _pdf(s);
          expect(
            pdf / screen,
            inInclusiveRange(0.85, 1.15),
            reason: '${tool.name} widthQ $wq: PDF $pdf vs screen $screen',
          );
          final outline = OutlineGenerator.outline(s);
          final live = _coverage(
            (await renderPixels(
              _n,
              _n,
              (c) => penRendererOf(tool).paintLive(
                c,
                PenLiveFrame(
                  style: s.style,
                  paths: [outline.toPath()],
                  centerline: [
                    for (var i = 0; i < s.points.length; i++)
                      s.points.offsetAt(i),
                  ],
                  bounds: s.bounds.inflate(1),
                  opacity: strokeOpacity(s),
                  seed: s.source.createdAt,
                  grain: s.profile.textured ? grain : null,
                ),
              ),
            )).bytes,
          );
          expect(
            live / screen,
            inInclusiveRange(0.82, 1.18),
            reason: '${tool.name} widthQ $wq: live $live vs committed $screen',
          );
        }
      });
    }

    test('the live chunks overlap without a darker joint', () async {
      for (final tool in [
        core.PenTool.watercolor,
        core.PenTool.chalk,
        core.PenTool.crayon,
      ]) {
        final style = core.StrokeStyle.defaultsFor(tool).copyWith(width: 8);
        // two chunks overlapping on x ∈ [70, 90]
        final a = ui.Path()..addRect(const ui.Rect.fromLTRB(20, 40, 90, 80));
        final b = ui.Path()..addRect(const ui.Rect.fromLTRB(70, 40, 140, 80));
        for (final g in [grain, null]) {
          Future<double> cover(List<ui.Path> paths, ui.Rect area) async {
            final px = await renderPixels(
              _n,
              _n,
              (c) => penRendererOf(tool).paintLive(
                c,
                PenLiveFrame(
                  style: style,
                  paths: paths,
                  centerline: const [ui.Offset(20, 60), ui.Offset(140, 60)],
                  bounds: const ui.Rect.fromLTRB(0, 0, 160, 120),
                  opacity: 1,
                  seed: 1,
                  grain: g,
                ),
              ),
            );
            var sum = 0;
            for (var y = area.top.toInt(); y < area.bottom; y++) {
              for (var x = area.left.toInt(); x < area.right; x++) {
                sum += px.bytes.getUint8((y * _n + x) * 4 + 3);
              }
            }
            return sum.toDouble();
          }

          const joint = ui.Rect.fromLTRB(72, 44, 88, 76);
          final split = await cover([a, b], joint);
          final whole = await cover([
            ui.Path()..addRect(const ui.Rect.fromLTRB(20, 40, 140, 80)),
          ], joint);
          expect(split, whole, reason: '${tool.name} (grain: ${g != null})');
        }
      }
    });
  });

  group('short strokes', () {
    test('a short brush bar never forks; a long one dries', () {
      final style = core.StrokeStyle.defaultsFor(core.PenTool.brush);
      final w = style.width;
      final short = InkStroke.of(
        strokeThrough(
          segment(const ui.Offset(20, 20), ui.Offset(20 + 2.5 * w, 20)),
          style,
          widthQ: 0.15,
        ),
      );
      final outline = OutlineGenerator.outline(short);
      final piece = penRendererOf(core.PenTool.brush)
          .vectorPieces(short, outline, opacity: 1, smooth: false)
          .single;
      expect(
        piece.path.coords.length,
        outline.toVectorPath(smooth: false).coords.length,
      );
      final long = InkStroke.of(
        strokeThrough(
          segment(const ui.Offset(20, 20), ui.Offset(20 + 120 * w, 20)),
          style,
          widthQ: 0.15,
        ),
      );
      final longOutline = OutlineGenerator.outline(long);
      expect(
        penRendererOf(core.PenTool.brush)
            .vectorPieces(long, longOutline, opacity: 1, smooth: false)
            .single
            .path
            .coords
            .length,
        greaterThan(longOutline.toVectorPath(smooth: false).coords.length),
        reason: 'dry-brush gaps on a long stroke',
      );
    });

    test('a short watercolor bar keeps its width (no diamond)', () async {
      final style = core.StrokeStyle.defaultsFor(core.PenTool.watercolor);
      final w = style.width;
      final s = InkStroke.of(
        strokeThrough(
          segment(const ui.Offset(40, 100), ui.Offset(40 + 2 * w, 100)),
          style,
          widthQ: 0.25,
        ),
      );
      final px = await renderPixels(_n, _n, (c) {
        paintFillStroke(c, s, OutlineGenerator.outline(s), grain: grain);
      });
      int height(double x) {
        var n = 0;
        for (var y = 0; y < _n; y++) {
          if (px.bytes.getUint8((y * _n + x.round()) * 4 + 3) > 20) n++;
        }
        return n;
      }

      // a quarter of the way along vs the middle (a diamond: about half)
      expect(height(40 + 0.5 * w) / height(40 + w), greaterThan(0.75));
    });
  });

  test(
    'watercolor recolor preview: the preview color sets the boost',
    () async {
      // dark stroke color, white preview color: light colors are boosted
      final s = _wave(core.PenTool.watercolor, 0.25);
      final o = OutlineGenerator.outline(s);
      Future<double> paint(int argb) async => _coverage(
        (await renderPixels(
          _n,
          _n,
          (c) =>
              penRendererOf(core.PenTool.watercolor)
                  .paintCommitted(c, s, o, colorArgb: argb, opacity: 1),
        )).bytes,
      );
      expect(
        await paint(0xFFFFFFFF),
        greaterThan(await paint(0xFF1A237E) * 1.3),
      );
    },
  );
}
