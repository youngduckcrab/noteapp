// T11 (03-ink 8, 4.12, 6.15): InkDiagnostics with a fake clock and synthetic
// FrameTimings — p50 / p95 / max windows, frame matching for event→rasterEnd,
// nothing recorded while disabled, listeners notified at most every 250 ms
// (fake_async), tile raster summary, the timings callback of the scheduler
// binding attached only while enabled.
import 'dart:ui' as ui;

import 'package:fake_async/fake_async.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

InkSample _sample(int timeUs, {double? pressure = 0.5}) => InkSample(
  position: ui.Offset(timeUs / 1000, 10),
  timeUs: timeUs,
  kind: InkPointerKind.stylus,
  pressure: pressure,
  tilt: 0.3,
);

/// A frame whose build starts at [buildStartUs].
ui.FrameTiming _frame(
  int buildStartUs, {
  int buildUs = 2000,
  int gapUs = 500,
  int rasterUs = 3000,
}) {
  final buildFinish = buildStartUs + buildUs;
  final rasterStart = buildFinish + gapUs;
  return ui.FrameTiming(
    vsyncStart: buildStartUs - 100,
    buildStart: buildStartUs,
    buildFinish: buildFinish,
    rasterStart: rasterStart,
    rasterFinish: rasterStart + rasterUs,
    rasterFinishWallTime: rasterStart + rasterUs,
  );
}

