// m5-7/03-ink 8.2 T42 (4.8, 6.21, 6.9.5, 6.10.2): InkVectorExport v2.
// - Lists and z order (K-8): image objects → underlay, highlighters → the
//   groups, the ink layer (strokes and shapes merged by compareOrder) →
//   inkShapes, text boxes and formulas → annotations (z order), tapes → cover;
//   unknown objects and objects without a drawable frame are left out.
// - Strokes: a dashed stroke is ONE InkFillShape with its dash outlines (and
//   dots) as sub-paths; a tape is a cover shape (opaque, opacity 1 — whatever
//   its style opacity or the reveal state on screen); a stored laser stroke is
//   the ballpoint fallback.
// - Shapes: the fill piece, then the outline piece; objectId = strokeId = the
//   object id, tool = ballpoint, strokes have objectId null; a closed polyline
//   fill = its polygon, an ellipse fill = 4 cubics (k = 0.5523, rotated); the
//   outline = the 6.9.5 polygons with the arrow heads in the same path (every
//   sub-path positively oriented — S-10); an open polyline is never filled;
//   opacity 0 pieces are left out.
// - Text lines: with NoteSans loaded the lines of the screen paragraph (count,
//   x, baseline, width — frame-local pt), text without the line break, lines
//   starting below the frame left out; before the load: no lines.
// - Formulas and images: their fields.
// - Painting the exported paths = the screen painting (< 1% ink, few pixels).
// - InkVectorFixtures rebuilds the real value (==).
@TestOn('vm')
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/geometry/outline_generator.dart';
import 'package:ink_engine/src/object/shape_path.dart';
import 'package:ink_engine/src/render/stroke_painter.dart';
import 'package:ink_engine/src/render/tape_painter.dart';
import 'package:ink_engine/src/text/fonts.dart';
import 'package:ink_engine/src/text/text_layout.dart';
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

import '../../support/pixels.dart';
import '../../support/raster.dart';

const _pageId = 'p1';
const _red = 0xFFDD0000;
const _blue = 0xFF0000FF;
const _green = 0xFF00AA00;

Future<Uint8List> _files({required bool bold}) async =>
    File('assets/fonts/NoteSans-${bold ? 'Bold' : 'Regular'}.ttf')
        .readAsBytesSync();

core.StrokeStyle _style(
  core.PenTool tool, {
  int? color,
  double? width,
  double? opacity,
}) =>
    core.StrokeStyle.defaultsFor(tool)
        .copyWith(colorArgb: color, width: width, opacity: opacity);

core.Stroke _stroke(
  String id,
  List<ui.Offset> points,
  core.StrokeStyle style,
  int createdAt,
) => strokeThrough(points, style, id: id).copyWith(createdAt: createdAt);

List<ui.Offset> _wave(ui.Offset o, {double length = 160, double amp = 20}) => [
  for (var i = 0; i <= 80; i++)
    o + ui.Offset(length * i / 80, amp * math.sin(i / 80 * 2 * math.pi)),
];

core.ShapeObject _shape(
  String id,
  core.ShapeKind kind,
  core.ShapeGeometry geometry,
  int createdAt, {
  int color = _green,
  double width = 4,
  double opacity = 1,
  core.LineDash dash = core.LineDash.solid,
  int? fill,
  double fillOpacity = 1,
  core.ArrowHeads heads = core.ArrowHeads.none,
}) => core.ShapeObject(
  id: id,
  pageId: _pageId,
  shapeKind: kind,
  geometry: geometry,
  style: core.ShapeStyle(
    strokeColorArgb: color,
    strokeWidth: width,
    strokeOpacity: opacity,
    dash: dash,
    fillColorArgb: fill,
    fillOpacity: fillOpacity,
    arrowHeads: heads,
  ),
  createdAt: createdAt,
);

core.TextBoxObject _text(
  String id,
  core.PageRect r,
  String text,
  int createdAt, {
  core.TextBoxStyle style = const core.TextBoxStyle(),
  double rotation = 0,
}) => core.TextBoxObject(
  id: id,
  pageId: _pageId,
  frame: core.ElementFrame(r, rotation: rotation),
  text: text,
  style: style,
  createdAt: createdAt,
);

InkPageContent _page({
  List<core.Stroke> strokes = const [],
  List<core.PageObject> objects = const [],
}) => SyntheticInk.pageContentWith(strokes: strokes, objects: objects);

List<InkPathVerb> _verbs(InkVectorPath p) => [
  for (final v in p.verbs) InkPathVerb.values[v],
];

int _subpaths(InkVectorPath p) =>
    _verbs(p).where((v) => v == InkPathVerb.moveTo).length;

/// The sub-paths of a path made of moveTo / lineTo / close only, as x,y pairs.
List<Float32List> _polygonsOf(InkVectorPath p) {
  final out = <Float32List>[];
  var current = <double>[];
  var c = 0;
  for (final v in _verbs(p)) {
    switch (v) {
      case InkPathVerb.moveTo:
        if (current.isNotEmpty) out.add(Float32List.fromList(current));
        current = [p.coords[c], p.coords[c + 1]];
        c += 2;
      case InkPathVerb.lineTo:
        current.addAll([p.coords[c], p.coords[c + 1]]);
        c += 2;
      case InkPathVerb.cubicTo:
        fail('a polygon path has no cubics');
      case InkPathVerb.close:
        break;
    }
  }
  if (current.isNotEmpty) out.add(Float32List.fromList(current));
  return out;
}

