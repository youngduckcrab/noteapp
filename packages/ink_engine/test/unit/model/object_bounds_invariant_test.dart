// m5-7/03-ink T33 (6.9.4 K-6, contract 7.3.2): every page object is drawn
// inside its CORE bounds.
// - Shapes: 7 kinds × rotation 0 · 30 · 90° × width 0.1 · 2 · 30 × line style
//   3 × arrow heads 3 (line / arrow kinds) × fill on / off (closed kinds) and
//   200 random shapes (random points, widths, opacities): the geometry (the
//   stroked path's bounds + w / 2, the dots, the heads, the fill, the vector
//   outline polygons) is inside bounds (0.01 pt), and the rendered pixels are
//   inside bounds + 1 device px (anti-aliasing fringe, as 1차 6.7-6).
// - Text boxes, formulas, images and unknown objects at 0 · 30 · 90°: pixels
//   inside bounds + 1 px.
//
// Also run in Chrome by test/web/object_bounds_web_test.dart.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/src/interop/core_interop.dart' as interop;
import 'package:ink_engine/src/object/object_painter.dart';
import 'package:ink_engine/src/object/shape_path.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

const double _tol = 0.01;
const _margin = 6;

/// MINSTD (web-safe: every product < 2^53, no bit operations).
final class _Rng {
  _Rng(this._state);
  int _state;
  double next() {
    _state = (_state * 48271) % 2147483647;
    return _state / 2147483647;
  }

  double range(double a, double b) => a + (b - a) * next();
  int nextInt(int n) => (next() * n).floor().clamp(0, n - 1);
}

const _center = core.PagePoint(200, 150);
const _frame = core.PageRect(140, 110, 260, 190);

core.Affine2 _rotation(double radians) =>
    core.Affine2.rotation(radians, originX: _center.x, originY: _center.y);

core.ShapeGeometry _geometryOf(core.ShapeKind kind, double rot) =>
    switch (kind) {
      core.ShapeKind.line => core.ShapeGeometry.line(
        const core.PagePoint(140, 110),
        const core.PagePoint(260, 190),
      ).transformed(_rotation(rot)),
      core.ShapeKind.arrow => const core.PolylineGeometry([
        core.PagePoint(140, 190),
        core.PagePoint(200, 110),
        core.PagePoint(260, 150),
      ], closed: false).transformed(_rotation(rot)),
      core.ShapeKind.rectangle => core.ShapeGeometry.rectangle(
        _frame,
        rotation: rot,
      ),
      core.ShapeKind.ellipse => core.ShapeGeometry.ellipse(
        _frame,
        rotation: rot,
      ),
      core.ShapeKind.triangle => core.ShapeGeometry.triangle(
        _frame,
      ).transformed(_rotation(rot)),
      core.ShapeKind.polygon => core.ShapeGeometry.regularPolygon(
        _frame,
        6,
        rotation: rot,
      ),
      core.ShapeKind.star => core.ShapeGeometry.star(
        _frame,
      ).transformed(_rotation(rot)),
    };

var _ids = 0;

core.ShapeObject _shape(
  core.ShapeKind kind,
  core.ShapeGeometry geometry, {
  required double width,
  required core.LineDash dash,
  required core.ArrowHeads heads,
  int? fill,
  double opacity = 1,
}) => core.ShapeObject(
  id: 'sh${_ids++}',
  pageId: 'p1',
  shapeKind: kind,
  geometry: geometry,
  style: core.ShapeStyle(
    strokeColorArgb: 0xFF202020,
    strokeWidth: width,
    strokeOpacity: opacity,
    dash: dash,
    arrowHeads: heads,
    fillColorArgb: fill,
    fillOpacity: 0.6,
  ),
  createdAt: 1,
);

bool _closedKind(core.ShapeKind k) =>
    k != core.ShapeKind.line && k != core.ShapeKind.arrow;

/// The shape geometry inside [o].bounds (0.01 pt).
void _expectGeometryInside(core.ShapeObject o) {
  final b = interop.rectOf(o.bounds).inflate(_tol);
  final g = shapeGeometryOf(o);
  final why =
      '${o.shapeKind} ${o.style.dash} ${o.style.arrowHeads} '
      'w ${o.style.strokeWidth} ${o.geometry}';
  bool inside(ui.Rect r) =>
      r.left >= b.left &&
      r.top >= b.top &&
      r.right <= b.right &&
      r.bottom <= b.bottom;
  final stroke = g.strokePath;
  if (stroke != null) {
    expect(
      inside(stroke.getBounds().inflate(g.width / 2)),
      isTrue,
      reason: 'stroke $why',
    );
  }
  for (final d in g.dots) {
    expect(
      inside(ui.Rect.fromCircle(center: d, radius: g.width / 2)),
      isTrue,
      reason: 'dot $why',
    );
  }
  for (final h in g.heads) {
    for (final p in h) {
      expect(
        b.contains(p) || inside(ui.Rect.fromPoints(p, p)),
        isTrue,
        reason: 'head $why',
      );
    }
  }
  final fill = g.fill;
  if (fill != null) {
    expect(inside(fill.getBounds()), isTrue, reason: 'fill $why');
  }
  final outline = shapeOutlineOf(o);
  for (final poly in [...outline.fill, ...outline.stroke]) {
    for (var i = 0; i < poly.length; i += 2) {
      expect(
        inside(ui.Rect.fromLTWH(poly[i], poly[i + 1], 0, 0)),
        isTrue,
        reason: 'vector $why',
      );
    }
  }
}

