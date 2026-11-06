// T16 (03-ink 6.20 P1–P8): the partial eraser splits strokes by vector:
// a perpendicular pass through a line leaves two pieces whose cut ends are
// R + r from the eraser centre; an end cut leaves one; erasing everything is
// RemoveStrokes; several passes in one gesture make one SplitStrokes with the
// pieces computed once per original; crumbs are dropped; pieces are
// core.Stroke.fragment copies; dots go whole; highlighter cut ends are flat.
// (m5-7/03-ink 8.2 T37b, 6.15 — v2) A shape the partial eraser touches goes
// whole: one gesture over a stroke and a shape = one splitStrokes edit
// (removedIds = the original + the shape, removedObjectIds = the shape, the
// pieces added) → CompositeCommand([SplitStrokes, RemoveElements]); everything
// of the stroke erased + a shape → Composite([RemoveStrokes, RemoveElements]);
// a shape only → RemoveElements alone; text boxes are never erased.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/edit/partial_eraser.dart';
import 'package:ink_engine/src/geometry/outline_generator.dart';
import 'package:ink_engine/src/interop/core_interop.dart' as interop;
import 'package:ink_engine/src/render/sessions.dart'
    show eraserIntervalsOf, eraserPreviewPieces;
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

import '../../support/pixels.dart';

// ballpoint width 4 at nominal widthQ → r = 2
final _pen = core.StrokeStyle.defaultsFor(core.PenTool.ballpoint)
    .copyWith(width: 4);
final _hl = core.StrokeStyle.defaultsFor(core.PenTool.highlighter); // w 12

InkSample _at(ui.Offset p, int i) =>
    InkSample(position: p, timeUs: i * 8333, kind: InkPointerKind.stylus);