/// The on-curve points of every sub-path (moveTo, lineTo and cubic end points).
List<Float32List> _onCurve(InkVectorPath p) {
  final out = <Float32List>[];
  var current = <double>[];
  var c = 0;
  for (final v in _verbs(p)) {
    switch (v) {
      case InkPathVerb.moveTo:
        if (current.isNotEmpty) out.add(Float32List.fromList(current));
        current = [p.coords[c], p.coords[c + 1]];
        c += 2;
      case InkPathVerb.lineTo:
        current.addAll([p.coords[c], p.coords[c + 1]]);
        c += 2;
      case InkPathVerb.cubicTo:
        current.addAll([p.coords[c + 4], p.coords[c + 5]]);
        c += 6;
      case InkPathVerb.close:
        break;
    }
  }
  if (current.isNotEmpty) out.add(Float32List.fromList(current));
  return out;
}

void _expectSamePolygons(List<Float32List> actual, List<Float32List> expected) {
  expect(actual.length, expected.length);
  for (var i = 0; i < actual.length; i++) {
    expect(actual[i], orderedEquals(expected[i]), reason: 'polygon $i');
  }
}

/// The outline path of [o] built independently: its 6.9.5 polygons.
InkVectorPath _outlinePathOf(core.ShapeObject o) {
  final verbs = <int>[];
  final coords = <double>[];
  for (final poly in shapeOutlineOf(o).stroke) {
    final m = poly.length ~/ 2;
    verbs
      ..add(InkPathVerb.moveTo.index)
      ..addAll(List.filled(m - 1, InkPathVerb.lineTo.index))
      ..add(InkPathVerb.close.index);
    coords.addAll(poly);
  }
  return InkVectorPath(Uint8List.fromList(verbs), Float32List.fromList(coords));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('lists and z order (K-8)', () {
    test('each element goes to its L-1 list; inkShapes = strokes and shapes '
        'merged by compareOrder; annotations in z order; unknown objects, '
        'objects without a drawable frame and deleted ones are left out', () {
      final image = PageObjectFixtures.image(
        pageId: _pageId,
        assetId: 'asset-a',
        rect: const core.PageRect(10, 10, 210, 160),
        pixelWidth: 800,
        pixelHeight: 600,
        createdAt: 90, // newest, still below everything (underlay)
        id: 'img',
      );
      final hl = _stroke(
        'hl',
        segment(const ui.Offset(20, 40), const ui.Offset(200, 40)),
        _style(core.PenTool.highlighter, color: 0xFFFFEE00),
        5,
      );
      final s1 = _stroke(
        's1',
        _wave(const ui.Offset(20, 80)),
        _style(core.PenTool.ballpoint, color: _blue, width: 3),
        10,
      );
      final sh1 = _shape(
        'sh1',
        core.ShapeKind.rectangle,
        core.ShapeGeometry.rectangle(const core.PageRect(30, 30, 130, 110)),
        20,
        fill: _red,
      );
      final s2 = _stroke(
        's2',
        _wave(const ui.Offset(20, 120)),
        _style(core.PenTool.fountain, color: _red, width: 4),
        30,
      );
      final sh2 = _shape(
        'sh2',
        core.ShapeKind.line,
        core.ShapeGeometry.line(
          const core.PagePoint(20, 200),
          const core.PagePoint(200, 220),
        ),
        40,
      );
      final text = _text(
        'tx',
        const core.PageRect(40, 300, 240, 360),
        'hello',
        50,
      );
      final formula = PageObjectFixtures.math(
        pageId: _pageId,
        rect: const core.PageRect(40, 400, 140, 450),
        createdAt: 45, // older than the text box: first in annotations
        id: 'mx',
      );
      final unknown = PageObjectFixtures.unknown(pageId: _pageId, id: 'unk');
      final flat = _text(
        'flat',
        const core.PageRect(300, 300, 300, 360), // width 0: nothing drawn
        'x',
        60,
      );
      final deleted = _shape(
        'gone',
        core.ShapeKind.ellipse,
        core.ShapeGeometry.ellipse(const core.PageRect(0, 0, 50, 50)),
        25,
      ).copyWithMeta(deletedAt: 99);
      final tape = _stroke(
        'tp',
        segment(const ui.Offset(20, 330), const ui.Offset(220, 330)),
        _style(core.PenTool.tape, color: 0xFF7755CC, width: 14),
        1, // the oldest element, still on top (cover)
      );
      final content = _page(
        strokes: [s2, tape, hl, s1],
        objects: [text, unknown, sh2, image, flat, formula, deleted, sh1],
      );
      final v = InkVectorExport.exportPage(content);

      expect(v.underlay, hasLength(1));
      expect(v.underlay.single.assetId, 'asset-a');
      expect(v.highlighterGroups.single.lines.single.strokeId, 'hl');
      expect(
        [for (final s in v.inkShapes) (s.strokeId, s.objectId)],
        [
          ('s1', null),
          ('sh1', 'sh1'), // fill
          ('sh1', 'sh1'), // outline
          ('s2', null),
          ('sh2', 'sh2'),
        ],
      );
      expect(
        [for (final a in v.annotations) a.frame],
        [formula.frame, text.frame],
      );
      expect(v.annotations.first, isA<InkMathVector>());
      expect(v.annotations.last, isA<InkTextVector>());
      expect([for (final c in v.cover) c.strokeId], ['tp']);
      expect(v.isEmpty, isFalse);

      // bounds = the union of every piece
      var union = v.underlay.single.frame.bounds;
      ui.Rect r = ui.Rect.fromLTRB(
        union.left,
        union.top,
        union.right,
        union.bottom,
      );
      for (final s in [...v.inkShapes, ...v.cover]) {
        r = r.expandToInclude(s.path.bounds);
      }
      for (final a in v.annotations) {
        union = a.frame.bounds;
        r = r.expandToInclude(
          ui.Rect.fromLTRB(union.left, union.top, union.right, union.bottom),
        );
      }
      expect(v.bounds.left, lessThanOrEqualTo(r.left + 1e-3));
      expect(v.bounds.top, lessThanOrEqualTo(r.top + 1e-3));
      expect(v.bounds.right, greaterThanOrEqualTo(r.right - 1e-3));
      expect(v.bounds.bottom, greaterThanOrEqualTo(r.bottom - 1e-3));
    });

    test('several images and annotations keep their compareOrder (same '
        'createdAt → id order); the lists are unmodifiable', () {
      final objects = <core.PageObject>[
        for (final (id, t) in [('b', 5), ('a', 5), ('c', 1)])
          PageObjectFixtures.image(
            pageId: _pageId,
            assetId: 'asset-$id',
            createdAt: t,
            id: 'img-$id',
          ),
        for (final (id, t) in [('z', 3), ('y', 7), ('x', 3)])
          _text('t-$id', const core.PageRect(10, 10, 110, 60), id, t),
      ];
      final v = InkVectorExport.exportPage(_page(objects: objects));
      expect(
        [for (final i in v.underlay) i.assetId],
        ['asset-c', 'asset-a', 'asset-b'],
      );
      expect(
        [for (final a in v.annotations) (a as InkTextVector).object.id],
        ['t-x', 't-z', 't-y'],
      );
      expect(() => v.underlay.add(v.underlay.first), throwsUnsupportedError);
      expect(
        () => v.annotations.add(v.annotations.first),
        throwsUnsupportedError,
      );
      expect(v.cover.clear, throwsUnsupportedError);
    });

    test('a page with objects only is not empty; an unknown object alone '
        'exports nothing (isEmpty, Rect.zero)', () {
      final onlyUnknown = InkVectorExport.exportPage(
        _page(objects: [PageObjectFixtures.unknown(pageId: _pageId)]),
      );
      expect(onlyUnknown.isEmpty, isTrue);
      expect(onlyUnknown.bounds, ui.Rect.zero);
      final onlyMath = InkVectorExport.exportPage(
        _page(objects: [PageObjectFixtures.math(pageId: _pageId)]),
      );
      expect(onlyMath.isEmpty, isFalse);
      expect(onlyMath.inkShapes, isEmpty);
      expect(onlyMath.bounds, const ui.Rect.fromLTRB(100, 600, 200, 650));
    });
  });

  group('strokes', () {
    test('a dashed stroke → ONE InkFillShape whose sub-paths are its dash '
        'outlines (and dots)', () {
      for (final pattern in const [
        [4.0, 3.0],
        [0.0, 2.0],
      ]) {
        final style = _style(
          core.PenTool.dashed,
          color: _blue,
          width: 2,
        ).withInkExtras(dashPattern: pattern);
        final s = _stroke('d', _wave(const ui.Offset(20, 60)), style, 1);
        final v = InkVectorExport.exportPage(_page(strokes: [s]));
        final shape = v.inkShapes.single;
        expect(shape.objectId, isNull);
        expect(shape.tool, core.PenTool.dashed);
        final outline = OutlineGenerator.outline(InkStroke.of(s));
        final pieces = outline.polygons.length + outline.dots.length;
        expect(pieces, greaterThan(10), reason: '$pattern');
        expect(_subpaths(shape.path), pieces, reason: '$pattern');
        final expected = outline.toVectorPath();
        expect(shape.path.verbs, orderedEquals(expected.verbs));
        expect(shape.path.coords, orderedEquals(expected.coords));
      }
    });

    test('a tape → cover: its covered outline, opaque color, opacity 1 '
        '(style opacity 0.3 too), never in inkShapes; the reveal state on '
        'screen does not change the export', () async {
      final tape = _stroke(
        'tp',
        segment(const ui.Offset(20, 60), const ui.Offset(220, 90)),
        _style(core.PenTool.tape, color: 0x807755CC, width: 14, opacity: 0.3),
        1,
      );
      final ink = _stroke(
        'ink',
        _wave(const ui.Offset(20, 70)),
        _style(core.PenTool.ballpoint, width: 3),
        2, // newer than the tape: still below it
      );
      final content = _page(strokes: [tape, ink]);
      final controller = createTestPageController()..updateContent(content);
      addTearDown(controller.dispose);
      final covered = InkVectorExport.exportPage(controller.content!);
      controller.setAllTapesRevealed(true);
      final revealed = InkVectorExport.exportPage(controller.content!);
      expect(revealed, covered);
      final c = covered.cover.single;
      expect(c.strokeId, 'tp');
      expect(c.tool, core.PenTool.tape);
      expect(c.opacity, 1.0);
      expect(c.colorArgb, 0xFF7755CC);
      expect(c.objectId, isNull);
      final expected = OutlineGenerator.outline(InkStroke.of(tape))
          .toVectorPath();
      expect(c.path.coords, orderedEquals(expected.coords));
      expect([for (final s in covered.inkShapes) s.strokeId], ['ink']);
    });

    test('a stored laser stroke → the ballpoint fallback the screen draws '
        '(tool stays laser)', () {
      final points = _wave(const ui.Offset(20, 60));
      final laser = _stroke(
        'lz',
        points,
        _style(core.PenTool.laser, color: _red, width: 3, opacity: 1),
        1,
      );
      final ballpoint = _stroke(
        'bp',
        points,
        _style(core.PenTool.ballpoint, color: _red, width: 3, opacity: 1),
        1,
      );
      final shape = InkVectorExport.exportPage(_page(strokes: [laser]))
          .inkShapes
          .single;
      expect(shape.tool, core.PenTool.laser);
      expect(shape.objectId, isNull);
      expect(shape.colorArgb, _red);
      final fallback = OutlineGenerator.outline(InkStroke.of(ballpoint))
          .toVectorPath();
      expect(shape.path.verbs, orderedEquals(fallback.verbs));
      expect(shape.path.coords, orderedEquals(fallback.coords));
    });

    test('exportStrokes takes strokes only: dashed, tape and laser rules '
        'apply, the object lists stay empty', () {
      final dashed = _stroke(
        'd',
        _wave(const ui.Offset(20, 60)),
        _style(core.PenTool.dashed, width: 2),
        1,
      );
      final tape = _stroke(
        'tp',
        segment(const ui.Offset(20, 60), const ui.Offset(220, 90)),
        _style(core.PenTool.tape, width: 12),
        2,
      );
      final page = InkVectorExport.exportPage(_page(strokes: [dashed, tape]));
      final strokes = InkVectorExport.exportStrokes([
        InkStroke.of(tape),
        InkStroke.of(dashed),
      ]);
      expect(strokes, page);
      expect(strokes.underlay, isEmpty);
      expect(strokes.annotations, isEmpty);
      expect(strokes.cover, hasLength(1));
    });
  });

  group('shapes (6.9.5, CP-INK-1)', () {
    test('a filled closed polyline: the fill piece (its polygon, fill color '
        'and opacity) then the outline piece (the 6.9.5 polygons, stroke '
        'color and opacity); objectId = strokeId = id, tool = ballpoint', () {
      final star = _shape(
        'st',
        core.ShapeKind.star,
        core.ShapeGeometry.star(const core.PageRect(40, 40, 240, 240)),
        1,
        color: 0x33112233, // the alpha is ignored (K-5)
        width: 5,
        opacity: 0.6,
        fill: 0x80AA5500,
        fillOpacity: 0.4,
      );
      final v = InkVectorExport.exportPage(_page(objects: [star]));
      expect(v.inkShapes, hasLength(2));
      final [fill, outline] = v.inkShapes;
      for (final piece in v.inkShapes) {
        expect(piece.objectId, 'st');
        expect(piece.strokeId, 'st');
        expect(piece.tool, core.PenTool.ballpoint);
      }
      expect(fill.colorArgb, 0xFFAA5500);
      expect(fill.opacity, 0.4);
      expect(outline.colorArgb, 0xFF112233);
      expect(outline.opacity, 0.6);
      final points = (star.geometry as core.PolylineGeometry).points;
      expect(_verbs(fill.path), [
        InkPathVerb.moveTo,
        for (var i = 1; i < points.length; i++) InkPathVerb.lineTo,
        InkPathVerb.close,
      ]);
      expect(fill.path.coords, [
        for (final p in points) ...[closeTo(p.x, 1e-4), closeTo(p.y, 1e-4)],
      ]);
      _expectSamePolygons(
        _polygonsOf(outline.path),
        shapeOutlineOf(star).stroke,
      );
      // the screen paints the fill first, then the outline (6.9.1)
      expect(v.bounds, outline.path.bounds.expandToInclude(fill.path.bounds));
    });

    test('an ellipse fill = 4 cubics (k = 0.5523) about the rotated frame; '
        'every on-curve point on the ellipse', () {
      const rotation = 0.6;
      final e = _shape(
        'el',
        core.ShapeKind.ellipse,
        core.ShapeGeometry.ellipse(
          const core.PageRect(100, 100, 300, 200),
          rotation: rotation,
        ),
        1,
        fill: _red,
        dash: core.LineDash.dashed,
      );
      final [fill, outline] = InkVectorExport.exportPage(_page(objects: [e]))
          .inkShapes;
      expect(_verbs(fill.path), [
        InkPathVerb.moveTo,
        InkPathVerb.cubicTo,
        InkPathVerb.cubicTo,
        InkPathVerb.cubicTo,
        InkPathVerb.cubicTo,
        InkPathVerb.close,
      ]);
      final c = fill.path.coords;
      const cx = 200.0, cy = 150.0, a = 100.0, b = 50.0;
      ui.Offset local(int i) {
        final dx = c[i] - cx, dy = c[i + 1] - cy;
        return ui.Offset(
          dx * math.cos(rotation) + dy * math.sin(rotation),
          -dx * math.sin(rotation) + dy * math.cos(rotation),
        );
      }

      final onCurve = [0, 6, 12, 18, 24].map(local).toList();
      final expected = const [
        ui.Offset(a, 0),
        ui.Offset(0, b),
        ui.Offset(-a, 0),
        ui.Offset(0, -b),
        ui.Offset(a, 0),
      ];
      for (var i = 0; i < 5; i++) {
        expect(onCurve[i].dx, closeTo(expected[i].dx, 1e-3));
        expect(onCurve[i].dy, closeTo(expected[i].dy, 1e-3));
      }
      // first control points: (a, k·b) and (k·a, b)
      expect(local(2).dx, closeTo(a, 1e-3));
      expect(local(2).dy, closeTo(0.5523 * b, 1e-3));
      expect(local(4).dx, closeTo(0.5523 * a, 1e-3));
      expect(local(4).dy, closeTo(b, 1e-3));
      // the dashed outline: dash pieces only (one sub-path each)
      _expectSamePolygons(_polygonsOf(outline.path), shapeOutlineOf(e).stroke);
      expect(_subpaths(outline.path), greaterThan(10));
    });

    test('an arrow: the line and the heads in ONE piece; every sub-path has '
        'the positive orientation (one nonzero fill paints the overlap once '
        '— S-10); the head triangles are sub-paths', () {
      for (final heads in [core.ArrowHeads.end, core.ArrowHeads.both]) {
        final arrow = _shape(
          'ar',
          core.ShapeKind.arrow,
          core.ShapeGeometry.line(
            const core.PagePoint(40, 200),
            const core.PagePoint(260, 120),
          ),
          1,
          width: 6,
          opacity: 0.5,
          heads: heads,
          fill: _red, // open polyline: never filled
        );
        final piece = InkVectorExport.exportPage(_page(objects: [arrow]))
            .inkShapes
            .single;
        expect(piece.opacity, 0.5);
        final polygons = _polygonsOf(piece.path);
        for (final p in polygons) {
          expect(shoelaceArea(p), greaterThan(0), reason: '$heads');
        }
        final triangles = shapeGeometryOf(arrow).heads;
        expect(triangles, hasLength(heads == core.ArrowHeads.both ? 2 : 1));
        for (final t in triangles) {
          final match = polygons.where((p) {
            if (p.length != 6) return false;
            final pts = {
              for (var i = 0; i < 6; i += 2)
                (p[i].toStringAsFixed(3), p[i + 1].toStringAsFixed(3)),
            };
            return t.every(
              (q) => pts.contains((
                q.dx.toStringAsFixed(3),
                q.dy.toStringAsFixed(3),
              )),
            );
          });
          expect(match, hasLength(1), reason: '$heads: head $t');
        }
        _expectSamePolygons(polygons, shapeOutlineOf(arrow).stroke);
      }
    });

    test('dotted outlines are circle polygons in the outline piece; fill '
        'opacity 0 → no fill piece; an open polyline with a fill color → no '
        'fill piece', () {
      final dotted = _shape(
        'dt',
        core.ShapeKind.triangle,
        core.ShapeGeometry.triangle(const core.PageRect(20, 20, 220, 200)),
        1,
        dash: core.LineDash.dotted,
        width: 3,
        fill: _red,
        fillOpacity: 0,
      );
      final line = _shape(
        'ln',
        core.ShapeKind.line,
        core.ShapeGeometry.line(
          const core.PagePoint(20, 260),
          const core.PagePoint(220, 280),
        ),
        2,
        fill: _red,
      );
      final v = InkVectorExport.exportPage(_page(objects: [dotted, line]));
      expect([for (final s in v.inkShapes) s.strokeId], ['dt', 'ln']);
      final dots = shapeGeometryOf(dotted).dots;
      expect(dots.length, greaterThan(20));
      final path = v.inkShapes.first.path;
      expect(_subpaths(path), dots.length);
      // each dot an exact circle: moveTo (x + r, y) + 4 cubics (k = 0.5523)
      expect(_verbs(path).take(6), [
        InkPathVerb.moveTo,
        InkPathVerb.cubicTo,
        InkPathVerb.cubicTo,
        InkPathVerb.cubicTo,
        InkPathVerb.cubicTo,
        InkPathVerb.close,
      ]);
      expect(path.coords[0], closeTo(dots.first.dx + 1.5, 1e-4));
      expect(path.coords[1], closeTo(dots.first.dy, 1e-4));
      expect(path.coords[3], closeTo(dots.first.dy + 0.5523 * 1.5, 1e-4));
      for (final p in _onCurve(path)) {
        expect(shoelaceArea(p), greaterThan(0));
      }
    });
  });

  test('K-6: every exported shape piece (control points included) is inside '
      'the CORE bounds — 7 kinds × solid / dashed / dotted × arrow heads × '
      'rotation × widths, filled', () {
    var checked = 0;
    for (final kind in core.ShapeKind.values) {
      for (final dash in core.LineDash.values) {
        for (final heads in core.ArrowHeads.values) {
          for (final rotation in const [0.0, 0.5]) {
            for (final width in const [0.1, 3.0, 30.0]) {
              const r = core.PageRect(100, 100, 260, 200);
              final geometry = switch (kind) {
                core.ShapeKind.line ||
                core.ShapeKind.arrow => core.ShapeGeometry.line(
                  const core.PagePoint(100, 200),
                  const core.PagePoint(260, 100),
                ),
                core.ShapeKind.rectangle => core.ShapeGeometry.rectangle(
                  r,
                  rotation: rotation,
                ),
                core.ShapeKind.ellipse => core.ShapeGeometry.ellipse(
                  r,
                  rotation: rotation,
                ),
                core.ShapeKind.triangle => core.ShapeGeometry.triangle(r),
                core.ShapeKind.polygon => core.ShapeGeometry.regularPolygon(
                  r,
                  6,
                  rotation: rotation,
                ),
                core.ShapeKind.star => core.ShapeGeometry.star(r),
              };
              final o = _shape(
                'k',
                kind,
                geometry,
                1,
                width: width,
                dash: dash,
                heads: heads,
                fill: _red,
              );
              final b = o.bounds;
              final v = InkVectorExport.exportPage(_page(objects: [o]));
              expect(v.inkShapes, isNotEmpty);
              for (final piece in v.inkShapes) {
                final pb = piece.path.bounds;
                final why = '$kind $dash $heads $rotation $width';
                expect(
                  pb.left,
                  greaterThanOrEqualTo(b.left - 0.01),
                  reason: why,
                );
                expect(pb.top, greaterThanOrEqualTo(b.top - 0.01), reason: why);
                expect(
                  pb.right,
                  lessThanOrEqualTo(b.right + 0.01),
                  reason: why,
                );
                expect(
                  pb.bottom,
                  lessThanOrEqualTo(b.bottom + 0.01),
                  reason: why,
                );
                checked++;
              }
            }
          }
        }
      }
    }
    expect(checked, greaterThan(500));
  });

  group('text lines (6.10.2, CP-INK-9)', () {
    tearDown(() => debugSetInkFontSource(null));

    test('before NoteSans is loaded: the text vector without lines; after the '
        'load: the lines of the screen paragraph (count, x, baseline, width), '
        'the text without line breaks, soft wraps rebuild the text', () async {
      debugSetInkFontSource(_files);
      expect(InkFontsDebug.isLoaded, isFalse);
      const text =
          '첫 줄은 짧다\n둘째 줄은 이 상자보다 훨씬 길어서 음절 사이에서 '
          '줄이 바뀐다 hello world\n\n끝';
      final box = _text(
        'tx',
        const core.PageRect(50, 50, 210, 650),
        text,
        1,
        style: const core.TextBoxStyle(fontSizePt: 14, lineHeight: 1.5),
      );
      final before = InkVectorExport.exportPage(_page(objects: [box]));
      final vector = before.annotations.single as InkTextVector;
      expect(vector.object, same(box));
      expect(vector.frame, box.frame);
      expect(vector.lines, isEmpty);

      await InkFonts.ensureLoaded();
      final after = InkVectorExport.exportPage(_page(objects: [box]));
      final lines = (after.annotations.single as InkTextVector).lines;
      final paragraph = buildTextBoxParagraph(text, box.style, 160);
      final metrics = paragraph.computeLineMetrics();
      expect(lines.length, paragraph.numberOfLines);
      expect(lines.length, greaterThanOrEqualTo(6), reason: 'soft wraps');
      for (var i = 0; i < lines.length; i++) {
        expect(lines[i].x, metrics[i].left, reason: 'line $i');
        expect(lines[i].baselineY, metrics[i].baseline, reason: 'line $i');
        expect(lines[i].width, metrics[i].width, reason: 'line $i');
        expect(lines[i].text.contains('\n'), isFalse);
      }
      expect(lines.first.text, '첫 줄은 짧다');
      expect(lines.last.text, '끝');
      expect(lines[lines.length - 2].text, '', reason: 'the empty line');
      // the hard breaks are the lines that ended with '\n' — joining the rest
      // back gives the text
      final hard = <int>{};
      var offset = 0;
      for (var i = 0; i < lines.length; i++) {
        offset += lines[i].text.length;
        if (offset < text.length && text[offset] == '\n') {
          hard.add(i);
          offset++;
        }
      }
      final rebuilt = StringBuffer();
      for (var i = 0; i < lines.length; i++) {
        rebuilt.write(lines[i].text);
        if (hard.contains(i)) rebuilt.write('\n');
      }
      expect(rebuilt.toString(), text);
      expect(hard, hasLength(3));
      // baselines go down one forced strut line (14 × 1.5) at a time
      for (var i = 1; i < lines.length; i++) {
        expect(
          lines[i].baselineY - lines[i - 1].baselineY,
          closeTo(metrics[i].height, 0.01),
        );
      }
    });

    test('lines that start at or below the frame height are left out; the '
        'alignment moves x; a rotated frame keeps frame-local lines; an '
        'empty text has no lines', () async {
      debugSetInkFontSource(_files);
      await InkFonts.ensureLoaded();
      const style = core.TextBoxStyle(fontSizePt: 16, lineHeight: 1.25);
      const text = 'a\nb\nc\nd\ne';
      final full = buildTextBoxParagraph(text, style, 200).computeLineMetrics();
      final lineH = full.first.height;
      for (final (height, expected) in [
        (lineH * 5, 5),
        (lineH * 3, 3), // the 4th line starts exactly at the bottom
        (lineH * 3 + 0.5, 4), // its top 0.5 pt shows
        (1.0, 1),
      ]) {
        final box = _text(
          'b',
          core.PageRect(0, 0, 200, height),
          text,
          1,
          style: style,
        );
        final lines =
            (InkVectorExport.exportPage(_page(objects: [box]))
                        .annotations
                        .single
                    as InkTextVector)
                .lines;
        expect(lines.length, expected, reason: 'height $height');
        expect(
          [for (final l in lines) l.text],
          [for (var i = 0; i < expected; i++) 'abcde'[i]],
        );
      }
      final centered = _text(
        'c',
        const core.PageRect(0, 0, 200, 100),
        'mid',
        1,
        style: const core.TextBoxStyle(align: core.TextAlignKind.center),
        rotation: math.pi / 6,
      );
      final line =
          (InkVectorExport.exportPage(_page(objects: [centered]))
                      .annotations
                      .single
                  as InkTextVector)
              .lines
              .single;
      expect(line.x, closeTo((200 - line.width) / 2, 0.01));
      expect(line.baselineY, lessThan(lineH * 1.5));
      final empty = _text(
        'e',
        const core.PageRect(0, 0, 200, 100),
        '',
        1,
        style: const core.TextBoxStyle(backgroundArgb: 0xFFFFEEAA),
      );
      final emptyVector =
          InkVectorExport.exportPage(_page(objects: [empty])).annotations.single
              as InkTextVector;
      expect(emptyVector.lines, isEmpty);
      expect(emptyVector.object.style.backgroundArgb, 0xFFFFEEAA);
    });
  });

  test('formulas and images: their fields; a formula that does not parse is '
      'still exported (PDF draws its placeholder)', () {
    final image =
        PageObjectFixtures.image(
          pageId: _pageId,
          assetId: 'asset-x',
          rect: const core.PageRect(20, 30, 220, 180),
          pixelWidth: 1600,
          pixelHeight: 1200,
          id: 'im',
        ).copyWith(
          frame: core.ElementFrame(
            const core.PageRect(20, 30, 220, 180),
            rotation: 0.3,
          ),
        );
    final good = PageObjectFixtures.math(pageId: _pageId, id: 'm1');
    final bad = PageObjectFixtures.math(
      pageId: _pageId,
      latex: r'\frac{a',
      createdAt: 2,
      id: 'm2',
    );
    final v = InkVectorExport.exportPage(_page(objects: [bad, image, good]));
    final iv = v.underlay.single;
    expect(iv.assetId, 'asset-x');
    expect(iv.frame, image.frame);
    expect(iv.frame.rotation, 0.3);
    expect((iv.pixelWidth, iv.pixelHeight), (1600, 1200));
    final [m1, m2] = v.annotations;
    expect((m1 as InkMathVector).object, same(good));
    expect(m1.frame, good.frame);
    expect((m2 as InkMathVector).object, same(bad));
    expect(v.inkShapes, isEmpty);
    expect(v.cover, isEmpty);
    expect(v.highlighterGroups, isEmpty);
  });

  test('the exported paths painted (PDF order) = the screen painting: ink '
      'within 1%, < 1% of the pixels differ and only on edges (strokes, dashed '
      'stroke, shapes z-mixed, fills, dashes, dots, translucent arrows, '
      'tape on top)', () async {
    final strokes = [
      _stroke(
        'bp',
        _wave(const ui.Offset(20, 60), length: 260, amp: 30),
        _style(core.PenTool.ballpoint, color: _blue, width: 3),
        10,
      ),
      _stroke(
        'ds',
        _wave(const ui.Offset(20, 250), length: 260),
        _style(core.PenTool.dashed, color: _red, width: 2.5),
        30,
      ),
      _stroke(
        'tp',
        segment(const ui.Offset(30, 180), const ui.Offset(270, 200)),
        _style(core.PenTool.tape, color: 0xFF7755CC, width: 12),
        5,
      ),
    ];
    final objects = <core.PageObject>[
      _shape(
        'rc',
        core.ShapeKind.rectangle,
        core.ShapeGeometry.rectangle(const core.PageRect(40, 40, 160, 140)),
        20, // above bp, below ds
        color: _green,
        width: 5,
        dash: core.LineDash.dashed,
        fill: 0xFFFFCC00,
        fillOpacity: 0.7,
      ),
      _shape(
        'el',
        core.ShapeKind.ellipse,
        core.ShapeGeometry.ellipse(
          const core.PageRect(150, 30, 280, 120),
          rotation: 0.4,
        ),
        25,
        color: _blue,
        width: 4,
        fill: 0xFF66CCFF,
      ),
      _shape(
        'ar',
        core.ShapeKind.arrow,
        core.ShapeGeometry.line(
          const core.PagePoint(30, 290),
          const core.PagePoint(270, 220),
        ),
        40,
        color: _red,
        width: 6,
        opacity: 0.5,
        heads: core.ArrowHeads.both,
      ),
      _shape(
        'sr',
        core.ShapeKind.star,
        core.ShapeGeometry.star(const core.PageRect(170, 130, 270, 230)),
        15,
        color: 0xFF222222,
        width: 3,
        dash: core.LineDash.dotted,
      ),
    ];
    final content = _page(strokes: strokes, objects: objects);
    final v = InkVectorExport.exportPage(content);

    final exported = await renderPixels(300, 300, (canvas) {
      paintPaper(canvas, core.PaperColors.white, size: 300);
      for (final s in [...v.inkShapes, ...v.cover]) {
        canvas.drawPath(
          s.path.toUiPath(),
          ui.Paint()
            ..isAntiAlias = true
            ..color = inkColor(s.colorArgb, s.opacity),
        );
      }
    });
    final byId = {for (final o in objects) o.id: o};
    final screen = await renderPixels(300, 300, (canvas) {
      paintPaper(canvas, core.PaperColors.white, size: 300);
      // the ink layer in compareOrder, then the cover layer (L-1)
      final items =
          [...content.strokes.where((s) => s.layer == InkLayer.ink), ...objects]
            ..sort((a, b) {
              core.PageElement el(Object x) =>
                  x is InkStroke ? x.source : x as core.PageElement;
              return core.Stroke.compareOrder(el(a), el(b));
            });
      for (final item in items) {
        if (item is InkStroke) {
          paintFillStroke(canvas, item, OutlineGenerator.outline(item));
        } else {
          paintShape(
            canvas,
            byId[(item as core.PageObject).id]! as core.ShapeObject,
          );
        }
      }
      for (final s in content.strokes.where((s) => s.layer == InkLayer.cover)) {
        paintTapeCovered(canvas, s, OutlineGenerator.outline(s));
      }
    });
    // Skia rasterizes a stroked curve and the filled outline polygon a little
    // differently (an oval stroke covers ~1% more than its geometry, a 3 px dot
    // a little less): edge pixels may differ, the ink and the shapes match.
    int ink(List<int> p) => 765 - p[0] - p[1] - p[2];
    bool flat(int x, int y) {
      final c = screen.at(x, y);
      for (final (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
        if (!samePixel(screen.at(x + dx, y + dy), c)) return false;
      }
      return true;
    }

    var inkExported = 0, inkScreen = 0, inked = 0, maxDiff = 0;
    for (var y = 1; y < 299; y++) {
      for (var x = 1; x < 299; x++) {
        final a = exported.at(x, y), b = screen.at(x, y);
        inkExported += ink(a);
        inkScreen += ink(b);
        if (ink(b) > 24) inked++;
        var d = 0;
        for (var k = 0; k < 3; k++) {
          d = math.max(d, (a[k] - b[k]).abs());
        }
        if (d > 24) {
          expect(flat(x, y), isFalse, reason: '($x, $y) off an edge');
        }
        maxDiff = math.max(maxDiff, d);
      }
    }
    expect(inked, greaterThan(10000));
    // measured: ink −0.04%, 0.34% of the pixels differ by > 24, at most 73
    expect((inkExported - inkScreen).abs() / inkScreen, lessThan(0.01));
    expect(differingShare(exported, screen, tolerance: 24), lessThan(0.01));
    expect(maxDiff, lessThanOrEqualTo(96));
  });

  test('InkVectorFixtures rebuilds the real export value (==)', () async {
    debugSetInkFontSource(_files);
    addTearDown(() => debugSetInkFontSource(null));
    await InkFonts.ensureLoaded();
    final image = PageObjectFixtures.image(
      pageId: _pageId,
      assetId: 'asset-f',
      createdAt: 9,
      id: 'im',
    );
    final hl = _stroke(
      'hl',
      segment(const ui.Offset(20, 40), const ui.Offset(200, 40)),
      _style(core.PenTool.highlighter, color: 0xFFFFEE00),
      1,
    );
    final bp = _stroke(
      'bp',
      _wave(const ui.Offset(20, 80)),
      _style(core.PenTool.ballpoint, color: _blue, width: 3),
      2,
    );
    final rect = _shape(
      'rc',
      core.ShapeKind.rectangle,
      core.ShapeGeometry.rectangle(const core.PageRect(30, 30, 130, 110)),
      3,
      fill: _red,
      fillOpacity: 0.5,
    );
    final tape = _stroke(
      'tp',
      segment(const ui.Offset(20, 140), const ui.Offset(220, 140)),
      _style(core.PenTool.tape, color: 0xFF7755CC, width: 12),
      4,
    );
    final box = _text(
      'tx',
      const core.PageRect(40, 300, 440, 400),
      '첫 줄\n둘째 줄 hello\n',
      5,
    );
    final formula = PageObjectFixtures.math(
      pageId: _pageId,
      createdAt: 6,
      id: 'mx',
    );
    final content = _page(
      strokes: [hl, bp, tape],
      objects: [image, rect, box, formula],
    );
    final actual = InkVectorExport.exportPage(content);

    final metrics = buildTextBoxParagraph(
      box.text,
      box.style,
      400,
    ).computeLineMetrics();
    final points = (rect.geometry as core.PolylineGeometry).points;
    final bpPath = OutlineGenerator.outline(InkStroke.of(bp)).toVectorPath();
    final hlStroke = InkStroke.of(hl);
    final rebuilt = InkVectorFixtures.pageVectors(
      highlighterGroups: [
        InkVectorFixtures.highlighterGroup(
          colorArgb: 0xFFFFEE00,
          opacity: hlStroke.style.opacity,
          blend: InkBlendMode.multiply,
          lines: [
            InkVectorFixtures.highlighterLine(
              strokeId: 'hl',
              centerline: InkVectorPath(
                Uint8List.fromList([
                  InkPathVerb.moveTo.index,
                  for (var i = 1; i < hlStroke.points.length; i++)
                    InkPathVerb.lineTo.index,
                ]),
                Float32List.fromList([
                  for (var i = 0; i < hlStroke.points.length; i++) ...[
                    hlStroke.points.x(i),
                    hlStroke.points.y(i),
                  ],
                ]),
              ),
              width: hlStroke.style.width,
              cap: hlStroke.profile.cap,
            ),
          ],
        ),
      ],
      inkShapes: [
        InkVectorFixtures.fillShape(
          strokeId: 'bp',
          tool: core.PenTool.ballpoint,
          path: bpPath,
          colorArgb: _blue,
          opacity: 1,
        ),
        InkVectorFixtures.fillShape(
          strokeId: 'rc',
          tool: core.PenTool.ballpoint,
          path: InkVectorPath(
            Uint8List.fromList([
              InkPathVerb.moveTo.index,
              for (var i = 1; i < points.length; i++) InkPathVerb.lineTo.index,
              InkPathVerb.close.index,
            ]),
            Float32List.fromList([
              for (final p in points) ...[p.x, p.y],
            ]),
          ),
          colorArgb: _red,
          opacity: 0.5,
          objectId: 'rc',
        ),
        InkVectorFixtures.fillShape(
          strokeId: 'rc',
          tool: core.PenTool.ballpoint,
          path: _outlinePathOf(rect),
          colorArgb: _green,
          objectId: 'rc',
        ),
      ],
      underlay: [
        InkVectorFixtures.imageVector(
          assetId: 'asset-f',
          frame: image.frame,
          pixelWidth: image.pixelWidth,
          pixelHeight: image.pixelHeight,
        ),
      ],
      annotations: [
        InkVectorFixtures.textVector(
          object: box,
          lines: [
            for (final (i, t) in ['첫 줄', '둘째 줄 hello', ''].indexed)
              InkVectorFixtures.textLine(
                text: t,
                x: metrics[i].left,
                baselineY: metrics[i].baseline,
                width: metrics[i].width,
              ),
          ],
        ),
        InkVectorFixtures.mathVector(object: formula),
      ],
      cover: [
        InkVectorFixtures.fillShape(
          strokeId: 'tp',
          tool: core.PenTool.tape,
          path: OutlineGenerator.outline(InkStroke.of(tape)).toVectorPath(),
          colorArgb: 0xFF7755CC,
        ),
      ],
      bounds: actual.bounds,
    );
    expect(metrics, hasLength(3));
    expect(rebuilt, actual);
    expect(rebuilt.hashCode, actual.hashCode);
    // one field off → not equal
    final other = InkVectorFixtures.pageVectors(
      highlighterGroups: rebuilt.highlighterGroups,
      inkShapes: rebuilt.inkShapes,
      underlay: rebuilt.underlay,
      annotations: rebuilt.annotations.sublist(1),
      cover: rebuilt.cover,
      bounds: actual.bounds,
    );
    expect(other == actual, isFalse);
  });
}
