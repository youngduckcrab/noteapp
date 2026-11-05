// T06 (03-ink 8, 4.4, 6.3–6.7, 6.12 R5): StrokeBuilder — live geometry and finish.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/input/pressure_detector.dart';
import 'package:ink_engine/src/render/sessions.dart';
import 'package:ink_engine/src/stroke/stroke_builder.dart';
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

import '../../support/stroke_scripts.dart';

core.StrokeStyle _style(core.PenTool tool) =>
    core.StrokeStyle.defaultsFor(tool);

StrokeBuilder _builder(
  core.PenTool tool, {
  InkPointerKind kind = InkPointerKind.stylus,
  PressureMode mode = PressureMode.auto,
  PressureCapability prior = PressureCapability.unknown,
  double viewScale = 1,
  core.StrokeStyle? style,
}) => StrokeBuilder(
  style: style ?? _style(tool),
  viewScale: viewScale,
  pressure: PressureDetector(kind: kind, mode: mode, prior: prior),
);

List<double> _q(Float32List data) => [
  for (var o = 2; o < data.length; o += core.StrokePoints.stride) data[o],
];

void main() {
  test('one sample at a time vs ten at a time: the same CORE stroke', () {
    final samples = scriptedStroke();
    core.Stroke run(int batch) {
      final c = createTestPageController()
        ..updateContent(SyntheticInk.pageContent());
      addTearDown(c.dispose);
      final session = c.beginStroke(
        samples.first,
        style: _style(core.PenTool.fountain),
        viewScale: 1,
      );
      final rest = samples.skip(1).toList();
      if (batch == 1) {
        rest.forEach(session.addSample);
      } else {
        for (var i = 0; i < rest.length; i += batch) {
          session.addSamples(rest.sublist(i, math.min(i + batch, rest.length)));
        }
      }
      return session.end()!.added.single;
    }

    final a = run(1), b = run(10);
    expect(b.points.rawData, a.points.rawData);
    expect(b.points.length, greaterThan(10));
  });

  test('buildStroke = add(...) for every sample + finish()', () {
    final samples = scriptedStroke();
    for (final tool in scriptedTools) {
      final b = _builder(tool);
      samples.forEach(b.add);
      final live = b.finish()!;
      final offline = buildStroke(samples, style: _style(tool), viewScale: 1)!;
      expect(offline.data, live.data, reason: '$tool');
      expect(offline.hasTilt, live.hasTilt);
      expect(offline.pressureSource, live.pressureSource);
    }
  });

  test('determinism: the script checksum is the recorded VM value', () {
    expect(scriptChecksum(), recordedScriptChecksum);
  });

  test('the live tail ends at the last raw position', () {
    final b = _builder(core.PenTool.ballpoint);
    final samples = SyntheticInk.line(
      const Offset(10, 10),
      const Offset(300, 200),
      samples: 120,
    );
    for (final s in samples) {
      b.add(s);
      final pts = livePoints(b.live);
      final last = pts.last;
      // the filtered end lags behind; the tail reaches the pen
      expect((last - s.position).distance, lessThanOrEqualTo(0.2 + 1e-9));
      if (b.stablePointCount > 3) expect(last, s.position);
      expect(b.live.bounds.contains(s.position), isTrue);
      expect(b.live.isEmpty, isFalse);
    }
    expect(b.live.tailPath.getBounds().isEmpty, isFalse);
    expect(b.live.polyline, isNull);
  });

  test('2000 samples: frozenPath is append-only, 64-point chunks', () {
    final b = _builder(
      core.PenTool.fountain,
      prior: PressureCapability.supported,
    );
    var chunks = <Path>[];
    var frozenBounds = Rect.zero;
    var version = b.live.version;
    for (var i = 0; i < 2000; i++) {
      final u = i / 1999;
      b.add(
        InkSample(
          position: Offset(
            100 + 200 * math.cos(u * 12 * math.pi) * (0.3 + 0.7 * u),
            300 + 200 * math.sin(u * 12 * math.pi) * (0.3 + 0.7 * u),
          ),
          timeUs: i * 4167,
          kind: InkPointerKind.stylus,
          pressure: 0.3 + 0.4 * u,
        ),
      );
      final now = liveFrozenChunks(b.live);
      expect(now.length, greaterThanOrEqualTo(chunks.length));
      for (var k = 0; k < chunks.length; k++) {
        expect(identical(now[k], chunks[k]), isTrue, reason: 'chunk $k');
      }
      chunks = now;
      final fb = b.live.frozenPath.getBounds();
      if (!frozenBounds.isEmpty) {
        // the frozen geometry only grows
        expect(fb.expandToInclude(frozenBounds), fb);
      }
      frozenBounds = fb;
      expect(b.live.version, greaterThan(version));
      version = b.live.version;
    }
    // chunk k holds points [64k, 64k + 64]; the last point opens the next one
    expect(
      chunks.length,
      (b.stablePointCount - 1) ~/ InkTuning.liveChunkPoints,
    );
    expect(chunks.length, greaterThan(25));
  });

  test('no samples → null; one sample → a dot at t = 0', () {
    expect(_builder(core.PenTool.ballpoint).finish(), isNull);
    expect(
      buildStroke(
        const [],
        style: _style(core.PenTool.ballpoint),
        viewScale: 1,
      ),
      isNull,
    );
    final dot = buildStroke(
      SyntheticInk.line(const Offset(40, 50), const Offset(40, 50), samples: 1),
      style: _style(core.PenTool.fountain),
      viewScale: 1,
    )!;
    expect(dot.pointCount, 1);
    expect(dot.data[0], 40);
    expect(dot.data[1], 50);
    expect(dot.data[5], 0);
    // the dot keeps its width (no taper on a single point)
    expect(dot.data[2], greaterThan(0.2));
    // finish(last:) alone also makes a dot
    final b = _builder(core.PenTool.ballpoint);
    final onlyUp = b.finish(
      last: const InkSample(
        position: Offset(5, 6),
        timeUs: 0,
        kind: InkPointerKind.stylus,
      ),
    )!;
    expect(onlyUp.pointCount, 1);
  });

  test('pending for 11 points, then real: earlier widthQ recomputed', () {
    // 11 samples at a constant 0.6 (not a W3C default → stays pending), then
    // a rising pressure: the 12th sample decides "real" (6.4 rule 4)
    final samples = [
      for (var i = 0; i < 40; i++)
        InkSample(
          position: Offset(20 + i * 3.0, 40),
          timeUs: i * 8333,
          kind: InkPointerKind.stylus,
          pressure: i < 11 ? 0.6 : 0.6 + (i - 10) * 0.01,
        ),
    ];
    final b = _builder(core.PenTool.fountain);
    for (var i = 0; i < 11; i++) {
      b.add(samples[i]);
    }
    expect(b.pressureSource, PressureSource.pending);
    final qPending = livePoints(b.live).length;
    expect(qPending, greaterThan(0));
    for (var i = 11; i < samples.length; i++) {
      b.add(samples[i]);
    }
    expect(b.pressureSource, PressureSource.real);
    final auto = b.finish()!;
    expect(auto.pressureSource, PressureSource.real);
    // identical to a stroke that used real pressure from the first sample
    final real = buildStroke(
      samples,
      style: _style(core.PenTool.fountain),
      viewScale: 1,
      mode: PressureMode.alwaysReal,
    )!;
    expect(auto.data, real.data);
    // and different from the simulated widths it started with
    final sim = buildStroke(
      samples,
      style: _style(core.PenTool.fountain),
      viewScale: 1,
      mode: PressureMode.alwaysSimulated,
    )!;
    expect(_q(sim.data), isNot(_q(auto.data)));
  });

  test('real pressure shapes the width; simulated follows the speed', () {
    double midQ(FinishedStroke f) => _q(f.data)[f.pointCount ~/ 2];
    FinishedStroke at(double pressure) => buildStroke(
      SyntheticInk.line(
        const Offset(10, 10),
        const Offset(210, 10),
        samples: 100,
        pressure: pressure,
      ),
      style: _style(core.PenTool.fountain),
      viewScale: 1,
      mode: PressureMode.alwaysReal,
    )!;
    expect(midQ(at(0.9)), greaterThan(midQ(at(0.5))));
    expect(midQ(at(0.5)), greaterThan(midQ(at(0.1))));
    // touch: simulated, fast → thinner than slow
    FinishedStroke touch(int samples) => buildStroke(
      SyntheticInk.line(
        const Offset(10, 10),
        const Offset(210, 10),
        samples: samples,
        kind: InkPointerKind.touch,
        pressure: null,
      ),
      style: _style(core.PenTool.fountain),
      viewScale: 1,
    )!;
    final fast = touch(30), slow = touch(600);
    expect(fast.pressureSource, PressureSource.simulated);
    expect(midQ(fast), lessThan(midQ(slow)));
  });

  test('fountain finish: tapered ends, the PointerUp pressure is ignored', () {
    final samples = SyntheticInk.line(
      const Offset(10, 10),
      const Offset(110, 10),
      samples: 80,
      pressure: 0.7,
    );
    final b = _builder(core.PenTool.fountain, mode: PressureMode.alwaysReal);
    samples.forEach(b.add);
    final f = b.finish(
      last: InkSample(
        position: const Offset(111, 10),
        timeUs: samples.last.timeUs + 8000,
        kind: InkPointerKind.stylus,
        pressure: 0, // web up events report 0: must not thin the end
      ),
    )!;
    final q = _q(f.data);
    final mid = q[q.length ~/ 2];
    expect(q.first, closeTo(mid * PenProfile.fountain.taperMinFactor, 0.002));
    expect(q.last, closeTo(mid * PenProfile.fountain.taperMinFactor, 0.002));
    // F1: the raw up position is the end point
    final n = f.pointCount, s = core.StrokePoints.stride;
    expect(f.data[(n - 1) * s], 111);
  });

  test('highlighter: polyline live geometry, widthQ 0.25, straightening', () {
    final style = _style(core.PenTool.highlighter)
        .withHighlighterStraightening(HighlighterStraightening.alwaysStraight);
    final b = _builder(core.PenTool.highlighter, style: style);
    final samples = SyntheticInk.wave(const Offset(50, 300), length: 200);
    for (final s in samples) {
      b.add(s);
      final pts = livePoints(b.live);
      expect(pts.length, 2);
      expect(pts.first, samples.first.position);
    }
    expect(b.live.polyline!.length, 4);
    expect(b.live.tailPath.getBounds().isEmpty, isTrue);
    final f = b.finish()!;
    expect(f.pointCount, 2);
    expect(_q(f.data).toSet(), {core.kNominalWidthQ});

    final off = buildStroke(
      samples,
      style: _style(core.PenTool.highlighter),
      viewScale: 1,
    )!;
    expect(off.pointCount, greaterThan(2));
    expect(_q(off.data).toSet(), {core.kNominalWidthQ});
  });

  test('duplicates are merged; time going backwards is fixed', () {
    final b = _builder(core.PenTool.ballpoint);
    b
      ..add(
        const InkSample(
          position: Offset(10, 10),
          timeUs: 10000,
          kind: InkPointerKind.stylus,
          pressure: 0.4,
        ),
      )
      ..add(
        const InkSample(
          position: Offset(10.05, 10),
          timeUs: 11000,
          kind: InkPointerKind.stylus,
          pressure: 0.45,
        ),
      );
    expect(b.rawSampleCount, 1);
    b.add(
      const InkSample(
        position: Offset(20, 10),
        timeUs: 5000, // earlier than the previous one
        kind: InkPointerKind.stylus,
        pressure: 0.5,
      ),
    );
    expect(b.rawSampleCount, 2);
    final f = b.finish()!;
    final s = core.StrokePoints.stride;
    for (var i = 1; i < f.pointCount; i++) {
      expect(f.data[i * s + 5], greaterThanOrEqualTo(f.data[(i - 1) * s + 5]));
    }
  });
}
