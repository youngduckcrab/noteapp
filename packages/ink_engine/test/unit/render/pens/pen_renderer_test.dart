// (v2.11, C211-01) The per-pen renderer dispatch (render/pens/pen_renderer.dart)
// — FOUNDATION TEST, shared by the texture and decor tracks:
//   * every tool has a renderer; the pens without their own are the plain fill;
//   * K-1 for every renderer: no painted pixel and no PDF piece outside
//     core.Stroke.bounds (straight line, S curve, dot; three widths);
//   * determinism: two paints of the same stroke give the same bytes, and the
//     vector pieces are equal;
//   * PenRandom / penSeed: fixed sequences (VM = web — arithmetic only).
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/geometry/outline_generator.dart';
import 'package:ink_engine/src/render/pens/pen_random.dart';
import 'package:ink_engine/src/render/pens/pen_renderer.dart';
import 'package:ink_engine/src/render/stroke_painter.dart';
import 'package:note_core/note_core.dart' as core;

import '../../../support/pixels.dart';

const int _size = 160;

/// Strokes of [tool] at [width]: a straight line, an S curve, a dot.
List<core.Stroke> _strokes(core.PenTool tool, double width) {
  final style = core.StrokeStyle.defaultsFor(tool).copyWith(width: width);
  return [
    strokeThrough(
      segment(const ui.Offset(40, 80), const ui.Offset(120, 80)),
      style,
      id: '${tool.name}-line-$width',
    ),
    strokeThrough(
      [
        for (var i = 0; i <= 40; i++)
          ui.Offset(40 + 2.0 * i, 80 - 25 * math.sin(i / 40 * 2 * math.pi)),
      ],
      style,
      widthQ: 1.4,
      id: '${tool.name}-s-$width',
    ),
    strokeThrough(
      const [ui.Offset(80, 80)],
      style,
      id: '${tool.name}-dot-$width',
    ),
  ];
}

Future<Uint8List> _paint(InkStroke s) async {
  final px = await renderPixels(_size, _size, (canvas) {
    paintFillStroke(canvas, s, OutlineGenerator.outline(s));
  });
  return px.bytes.buffer.asUint8List();
}

void main() {
  test('every tool has a renderer; the plain fill where none is written', () {
    for (final t in core.PenTool.values) {
      expect(penRendererOf(t), isA<PenRenderer>(), reason: t.name);
    }
    for (final t in [
      core.PenTool.ballpoint,
      core.PenTool.fountain,
      core.PenTool.highlighter,
      core.PenTool.marker,
      core.PenTool.calligraphy,
      core.PenTool.dashed,
      core.PenTool.laser,
      core.PenTool.tape,
    ]) {
      expect(penRendererOf(t), same(PenRenderer.fill), reason: t.name);
    }
  });

  group('K-1 and determinism for every ink-layer pen', () {
    for (final tool in core.PenTool.values) {
      if (PenProfile.of(tool).layer != InkLayer.ink) continue;
      test(tool.name, () async {
        for (final width in [1.0, 4.0, 12.0]) {
          for (final source in _strokes(tool, width)) {
            final s = InkStroke.of(source);
            final b = s.bounds;
            final a = await _paint(s);
            expect(await _paint(s), a, reason: '${source.id} repaint');
            // pixels: none outside bounds (1 px anti-aliasing allowance)
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
            expect(outside, 0, reason: '${source.id}: pixels outside bounds');
            // PDF pieces: inside bounds, the same twice
            final outline = OutlineGenerator.outline(s);
            final r = penRendererOf(tool);
            final p1 = r.vectorPieces(s, outline, opacity: 1, smooth: true);
            final p2 = r.vectorPieces(s, outline, opacity: 1, smooth: true);
            expect(p1, isNotEmpty, reason: source.id);
            expect(p1.length, p2.length);
            for (var i = 0; i < p1.length; i++) {
              expect(p1[i].colorArgb, p2[i].colorArgb);
              expect(p1[i].opacity, p2[i].opacity);
              expect(p1[i].path.coords, p2[i].path.coords);
              expect(p1[i].colorArgb ~/ 0x1000000, 0xFF, reason: 'K-5');
              final pb = p1[i].path.bounds;
              expect(
                b.inflate(0.01).contains(pb.topLeft) &&
                    b.inflate(0.01).contains(pb.bottomRight),
                isTrue,
                reason: '${source.id}: piece $i $pb outside $b',
              );
            }
          }
        }
      });
    }
  });

  test('the plain fill: one PDF piece = the outline, color and opacity', () {
    final s = InkStroke.of(_strokes(core.PenTool.ballpoint, 2).first);
    final outline = OutlineGenerator.outline(s);
    final pieces = PenRenderer.fill.vectorPieces(
      s,
      outline,
      opacity: 0.5,
      smooth: true,
    );
    expect(pieces, hasLength(1));
    expect(pieces.single.path.coords, outline.toVectorPath().coords);
    expect(pieces.single.colorArgb, opaqueArgb(s.style.colorArgb));
    expect(pieces.single.opacity, 0.5);
  });

  test('PenRandom / penSeed: fixed, platform-independent sequences', () {
    final r = PenRandom(1);
    expect(
      [for (var i = 0; i < 3; i++) r.next()],
      [48271 / 2147483647, 182605794 / 2147483647, 1291394886 / 2147483647],
    );
    expect(PenRandom(0).next(), PenRandom(1).next(), reason: '0 → 1');
    expect(penSeed([1, 2.5, -3]), penSeed([1, 2.5, -3]));
    expect(penSeed([1, 2.5]), isNot(penSeed([2.5, 1])));
    expect(penSeed([0.01]), penSeed([0.02]), reason: '1/16 pt quantum');
    final seed = penSeed([1793750400000, 12.25, 80]);
    expect(seed, inInclusiveRange(1, 2147483646));
    final g = PenRandom(seed);
    for (var i = 0; i < 1000; i++) {
      final v = g.next();
      expect(v > 0 && v < 1, isTrue);
      expect(g.nextInt(7), inInclusiveRange(0, 6));
    }
  });
}
