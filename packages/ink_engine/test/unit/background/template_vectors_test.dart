// T13 (03-ink 8, 4.10, 6.16): TemplateVectors.build for lined / grid /
// dotted / cornell — positions, widths and colors by the 6.16 table, grid
// centring, dot diameter, Cornell structure lines, the clip (nothing outside,
// lines cut), dark-paper colors, lineColorArgb, extras type errors.
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/background/template_vectors.dart'
    show clipSegment;
import 'package:note_core/note_core.dart' as core;

const _a4 = Size(595.2756, 841.8898);
const _white = core.PaperColors.white;
const _black = core.PaperColors.black;

List<TemplateVectorItem> _build(
  core.PageTemplate t, {
  Size size = _a4,
  int paper = _white,
  Rect? clip,
}) =>
    TemplateVectors.build(t, pageSize: size, paperColorArgb: paper, clip: clip);

core.PageTemplate _t(
  core.PageTemplateKind kind, {
  double? spacing,
  int? color,
  double? lineWidth,
  Map<String, Object?> extras = const {},
}) => core.PageTemplate(
  kind: kind,
  spacing: spacing,
  lineColorArgb: color,
  lineWidth: lineWidth,
  extras: extras,
);

Iterable<TemplateLine> _lines(List<TemplateVectorItem> items) =>
    items.whereType<TemplateLine>();

bool _horizontal(TemplateLine l) => l.p0.dy == l.p1.dy;
bool _vertical(TemplateLine l) => l.p0.dx == l.p1.dx;

