// (v2.11, C211-01) The texture pens (render/pens/texture/) with the paper
// tiles ready — the textured look the foundation test (pen_renderer_test.dart,
// grain null → flat look) does not reach:
//   * K-1: no painted pixel and no PDF piece outside core.Stroke.bounds
//     (line, S curve, dot, a real pressure stroke; widths 1 / 4 / 12 pt);
//   * determinism: two paints give the same bytes, the pieces are equal, and a
//     different createdAt gives a different texture (the seed is the stroke's);
//   * pressure: harder strokes cover more (crayon, chalk, spray);
//   * the PDF export: every pen's pieces carry the stroke id and tool, opaque
//     colors and opacity in (0, 1], inside the bounds;
//   * the live paint works with and without the tiles;
//   * the tiles: channels equalized, fixed checksum, generated once with the grain;
//   (the review regressions — cost, cache, PDF tone, live look, short strokes —
//   are in texture_review_test.dart)
//   * the texture files use no bit operators (7.4.3, web = VM).
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/geometry/outline_generator.dart';
import 'package:ink_engine/src/interop/core_interop.dart' as interop;
import 'package:ink_engine/src/render/pens/pen_renderer.dart';
import 'package:ink_engine/src/render/pens/texture/texture_geometry.dart';
import 'package:ink_engine/src/render/pens/texture/texture_tiles.dart';
import 'package:ink_engine/src/render/stroke_painter.dart';
import 'package:ink_engine/src/stroke/stroke_builder.dart';
import 'package:note_core/note_core.dart' as core;

import '../../../../support/grain_checksum.dart';
import '../../../../support/pixels.dart';
import '../../../../support/texture_tile_checksum.dart';

const int _size = 160;

const List<core.PenTool> _tools = [
  core.PenTool.pencil,
  core.PenTool.brush,
  core.PenTool.crayon,
  core.PenTool.chalk,
  core.PenTool.watercolor,
  core.PenTool.spray,
];

/// A stylus S curve through the real pipeline (pressure swell).
core.Stroke _real(
  core.PenTool tool,
  double width, {
  double pressure = -1,
  int createdAt = 1793750400000,
  String id = 'real',
}) {
  final samples = <InkSample>[];
  for (var i = 0; i < 60; i++) {
    final u = i / 59;
    samples.add(
      InkSample(
        position: ui.Offset(30 + 100 * u, 80 + 30 * math.sin(u * 2 * math.pi)),
        timeUs: i * 8333,
        kind: InkPointerKind.stylus,
        pressure: pressure >= 0
            ? pressure + 0.05 * math.sin(u * 7)
            : 0.1 + 0.85 * math.sin(u * math.pi),
      ),
    );
  }
  final style = core.StrokeStyle.defaultsFor(tool).copyWith(width: width);
  return interop.newCoreStroke(
    buildStroke(samples, style: style, viewScale: 1)!,
    id: '$id-${tool.name}-$width',
    pageId: 'p',
    penDownMillis: createdAt,
  );
}

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
      widthQ: 0.35,
      id: '${tool.name}-s-$width',
    ),
    strokeThrough(
      const [ui.Offset(80, 80)],
      style,
      id: '${tool.name}-dot-$width',
    ),
    _real(tool, width),
  ];
}

Future<Uint8List> _paint(InkStroke s, ui.Image grain) async {
  final px = await renderPixels(_size, _size, (canvas) {
    paintFillStroke(canvas, s, OutlineGenerator.outline(s), grain: grain);
  });
  return px.bytes.buffer.asUint8List();
}

double _meanAlpha(Uint8List rgba) {
  var sum = 0;
  for (var i = 3; i < rgba.length; i += 4) {
    sum += rgba[i];
  }
  return sum / (rgba.length / 4) / 255;
}

