// T21 (03-ink 8, 4.11, 6.24): InkVectorExport — z order, highlighter groups
// (color · opacity), paper-dependent blend, pencil opacity × 0.85, exported
// path = the screen's L1 outline, page pt coordinates (y down),
// InkFillShape.tool = core.PenTool.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/geometry/outline_generator.dart';
import 'package:ink_engine/src/render/highlighter_compositor.dart';
import 'package:ink_engine/src/render/layer_painters.dart';
import 'package:ink_engine/src/render/stroke_painter.dart';
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

import '../../support/pixels.dart';

core.StrokeStyle _style(
  core.PenTool tool, {
  int? color,
  double? width,
  double? opacity,
}) =>
    core.StrokeStyle.defaultsFor(tool)
        .copyWith(colorArgb: color, width: width, opacity: opacity);

InkStroke _ink(
  List<ui.Offset> points,
  core.StrokeStyle style, {
  String? id,
  int createdAt = 1000,
  double widthQ = core.kNominalWidthQ,
  double tilt = 0,
}) => InkStroke.of(
  strokeThrough(
    points,
    style,
    id: id,
    createdAt: createdAt,
    widthQ: widthQ,
    tilt: tilt,
  ),
);

List<ui.Offset> _wave(ui.Offset o, {double length = 160, double amp = 20}) => [
  for (var i = 0; i <= 80; i++)
    o + ui.Offset(length * i / 80, amp * math.sin(i / 80 * 2 * math.pi)),
];

/// Every (x, y) the vector path passes through or uses as a control point.
List<ui.Offset> _coords(InkVectorPath p) => [
  for (var i = 0; i + 1 < p.coords.length; i += 2)
    ui.Offset(p.coords[i], p.coords[i + 1]),
];

List<InkPathVerb> _verbs(InkVectorPath p) => [
  for (final v in p.verbs) InkPathVerb.values[v],
];

/// The PDF way of painting a group (6.24-3): all centerlines as sub-paths of
/// ONE path, stroked once with the opaque color inside one layer with the
/// group opacity and blend.
void _paintGroupAsOnePath(ui.Canvas canvas, InkHighlighterGroup g) {
  final path = ui.Path();
  for (final line in g.lines) {
    path.addPath(line.centerline.toUiPath(), ui.Offset.zero);
  }
  canvas.saveLayer(
    null,
    ui.Paint()
      ..color = inkColor(0, g.opacity)
      ..blendMode = g.blend == InkBlendMode.multiply
          ? ui.BlendMode.multiply
          : ui.BlendMode.srcOver,
  );
  canvas.drawPath(
    path,
    ui.Paint()
      ..isAntiAlias = true
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = g.lines.first.width
      ..strokeCap = ui.StrokeCap.square
      ..strokeJoin = ui.StrokeJoin.round
      ..color = ui.Color(g.colorArgb),
  );
  canvas.restore();
}

