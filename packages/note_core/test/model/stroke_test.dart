import 'dart:math' as math;

import 'package:note_core/note_core.dart';
import 'package:test/test.dart';

Stroke _stroke({
  String id = 's1',
  PenTool tool = PenTool.ballpoint,
  List<StrokePoint> points = const [StrokePoint(0, 0), StrokePoint(10, 5)],
  int createdAt = 100,
}) => Stroke(
  id: id,
  pageId: 'p1',
  style: StrokeStyle.defaultsFor(tool),
  points: StrokePoints.fromList(points),
  createdAt: createdAt,
);

void main() {
  group('bounds = pointBounds.inflate(width * max(2 * maxWidthQ, 0.75))', () {
    test('nominal widthQ 0.25 → 0.75 floor (highlighter caps)', () {
      final s = _stroke(tool: PenTool.highlighter);
      expect(s.bounds, const PageRect(0, 0, 10, 5).inflate(12 * 0.75));
    });

    test('fountain with widthQ 1.0 → factor 2', () {
      final s = _stroke(
        tool: PenTool.fountain,
        points: const [
          StrokePoint(0, 0, widthQ: 1),
          StrokePoint(1, 1, widthQ: 0.2),
        ],
      );
      expect(s.bounds, const PageRect(0, 0, 1, 1).inflate(2.2 * 2));
    });

    test('maxWidthQ between: 0.5 → factor 1', () {
      final s = _stroke(points: const [StrokePoint(3, 3, widthQ: 0.5)]);
      expect(s.bounds, const PageRect(3, 3, 3, 3).inflate(1.6 * 1.0));
    });

    test('single point stroke has a non-empty bounds', () {
      final s = _stroke(points: const [StrokePoint(5, 5)]);
      expect(s.bounds.isEmpty, isFalse);
      expect(s.bounds.width, closeTo(2 * 1.6 * 0.75, 1e-9));
    });
  });

  test('compareOrder: createdAt, then id', () {
    final a = _stroke(id: 'b', createdAt: 1);
    final b = _stroke(id: 'a', createdAt: 2);
    final c = _stroke(id: 'c', createdAt: 2);
    final list = [c, b, a]..sort(Stroke.compareOrder);
    expect(list.map((s) => s.id), ['b', 'a', 'c']);
  });

  test('updatedAt defaults to createdAt; estimatedBytes', () {
    final s = _stroke();
    expect(s.updatedAt, s.createdAt);
    expect(s.estimatedBytes, 96 + 2 * 24);
    expect(s.kind, EntityKind.stroke);
    expect(s.isDeleted, isFalse);
  });

  test('fragment inherits style, createdAt, recording; points keep t', () {
    final s = Stroke(
      id: 's1',
      pageId: 'p1',
      style: StrokeStyle.defaultsFor(PenTool.pencil),
      points: StrokePoints.fromList(const [
        StrokePoint(0, 0, t: 0),
        StrokePoint(1, 0, t: 8),
        StrokePoint(2, 0, t: 16),
      ]),
      recordingId: 'r1',
      recordingOffsetMs: 500,
      createdAt: 1000,
      version: const Hlc(1, 0, '0000000000000001'),
    );
    final f = s.fragment(id: 's2', points: s.points.sublist(1));
    expect(f.id, 's2');
    expect(f.pageId, s.pageId);
    expect(f.style, s.style);
    expect(f.createdAt, 1000);
    expect(f.recordingId, 'r1');
    expect(f.recordingOffsetMs, 500);
    expect(f.points.t(0), 8);
    expect(f.version, isNull);
  });

  test('transformed scales width within limits; version reset', () {
    final s = _stroke().copyWith(version: const Hlc(1, 0, '0000000000000001'));
    final t = s.transformed(Affine2.scaling(2, 2));
    expect(t.style.width, closeTo(3.2, 1e-9));
    expect(t.points.x(1), 20);
    expect(t.version, isNull);
    expect(s.transformed(Affine2.scaling(100, 100)).style.width, 30);
    expect(s.transformed(Affine2.scaling(0.001, 0.001)).style.width, 0.1);
    expect(
      s.transformed(Affine2.scaling(2, 2), scaleWidth: false).style.width,
      1.6,
    );
    expect(
      s.transformed(Affine2.rotation(math.pi)).points.x(1),
      closeTo(-10, 1e-6),
    );
  });

  test('copyWith(id:) for paste; clearDeletedAt', () {
    final s = _stroke().copyWith(deletedAt: 5);
    expect(s.isDeleted, isTrue);
    final c = s.copyWith(id: 'new', createdAt: 999, clearDeletedAt: true);
    expect(c.id, 'new');
    expect(c.createdAt, 999);
    expect(c.isDeleted, isFalse);
    expect(c.version, isNull);
  });

  test('value equality uses point content', () {
    expect(_stroke(), _stroke());
    expect(_stroke().hashCode, _stroke().hashCode);
    expect(_stroke() == _stroke(id: 'other'), isFalse);
  });
}
