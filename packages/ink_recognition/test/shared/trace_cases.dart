// Shared body (VM + Chrome) of the HandwritingTrace tests — m5-7/05-library
// 4.4.6, 6.4 (8.1 B6-b `unit/handwriting_trace_test.dart`; the same body runs
// in `web/recognition_browser_test.dart`). The point of running it on dart2js:
// ts is a Float64List and 13-digit epoch ms stay exact there too.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_recognition/ink_recognition.dart';
import 'package:note_core/note_core.dart' as core;

core.Stroke _stroke({
  String id = 'st1',
  required List<core.StrokePoint> points,
  int createdAt = 1730790000000,
}) => core.Stroke(
  id: id,
  pageId: 'p1',
  style: core.StrokeStyle.defaultsFor(core.PenTool.ballpoint),
  points: core.StrokePoints.fromList(points),
  createdAt: createdAt,
);

void defineHandwritingTraceTests() {
  group('HandwritingTrace.fromStroke', () {
    test('copies x / y per point as Float32List and keeps the stroke id', () {
      final stroke = _stroke(
        points: const [
          core.StrokePoint(10.25, 20.5),
          core.StrokePoint(11.75, 21.25, t: 8),
          core.StrokePoint(-3.5, 840.5, t: 16),
        ],
      );
      final trace = HandwritingTrace.fromStroke(stroke);
      expect(trace.xs, isA<Float32List>());
      expect(trace.ys, isA<Float32List>());
      expect(trace.ts, isA<Float64List>());
      expect(trace.xs, [10.25, 11.75, -3.5]);
      expect(trace.ys, [20.5, 21.25, 840.5]);
      expect(trace.strokeId, 'st1');
      for (var i = 0; i < stroke.points.length; i++) {
        expect(trace.xs[i], stroke.points.x(i));
        expect(trace.ys[i], stroke.points.y(i));
      }
    });

    test('ts = createdAt + t(i), exact 13-digit epoch ms', () {
      final stroke = _stroke(
        points: const [
          core.StrokePoint(0, 0),
          core.StrokePoint(1, 0, t: 8),
          core.StrokePoint(2, 0, t: 16),
          core.StrokePoint(3, 0, t: 499992),
        ],
      );
      final trace = HandwritingTrace.fromStroke(stroke);
      expect(trace.ts, [
        1730790000000.0,
        1730790000008.0,
        1730790000016.0,
        1730790499992.0,
      ]);
      // The ML Kit adapter rounds to int ms (6.4) — exact on the web too.
      expect(trace.ts.map((t) => t.round()).toList(), [
        1730790000000,
        1730790000008,
        1730790000016,
        1730790499992,
      ]);
    });

    test('fractional t (0.1 ms steps) keeps its fraction', () {
      final stroke = _stroke(
        createdAt: 4102444800000, // 2100-01-01
        points: const [
          core.StrokePoint(0, 0, t: 0.5),
          core.StrokePoint(1, 1, t: 12.3),
        ],
      );
      final trace = HandwritingTrace.fromStroke(stroke);
      for (var i = 0; i < stroke.points.length; i++) {
        expect(trace.ts[i], 4102444800000 + stroke.points.t(i));
      }
      expect(trace.ts[0], 4102444800000.5);
      expect(trace.ts[1].floor(), 4102444800012);
      expect(trace.ts[1] - 4102444800000, closeTo(12.3, 1e-3));
    });

    test('one point → lists of length 1; fragments keep createdAt and t', () {
      final single = HandwritingTrace.fromStroke(
        _stroke(id: 'dot', points: const [core.StrokePoint(5, 6, t: 3)]),
      );
      expect((single.xs.length, single.ys.length, single.ts.length), (1, 1, 1));
      expect(single.ts.single, 1730790000003);

      final whole = _stroke(
        points: const [
          core.StrokePoint(0, 0),
          core.StrokePoint(1, 0, t: 8),
          core.StrokePoint(2, 0, t: 16),
        ],
      );
      final piece = whole.fragment(
        id: 'piece',
        points: whole.points.sublist(1),
      );
      final trace = HandwritingTrace.fromStroke(piece);
      expect(trace.strokeId, 'piece');
      expect(trace.ts, [1730790000008.0, 1730790000016.0]);
    });
  });

  test('HandwritingLineInput defaults', () {
    const input = HandwritingLineInput([]);
    expect(input.traces, isEmpty);
    expect(input.preContext, '');
    expect(input.writingAreaPt, isNull);
  });
}