void main() {
  group('z order and layers', () {
    test('ink shapes follow core.Stroke.compareOrder, unsorted input too', () {
      final a = _ink(
        _wave(const ui.Offset(20, 40)),
        _style(core.PenTool.ballpoint),
        id: 'a',
        createdAt: 30,
      );
      final b = _ink(
        _wave(const ui.Offset(20, 80)),
        _style(core.PenTool.marker),
        id: 'b',
        createdAt: 10,
      );
      final c = _ink(
        _wave(const ui.Offset(20, 120)),
        _style(core.PenTool.fountain),
        id: 'c',
        createdAt: 20,
      );
      final d = _ink(
        _wave(const ui.Offset(20, 160)),
        _style(core.PenTool.pencil),
        id: 'd',
        createdAt: 20,
      );
      final sorted = InkVectorExport.exportStrokes([b, c, d, a]);
      expect(sorted.inkShapes.map((s) => s.strokeId), ['b', 'c', 'd', 'a']);
      final shuffled = InkVectorExport.exportStrokes([a, d, b, c]);
      expect(shuffled.inkShapes.map((s) => s.strokeId), ['b', 'c', 'd', 'a']);
      expect(shuffled.highlighterGroups, isEmpty);
    });

    test('highlighters go to the groups (drawn first, below the ink) '
        'whatever their z; groups by lowest z, lines in z order', () {
      final yellow = _style(core.PenTool.highlighter);
      final green = _style(core.PenTool.highlighter, color: 0xFF33DD55);
      final h1 = _ink(
        _wave(const ui.Offset(20, 40)),
        yellow,
        id: 'h1',
        createdAt: 50,
      );
      final g1 = _ink(
        _wave(const ui.Offset(20, 80)),
        green,
        id: 'g1',
        createdAt: 5,
      );
      final h2 = _ink(
        _wave(const ui.Offset(20, 120)),
        yellow,
        id: 'h2',
        createdAt: 1,
      );
      final ink = _ink(
        _wave(const ui.Offset(20, 160)),
        _style(core.PenTool.ballpoint),
        id: 'k',
        createdAt: 0,
      );
      final v = InkVectorExport.exportStrokes([ink, h2, g1, h1]);
      expect(v.inkShapes.map((s) => s.strokeId), ['k']);
      expect(v.highlighterGroups, hasLength(2));
      // Yellow's lowest z (h2, createdAt 1) is below green's (g1, 5).
      expect(v.highlighterGroups[0].colorArgb, 0xFFFFE600);
      expect(v.highlighterGroups[0].lines.map((l) => l.strokeId), ['h2', 'h1']);
      expect(v.highlighterGroups[1].colorArgb, 0xFF33DD55);
      expect(v.highlighterGroups[1].lines.map((l) => l.strokeId), ['g1']);
      expect(v.isEmpty, isFalse);
    });

    test('the group order is the one the screen composites (6.10-1)', () {
      final strokes = [
        for (var i = 0; i < 12; i++)
          _ink(
            _wave(ui.Offset(20, 20.0 + 30 * i)),
            _style(
              core.PenTool.highlighter,
              color: [0xFFFFE600, 0xFF33DD55, 0xFF55AAFF][i * 7 % 3],
              opacity: [0.35, 0.5][i % 2],
            ),
            createdAt: 100 + i,
          ),
      ];
      final screen = groupHighlighters(strokes);
      final v = InkVectorExport.exportStrokes(strokes);
      expect(v.highlighterGroups, hasLength(screen.length));
      for (var i = 0; i < screen.length; i++) {
        final e = v.highlighterGroups[i], s = screen[i];
        expect(e.colorArgb, s.key.colorArgb);
        expect(e.opacity, s.key.opacity);
        expect(e.lines, hasLength(s.lines.length));
      }
    });

    test('deleted strokes are left out; no strokes → empty, Rect.zero', () {
      final live = strokeThrough(
        _wave(const ui.Offset(20, 40)),
        _style(core.PenTool.ballpoint),
        id: 'live',
      );
      final gone = strokeThrough(
        _wave(const ui.Offset(20, 80)),
        _style(core.PenTool.ballpoint),
        id: 'gone',
      ).copyWith(deletedAt: 5);
      final hlGone = strokeThrough(
        _wave(const ui.Offset(20, 80)),
        _style(core.PenTool.highlighter),
        id: 'hg',
      ).copyWith(deletedAt: 5);
      final v = InkVectorExport.exportStrokes([
        InkStroke.of(live),
        InkStroke.of(gone),
        InkStroke.of(hlGone),
      ]);
      expect(v.inkShapes.map((s) => s.strokeId), ['live']);
      expect(v.highlighterGroups, isEmpty);

      final empty = InkVectorExport.exportStrokes(const []);
      expect(empty.isEmpty, isTrue);
      expect(empty.inkShapes, isEmpty);
      expect(empty.highlighterGroups, isEmpty);
      expect(empty.bounds, ui.Rect.zero);
      expect(
        InkVectorExport.exportPage(SyntheticInk.pageContent()).isEmpty,
        isTrue,
      );
    });

    test('the result lists are unmodifiable', () {
      final v = InkVectorExport.exportStrokes([
        _ink(_wave(const ui.Offset(20, 40)), _style(core.PenTool.highlighter)),
        _ink(_wave(const ui.Offset(20, 80)), _style(core.PenTool.ballpoint)),
      ]);
      expect(v.inkShapes.clear, throwsUnsupportedError);
      expect(v.highlighterGroups.clear, throwsUnsupportedError);
      expect(
        () => v.highlighterGroups.single.lines.clear(),
        throwsUnsupportedError,
      );
    });
  });

  group('highlighter groups', () {
    test('same color + opacity (1/100) = one group; color or opacity '
        'differs = another group', () {
      final base = _style(core.PenTool.highlighter, opacity: 0.35);
      final strokes = [
        _ink(_wave(const ui.Offset(20, 40)), base, id: 'a', createdAt: 1),
        _ink(
          _wave(const ui.Offset(20, 60)),
          base.copyWith(width: 20),
          id: 'b',
          createdAt: 2,
        ),
        _ink(
          _wave(const ui.Offset(20, 80)),
          base.copyWith(opacity: 0.352),
          id: 'c',
          createdAt: 3,
        ),
        _ink(
          _wave(const ui.Offset(20, 100)),
          base.copyWith(opacity: 0.5),
          id: 'd',
          createdAt: 4,
        ),
        _ink(
          _wave(const ui.Offset(20, 120)),
          base.copyWith(colorArgb: 0xFFFF7799),
          id: 'e',
          createdAt: 5,
        ),
      ];
      final groups = InkVectorExport.exportStrokes(strokes).highlighterGroups;
      expect(groups.map((g) => g.lines.map((l) => l.strokeId).toList()), [
        ['a', 'b', 'c'],
        ['d'],
        ['e'],
      ]);
      expect(groups.map((g) => g.colorArgb), [
        0xFFFFE600,
        0xFFFFE600,
        0xFFFF7799,
      ]);
      expect(groups.map((g) => g.opacity), [0.35, 0.5, 0.35]);
    });

    test(
      'a line: stored centerline (moveTo + lineTo, pt), width, square cap',
      () {
        final pts = _wave(const ui.Offset(30, 500));
        final s = _ink(
          pts,
          _style(core.PenTool.highlighter, width: 14),
          id: 'h',
        );
        final line = InkVectorExport.exportStrokes([s])
            .highlighterGroups
            .single
            .lines
            .single;
        expect(line.strokeId, 'h');
        expect(line.width, 14);
        expect(line.cap, InkCap.square);
        expect(line.cap, s.profile.cap);
        expect(_verbs(line.centerline), [
          InkPathVerb.moveTo,
          for (var i = 1; i < pts.length; i++) InkPathVerb.lineTo,
        ]);
        // The same coordinates the screen strokes (CORE stores float32 pt).
        expect(line.centerline.coords, OutlineGenerator.polyline(s.points));
        for (var i = 0; i < pts.length; i++) {
          expect(line.centerline.coords[2 * i], closeTo(pts[i].dx, 0.006));
          expect(line.centerline.coords[2 * i + 1], closeTo(pts[i].dy, 0.006));
        }
      },
    );

    test('a zero-length line becomes a 0.001 pt horizontal segment', () {
      final s = _ink(
        const [ui.Offset(100, 200), ui.Offset(100, 200)],
        _style(core.PenTool.highlighter),
        id: 'dot',
      );
      final v = InkVectorExport.exportStrokes([s]);
      final line = v.highlighterGroups.single.lines.single;
      expect(_verbs(line.centerline), [InkPathVerb.moveTo, InkPathVerb.lineTo]);
      expect(line.centerline.coords[0], 100);
      expect(line.centerline.coords[1], 200);
      expect(line.centerline.coords[2], closeTo(100.001, 1e-4));
      expect(line.centerline.coords[3], 200);
      // The square the caps make lies inside the bounds.
      expect(v.bounds.contains(const ui.Offset(94.1, 194.1)), isTrue);
      expect(v.bounds.contains(const ui.Offset(105.9, 205.9)), isTrue);
    });

    test('blend: multiply on light paper, normal on dark paper (6.10-4)', () {
      final strokes = [
        _ink(_wave(const ui.Offset(20, 40)), _style(core.PenTool.highlighter)),
      ];
      InkBlendMode blendOn(int paper) => InkVectorExport.exportStrokes(
        strokes,
        options: InkExportOptions(paperColorArgb: paper),
      ).highlighterGroups.single.blend;
      expect(blendOn(core.PaperColors.white), InkBlendMode.multiply);
      expect(blendOn(core.PaperColors.ivory), InkBlendMode.multiply);
      expect(blendOn(core.PaperColors.gray), InkBlendMode.multiply);
      expect(blendOn(core.PaperColors.black), InkBlendMode.normal);
      expect(blendOn(0xFF101010), InkBlendMode.normal);
      // Default options: white paper.
      expect(
        InkVectorExport.exportStrokes(strokes).highlighterGroups.single.blend,
        InkBlendMode.multiply,
      );
      for (final paper in core.PaperColors.all) {
        expect(
          blendOn(paper) == InkBlendMode.multiply,
          highlighterBlendFor(paper) == ui.BlendMode.multiply,
          reason: 'same rule as the screen for 0x${paper.toRadixString(16)}',
        );
      }
    });

    test('exportPage: options == null → the page paper decides the blend', () {
      final hl = strokeThrough(
        _wave(const ui.Offset(20, 40)),
        _style(core.PenTool.highlighter),
      );
      final dark = SyntheticInk.pageContent(
        strokes: [hl],
        background: const core.BlankBackground(
          paperColorArgb: core.PaperColors.black,
        ),
      );
      final light = SyntheticInk.pageContent(
        strokes: [hl],
        background: const core.TemplateBackground(
          template: core.PageTemplate(kind: core.PageTemplateKind.lined),
          paperColorArgb: core.PaperColors.ivory,
        ),
      );
      expect(
        InkVectorExport.exportPage(dark).highlighterGroups.single.blend,
        InkBlendMode.normal,
      );
      expect(
        InkVectorExport.exportPage(light).highlighterGroups.single.blend,
        InkBlendMode.multiply,
      );
      // Explicit options win.
      expect(
        InkVectorExport.exportPage(
          dark,
          options: const InkExportOptions(),
        ).highlighterGroups.single.blend,
        InkBlendMode.multiply,
      );
      // exportPage = exportStrokes(content.strokes, …).
      final both = SyntheticInk.pageContent(
        strokes: [
          hl,
          strokeThrough(
            _wave(const ui.Offset(20, 80)),
            _style(core.PenTool.ballpoint),
            id: 'k',
          ),
        ],
      );
      final page = InkVectorExport.exportPage(both);
      final direct = InkVectorExport.exportStrokes(both.strokes);
      expect(
        page.inkShapes.single.path.coords,
        direct.inkShapes.single.path.coords,
      );
      expect(page.bounds, direct.bounds);
    });

    test(
      'crossing lines of one group, painted as ONE path: the crossing has '
      'the single-line color, the image equals the screen composite',
      () async {
        final style = _style(core.PenTool.highlighter, opacity: 0.4, width: 12);
        final strokes = [
          _ink(
            segment(const ui.Offset(10, 50), const ui.Offset(90, 50)),
            style,
            createdAt: 1,
          ),
          _ink(
            segment(const ui.Offset(50, 10), const ui.Offset(50, 90)),
            style,
            createdAt: 2,
          ),
        ];
        final v = InkVectorExport.exportStrokes(strokes);
        expect(v.highlighterGroups, hasLength(1));
        final exported = await renderPixels(100, 100, (canvas) {
          paintPaper(canvas, core.PaperColors.white, size: 100);
          _paintGroupAsOnePath(canvas, v.highlighterGroups.single);
        });
        final screen = await renderPixels(100, 100, (canvas) {
          paintPaper(canvas, core.PaperColors.white, size: 100);
          paintStrokeLayer(
            canvas,
            strokes,
            layer: InkLayer.highlighter,
            paperColorArgb: core.PaperColors.white,
            outlineOf: OutlineGenerator.outline,
          );
        });
        final single = exported.at(25, 50);
        expect(single, isNot([255, 255, 255, 255]));
        expect(
          samePixel(exported.at(50, 50), single),
          isTrue,
          reason: 'crossing ${exported.at(50, 50)} vs $single',
        );
        var differing = 0;
        for (var y = 0; y < 100; y++) {
          for (var x = 0; x < 100; x++) {
            if (!samePixel(exported.at(x, y), screen.at(x, y))) differing++;
          }
        }
        expect(differing, 0);
      },
    );
  });

  group('fill shapes', () {
    test('InkFillShape.tool = core.PenTool (P1 tools keep their own tool); '
        'tapes go to cover (m5-7 T31)', () {
      final tools = [
        for (final t in core.PenTool.values)
          if (t != core.PenTool.highlighter && t != core.PenTool.tape) t,
      ];
      final strokes = [
        for (var i = 0; i < tools.length; i++)
          _ink(
            _wave(ui.Offset(20, 30.0 + 40 * i)),
            _style(tools[i]),
            id: tools[i].name,
            createdAt: i,
          ),
      ];
      final tape = _ink(
        _wave(ui.Offset(20, 30.0 + 40 * tools.length)),
        _style(core.PenTool.tape),
        id: 'tape',
        createdAt: tools.length,
      );
      final v = InkVectorExport.exportStrokes([...strokes, tape]);
      expect(v.inkShapes.map((s) => s.tool), tools);
      expect(v.inkShapes.map((s) => s.strokeId), tools.map((t) => t.name));
      for (final s in v.inkShapes) {
        expect(s.tool, isA<core.PenTool>());
      }
      expect(v.cover.map((s) => (s.strokeId, s.tool)), [
        ('tape', core.PenTool.tape),
      ]);
    });

    test(
      'color alpha 0xFF (K-5), opacity = style opacity for non-pencil pens',
      () {
        final v = InkVectorExport.exportStrokes([
          _ink(
            _wave(const ui.Offset(20, 40)),
            _style(core.PenTool.ballpoint, color: 0xFF336699, opacity: 0.6),
            createdAt: 1,
          ),
          _ink(
            _wave(const ui.Offset(20, 80)),
            _style(core.PenTool.marker, opacity: 0.3),
            createdAt: 2,
          ),
          _ink(
            _wave(const ui.Offset(20, 120)),
            _style(core.PenTool.fountain),
            createdAt: 3,
          ),
        ]);
        expect(v.inkShapes.map((s) => s.colorArgb), [
          0xFF336699,
          0xFF1A1A1A,
          0xFF1B2A6B,
        ]);
        expect(v.inkShapes.map((s) => s.opacity), [0.6, 0.3, 1.0]);
      },
    );

    test('pencil: flat color, opacity × 0.85 (× the screen tilt factor)', () {
      expect(const InkExportOptions().pencilOpacityFactor, 0.85);
      expect(InkTuning.exportPencilOpacityFactor, 0.85);
      final flat = _ink(
        _wave(const ui.Offset(20, 40)),
        _style(core.PenTool.pencil),
        createdAt: 1,
      );
      final tilted = _ink(
        _wave(const ui.Offset(20, 80)),
        _style(core.PenTool.pencil, opacity: 0.8),
        createdAt: 2,
        tilt: 1.0,
      );
      final v = InkVectorExport.exportStrokes([flat, tilted]);
      expect(v.inkShapes[0].tool, core.PenTool.pencil);
      expect(v.inkShapes[0].colorArgb, 0xFF3C3C3C);
      expect(v.inkShapes[0].opacity, closeTo(0.9 * 0.85, 1e-9));
      // The tilt lowers the screen opacity (6.11); export keeps that factor.
      expect(strokeOpacity(tilted), lessThan(0.8));
      expect(
        v.inkShapes[1].opacity,
        closeTo(strokeOpacity(tilted) * 0.85, 1e-9),
      );

      final custom = InkVectorExport.exportStrokes([
        flat,
      ], options: const InkExportOptions(pencilOpacityFactor: 1));
      expect(custom.inkShapes.single.opacity, closeTo(0.9, 1e-9));
      final half = InkVectorExport.exportStrokes([
        flat,
      ], options: const InkExportOptions(pencilOpacityFactor: 0.5));
      expect(half.inkShapes.single.opacity, closeTo(0.45, 1e-9));
      // The factor applies to the pencil only.
      final ball = _ink(
        _wave(const ui.Offset(20, 40)),
        _style(core.PenTool.ballpoint, opacity: 0.9),
      );
      expect(
        InkVectorExport.exportStrokes(
          [ball],
          options: const InkExportOptions(pencilOpacityFactor: 0.5),
        ).inkShapes.single.opacity,
        0.9,
      );
    });

    test('smooth: false → the L1 outline polygons exactly (moveTo, lineTo…, close)', () {
      for (final tool in [
        core.PenTool.ballpoint,
        core.PenTool.fountain,
        core.PenTool.pencil,
        core.PenTool.marker,
      ]) {
        final s = _ink(
          [
            ..._wave(const ui.Offset(40, 300), amp: 30),
            ..._wave(const ui.Offset(200, 300), length: 60, amp: -40),
          ],
          _style(tool, width: 4),
          widthQ: 0.3,
        );
        final outline = OutlineGenerator.outline(s);
        expect(outline.polygons, isNotEmpty);
        final path = InkVectorExport.exportStrokes(
          [s],
          options: const InkExportOptions(smooth: false),
        ).inkShapes.single.path;
        final expectedVerbs = <InkPathVerb>[];
        final expectedCoords = <double>[];
        for (final poly in outline.polygons) {
          final m = poly.length ~/ 2;
          if (m < 3) continue;
          expectedVerbs
            ..add(InkPathVerb.moveTo)
            ..addAll(List.filled(m - 1, InkPathVerb.lineTo))
            ..add(InkPathVerb.close);
          expectedCoords.addAll(poly);
        }
        expect(_verbs(path), expectedVerbs, reason: '$tool');
        expect(
          path.coords,
          Float32List.fromList(expectedCoords),
          reason: '$tool',
        );
      }
    });

    test('smooth: true → the screen curve: cubics through the edge midpoints '
        '(quadratic control point → ⅔ rule)', () {
      final s = _ink(
        _wave(const ui.Offset(40, 300), amp: 30),
        _style(core.PenTool.fountain, width: 3),
        widthQ: 0.35,
      );
      final poly = OutlineGenerator.outline(s).polygons.single;
      final m = poly.length ~/ 2;
      final path = InkVectorExport.exportStrokes([s]).inkShapes.single.path;
      expect(_verbs(path), [
        InkPathVerb.moveTo,
        ...List.filled(m, InkPathVerb.cubicTo),
        InkPathVerb.close,
      ]);
      ui.Offset v(int i) => ui.Offset(poly[2 * (i % m)], poly[2 * (i % m) + 1]);
      final c = _coords(path);
      expect(c.first.dx, closeTo(((v(m - 1) + v(0)) / 2).dx, 1e-3));
      expect(c.first.dy, closeTo(((v(m - 1) + v(0)) / 2).dy, 1e-3));
      for (var i = 0; i < m; i++) {
        final p0 = i == 0 ? (v(m - 1) + v(0)) / 2 : (v(i - 1) + v(i)) / 2;
        final q = v(i);
        final p1 = (v(i) + v(i + 1)) / 2;
        final c1 = c[1 + 3 * i], c2 = c[2 + 3 * i], end = c[3 + 3 * i];
        final e1 = p0 + (q - p0) * (2 / 3), e2 = p1 + (q - p1) * (2 / 3);
        expect((c1 - e1).distance, lessThan(1e-3));
        expect((c2 - e2).distance, lessThan(1e-3));
        expect((end - p1).distance, lessThan(1e-3));
        // Degree elevation keeps the curve AND its parameter.
        for (final t in [0.25, 0.5, 0.75]) {
          final u = 1 - t;
          final quad = p0 * (u * u) + q * (2 * u * t) + p1 * (t * t);
          final cubic =
              c[3 * i] * (u * u * u) +
              c1 * (3 * u * u * t) +
              c2 * (3 * u * t * t) +
              end * (t * t * t);
          expect((cubic - quad).distance, lessThan(1e-3));
        }
      }
    });

    test(
      'exported fill painted = the screen stroke: same ink (< 0.5%), '
      'only anti-aliased edge pixels differ, by ≤ 48 (dot: ink < 2.5%) '
      '(pens × smooth curve, dot, self-crossing loop at opacity 0.5)',
      () async {
        // Skia flattens a quadratic (screen) and its exact cubic (export) — and
        // an oval and its 4-cubic circle — a little differently, so edge
        // pixels may differ by a few levels; the geometry is the same (see the
        // smooth: true test).
        final loop = [
          for (var i = 0; i <= 120; i++)
            ui.Offset(
              100 + 50 * math.cos(i / 120 * 4 * math.pi) + i * 0.3,
              100 + 35 * math.sin(i / 120 * 4 * math.pi),
            ),
        ];
        final cases = <String, InkStroke>{
          'ballpoint': _ink(
            _wave(const ui.Offset(20, 60)),
            _style(core.PenTool.ballpoint, width: 3),
          ),
          'fountain': _ink(
            _wave(const ui.Offset(20, 100), amp: 30),
            _style(core.PenTool.fountain, width: 4),
            widthQ: 0.4,
          ),
          'marker 0.5': _ink(
            loop,
            _style(core.PenTool.marker, width: 6, opacity: 0.5),
          ),
          'dot': _ink(const [
            ui.Offset(90, 90),
          ], _style(core.PenTool.marker, width: 10)),
        };
        for (final MapEntry(key: name, value: s) in cases.entries) {
          final shape = InkVectorExport.exportStrokes([s]).inkShapes.single;
          final exported = await renderPixels(200, 200, (canvas) {
            paintPaper(canvas, core.PaperColors.white, size: 200);
            canvas.drawPath(
              shape.path.toUiPath(),
              ui.Paint()
                ..isAntiAlias = true
                ..color = inkColor(shape.colorArgb, shape.opacity),
            );
          });
          final screen = await renderPixels(200, 200, (canvas) {
            paintPaper(canvas, core.PaperColors.white, size: 200);
            paintFillStroke(canvas, s, OutlineGenerator.outline(s));
          });
          int ink(List<int> p) => 765 - p[0] - p[1] - p[2];
          bool flat(int x, int y) {
            final c = screen.at(x, y);
            for (final (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
              if (!samePixel(screen.at(x + dx, y + dy), c)) return false;
            }
            return true;
          }

          var inkExported = 0, inkScreen = 0, maxDiff = 0;
          for (var y = 1; y < 199; y++) {
            for (var x = 1; x < 199; x++) {
              final a = exported.at(x, y), b = screen.at(x, y);
              inkExported += ink(a);
              inkScreen += ink(b);
              if (samePixel(a, b)) continue;
              expect(
                flat(x, y),
                isFalse,
                reason: '$name: ($x, $y) off an edge',
              );
              for (var k = 0; k < 4; k++) {
                maxDiff = math.max(maxDiff, (a[k] - b[k]).abs());
              }
            }
          }
          expect(inkScreen, greaterThan(20 * 255), reason: name);
          // The small dot: Skia paints the screen's oval with analytic
          // coverage and the 4-cubic circle as a path (measured 1.7%).
          expect(
            (inkExported - inkScreen).abs() / inkScreen,
            lessThan(name == 'dot' ? 0.025 : 0.005),
            reason: name,
          );
          expect(maxDiff, lessThanOrEqualTo(48), reason: name);
        }
      },
    );

    test('a dot stroke → a circle of 4 cubics (k = 0.5523)', () {
      final s = _ink(const [
        ui.Offset(120, 220),
      ], _style(core.PenTool.ballpoint, width: 4));
      final outline = OutlineGenerator.outline(s);
      expect(outline.isDot, isTrue);
      final path = InkVectorExport.exportStrokes([s]).inkShapes.single.path;
      expect(_verbs(path), [
        InkPathVerb.moveTo,
        InkPathVerb.cubicTo,
        InkPathVerb.cubicTo,
        InkPathVerb.cubicTo,
        InkPathVerb.cubicTo,
        InkPathVerb.close,
      ]);
      final r = outline.dotRadius;
      final c = _coords(path);
      expect(c.first.dx, closeTo(120 + r, 1e-3));
      expect(c.first.dy, closeTo(220, 1e-3));
      expect(c[1].dy, closeTo(220 + 0.5523 * r, 1e-3));
      expect(path.bounds.width, closeTo(2 * r, 1e-3));
      // Every cubic's midpoint lies on the circle (k = 0.5523: error < 0.03%).
      for (var i = 0; i < 4; i++) {
        final p0 = c[3 * i], c1 = c[3 * i + 1], c2 = c[3 * i + 2];
        final p1 = c[3 * i + 3];
        final mid = (p0 + p1) * 0.125 + (c1 + c2) * 0.375;
        expect(
          (mid - const ui.Offset(120, 220)).distance,
          closeTo(r, r * 3e-4),
        );
      }
    });
  });

  group('coordinates and bounds', () {
    test(
      'page pt, y down: no scaling, no flip; shapes ⊆ CORE bounds (K-1)',
      () {
        final size = _a4;
        final top = _ink(
          segment(const ui.Offset(50, 30), const ui.Offset(300, 30)),
          _style(core.PenTool.ballpoint),
          createdAt: 1,
        );
        final bottom = _ink(
          segment(const ui.Offset(50, 800), const ui.Offset(540, 800)),
          _style(core.PenTool.marker),
          createdAt: 2,
        );
        final hl = _ink(
          segment(const ui.Offset(60, 420), const ui.Offset(400, 420)),
          _style(core.PenTool.highlighter),
          createdAt: 3,
        );
        final v = InkVectorExport.exportStrokes([top, bottom, hl]);
        final topPath = v.inkShapes[0].path, bottomPath = v.inkShapes[1].path;
        expect(topPath.bounds.center.dy, closeTo(30, 0.5));
        expect(bottomPath.bounds.center.dy, closeTo(800, 0.5));
        expect(
          bottomPath.bounds.left,
          closeTo(50 - 2.5, 0.1),
        ); // marker width 5, round cap
        expect(bottomPath.bounds.right, closeTo(540 + 2.5, 0.1));
        for (final (s, p) in [(top, topPath), (bottom, bottomPath)]) {
          final b = p.bounds;
          expect(s.bounds.inflate(1e-3).contains(b.topLeft), isTrue);
          expect(s.bounds.inflate(1e-3).contains(b.bottomRight), isTrue);
        }
        final line = v.highlighterGroups.single.lines.single;
        expect(
          line.centerline.bounds,
          const ui.Rect.fromLTRB(60, 420, 400, 420),
        );
        // Everything inside the A4 page in pt.
        expect((ui.Offset.zero & size).contains(v.bounds.topLeft), isTrue);
        expect((ui.Offset.zero & size).contains(v.bounds.bottomRight), isTrue);
      },
    );

    test('bounds = union of the fill outlines and the highlighter line '
        'extents (square caps: width / 2 · √2)', () {
      final ink = _ink(
        segment(const ui.Offset(100, 100), const ui.Offset(200, 100)),
        _style(core.PenTool.ballpoint, width: 2),
      );
      final hl = _ink(
        segment(const ui.Offset(150, 300), const ui.Offset(250, 300)),
        _style(core.PenTool.highlighter, width: 10),
      );
      final v = InkVectorExport.exportStrokes([ink, hl]);
      final o = OutlineGenerator.outline(ink).bounds;
      final e = 5 * math.sqrt2;
      final expected = o.expandToInclude(
        ui.Rect.fromLTRB(150 - e, 300 - e, 250 + e, 300 + e),
      );
      expect(v.bounds.left, closeTo(expected.left, 1e-3));
      expect(v.bounds.top, closeTo(expected.top, 1e-3));
      expect(v.bounds.right, closeTo(expected.right, 1e-3));
      expect(v.bounds.bottom, closeTo(expected.bottom, 1e-3));
      expect(v.inkShapes.single.path.bounds.width, closeTo(o.width, 0.01));
    });
  });
}

/// A4 portrait in pt.
const ui.Size _a4 = ui.Size(595.28, 841.89);
