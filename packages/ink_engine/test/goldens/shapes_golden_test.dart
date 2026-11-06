@TestOn('vm')
@Tags(['golden'])
library;

// m5-7/03-ink T33 (6.9, 9.4): the shapes on white paper, drawn by the page
// object painter — no text.
// - shapes_lines.png: the 7 kinds (rows) × solid · dashed · dotted (columns).
// - shapes_fill_arrows.png: the 5 closed kinds filled; line / arrow with heads
//   end and both (solid, dashed, opacity 0.5); filled dashed / dotted, a
//   rotated filled star, a thick arrow.
// Update with: flutter test --update-goldens test/goldens/shapes_golden_test.dart
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/src/object/object_painter.dart';
import 'package:note_core/note_core.dart' as core;

const _ink = 0xFF1F3A93;
const _fill = 0xFFF2A541;

var _ids = 0;

core.ShapeObject _shape(
  core.ShapeKind kind,
  core.ShapeGeometry geometry, {
  double width = 3,
  core.LineDash dash = core.LineDash.solid,
  core.ArrowHeads heads = core.ArrowHeads.none,
  int? fill,
  double opacity = 1,
}) => core.ShapeObject(
  id: 'g${_ids++}',
  pageId: 'p1',
  shapeKind: kind,
  geometry: geometry,
  style: core.ShapeStyle(
    strokeColorArgb: _ink,
    strokeWidth: width,
    strokeOpacity: opacity,
    dash: dash,
    arrowHeads: heads,
    fillColorArgb: fill,
    fillOpacity: 0.7,
  ),
  createdAt: 1,
);

/// The geometry of [kind] inside [r].
core.ShapeGeometry _geometry(core.ShapeKind kind, core.PageRect r) =>
    switch (kind) {
      core.ShapeKind.line => core.ShapeGeometry.line(
        core.PagePoint(r.left, r.bottom),
        core.PagePoint(r.right, r.top),
      ),
      core.ShapeKind.arrow => core.PolylineGeometry([
        core.PagePoint(r.left, r.bottom),
        core.PagePoint((r.left + r.right) / 2, r.top),
        core.PagePoint(r.right, (r.top + r.bottom) / 2),
      ], closed: false),
      core.ShapeKind.rectangle => core.ShapeGeometry.rectangle(r),
      core.ShapeKind.ellipse => core.ShapeGeometry.ellipse(r),
      core.ShapeKind.triangle => core.ShapeGeometry.triangle(r),
      core.ShapeKind.polygon => core.ShapeGeometry.regularPolygon(r, 6),
      core.ShapeKind.star => core.ShapeGeometry.star(r),
    };

core.PageRect _cell(int col, int row, double w, double h, {double pad = 12}) =>
    core.PageRect(
      col * w + pad,
      row * h + pad,
      (col + 1) * w - pad,
      (row + 1) * h - pad,
    );

class _ShapesPainter extends CustomPainter {
  _ShapesPainter(this.shapes);
  final List<core.ShapeObject> shapes;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(core.PaperColors.white),
    );
    for (final s in shapes) {
      paintObjectSimple(canvas, s, paperArgb: core.PaperColors.white, onePx: 1);
    }
  }

  @override
  bool shouldRepaint(_ShapesPainter oldDelegate) => true;
}

Future<void> _golden(
  WidgetTester tester,
  Size size,
  List<core.ShapeObject> shapes,
  String name,
) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    Center(
      child: RepaintBoundary(
        child: CustomPaint(size: size, painter: _ShapesPainter(shapes)),
      ),
    ),
  );
  await expectLater(
    find.byType(RepaintBoundary).first,
    matchesGoldenFile('images/$name.png'),
  );
}

void main() {
  testWidgets('shapes_lines', (tester) async {
    const w = 130.0, h = 54.0;
    await _golden(tester, const Size(3 * w, 7 * h), [
      for (final (row, kind) in core.ShapeKind.values.indexed)
        for (final (col, dash) in core.LineDash.values.indexed)
          _shape(kind, _geometry(kind, _cell(col, row, w, h)), dash: dash),
    ], 'shapes_lines');
  });

  testWidgets('shapes_fill_arrows', (tester) async {
    const w = 78.0, h = 78.0;
    final closed = [
      core.ShapeKind.rectangle,
      core.ShapeKind.ellipse,
      core.ShapeKind.triangle,
      core.ShapeKind.polygon,
      core.ShapeKind.star,
    ];
    final r2 = [for (var c = 0; c < 5; c++) _cell(c, 1, w, h, pad: 16)];
    await _golden(tester, const Size(5 * w, 3 * h), [
      for (final (col, kind) in closed.indexed)
        _shape(kind, _geometry(kind, _cell(col, 0, w, h)), fill: _fill),
      _shape(
        core.ShapeKind.line,
        _geometry(core.ShapeKind.line, r2[0]),
        heads: core.ArrowHeads.end,
      ),
      _shape(
        core.ShapeKind.line,
        _geometry(core.ShapeKind.line, r2[1]),
        heads: core.ArrowHeads.both,
      ),
      _shape(
        core.ShapeKind.arrow,
        _geometry(core.ShapeKind.arrow, r2[2]),
        heads: core.ArrowHeads.end,
        dash: core.LineDash.dashed,
      ),
      _shape(
        core.ShapeKind.arrow,
        _geometry(core.ShapeKind.arrow, r2[3]),
        heads: core.ArrowHeads.both,
        dash: core.LineDash.dotted,
      ),
      _shape(
        core.ShapeKind.line,
        _geometry(core.ShapeKind.line, r2[4]),
        heads: core.ArrowHeads.end,
        width: 6,
        opacity: 0.5,
      ),
      _shape(
        core.ShapeKind.rectangle,
        _geometry(core.ShapeKind.rectangle, _cell(0, 2, w, h)),
        dash: core.LineDash.dashed,
        fill: _fill,
      ),
      _shape(
        core.ShapeKind.ellipse,
        _geometry(core.ShapeKind.ellipse, _cell(1, 2, w, h)),
        dash: core.LineDash.dotted,
        fill: _fill,
      ),
      _shape(
        core.ShapeKind.star,
        core.ShapeGeometry.star(_cell(2, 2, w, h)).transformed(
          core.Affine2.rotation(
            math.pi / 6,
            originX: 2.5 * w,
            originY: 2.5 * h,
          ),
        ),
        fill: _fill,
        opacity: 0.8,
      ),
      _shape(
        core.ShapeKind.arrow,
        core.ShapeGeometry.line(
          core.PagePoint(3 * w + 20, 3 * h - 20),
          core.PagePoint(5 * w - 20, 2 * h + 20),
        ),
        heads: core.ArrowHeads.both,
        width: 10,
      ),
    ], 'shapes_fill_arrows');
  });
}
