// m5-7/04-editor 8.2 E2-09, 6.9.2: ShapeDrafts — the shape tool's geometry
// from a drag (pure). The 7 kinds = CORE's templates on the drag box; a
// line's angle snaps to 15° within ±3° (14° → 15°, 20° stays — ≥ 1° from
// the borders, review S-12(f)); the equal-sided kinds square within
// |w / h − 1| ≤ 0.06 (the long side, p0 fixed); Shift = always, Alt = never;
// the style (an arrow without heads gets one at the end).
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:feature_editor/src/tools/shape_drafts.dart';
import 'package:feature_editor/src/tools/tool_options.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;

bool _sameGeometry(core.ShapeGeometry a, core.ShapeGeometry b) =>
    const DeepCollectionEquality().equals(a.toJson(), b.toJson());

core.PagePoint _at(double degrees, double length) {
  final a = degrees * math.pi / 180;
  return core.PagePoint(100 + math.cos(a) * length, 200 + math.sin(a) * length);
}

void main() {
  const options = ToolOptions(polygonSides: 7, starPoints: 6);
  const p0 = core.PagePoint(100, 200);
  const p1 = core.PagePoint(260, 270); // 160 × 70 — no square snapping
  const box = core.PageRect(100, 200, 260, 270);

  test('the 7 kinds = the CORE templates on the drag box', () {
    final expected = <core.ShapeKind, core.ShapeGeometry>{
      core.ShapeKind.line: core.ShapeGeometry.line(p0, p1),
      core.ShapeKind.arrow: core.ShapeGeometry.line(p0, p1),
      core.ShapeKind.rectangle: core.ShapeGeometry.rectangle(box),
      core.ShapeKind.ellipse: core.ShapeGeometry.ellipse(box),
      core.ShapeKind.triangle: core.ShapeGeometry.triangle(box),
      core.ShapeKind.polygon: core.ShapeGeometry.regularPolygon(box, 7),
      core.ShapeKind.star: core.ShapeGeometry.star(box, points: 6),
    };
    expect(expected.keys.toSet(), core.ShapeKind.values.toSet());
    for (final MapEntry(key: kind, value: geometry) in expected.entries) {
      // The line's 23.6° is ≥ 1° from a snap border (15° + 3°, 30° − 3°).
      final got = ShapeDrafts.geometry(kind, p0, p1, options);
      expect(_sameGeometry(got, geometry), isTrue, reason: kind.name);
    }
    // Dragged up-left: the same box.
    expect(
      _sameGeometry(
        ShapeDrafts.geometry(core.ShapeKind.rectangle, p1, p0, options),
        core.ShapeGeometry.rectangle(box),
      ),
      isTrue,
    );
  });

  test('a line: 14° → 15° (the length kept), 20° stays; Shift → 20° to 15°; '
      'Alt → 14° stays', () {
    core.PagePoint endOf(core.ShapeGeometry g) =>
        (g as core.PolylineGeometry).points[1];
    final snapped = endOf(
      ShapeDrafts.geometry(core.ShapeKind.line, p0, _at(14, 150), options),
    );
    expect(snapped.x, closeTo(_at(15, 150).x, 1e-9));
    expect(snapped.y, closeTo(_at(15, 150).y, 1e-9));
    final free = endOf(
      ShapeDrafts.geometry(core.ShapeKind.arrow, p0, _at(20, 150), options),
    );
    expect(free.x, closeTo(_at(20, 150).x, 1e-9));
    expect(free.y, closeTo(_at(20, 150).y, 1e-9));
    final shift = endOf(
      ShapeDrafts.geometry(
        core.ShapeKind.line,
        p0,
        _at(20, 150),
        options,
        snap: ShapeSnap.always,
      ),
    );
    expect(shift.x, closeTo(_at(15, 150).x, 1e-9));
    expect(shift.y, closeTo(_at(15, 150).y, 1e-9));
    final alt = endOf(
      ShapeDrafts.geometry(
        core.ShapeKind.line,
        p0,
        _at(14, 150),
        options,
        snap: ShapeSnap.off,
      ),
    );
    expect(alt.x, closeTo(_at(14, 150).x, 1e-9));
    expect(alt.y, closeTo(_at(14, 150).y, 1e-9));
    // The start point is p0 in every case.
    final g = ShapeDrafts.geometry(
      core.ShapeKind.line,
      p0,
      _at(14, 150),
      options,
    ) as core.PolylineGeometry;
    expect(g.points[0], p0);
  });

  test('the ratio threshold 0.06: 1.05 → a square / circle of the long side '
      'from p0 (toward p1), 1.08 → the box', () {
    // 105 × 100 → a 105 square, p0 kept, dragged down-right.
    final near = ShapeDrafts.geometry(
      core.ShapeKind.rectangle,
      p0,
      const core.PagePoint(205, 300),
      options,
    );
    expect(
      _sameGeometry(
        near,
        core.ShapeGeometry.rectangle(const core.PageRect(100, 200, 205, 305)),
      ),
      isTrue,
    );
    // Dragged up-left (−100, −105): the square goes up-left from p0.
    final upLeft = ShapeDrafts.geometry(
      core.ShapeKind.ellipse,
      p0,
      const core.PagePoint(0, 95),
      options,
    );
    expect(
      _sameGeometry(
        upLeft,
        core.ShapeGeometry.ellipse(const core.PageRect(-5, 95, 100, 200)),
      ),
      isTrue,
    );
    // 108 × 100: no snapping.
    final far = ShapeDrafts.geometry(
      core.ShapeKind.rectangle,
      p0,
      const core.PagePoint(208, 300),
      options,
    );
    expect(
      _sameGeometry(
        far,
        core.ShapeGeometry.rectangle(const core.PageRect(100, 200, 208, 300)),
      ),
      isTrue,
    );
    // A polygon and a star square the same way; a triangle never does.
    for (final kind in [core.ShapeKind.polygon, core.ShapeKind.star]) {
      final g = ShapeDrafts.geometry(
        kind,
        p0,
        const core.PagePoint(205, 300),
        options,
      );
      final r = g.frame.rect;
      expect(r.left, greaterThanOrEqualTo(100 - 1e-9), reason: kind.name);
      final squareBox = const core.PageRect(100, 200, 205, 305);
      final template = kind == core.ShapeKind.polygon
          ? core.ShapeGeometry.regularPolygon(squareBox, 7)
          : core.ShapeGeometry.star(squareBox, points: 6);
      expect(_sameGeometry(g, template), isTrue, reason: kind.name);
    }
    expect(
      _sameGeometry(
        ShapeDrafts.geometry(
          core.ShapeKind.triangle,
          p0,
          const core.PagePoint(205, 300),
          options,
        ),
        core.ShapeGeometry.triangle(const core.PageRect(100, 200, 205, 300)),
      ),
      isTrue,
    );
  });

  test('Shift squares any box (2:1 → the long side); Alt never squares', () {
    final shift = ShapeDrafts.geometry(
      core.ShapeKind.rectangle,
      p0,
      const core.PagePoint(300, 300), // 200 × 100
      options,
      snap: ShapeSnap.always,
    );
    expect(
      _sameGeometry(
        shift,
        core.ShapeGeometry.rectangle(const core.PageRect(100, 200, 300, 400)),
      ),
      isTrue,
    );
    final alt = ShapeDrafts.geometry(
      core.ShapeKind.ellipse,
      p0,
      const core.PagePoint(203, 300), // 1.03 — would snap
      options,
      snap: ShapeSnap.off,
    );
    expect(
      _sameGeometry(
        alt,
        core.ShapeGeometry.ellipse(const core.PageRect(100, 200, 203, 300)),
      ),
      isTrue,
    );
  });

  test('styleFor: the tool style normalized; an arrow without heads gets '
      'one at the end, a line keeps none', () {
    const style = core.ShapeStyle(
      strokeColorArgb: 0x803366CC, // alpha forced to 0xFF
      strokeWidth: 50, // clamped to 30
    );
    const withStyle = ToolOptions(shapeStyle: style);
    final arrow = ShapeDrafts.styleFor(core.ShapeKind.arrow, withStyle);
    expect(arrow.arrowHeads, core.ArrowHeads.end);
    expect(arrow.strokeColorArgb, 0xFF3366CC);
    expect(arrow.strokeWidth, core.ShapeStyle.maxWidth);
    final line = ShapeDrafts.styleFor(core.ShapeKind.line, withStyle);
    expect(line.arrowHeads, core.ArrowHeads.none);
    const both = ToolOptions(
      shapeStyle: core.ShapeStyle(
        strokeColorArgb: 0xFF000000,
        arrowHeads: core.ArrowHeads.both,
      ),
    );
    expect(
      ShapeDrafts.styleFor(core.ShapeKind.arrow, both).arrowHeads,
      core.ArrowHeads.both,
    );
    expect(
      ShapeDrafts.styleFor(core.ShapeKind.rectangle, withStyle),
      style.normalized(),
    );
  });
}