void _expectNothingRecorded(InkStatsSnapshot s) {
  expect(s.lastKind, isNull);
  expect(s.lastRawPressure, isNull);
  expect(s.lastWidthFactor, isNull);
  expect(s.inputHz, 0);
  expect(s.samplesPerFrame, 0);
  for (final w in [
    s.eventToPaint,
    s.receiveToPaint,
    s.eventToRasterEnd,
    s.tileRaster,
  ]) {
    expect(w, LatencySummary.empty);
  }
  expect(s.frameBuildP95Ms, 0);
  expect(s.lastTileRasterMs, 0);
  expect(s.warnings, 0);
  expect(s.pressureSource, PressureSource.pending);
  expect(s.stylusCapability, PressureCapability.unknown);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeInkClock clock;
  late InkDiagnostics d;

  setUp(() {
    clock = FakeInkClock(startUs: 1000000);
    d = InkDiagnostics(clock: clock)..enabled = true;
  });
  tearDown(() => d.dispose());

  /// One sample received [receiveDelayUs] after its event, painted
  /// [paintDelayUs] after receipt.
  void inputThenPaint(int eventUs, int receiveDelayUs, int paintDelayUs) {
    clock.us = eventUs + receiveDelayUs;
    d.onSamples([_sample(eventUs)], receiveUs: clock.us);
    clock.us += paintDelayUs;
    d.onActivePaint(paintUs: clock.us, updateMs: 0.4);
  }

  group('latency windows (p50 / p95 / max)', () {
    test('receive→paint and event→paint, nearest rank', () {
      // receive→paint 1..20 ms, event→paint = that + 2 ms
      for (var i = 1; i <= 20; i++) {
        inputThenPaint(2000000 + i * 20000, 2000, i * 1000);
      }
      final s = d.snapshot;
      expect(s.receiveToPaint.count, 20);
      expect(s.receiveToPaint.p50Ms, 10);
      expect(s.receiveToPaint.p95Ms, 19);
      expect(s.receiveToPaint.maxMs, 20);
      expect(s.eventToPaint.p50Ms, 12);
      expect(s.eventToPaint.p95Ms, 21);
      expect(s.eventToPaint.maxMs, 22);
      expect(s.activeStrokeUpdateMs, 0.4);
      expect(s.clockAligned, isTrue);
    });

    test('a paint without new samples adds no latency value', () {
      inputThenPaint(2000000, 1000, 3000);
      d.onActivePaint(paintUs: clock.us + 16000, updateMs: 0.1);
      expect(d.snapshot.receiveToPaint.count, 1);
      expect(d.snapshot.eventToPaint.count, 1);
    });

    test('the window keeps the last 240 values', () {
      for (var i = 0; i < 300; i++) {
        inputThenPaint(2000000 + i * 10000, 0, i < 60 ? 9000 : 1000);
      }
      expect(InkTuning.latencyWindow, 240);
      final s = d.snapshot.receiveToPaint;
      expect(s.count, 240);
      expect(s.maxMs, 1, reason: 'the 60 slow ones fell out');
    });

    test('input Hz and samples per frame over the last second', () {
      // 240 samples / s, painted in batches of 2 → 120 paints
      for (var i = 0; i < 240; i++) {
        clock.us = 3000000 + i * 4167;
        d.onSamples([_sample(clock.us)], receiveUs: clock.us);
        if (i.isOdd) d.onActivePaint(paintUs: clock.us + 500, updateMs: 0.2);
      }
      final s = d.snapshot;
      expect(s.inputHz, closeTo(240, 1));
      expect(s.samplesPerFrame, closeTo(2, 0.05));
      expect(s.lastKind, InkPointerKind.stylus);
      expect(s.lastRawPressure, 0.5);
      expect(s.lastTilt, 0.3);
    });
  });

  group('frame matching (event→rasterEnd)', () {
    test('a paint inside [buildStart, rasterStart] takes that frame', () {
      // event at 10.000 s, paint at 10.004 s, frame build 10.003 s
      inputThenPaint(10000000, 1000, 3000);
      final frame = _frame(10003000);
      d.onFrameTimings([frame]);
      final s = d.snapshot;
      // rasterFinish = 10.003 + 0.002 + 0.0005 + 0.003 = 10.0085 s
      expect(s.eventToRasterEnd.count, 1);
      expect(s.eventToRasterEnd.p50Ms, closeTo(8.5, 1e-9));
      expect(s.frameBuildP95Ms, 2);
      expect(s.frameRasterP95Ms, 3);
    });

    test('several frames in one batch; each paint matched once', () {
      inputThenPaint(10000000, 1000, 3000); // paint 10.004
      inputThenPaint(10016000, 1000, 3000); // paint 10.020
      d.onFrameTimings([_frame(10003000), _frame(10019000)]);
      expect(d.snapshot.eventToRasterEnd.count, 2);
      expect(d.snapshot.eventToRasterEnd.maxMs, closeTo(8.5, 1e-9));
      d.onFrameTimings([_frame(10019000)]); // the same frame again
      expect(d.snapshot.eventToRasterEnd.count, 2);
    });

    test('a paint later than rasterStart waits for the next frame', () {
      inputThenPaint(10000000, 1000, 9000); // paint 10.010
      d.onFrameTimings([_frame(10003000)]); // raster starts 10.0055
      expect(d.snapshot.eventToRasterEnd.count, 0);
      d.onFrameTimings([_frame(10009000)]);
      expect(d.snapshot.eventToRasterEnd.count, 1);
      // rasterFinish 10.009 + 0.002 + 0.0005 + 0.003 − event 10.000
      expect(d.snapshot.eventToRasterEnd.p50Ms, closeTo(14.5, 1e-9));
    });

    test(
      'a paint before the frame that arrives is dropped (never matched)',
      () {
        inputThenPaint(10000000, 1000, 1000); // paint 10.002
        d.onFrameTimings([_frame(10005000)]); // build starts after it
        d.onFrameTimings([_frame(10001000)]); // out of order: ignored
        expect(d.snapshot.eventToRasterEnd.count, 0);
      },
    );

    test('clock not aligned with event timestamps → no event→rasterEnd', () {
      final native = InkDiagnostics(
        clock: FakeInkClock(alignedWithEventTimestamps: false),
      )..enabled = true;
      addTearDown(native.dispose);
      native
        ..onSamples([_sample(0)], receiveUs: 1000)
        ..onActivePaint(paintUs: 4000, updateMs: 0.1)
        ..onFrameTimings([_frame(3000)]);
      final s = native.snapshot;
      expect(s.clockAligned, isFalse);
      expect(s.eventToRasterEnd.count, 0);
      expect(s.receiveToPaint.count, 1);
      expect(s.frameBuildP95Ms, 2, reason: 'frame durations still count');
    });
  });

  group('enabled == false', () {
    test('nothing is recorded and nobody is notified', () {
      final off = InkDiagnostics(clock: clock);
      addTearDown(off.dispose);
      var notified = 0;
      off.addListener(() => notified++);
      off
        ..onSamples([_sample(0)], receiveUs: 1)
        ..onActivePaint(paintUs: 5, updateMs: 1)
        ..onFrameTimings([_frame(2)])
        ..onWidthFactor(2, PressureSource.real, PressureCapability.supported)
        ..onTileRaster(7)
        ..onWarning('x');
      _expectNothingRecorded(off.snapshot);
      expect(notified, 0);
    });

    test('disabling stops recording; reset clears', () {
      inputThenPaint(10000000, 1000, 3000);
      d.enabled = false;
      inputThenPaint(10100000, 1000, 3000);
      d.enabled = true;
      expect(d.snapshot.receiveToPaint.count, 1);
      d.reset();
      _expectNothingRecorded(d.snapshot);
    });
  });

  test('onTileRaster → tileRaster summary and lastTileRasterMs', () {
    for (final ms in [3.0, 1.0, 9.0, 4.0, 2.0]) {
      d.onTileRaster(ms);
    }
    final s = d.snapshot;
    expect(s.lastTileRasterMs, 2);
    expect(s.tileRaster.count, 5);
    expect(s.tileRaster.p50Ms, 3);
    expect(s.tileRaster.p95Ms, 9);
    expect(s.tileRaster.maxMs, 9);
  });

  test('width factor, pressure source, capability, cache, warnings', () {
    d
      ..onWidthFactor(1.7, PressureSource.real, PressureCapability.supported)
      ..onCacheStats(
        const InkCacheStats(
          outlineEntries: 3,
          outlineBytes: 300,
          rasterTiles: 0,
          rasterBytes: 0,
          chunkPictures: 0,
        ),
        visibleStrokes: 3,
      )
      ..onWarning('pendingCommitTimeout');
    final s = d.snapshot;
    expect(s.lastWidthFactor, 1.7);
    expect(s.pressureSource, PressureSource.real);
    expect(s.stylusCapability, PressureCapability.supported);
    expect(s.cache.outlineBytes, 300);
    expect(s.visibleStrokeCount, 3);
    expect(s.warnings, 1);
  });

  test('notifications: at most every 250 ms, never inside a hook', () {
    fakeAsync((async) {
      final diag = InkDiagnostics(clock: clock)..enabled = true;
      var notified = 0;
      diag.addListener(() => notified++);
      diag.onWarning('a');
      expect(notified, 0, reason: 'not synchronously (hooks run in paint)');
      async.elapse(Duration.zero);
      expect(notified, 1);
      for (var i = 0; i < 20; i++) {
        diag.onTileRaster(i.toDouble());
        async.elapse(const Duration(milliseconds: 10));
      }
      // 200 ms into the 250 ms window
      expect(notified, 1);
      async.elapse(const Duration(milliseconds: 50));
      expect(notified, 2, reason: 'trailing notification');
      expect(diag.snapshot.tileRaster.count, 20);
      async.elapse(const Duration(seconds: 1));
      expect(notified, 2, reason: 'no change, no notification');
      diag.onWarning('b');
      async.elapse(Duration.zero);
      expect(notified, 3);
      diag.dispose();
      async.elapse(const Duration(seconds: 1));
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('the scheduler timings callback is attached only while enabled', () {
    final dispatcher = TestWidgetsFlutterBinding.instance.platformDispatcher;
    void report() => dispatcher.onReportTimings?.call([_frame(1000)]);
    final diag = InkDiagnostics(clock: clock);
    addTearDown(diag.dispose);
    report();
    diag.enabled = true;
    report();
    report();
    expect(diag.snapshot.frameBuildP95Ms, 2);
    diag.enabled = false;
    diag.enabled = true;
    report();
    final before = diag.snapshot;
    diag.enabled = false;
    report();
    expect(diag.snapshot, before);
    expect(SchedulerBinding.instance, isNotNull);
  });

  testWidgets('a pen session reports the width factor of its samples', (
    tester,
  ) async {
    final c = createTestPageController()
      ..updateContent(SyntheticInk.pageContent());
    addTearDown(c.dispose);
    c.diagnostics.enabled = true;
    final samples = SyntheticInk.line(
      const ui.Offset(10, 10),
      const ui.Offset(200, 40),
      pressure: 0.9,
    );
    final s = c.beginStroke(
      samples.first,
      style: core.StrokeStyle.defaultsFor(core.PenTool.fountain),
      viewScale: 1,
    )..addSamples(samples.skip(1));
    final snap = c.diagnostics.snapshot;
    expect(snap.lastWidthFactor, isNot(1.0));
    expect(snap.pressureSource, s.pressureSource);
    expect(snap.inputHz, greaterThan(0));
    s.cancel();
    c.diagnostics.enabled = false;
  });
}