/// Renders [o] at 1 px per pt and expects no pixel outside bounds + 1 px.
Future<void> _expectPixelsInside(core.PageObject o) async {
  final b = interop.rectOf(o.bounds);
  final left = b.left.floor() - _margin, top = b.top.floor() - _margin;
  final w = b.right.ceil() + _margin - left,
      h = b.bottom.ceil() + _margin - top;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)
    ..translate(-left.toDouble(), -top.toDouble());
  expect(paintObjectSimple(canvas, o, paperArgb: 0xFFFFFFFF, onePx: 1), isTrue);
  final picture = recorder.endRecording();
  final image = await picture.toImage(w, h);
  final ByteData bytes;
  try {
    bytes = (await image.toByteData())!;
  } finally {
    image.dispose();
    picture.dispose();
  }
  // allowed: pixels meeting bounds + 1 px
  final allowed = b.inflate(1).translate(-left.toDouble(), -top.toDouble());
  var outside = 0;
  for (var y = 0; y < h; y++) {
    final rowInside = y + 1 > allowed.top && y < allowed.bottom;
    for (var x = 0; x < w; x++) {
      if (rowInside && x + 1 > allowed.left && x < allowed.right) continue;
      if (bytes.getUint8((y * w + x) * 4 + 3) != 0) outside++;
    }
  }
  expect(outside, 0, reason: 'pixels outside the bounds of $o');
}

void main() {
  final cases = <core.ShapeObject>[];
  for (final kind in core.ShapeKind.values) {
    for (final rot in const [0.0, math.pi / 6, math.pi / 2]) {
      for (final width in const [0.1, 2.0, 30.0]) {
        for (final dash in core.LineDash.values) {
          for (final heads
              in _closedKind(kind)
                  ? const [core.ArrowHeads.none]
                  : core.ArrowHeads.values) {
            for (final fill
                in _closedKind(kind)
                    ? const [null, 0xFF3366CC]
                    : const [null]) {
              cases.add(
                _shape(
                  kind,
                  _geometryOf(kind, rot),
                  width: width,
                  dash: dash,
                  heads: heads,
                  fill: fill,
                  opacity: heads == core.ArrowHeads.none ? 1 : 0.5,
                ),
              );
            }
          }
        }
      }
    }
  }
  final rng = _Rng(20261106);
  final random = <core.ShapeObject>[];
  for (var i = 0; i < 200; i++) {
    final kind = core.ShapeKind.values[rng.nextInt(7)];
    final width = rng.range(0.1, 30);
    final core.ShapeGeometry geometry;
    if (kind == core.ShapeKind.ellipse) {
      final x = rng.range(20, 300), y = rng.range(20, 300);
      geometry = core.ShapeGeometry.ellipse(
        core.PageRect(x, y, x + rng.range(0, 200), y + rng.range(0, 200)),
        rotation: rng.range(-math.pi, math.pi),
      );
    } else {
      final n = 2 + rng.nextInt(8);
      geometry = core.PolylineGeometry([
        for (var k = 0; k < n; k++)
          core.PagePoint(rng.range(20, 400), rng.range(20, 400)),
      ], closed: _closedKind(kind) && n > 2);
    }
    random.add(
      _shape(
        kind,
        geometry,
        width: width,
        dash: core.LineDash.values[rng.nextInt(3)],
        heads: core.ArrowHeads.values[rng.nextInt(3)],
        fill: rng.next() < 0.5 ? 0xFFCC6633 : null,
        opacity: rng.range(0.05, 1),
      ),
    );
  }

  test('shape geometry inside bounds: ${cases.length} grid + 200 random', () {
    // closed kinds 5 × 3 × 3 × 3 × fill 2 + open kinds 2 × 3 × 3 × 3 × heads 3
    expect(cases.length, 270 + 162);
    for (final o in [...cases, ...random]) {
      _expectGeometryInside(o);
    }
  });

  test('shape pixels inside bounds + 1 px (grid)', () async {
    for (final o in cases) {
      await _expectPixelsInside(o);
    }
  });

  test('shape pixels inside bounds + 1 px (200 random)', () async {
    for (final o in random) {
      await _expectPixelsInside(o);
    }
  });

  test(
    'text, formula, image and unknown pixels inside bounds + 1 px',
    () async {
      for (final rot in const [0.0, math.pi / 6, math.pi / 2]) {
        final frame = core.ElementFrame(_frame, rotation: rot);
        final objects = <core.PageObject>[
          core.TextBoxObject(
            id: 'tx',
            pageId: 'p1',
            frame: frame,
            text:
                '안녕 hello — a long line that wraps and overflows the box\n'
                'second line\nthird line\nfourth line',
            style: const core.TextBoxStyle(backgroundArgb: 0xFFEEDD88),
            createdAt: 1,
          ),
          PageObjectFixtures.math(
            pageId: 'p1',
            id: 'mx',
            rect: _frame,
          ).copyWith(frame: frame),
          PageObjectFixtures.image(
            pageId: 'p1',
            assetId: 'a',
            id: 'im',
          ).copyWith(frame: frame),
          if (rot == 0)
            PageObjectFixtures.unknown(pageId: 'p1', id: 'un', rect: _frame),
        ];
        for (final o in objects) {
          await _expectPixelsInside(o);
        }
      }
    },
  );
}
