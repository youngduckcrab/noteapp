// T06 (03-ink 8, 6.7 F8): what finish() hands to CORE — t base, createdAt,
// tilt / azimuth presence, and the rollover of strokes longer than 500 s.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/stroke/stroke_builder.dart';
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

core.StrokeStyle _style(core.PenTool tool) =>
    core.StrokeStyle.defaultsFor(tool);

const _stride = core.StrokePoints.stride;

List<double> _t(Float32List data) => [
  for (var o = 5; o < data.length; o += _stride) data[o],
];

void main() {
  test('t = ms since pen down; the first point is at 0', () {
    final samples = SyntheticInk.line(
      const Offset(10, 10),
      const Offset(110, 60),
      samples: 60,
      startUs: 7000000, // the sample clock does not start at 0
    );
    final f = buildStroke(
      samples,
      style: _style(core.PenTool.ballpoint),
      viewScale: 1,
    )!;
    final t = _t(f.data);
    expect(t.first, 0);
    expect(f.startTimeUs, 7000000);
    // the last point is the last sample: (59 / 120 Hz) s later
    expect(t.last, closeTo((samples.last.timeUs - 7000000) / 1000, 0.01));
    for (var i = 1; i < t.length; i++) {
      expect(t[i], greaterThanOrEqualTo(t[i - 1]));
    }
    expect(f.createdAtOffsetMs, 0);
  });

  test(
    'a start hook is cut: first t > 0, createdAt stays the pen-down time',
    () {
      // 3 samples flicking back (150°) into (20, 20), then 40 pt to the right
      final hook = [
        for (var k = 0; k < 3; k++)
          InkSample(
            position: Offset(
              20 + (3 - k) * 0.35 * 0.866,
              20 - (3 - k) * 0.35 * 0.5,
            ),
            timeUs: k * 8000,
            kind: InkPointerKind.stylus,
            pressure: 0.5,
          ),
      ];
      final line = [
        for (var i = 0; i <= 40; i++)
          InkSample(
            position: Offset(20.0 + i, 20),
            timeUs: 24000 + i * 8000,
            kind: InkPointerKind.stylus,
            pressure: 0.5,
          ),
      ];
      final style = _style(core.PenTool.ballpoint).copyWith(
        smoothing: 0,
      ); // raw positions, so the hook is exactly as drawn
      final f = buildStroke([...hook, ...line], style: style, viewScale: 1)!;
      final t = _t(f.data);
      expect(t.first, greaterThan(0));
      expect(t.first, lessThan(50));
      expect(f.data[1], closeTo(20, 1e-3)); // starts on the line

      final c = createTestPageController(
        services: testInkCoreServices(startMillis: 5000),
      )..updateContent(SyntheticInk.pageContent());
      addTearDown(c.dispose);
      final session = c.beginStroke(hook.first, style: style, viewScale: 1);
      [...hook.skip(1), ...line].forEach(session.addSample);
      final stroke = session.end()!.added.single;
      expect(stroke.createdAt, 5000);
      expect(stroke.points.t(0), greaterThan(0));
    },
  );

  test('web-like input (orientation 0) → hasAzimuth false', () {
    final web = buildStroke(
      SyntheticInk.line(Offset.zero, const Offset(50, 0), tilt: 0.6),
      style: _style(core.PenTool.pencil),
      viewScale: 1,
    )!;
    expect(web.hasAzimuth, isFalse);
    expect(web.hasTilt, isTrue);
    final native = buildStroke(
      [
        for (final s in SyntheticInk.line(Offset.zero, const Offset(50, 0)))
          s.copyWith(orientation: 0.8),
      ],
      style: _style(core.PenTool.pencil),
      viewScale: 1,
    )!;
    expect(native.hasAzimuth, isTrue);
    expect(native.data[4], closeTo(0.8, 1e-6));
    // no tilt reported → hasTilt false and the channel is 0
    expect(native.hasTilt, isFalse);
    expect(native.data[3], 0);
  });

  test('a finger → hasTilt false (tilt ignored)', () {
    final f = buildStroke(
      SyntheticInk.line(
        Offset.zero,
        const Offset(50, 0),
        kind: InkPointerKind.touch,
        pressure: null,
        tilt: 0.9,
      ),
      style: _style(core.PenTool.pencil),
      viewScale: 1,
    )!;
    expect(f.hasTilt, isFalse);
    expect(f.data[3], 0);
    expect(f.pressureSource, PressureSource.simulated);
  });

  test('rollover: a 501 s stroke → 2 CORE strokes in one AddStrokes', () {
    // about 10 Hz for 501 s, a slow line to the right; the clock is fake
    const dtUs = 99013;
    final samples = [
      for (var i = 0; i * dtUs <= 501000000; i++)
        InkSample(
          position: Offset(40 + i * 0.1, 200),
          timeUs: i * dtUs,
          kind: InkPointerKind.touch,
        ),
    ];
    final clock = FakeInkClock();
    final c = createTestPageController(
      clock: clock,
      services: testInkCoreServices(startMillis: 1000000),
    )..updateContent(SyntheticInk.pageContent());
    addTearDown(c.dispose);
    final session = c.beginStroke(
      samples.first,
      style: _style(core.PenTool.fountain),
      viewScale: 1,
      meta: const InkStrokeMeta(recordingId: 'rec-1', recordingOffsetMs: 4200),
    );
    for (final s in samples.skip(1)) {
      clock.us = s.timeUs;
      session.addSample(s);
    }
    final edit = session.end()!;
    expect(edit.added, hasLength(2));
    final (a, b) = (edit.added[0], edit.added[1]);

    // every t inside the contract range
    for (final s in edit.added) {
      for (var i = 0; i < s.points.length; i++) {
        expect(s.points.t(i), inInclusiveRange(0, InkTuning.strokeRolloverMs));
      }
    }
    // the boundary sample b is the last one within 500 000 ms
    final bIndex = samples.lastIndexWhere(
      (s) => s.timeUs / 1000 <= InkTuning.strokeRolloverMs,
    );
    final tb = samples[bIndex].timeUs / 1000;
    expect(a.createdAt, 1000000);
    expect(b.createdAt, a.createdAt + tb.floor());
    expect(a.recordingId, 'rec-1');
    expect(b.recordingId, 'rec-1');
    expect(a.recordingOffsetMs, 4200);
    expect(b.recordingOffsetMs, 4200 + tb.floor());
    expect(a.points.t(a.points.length - 1), closeTo(tb, 0.1));
    expect(b.points.t(0), 0);
    expect(
      b.points.t(b.points.length - 1),
      closeTo((samples.last.timeUs - samples[bIndex].timeUs) / 1000, 0.1),
    );
    // b is on top of a (z order by createdAt)
    expect(b.createdAt, greaterThan(a.createdAt));

    // the parts meet at the same point with the same radius …
    final ia = InkStroke.of(a), ib = InkStroke.of(b);
    final ae = a.points.length - 1;
    expect(b.points.x(0), a.points.x(ae));
    expect(b.points.y(0), a.points.y(ae));
    expect(b.points.x(0), closeTo(samples[bIndex].position.dx, 0.01));
    expect(ib.radiusAt(0), ia.radiusAt(ae));
    // … with no taper at the join, the outer ends tapered (fountain)
    final mid = ia.maxRadius; // the untapered width
    expect(ia.radiusAt(ae), closeTo(mid, mid * 0.02));
    expect(ia.radiusAt(0), lessThan(mid * 0.5));
    expect(ib.radiusAt(b.points.length - 1), lessThan(mid * 0.5));

    // one gesture = one command = one undo step
    final cmd = edit.toCommand();
    expect(cmd, isA<core.AddStrokes>());
    expect((cmd as core.AddStrokes).strokes, hasLength(2));
    expect(c.pendingIds, {a.id, b.id});
  });
}
