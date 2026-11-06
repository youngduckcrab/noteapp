// T02 (03-ink 8, 4.1): InkStroke is the cached render view of one core.Stroke.
import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:note_core/note_core.dart' as core;

core.Stroke _stroke({
  String id = 's1',
  core.PenTool tool = core.PenTool.ballpoint,
  double? width,
  List<core.StrokePoint> points = const [
    core.StrokePoint(10, 10, widthQ: 0.25),
    core.StrokePoint(40, 30, widthQ: 0.5),
    core.StrokePoint(60, 20, widthQ: 0),
  ],
}) {
  final base = core.StrokeStyle.defaultsFor(tool);
  return core.Stroke(
    id: id,
    pageId: 'p1',
    style: width == null ? base : base.copyWith(width: width),
    points: core.StrokePoints.fromList(points),
    createdAt: 100,
  );
}

void main() {
  test('the same core.Stroke gives the same InkStroke (K-4)', () {
    final s = _stroke();
    final a = InkStroke.of(s);
    expect(identical(InkStroke.of(s), a), isTrue);
    expect(identical(a.source, s), isTrue);
    expect(a.id, 's1');
    expect(a.style, s.style);
    // Equal content, another instance → another InkStroke (identity, not value).
    final b = InkStroke.of(_stroke());
    expect(identical(a, b), isFalse);
    expect(a == b, isFalse);
    expect(a == InkStroke.of(s), isTrue);
    expect(a.hashCode, InkStroke.of(s).hashCode);
  });

  test('bounds is the CORE bounds as a Rect', () {
    for (final tool in core.PenTool.values) {
      final s = _stroke(tool: tool);
      final b = s.bounds;
      expect(
        InkStroke.of(s).bounds,
        Rect.fromLTRB(b.left, b.top, b.right, b.bottom),
      );
    }
  });

  test('radiusAt = max(minRadiusPt, 2 · width · widthQ)', () {
    final s = InkStroke.of(_stroke(width: 2));
    final p = s.source.points;
    for (var i = 0; i < p.length; i++) {
      expect(
        s.radiusAt(i),
        math.max(InkTuning.minRadiusPt, 2 * 2 * p.widthQ(i)),
      );
    }
    expect(s.radiusAt(0), closeTo(1.0, 1e-9)); // widthQ 0.25 → width / 2
    expect(s.radiusAt(1), closeTo(2.0, 1e-9));
    expect(s.radiusAt(2), InkTuning.minRadiusPt); // widthQ 0
    expect(s.maxRadius, closeTo(2.0, 1e-9));
  });

  test('highlighter radius is width / 2 whatever widthQ', () {
    final s = InkStroke.of(_stroke(tool: core.PenTool.highlighter, width: 12));
    for (var i = 0; i < s.points.length; i++) {
      expect(s.radiusAt(i), 6);
    }
    expect(s.maxRadius, 6);
    expect(s.layer, InkLayer.highlighter);
    expect(s.profile.cap, InkCap.square);
  });

  test('profile and layer follow the tool (every P1 pen its own profile, '
      'm5-7 T27–T31); the tape is cover (T31)', () {
    for (final tool in core.PenTool.values) {
      final s = InkStroke.of(_stroke(tool: tool));
      expect(s.profile, PenProfile.of(tool));
      if (!tool.isP0) {
        expect(
          s.profile,
          same(switch (tool) {
            core.PenTool.brush => PenProfile.brush,
            core.PenTool.calligraphy => PenProfile.calligraphy,
            core.PenTool.dashed => PenProfile.dashed,
            core.PenTool.laser => PenProfile.laser,
            core.PenTool.tape => PenProfile.tape,
            _ => PenProfile.ballpoint,
          }),
        );
      }
      expect(s.layer, switch (tool) {
        core.PenTool.highlighter => InkLayer.highlighter,
        core.PenTool.tape => InkLayer.cover,
        _ => InkLayer.ink,
      });
    }
  });

  test('isDot: one point or a zero-length centerline', () {
    expect(
      InkStroke.of(_stroke(points: const [core.StrokePoint(5, 5)])).isDot,
      isTrue,
    );
    expect(
      InkStroke.of(
        _stroke(
          points: const [
            core.StrokePoint(5, 5),
            core.StrokePoint(5, 5, widthQ: 0.5),
          ],
        ),
      ).isDot,
      isTrue,
    );
    expect(InkStroke.of(_stroke()).isDot, isFalse);
  });
}