void main() {
  late InkPageController c;
  setUp(() => c = createTestPageController());
  tearDown(() => c.dispose());

  void load(List<core.Stroke> strokes) =>
      c.updateContent(SyntheticInk.pageContent(strokes: strokes));

  EraserSession begin(ui.Offset first, double radius) => c.beginErase(
    _at(first, 0),
    spec: EraserSpec(mode: EraserMode.partial, radius: radius),
    viewScale: 1,
  );

  InkEdit? erase(List<ui.Offset> path, {double radius = 5}) {
    final s = begin(path.first, radius);
    for (var i = 1; i < path.length; i++) {
      s.addSample(_at(path[i], i));
    }
    return s.end();
  }

  /// A horizontal line x 100 → 300 at [y], points every 2 pt.
  core.Stroke line(String id, double y, {core.StrokeStyle? style}) =>
      strokeThrough(
        segment(ui.Offset(100, y), ui.Offset(300, y)),
        style ?? _pen,
        id: id,
      );

  double firstX(core.Stroke s) => s.points.x(0);
  double lastX(core.Stroke s) => s.points.x(s.points.length - 1);

  test(
    'perpendicular pass through the middle → 2 pieces, cut at cx ± (R + r)',
    () {
      load([line('a', 300)]);
      final edit = erase([
        const ui.Offset(200, 250),
        const ui.Offset(200, 350),
      ]);
      expect(edit, isNotNull);
      expect(edit!.kind, InkEditKind.splitStrokes);
      expect(edit.removedIds, {'a'});
      expect(edit.added, hasLength(2));
      final left = edit.added[0], right = edit.added[1];
      // R 5 + r 2: pieces end 7 pt from the eraser centre line
      expect(firstX(left), closeTo(100, 0.006));
      expect(lastX(left), closeTo(193, 0.01));
      expect(firstX(right), closeTo(207, 0.01));
      expect(lastX(right), closeTo(300, 0.006));
      // the cut is on the outside: never inside the eraser
      expect(lastX(left), lessThanOrEqualTo(193 + 0.006));
      expect(firstX(right), greaterThanOrEqualTo(207 - 0.006));
      final cmd = edit.toCommand() as core.SplitStrokes;
      expect(cmd.removedIds, ['a']);
      expect(cmd.added.map((s) => s.id), edit.added.map((s) => s.id));
    },
  );

  test('cut at the end → 1 piece; everything erased → RemoveStrokes', () {
    load([line('a', 300), line('b', 400)]);
    final end = erase([const ui.Offset(98, 300)]);
    expect(end!.added, hasLength(1));
    expect(firstX(end.added.single), closeTo(105, 0.01));
    expect(lastX(end.added.single), closeTo(300, 0.006));

    final all = erase([
      const ui.Offset(90, 400),
      const ui.Offset(200, 400),
      const ui.Offset(310, 400),
    ]);
    expect(all!.kind, InkEditKind.splitStrokes);
    expect(all.removedIds, {'b'});
    expect(all.added, isEmpty);
    expect(all.toCommand(), isA<core.RemoveStrokes>());
  });

  test('several passes in one gesture → one SplitStrokes, pieces made once', () {
    load([line('a', 300)]);
    // down at x 150, up at x 200, down at x 250, and back over x 200
    final edit = erase([
      const ui.Offset(150, 250),
      const ui.Offset(150, 350),
      const ui.Offset(200, 350),
      const ui.Offset(200, 250),
      const ui.Offset(250, 250),
      const ui.Offset(250, 350),
      const ui.Offset(200, 350),
      const ui.Offset(200, 250),
    ], radius: 2);
    // the horizontal moves at y 250 / 350 are 50 pt away; three cuts → 4 pieces
    expect(edit!.removedIds, {'a'});
    expect(edit.added, hasLength(4));
    // the controller's services handed out exactly four ids, at end()
    expect(
      [for (final s in edit.added) s.id],
      ['s-000001', 's-000002', 's-000003', 's-000004'],
    );
    final xs = [for (final s in edit.added) (firstX(s), lastX(s))];
    expect(xs[0].$2, closeTo(146, 0.01));
    expect(xs[1].$1, closeTo(154, 0.01));
    expect(xs[1].$2, closeTo(196, 0.01));
    expect(xs[2].$1, closeTo(204, 0.01));
    expect(xs[3].$1, closeTo(254, 0.01));
    expect(edit.toCommand(), isA<core.SplitStrokes>());
  });

  test('two strokes in one pass, originals in z order', () {
    load([
      strokeThrough(
        segment(const ui.Offset(100, 300), const ui.Offset(300, 300)),
        _pen,
        id: 'upper',
        createdAt: 3000,
      ),
      strokeThrough(
        segment(const ui.Offset(100, 320), const ui.Offset(300, 320)),
        _pen,
        id: 'lower',
        createdAt: 1000,
      ),
    ]);
    final edit = erase([const ui.Offset(200, 280), const ui.Offset(200, 340)]);
    expect(edit!.removedIds.toList(), ['lower', 'upper']);
    expect(edit.added, hasLength(4));
    final cmd = edit.toCommand() as core.SplitStrokes;
    expect(cmd.removedIds, ['lower', 'upper']);
  });

  test('crumbs shorter than max(0.3 pt, 0.25 · width) are dropped', () {
    // width 4 → threshold 1 pt; the eraser removes [cx − 7, cx + 7]
    load([line('a', 300)]);
    final short = erase([const ui.Offset(107.8, 300)]);
    expect(short!.added, hasLength(1), reason: 'left piece 0.8 pt dropped');
    expect(firstX(short.added.single), closeTo(114.8, 0.01));
    c.discardEdit(short);
    final kept = erase([const ui.Offset(108.5, 300)]);
    expect(kept!.added, hasLength(2), reason: 'left piece 1.5 pt kept');
    expect(lastX(kept.added.first), closeTo(101.5, 0.01));
    expect(PartialEraser.minPieceLength(_pen), 1);
    expect(PartialEraser.minPieceLength(_pen.copyWith(width: 0.5)), 0.3);
  });

  test('pieces are core.Stroke.fragment copies of the original', () {
    const stride = core.StrokePoints.stride;
    final data = Float32List(101 * stride);
    for (var i = 0; i <= 100; i++) {
      data[i * stride] = 100 + 2.0 * i;
      data[i * stride + 1] = 300;
      data[i * stride + 2] = 0.1 + 0.004 * i; // tapering
      data[i * stride + 3] = 0.5;
      data[i * stride + 4] = 1.0;
      data[i * stride + 5] = 1000 + 10.0 * i;
    }
    final original = interop.strokeFromData(
      data,
      id: 'rec',
      pageId: 'p1',
      style: core.StrokeStyle.defaultsFor(core.PenTool.fountain),
      createdAt: 4242,
      hasTilt: true,
      hasAzimuth: true,
      recordingId: 'r-1',
      recordingOffsetMs: 777,
    );
    load([original]);
    final edit = erase([const ui.Offset(201, 280), const ui.Offset(201, 320)]);
    expect(edit!.added, hasLength(2));
    for (final f in edit.added) {
      expect(f.style, original.style);
      expect(f.createdAt, 4242);
      expect(f.recordingId, 'r-1');
      expect(f.recordingOffsetMs, 777);
      expect(f.version, isNull);
      expect(f.pageId, 'p1');
      expect(f.points.hasTilt, isTrue);
      expect(f.points.hasAzimuth, isTrue);
      for (var j = 0; j < f.points.length; j++) {
        final t = f.points.t(j);
        expect(t, inInclusiveRange(1000, 2000));
        // t is interpolated, not renumbered from 0 (CORE 7.2.3)
        final x = f.points.x(j);
        expect(t, closeTo(1000 + (x - 100) * 5, 0.1));
        expect(f.points.widthQ(j), closeTo(0.1 + 0.002 * (x - 100), 0.0011));
      }
    }
    // the left piece keeps the original's first point; the cut point is a lerp
    final left = edit.added.first;
    expect(left.points.t(0), 1000);
    expect(left.points.tilt(0), closeTo(0.5, 1e-3));
  });

  test('dot strokes go whole when touched; untouched → null', () {
    load([
      strokeThrough([const ui.Offset(200, 200)], _pen, id: 'dot'),
      line('a', 400),
    ]);
    expect(erase([const ui.Offset(200, 230)]), isNull, reason: 'out of reach');
    final edit = erase([const ui.Offset(200, 206.9)]); // R 5 + r 2 = 7
    expect(edit!.removedIds, {'dot'});
    expect(edit.added, isEmpty);
    expect(edit.toCommand(), isA<core.RemoveStrokes>());
  });

  test('highlighter pieces end flat, tangent to the eraser circle', () {
    load([line('hl', 300, style: _hl)]);
    final edit = erase([const ui.Offset(200, 250), const ui.Offset(200, 350)]);
    expect(edit!.added, hasLength(2));
    final left = edit.added.first;
    // centerline ends R + w/2 = 5 + 6 from the eraser
    expect(lastX(left), closeTo(189, 0.01));
    // square cap: the outline reaches x = cx − R across the full width
    final outline = OutlineGenerator.outline(InkStroke.of(left));
    expect(outline.bounds.right, closeTo(195, 0.02));
    final poly = outline.polygons.single;
    final capYs = <double>[
      for (var i = 0; i + 1 < poly.length; i += 2)
        if (poly[i] > 195 - 0.02) poly[i + 1],
    ]..sort();
    expect(capYs.first, closeTo(294, 0.02));
    expect(capYs.last, closeTo(306, 0.02));
  });

  test(
    'during the gesture: pv- preview pieces, merged intervals; end clears',
    () {
      load([line('a', 300)]);
      final s = begin(const ui.Offset(200, 250), 5)
        ..addSample(_at(const ui.Offset(200, 350), 1));
      final previews = eraserPreviewPieces(s).toList();
      expect(previews, hasLength(2));
      expect(previews.every((p) => p.id.startsWith('pv-')), isTrue);
      final intervals = eraserIntervalsOf(s, 'a');
      expect(intervals, hasLength(1));
      // x = 100 + 2 s → s = (x − 100) / 2: [93/2, 107/2]
      expect(intervals.single.start, closeTo(46.5, 0.005));
      expect(intervals.single.end, closeTo(53.5, 0.005));
      expect(s.touchedStrokeIds, {'a'});
      // a second pass widening the same cut changes the preview, same original
      s.addSample(_at(const ui.Offset(204, 250), 2));
      expect(eraserIntervalsOf(s, 'a'), hasLength(1));
      // the capsule (200, 350) → (204, 250) crosses y 300 at x 202 → cut to 209
      expect(eraserIntervalsOf(s, 'a').single.end, closeTo(54.5, 0.005));
      final shown = eraserPreviewPieces(s).toList();
      final edit = s.end()!;
      expect(eraserPreviewPieces(s), isEmpty, reason: 'cleared at end');
      // the final pieces are the last previews' points with real ids
      expect(edit.added, hasLength(shown.length));
      for (var i = 0; i < shown.length; i++) {
        expect(edit.added[i].id, isNot(startsWith('pv-')));
        expect(edit.added[i].points, shown[i].points);
      }
      expect(firstX(edit.added[1]), closeTo(209, 0.01));
    },
  );

  test('the stroke filter applies to the partial eraser too', () {
    load([line('pen', 300), line('hl', 300, style: _hl)]);
    final s = c.beginErase(
      _at(const ui.Offset(200, 280), 0),
      spec: const EraserSpec(
        mode: EraserMode.partial,
        radius: 5,
        filter: core.StrokeFilter.exceptHighlighter,
      ),
      viewScale: 1,
    )..addSample(_at(const ui.Offset(200, 320), 1));
    final edit = s.end()!;
    expect(edit.removedIds, {'pen'});
  });

  group('shapes (v2, 6.15)', () {
    final shape = core.ShapeObject(
      id: 'sh',
      pageId: 'p1',
      shapeKind: core.ShapeKind.line,
      geometry: core.ShapeGeometry.line(
        const core.PagePoint(100, 400),
        const core.PagePoint(300, 400),
      ),
      style: const core.ShapeStyle(strokeColorArgb: 0xFFDD0000),
      createdAt: 1,
    );
    final text = core.TextBoxObject(
      id: 'tx',
      pageId: 'p1',
      frame: const core.ElementFrame(core.PageRect(150, 480, 250, 520)),
      text: 'keep',
      style: const core.TextBoxStyle(),
      createdAt: 2,
    );
    void loadAll(List<core.Stroke> strokes) => c.updateContent(
      SyntheticInk.pageContentWith(strokes: strokes, objects: [shape, text]),
    );

    test(
      'a stroke and a shape in one pass → Composite[Split, RemoveElements]',
      () {
        loadAll([line('a', 300)]);
        final edit = erase(const [ui.Offset(200, 280), ui.Offset(200, 420)])!;
        expect(edit.kind, InkEditKind.splitStrokes);
        expect(edit.removedIds, {'sh', 'a'});
        expect(edit.removedObjectIds, {'sh'});
        expect(edit.added, hasLength(2));
        final cmd = edit.toCommand() as core.CompositeCommand;
        expect(cmd.commands.map((x) => x.runtimeType), [
          core.SplitStrokes,
          core.RemoveElements,
        ]);
        expect((cmd.commands[1] as core.RemoveElements).elementIds, ['sh']);
        expect(
          c.pendingIds,
          containsAll(['a', 'sh', ...edit.added.map((s) => s.id)]),
        );
      },
    );

    test(
      'a whole stroke + a shape → Composite[RemoveStrokes, RemoveElements]',
      () {
        loadAll([
          strokeThrough(
            segment(const ui.Offset(195, 300), const ui.Offset(205, 300)),
            _pen,
            id: 'short',
          ),
        ]);
        final edit = erase(const [ui.Offset(200, 290), ui.Offset(200, 410)])!;
        expect(edit.added, isEmpty);
        final cmd = edit.toCommand() as core.CompositeCommand;
        expect(cmd.commands.map((x) => x.runtimeType), [
          core.RemoveStrokes,
          core.RemoveElements,
        ]);
      },
    );

    test('a shape only → RemoveElements alone; the text box stays', () {
      loadAll([line('a', 300)]);
      final edit = erase(const [
        ui.Offset(120, 390),
        ui.Offset(120, 530),
        ui.Offset(220, 500),
      ])!;
      expect(edit.removedIds, {'sh'});
      expect(edit.removedObjectIds, {'sh'});
      expect(edit.toCommand(), isA<core.RemoveElements>());
      expect(c.content!.objects.map((o) => o.id), contains('tx'));
      expect(c.pendingIds, {'sh'});
    });
  });

  group('intervals', () {
    test('merge joins overlapping and ε-close intervals', () {
      const p = ParamInterval.new;
      expect(PartialEraser.mergeIntervals([p(3, 4), p(1, 2), p(1.5, 2.5)]), [
        p(1, 2.5),
        p(3, 4),
      ]);
      expect(PartialEraser.mergeIntervals([p(1, 2), p(2 + 5e-7, 3)]), [
        p(1, 3),
      ]);
      expect(PartialEraser.mergeIntervals([p(1, 2), p(2.01, 3)]), [
        p(1, 2),
        p(2.01, 3),
      ]);
    });

    test('complement within [0, last]', () {
      const p = ParamInterval.new;
      expect(PartialEraser.complement([p(1, 2), p(3, 4)], 5), [
        p(0, 1),
        p(2, 3),
        p(4, 5),
      ]);
      expect(PartialEraser.complement([p(0, 5)], 5), isEmpty);
      expect(PartialEraser.complement([p(0, 1.5)], 5), [p(1.5, 5)]);
    });

    test('piece data: lerp ends + the original points between', () {
      final s = InkStroke.of(line('a', 300));
      final data = PartialEraser.pieceData(
        s.points,
        const ParamInterval(2.25, 5),
      );
      // lerp(2.25), points 3 and 4, point 5 — no duplicate at the integer end
      expect(data.length, 4 * core.StrokePoints.stride);
      expect(data[0], closeTo(104.5, 1e-4));
      expect(data[core.StrokePoints.stride], closeTo(106, 1e-4));
      expect(data[3 * core.StrokePoints.stride], closeTo(110, 1e-4));
    });
  });
}