void main() {
  late PencilGrain grainSource;
  late ui.Image grain;

  setUpAll(() async {
    grainSource = PencilGrain();
    grain = await grainSource.ready;
  });
  tearDownAll(() => grainSource.dispose());

  test('the grain comes with the tiles (grain ready ⇒ tiles ready)', () {
    final tiles = TextureTiles.of(grain);
    expect(tiles, isNotNull);
    expect(tiles!.tooth.width, kTextureTileSize);
    expect(tiles.wash.height, kTextureTileSize);
    expect(TextureTiles.of(null), isNull);
  });

  group('K-1 and determinism with the tiles', () {
    for (final tool in _tools) {
      test(tool.name, () async {
        // (review) also a hairline and a very wide stroke
        for (final width in [0.3, 1.0, 4.0, 12.0, 30.0]) {
          for (final source in _strokes(tool, width)) {
            final s = InkStroke.of(source);
            final b = s.bounds;
            final a = await _paint(s, grain);
            expect(await _paint(s, grain), a, reason: '${source.id} repaint');
            expect(_meanAlpha(a), greaterThan(0), reason: '${source.id} empty');
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
            final outline = OutlineGenerator.outline(s);
            final r = penRendererOf(tool);
            final p1 = r.vectorPieces(s, outline, opacity: 0.8, smooth: true);
            final p2 = r.vectorPieces(s, outline, opacity: 0.8, smooth: true);
            expect(p1, isNotEmpty);
            expect(p1.length, p2.length);
            for (var i = 0; i < p1.length; i++) {
              expect(p1[i].path.coords, p2[i].path.coords);
              expect(p1[i].opacity, p2[i].opacity);
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

  test(
    'the texture follows the stroke (createdAt seed), not the clock',
    () async {
      for (final tool in [core.PenTool.crayon, core.PenTool.chalk]) {
        final a = InkStroke.of(_real(tool, 6, id: 'a'));
        final b = InkStroke.of(
          _real(tool, 6, id: 'b', createdAt: 1793750499999),
        );
        final a2 = InkStroke.of(_real(tool, 6, id: 'a2'));
        expect(
          await _paint(a, grain),
          await _paint(a2, grain),
          reason: tool.name,
        );
        expect(
          await _paint(a, grain),
          isNot(await _paint(b, grain)),
          reason: '${tool.name}: another seed, other ragged edges / dust',
        );
      }
    },
  );

  test('harder strokes cover more', () async {
    for (final tool in [
      core.PenTool.crayon,
      core.PenTool.chalk,
      core.PenTool.spray,
    ]) {
      final light = InkStroke.of(_real(tool, 6, pressure: 0.1, id: 'l'));
      final hard = InkStroke.of(_real(tool, 6, pressure: 0.9, id: 'h'));
      expect(
        _meanAlpha(await _paint(hard, grain)),
        greaterThan(_meanAlpha(await _paint(light, grain))),
        reason: tool.name,
      );
    }
  });

  test('the PDF export: pieces per pen, one stroke id and tool each', () {
    for (final tool in _tools) {
      final s = InkStroke.of(_real(tool, 5));
      final page = InkVectorExport.exportStrokes([s]);
      expect(page.inkShapes, isNotEmpty, reason: tool.name);
      for (final shape in page.inkShapes) {
        expect(shape.strokeId, s.id);
        expect(shape.tool, tool);
        expect(shape.colorArgb ~/ 0x1000000, 0xFF, reason: 'K-5');
        expect(shape.opacity, inInclusiveRange(0.0001, 1));
        final pb = shape.path.bounds;
        expect(
          s.bounds.inflate(0.01).contains(pb.topLeft) &&
              s.bounds.inflate(0.01).contains(pb.bottomRight),
          isTrue,
          reason: '${tool.name}: $pb outside ${s.bounds}',
        );
      }
      // the same pieces twice
      final again = InkVectorExport.exportStrokes([s]).inkShapes;
      expect(again.length, page.inkShapes.length);
      for (var i = 0; i < again.length; i++) {
        expect(again[i].path.coords, page.inkShapes[i].path.coords);
      }
    }
    // several layers where the screen has several (the pencil and the brush —
    // its dry-brush gaps cut out of the one piece — stay one piece)
    int count(core.PenTool t) =>
        InkVectorExport.exportStrokes([InkStroke.of(_real(t, 5, id: 'n'))])
            .inkShapes
            .length;
    expect(count(core.PenTool.pencil), 1);
    expect(count(core.PenTool.brush), 1);
    for (final t in [
      core.PenTool.crayon,
      core.PenTool.chalk,
      core.PenTool.watercolor,
      core.PenTool.spray,
    ]) {
      expect(count(t), greaterThan(1), reason: t.name);
    }
  });

  test(
    'the pencil: dark colors move toward graphite gray, light ones stay',
    () {
      final s = InkStroke.of(_real(core.PenTool.pencil, 2));
      final piece = penRendererOf(core.PenTool.pencil)
          .vectorPieces(
            s,
            OutlineGenerator.outline(s),
            opacity: 1,
            smooth: true,
          )
          .single;
      expect(piece.colorArgb, isNot(opaqueArgb(s.style.colorArgb)));
      final red = InkStroke.of(
        strokeThrough(
          segment(const ui.Offset(10, 10), const ui.Offset(60, 10)),
          core.StrokeStyle.defaultsFor(core.PenTool.pencil)
              .copyWith(colorArgb: 0xFFE53935),
          id: 'red-pencil',
        ),
      );
      expect(
        penRendererOf(core.PenTool.pencil)
            .vectorPieces(
              red,
              OutlineGenerator.outline(red),
              opacity: 1,
              smooth: true,
            )
            .single
            .colorArgb,
        0xFFE53935,
      );
    },
  );

  test('live paint: with and without the tiles, deterministic', () async {
    for (final tool in _tools) {
      final s = InkStroke.of(_real(tool, 6, id: 'live'));
      final outline = OutlineGenerator.outline(s);
      final pts = [
        for (var i = 0; i < s.points.length; i++) s.points.offsetAt(i),
      ];
      for (final g in [grain, null]) {
        final frame = PenLiveFrame(
          style: s.style,
          paths: [outline.toPath(), ui.Path()],
          centerline: pts,
          bounds: s.bounds.inflate(1),
          opacity: 0.9,
          seed: s.source.createdAt,
          grain: s.profile.textured ? g : null,
        );
        Future<Uint8List> paint() async => (await renderPixels(
          _size,
          _size,
          (c) => penRendererOf(tool).paintLive(c, frame),
        )).bytes.buffer.asUint8List();
        final a = await paint();
        expect(_meanAlpha(a), greaterThan(0), reason: tool.name);
        expect(await paint(), a, reason: tool.name);
      }
    }
  });

  group('tiles', () {
    test('every channel is equalized (threshold t ≈ uncovered fraction t)', () {
      for (final px in [
        TextureTiles.toothPixels(),
        TextureTiles.washPixels(),
      ]) {
        for (var c = 0; c < 3; c++) {
          final hist = List.filled(4, 0);
          for (var i = c; i < px.length; i += 4) {
            hist[px[i] * 4 ~/ 256]++;
          }
          for (final h in hist) {
            expect(h / (px.length / 4), closeTo(0.25, 0.03));
          }
        }
        for (var i = 3; i < px.length; i += 4) {
          if (px[i] != 255) fail('alpha must be 255');
        }
      }
    });

    test('fixed bytes (arithmetic only — the same on every platform)', () {
      // test/web/texture_tiles_checksum_test.dart expects the same in Chrome
      expect(byteChecksum(TextureTiles.toothPixels()), recordedToothChecksum);
      expect(byteChecksum(TextureTiles.washPixels()), recordedWashChecksum);
    });

    test('noise01: fixed, in [0, 1), neighbours unrelated', () {
      expect(noise01(1, 0), noise01(1, 0));
      var prev = noise01(7, 0);
      var bigSteps = 0;
      for (var k = 1; k < 200; k++) {
        final v = noise01(7, k);
        expect(v >= 0 && v < 1, isTrue);
        if ((v - prev).abs() > 0.1) bigSteps++;
        prev = v;
      }
      expect(bigSteps, greaterThan(120), reason: 'not a lattice');
    });
  });

  test('the texture pen files use no bit operators (7.4.3)', () {
    final dir = Directory('lib/src/render/pens/texture');
    for (final f in dir.listSync().whereType<File>()) {
      final code = f
          .readAsLinesSync()
          .map((l) => l.replaceAll(RegExp('//.*'), ''))
          .join('\n')
          .replaceAll('&&', ' ')
          .replaceAll('||', ' ')
          .replaceAll('~/', ' ')
          .replaceAll('=>', ' ');
      for (final op in [' << ', ' >> ', '>>>', ' & ', ' | ', ' ^ ', ' ~']) {
        expect(code.contains(op), isFalse, reason: '${f.path}: $op');
      }
    }
  });
}