void main() {
  group('lined', () {
    test('ruled lines y = 72 + 24k (y ≤ H − 24), full width; margin line', () {
      final items = _build(_t(core.PageTemplateKind.lined));
      final ruled = _lines(items).where(_horizontal).toList();
      var k = 0;
      for (final l in ruled) {
        expect(l.p0, Offset(0, 72 + 24.0 * k));
        expect(l.p1, Offset(_a4.width, 72 + 24.0 * k));
        expect(l.width, 0.5);
        expect(l.colorArgb, 0xFFB7C4D6);
        k++;
      }
      // last y ≤ H − spacing
      expect(72 + 24.0 * (k - 1), lessThanOrEqualTo(_a4.height - 24));
      expect(72 + 24.0 * k, greaterThan(_a4.height - 24));
      expect(k, 32);
      final margin = _lines(items).where(_vertical).single;
      expect(margin.p0, const Offset(72, 0));
      expect(margin.p1, Offset(72, _a4.height));
      expect(margin.width, 0.75);
      expect(margin.colorArgb, 0x99E57373);
    });

    test('extras: margins, no margin line; type errors → that key only', () {
      final items = _build(
        _t(
          core.PageTemplateKind.lined,
          spacing: 30,
          extras: {
            core.TemplateExtrasKeys.marginTop: 100,
            core.TemplateExtrasKeys.marginLeft: 'wide', // wrong type → 72
            core.TemplateExtrasKeys.showMarginLine: true,
          },
        ),
      );
      final ruled = _lines(items).where(_horizontal).toList();
      expect(ruled.first.p0.dy, 100);
      expect(ruled[1].p0.dy, 130);
      expect(_lines(items).where(_vertical).single.p0.dx, 72);
      final none = _build(
        _t(
          core.PageTemplateKind.lined,
          extras: {core.TemplateExtrasKeys.showMarginLine: false},
        ),
      );
      expect(_lines(none).where(_vertical), isEmpty);
    });
  });

  group('grid / dotted', () {
    test('grid: centred — first line at (side mod spacing) / 2', () {
      const s = 14.1732;
      final items = _build(_t(core.PageTemplateKind.grid));
      final ys = _lines(items).where(_horizontal).map((l) => l.p0.dy).toList();
      final xs = _lines(items).where(_vertical).map((l) => l.p0.dx).toList();
      expect(ys.first, closeTo((_a4.height % s) / 2, 1e-9));
      expect(xs.first, closeTo((_a4.width % s) / 2, 1e-9));
      // symmetric: the same margin at the far side
      expect(_a4.height - ys.last, closeTo(ys.first, 1e-6));
      expect(_a4.width - xs.last, closeTo(xs.first, 1e-6));
      for (var i = 1; i < xs.length; i++) {
        expect(xs[i] - xs[i - 1], closeTo(s, 1e-9));
      }
      expect(xs, hasLength((_a4.width / s).floor() + 1));
      expect(ys, hasLength((_a4.height / s).floor() + 1));
      for (final l in _lines(items)) {
        expect(l.width, 0.5);
        expect(l.colorArgb, 0xFFB7C4D6);
        if (_horizontal(l)) expect((l.p0.dx, l.p1.dx), (0, _a4.width));
        if (_vertical(l)) expect((l.p0.dy, l.p1.dy), (0, _a4.height));
      }
    });

    test('dotted: a dot (diameter 1.5) on every grid crossing', () {
      final grid = _build(_t(core.PageTemplateKind.grid));
      final xs = _lines(grid).where(_vertical).map((l) => l.p0.dx).toSet();
      final ys = _lines(grid).where(_horizontal).map((l) => l.p0.dy).toSet();
      final dots = _build(_t(core.PageTemplateKind.dotted))
          .whereType<TemplateDot>()
          .toList();
      // only crossings whose dot fits on the page (radius included)
      bool fits(double v, double side) => v - 0.75 >= 0 && v + 0.75 <= side;
      final fx = xs.where((x) => fits(x, _a4.width)).length;
      final fy = ys.where((y) => fits(y, _a4.height)).length;
      expect(dots, hasLength(fx * fy));
      expect(fx, greaterThanOrEqualTo(xs.length - 2));
      for (final d in dots) {
        expect(d.radius, 0.75);
        expect(d.colorArgb, 0xFF9AA5B4);
        expect(xs, contains(d.center.dx));
        expect(ys, contains(d.center.dy));
      }
      // a dot that would stick out of the page is left out
      final edge = _build(
        _t(core.PageTemplateKind.dotted, spacing: 10, lineWidth: 4),
        size: const Size(100, 100),
      ).whereType<TemplateDot>();
      for (final d in edge) {
        expect(d.center.dx - d.radius, greaterThanOrEqualTo(0));
        expect(d.center.dx + d.radius, lessThanOrEqualTo(100));
      }
      expect(edge.length, 81); // 0 and 100 are out (radius 2)
    });
  });

  group('cornell', () {
    test('structure lines and ruled lines', () {
      final items = _build(_t(core.PageTemplateKind.cornell));
      final structure = _lines(items).where((l) => l.width == 1.0).toList();
      final summaryTop = _a4.height - 144;
      final cue = 0.3 * _a4.width; // min(180, 178.58)
      expect(structure.map((l) => (l.p0, l.p1)), [
        (const Offset(0, 72), Offset(_a4.width, 72)),
        (Offset(0, summaryTop), Offset(_a4.width, summaryTop)),
        (Offset(cue, 72), Offset(cue, summaryTop)),
      ]);
      expect(structure.every((l) => l.colorArgb == 0xFF8FA3BF), isTrue);
      final ruled = _lines(items).where((l) => l.width == 0.5).toList();
      for (var i = 0; i < ruled.length; i++) {
        expect(ruled[i].p0, Offset(0, 72 + 24.0 * (i + 1)));
        expect(ruled[i].p1.dx, _a4.width);
      }
      expect(ruled.last.p0.dy, lessThanOrEqualTo(summaryTop - 12));
      expect(ruled.last.p0.dy + 24, greaterThan(summaryTop - 12));
    });

    test('landscape: cue column 180, summary 0.2 H', () {
      final size = Size(_a4.height, _a4.width);
      final items = _build(_t(core.PageTemplateKind.cornell), size: size);
      final cue = _lines(items).where(_vertical).single;
      expect(cue.p0.dx, 180);
      expect(cue.p1.dy, closeTo(size.height - 0.2 * size.height, 1e-9));
    });
  });

  test('dark paper colors; lineColorArgb for all but the margin line', () {
    final dark = _build(_t(core.PageTemplateKind.lined), paper: _black);
    expect(
      _lines(dark).where(_horizontal).every((l) => l.colorArgb == 0x4DFFFFFF),
      isTrue,
    );
    expect(_lines(dark).where(_vertical).single.colorArgb, 0x99EF9A9A);
    final dots = _build(
      _t(core.PageTemplateKind.dotted),
      paper: _black,
    ).whereType<TemplateDot>();
    expect(dots.every((d) => d.colorArgb == 0x66FFFFFF), isTrue);
    final cornell = _build(_t(core.PageTemplateKind.cornell), paper: _black);
    expect(
      _lines(cornell).where((l) => l.width == 1.0).map((l) => l.colorArgb),
      everyElement(0x80FFFFFF),
    );

    const c = 0xFF336699;
    final custom = _build(_t(core.PageTemplateKind.lined, color: c));
    expect(
      _lines(custom).where(_horizontal).map((l) => l.colorArgb),
      everyElement(c),
    );
    expect(_lines(custom).where(_vertical).single.colorArgb, 0x99E57373);
    final customDots = _build(_t(core.PageTemplateKind.dotted, color: c))
        .whereType<TemplateDot>();
    expect(customDots.map((d) => d.colorArgb), everyElement(c));
    final customCornell = _build(_t(core.PageTemplateKind.cornell, color: c));
    expect(_lines(customCornell).map((l) => l.colorArgb), everyElement(c));
  });

  test('clip: only items that meet it, lines cut to it', () {
    const clip = Rect.fromLTRB(100, 200, 300, 260);
    for (final kind in [
      core.PageTemplateKind.lined,
      core.PageTemplateKind.grid,
      core.PageTemplateKind.dotted,
      core.PageTemplateKind.cornell,
    ]) {
      final all = _build(_t(kind));
      final cut = _build(_t(kind), clip: clip);
      expect(cut, isNotEmpty, reason: '$kind');
      expect(cut.length, lessThan(all.length));
      for (final item in cut) {
        switch (item) {
          case TemplateLine(:final p0, :final p1):
            for (final p in [p0, p1]) {
              expect(
                clip.inflate(1e-9).contains(p),
                isTrue,
                reason: '$kind $p',
              );
            }
          case TemplateDot(:final center, :final radius):
            expect(clip.inflate(radius + 1e-9).contains(center), isTrue);
        }
      }
    }
    final lined = _build(_t(core.PageTemplateKind.lined), clip: clip);
    final ys = _lines(lined).where(_horizontal).map((l) => l.p0.dy).toList();
    expect(ys, [216, 240]); // 72 + 24k inside [200, 260]
    expect(_lines(lined).where(_horizontal).first.p0.dx, 100);
    expect(_lines(lined).where(_horizontal).first.p1.dx, 300);
    // outside the page → nothing
    expect(
      _build(
        _t(core.PageTemplateKind.grid),
        clip: const Rect.fromLTRB(700, 0, 800, 100),
      ),
      isEmpty,
    );
  });

  test('every line inside the page; degenerate sizes give no items', () {
    for (final kind in [
      core.PageTemplateKind.lined,
      core.PageTemplateKind.grid,
      core.PageTemplateKind.dotted,
      core.PageTemplateKind.cornell,
    ]) {
      for (final size in [_a4, const Size(100, 80), const Size(960, 540)]) {
        final page = (Offset.zero & size).inflate(1e-9);
        for (final l in _lines(_build(_t(kind), size: size))) {
          expect(page.contains(l.p0) && page.contains(l.p1), isTrue);
        }
      }
      expect(_build(_t(kind), size: Size.zero), isEmpty);
      expect(_build(_t(kind), size: const Size(double.nan, 10)), isEmpty);
    }
    expect(
      _build(_t(core.PageTemplateKind.lined), size: const Size(100, 80)),
      hasLength(1),
    ); // only the margin line (72 > 80 − 24)
  });

  group('music (T13b)', () {
    List<TemplateLine> staffLines(Size size, {core.PageTemplate? t}) =>
        _lines(_build(t ?? _t(core.PageTemplateKind.music), size: size))
            .toList();

    test(
      'A4 portrait: 12 staves, landscape: 8; gap 7, centred, margins 36',
      () {
        for (final (size, staves) in [
          (_a4, 12),
          (Size(_a4.height, _a4.width), 8),
        ]) {
          final lines = staffLines(size);
          expect(lines, hasLength(staves * 5), reason: '$size');
          for (final l in lines) {
            expect((l.p0.dx, l.p1.dx), (36, size.width - 36));
            expect(l.width, 0.6);
            expect(l.colorArgb, 0xFF8FA3BF);
            expect(_horizontal(l), isTrue);
          }
          for (var i = 0; i < staves; i++) {
            final staff = lines.sublist(5 * i, 5 * i + 5);
            for (var j = 1; j < 5; j++) {
              expect(staff[j].p0.dy - staff[j - 1].p0.dy, closeTo(7, 1e-9));
            }
            if (i > 0) {
              expect(
                staff.first.p0.dy - lines[5 * i - 1].p0.dy,
                closeTo(36, 1e-9),
              );
            }
          }
          // the block is centred vertically
          expect(
            size.height - lines.last.p0.dy,
            closeTo(lines.first.p0.dy, 1e-9),
          );
        }
      },
    );

    test('a small page → no staff; staffGap / spacing user values', () {
      expect(staffLines(const Size(200, 100)), isEmpty);
      final t = _t(
        core.PageTemplateKind.music,
        spacing: 10,
        extras: {core.TemplateExtrasKeys.staffGap: 50},
      );
      final lines = staffLines(_a4, t: t);
      // n = ⌊(841.89 − 108 + 50) / (40 + 50)⌋ = 8
      expect(lines, hasLength(8 * 5));
      expect(lines[1].p0.dy - lines[0].p0.dy, closeTo(10, 1e-9));
      expect(lines[5].p0.dy - lines[4].p0.dy, closeTo(50, 1e-9));
      // a wrongly typed staffGap → the default
      final bad = staffLines(
        _a4,
        t: _t(
          core.PageTemplateKind.music,
          extras: {core.TemplateExtrasKeys.staffGap: 'wide'},
        ),
      );
      expect(bad, hasLength(12 * 5));
    });

    test('dark paper and lineColorArgb', () {
      expect(
        _lines(_build(_t(core.PageTemplateKind.music), paper: _black))
            .map((l) => l.colorArgb),
        everyElement(0x80FFFFFF),
      );
      expect(
        _lines(_build(_t(core.PageTemplateKind.music, color: 0xFF010203)))
            .map((l) => l.colorArgb),
        everyElement(0xFF010203),
      );
    });
  });

  group('planner (T13b)', () {
    test('portrait: header line, 2 × 4 cells, title + ruled lines', () {
      final items = _lines(_build(_t(core.PageTemplateKind.planner))).toList();
      final structure = items.where((l) => l.width == 1.0).toList();
      final ruled = items.where((l) => l.width == 0.5).toList();
      expect(structure.every((l) => l.colorArgb == 0xFF8FA3BF), isTrue);
      expect(ruled.every((l) => l.colorArgb == 0xFFB7C4D6), isTrue);
      const top = 36 + 56.0; // header band bottom = body top
      final bottom = _a4.height - 36, right = _a4.width - 36;
      final ch = (bottom - top) / 4, cw = (right - 36) / 2;
      // borders: 5 horizontal (header line included) + 3 vertical
      final hs = structure.where(_horizontal).map((l) => l.p0.dy).toList();
      final vs = structure.where(_vertical).map((l) => l.p0.dx).toList();
      expect(hs, [for (var k = 0; k <= 4; k++) closeTo(top + k * ch, 1e-9)]);
      expect(vs, [36, closeTo(36 + cw, 1e-9), closeTo(right, 1e-9)]);
      for (final l in structure.where(_horizontal)) {
        expect(l.p0.dx, 36);
        expect(l.p1.dx, closeTo(right, 1e-9));
      }
      // every cell: title line 20 pt below its top, then every 20 pt down to
      // 4 pt above the cell bottom
      for (var row = 0; row < 4; row++) {
        for (var col = 0; col < 2; col++) {
          final x0 = 36 + col * cw, cellTop = top + row * ch;
          final cell = ruled
              .where(
                (l) =>
                    (l.p0.dx - x0).abs() < 1e-9 &&
                    l.p0.dy > cellTop &&
                    l.p0.dy < cellTop + ch,
              )
              .toList();
          expect(cell.first.p0.dy, closeTo(cellTop + 20, 1e-9));
          expect(cell.first.p1.dx, closeTo(x0 + cw, 1e-9));
          for (var i = 1; i < cell.length; i++) {
            expect(cell[i].p0.dy - cell[i - 1].p0.dy, closeTo(20, 1e-9));
          }
          expect(cell.last.p0.dy, lessThanOrEqualTo(cellTop + ch - 4 + 1e-9));
          expect(cell.last.p0.dy + 20, greaterThan(cellTop + ch - 4));
        }
      }
    });

    test('landscape: 4 × 2 cells; an unknown layout draws weekly', () {
      final size = Size(_a4.height, _a4.width);
      final items = _lines(
        _build(_t(core.PageTemplateKind.planner), size: size),
      );
      final structure = items.where((l) => l.width == 1.0);
      expect(structure.where(_vertical), hasLength(5));
      expect(structure.where(_horizontal), hasLength(3));
      final monthly = _build(
        _t(
          core.PageTemplateKind.planner,
          extras: {core.TemplateExtrasKeys.plannerLayout: 'monthly'},
        ),
      );
      expect(monthly, _build(_t(core.PageTemplateKind.planner)));
      final wrongType = _build(
        _t(
          core.PageTemplateKind.planner,
          extras: {core.TemplateExtrasKeys.plannerLayout: 3},
        ),
      );
      expect(wrongType, monthly);
    });

    test('extras, dark paper, tiny page', () {
      final moved = _lines(
        _build(
          _t(
            core.PageTemplateKind.planner,
            extras: {
              core.TemplateExtrasKeys.marginTop: 50,
              core.TemplateExtrasKeys.headerHeight: 30,
            },
          ),
        ),
      ).where((l) => l.width == 1.0 && _horizontal(l));
      expect(moved.first.p0.dy, 80);
      expect(moved.last.p0.dy, closeTo(_a4.height - 50, 1e-9));
      final dark = _lines(
        _build(_t(core.PageTemplateKind.planner), paper: _black),
      );
      expect(
        dark.where((l) => l.width == 1.0).map((l) => l.colorArgb),
        everyElement(0x80FFFFFF),
      );
      expect(
        _build(_t(core.PageTemplateKind.planner), size: const Size(60, 100)),
        isEmpty,
      );
    });
  });

  test('clipSegment (Liang–Barsky)', () {
    const r = Rect.fromLTRB(0, 0, 10, 10);
    expect(clipSegment(const Offset(2, 2), const Offset(8, 8), r), (
      const Offset(2, 2),
      const Offset(8, 8),
    ));
    expect(clipSegment(const Offset(-5, 5), const Offset(15, 5), r), (
      const Offset(0, 5),
      const Offset(10, 5),
    ));
    expect(clipSegment(const Offset(-5, 11), const Offset(15, 11), r), isNull);
    expect(clipSegment(const Offset(10, -1), const Offset(10, 4), r), (
      const Offset(10, 0),
      const Offset(10, 4),
    ));
  });
}
