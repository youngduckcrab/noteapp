// m5-7/03-ink 8.2 T39 (6.18, review S-8): the hold of automatic shape correction.
// - within shapeHoldRadiusPx (8 logical px) for shapeHoldMs (500): one fire — by
//   the sample times, or by the timer when no sample comes; 499 ms → none;
// - leaving the radius moves the anchor (the hold starts again from that sample and
//   that moment) and, after a fire, is 'moving again'; holding again fires again
//   (the detector alone — (C212-01) a StrokeSession stops it once a fit shows);
// - viewScale 2 → the radius in page pt is halved;
// - the clock rule: sample times are compared with sample times only and the timer
//   measures its own elapsed time — event times far from (or behind) the InkClock
//   give the same result, through the detector and through a StrokeSession.
import 'dart:ui' as ui;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/render/sessions.dart'
    show strokeSessionHoldOf, strokeSessionPreviewShape;
import 'package:ink_engine/src/shape/hold_detector.dart';
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

const _ms = 1000; // µs

/// A recorder of the detector's callbacks.
final class _Log {
  int holds = 0;
  int moves = 0;

  /// The index of the sample during which each hold fired (-1: the timer).
  final List<int> heldAt = [];
  int sample = -1;
}

HoldDetector _detector(
  _Log log, {
  ui.Offset start = const ui.Offset(100, 100),
  int startUs = 0,
  double viewScale = 1,
}) => HoldDetector(
  start: start,
  startUs: startUs,
  viewScale: viewScale,
  onHold: () {
    log.holds++;
    log.heldAt.add(log.sample);
  },
  onMove: () => log.moves++,
);

/// Feeds [points] at [hz] from [fromUs]; [log].sample = index while each is added.
void _feed(
  HoldDetector d,
  _Log log,
  List<ui.Offset> points, {
  int fromUs = 0,
  double hz = 120,
  int firstIndex = 0,
}) {
  for (var i = 0; i < points.length; i++) {
    log.sample = firstIndex + i;
    d.add(points[i], fromUs + (i * 1e6 / hz).round());
  }
  log.sample = -1;
}

/// [n] points jittering within [r] pt of [c] (deterministic).
List<ui.Offset> _jitter(ui.Offset c, int n, double r) => [
  for (var i = 0; i < n; i++)
    c + ui.Offset(r * ((i * 7) % 11 - 5) / 5, r * ((i * 5) % 9 - 4) / 4),
];

InkSample _sample(ui.Offset p, int timeUs) => InkSample(
  position: p,
  timeUs: timeUs,
  kind: InkPointerKind.stylus,
  pressure: 0.5,
);

final _fit = InkShapeFit(
  kind: core.ShapeKind.rectangle,
  geometry: core.ShapeGeometry.rectangle(const core.PageRect(50, 50, 150, 150)),
  score: 0.9,
);

void main() {
  group('by the sample times', () {
    test('within 8 px for 500 ms → one fire; 499 ms → none', () {
      fakeAsync((async) {
        final log = _Log();
        final d = _detector(log);
        // 7.9 pt of jitter around the anchor (radius 8 pt at viewScale 1)
        final pts = _jitter(const ui.Offset(100, 100), 61, 5.5);
        for (final p in pts) {
          expect((p - const ui.Offset(100, 100)).distance, lessThan(8));
        }
        // samples 0 … 499 ms (1 ms apart), the timer never elapses
        for (var t = 1; t <= 499; t++) {
          d.add(pts[t % pts.length], t * _ms);
        }
        expect(log.holds, 0, reason: '499 ms');
        expect(d.fired, isFalse);
        d.add(pts[3], 500 * _ms);
        expect(log.holds, 1, reason: '500 ms');
        expect(d.fired, isTrue);
        // holding on: no second fire, by samples or by the timer
        for (var t = 501; t <= 3000; t += 8) {
          d.add(pts[t % pts.length], t * _ms);
        }
        async.elapse(const Duration(seconds: 5));
        expect(log.holds, 1);
        expect(log.moves, 0);
        d.stop();
      });
    });

    test('the radius is inclusive: exactly 8 pt away stays, beyond moves the '
        'anchor (the hold restarts at that sample)', () {
      fakeAsync((async) {
        final log = _Log();
        final d = _detector(log);
        d.add(const ui.Offset(108, 100), 300 * _ms);
        expect(d.anchor, const ui.Offset(100, 100));
        d.add(const ui.Offset(108.01, 100), 400 * _ms);
        expect(d.anchor, const ui.Offset(108.01, 100));
        expect(d.anchorUs, 400 * _ms);
        d.add(const ui.Offset(108.01, 100), 899 * _ms);
        expect(log.holds, 0, reason: '499 ms after the new anchor');
        d.add(const ui.Offset(108.01, 100), 900 * _ms);
        expect(log.holds, 1);
        d.stop();
      });
    });

    test('moving out of the radius after a fire → onMove (cancel); holding '
        'again → fires again', () {
      fakeAsync((async) {
        final log = _Log();
        final d = _detector(log);
        _feed(d, log, List.filled(70, const ui.Offset(100, 100)));
        expect(log.holds, 1);
        expect(log.heldAt.single, 60, reason: 'the sample at 500 ms (120 Hz)');
        // within the radius: still held
        d.add(const ui.Offset(106, 103), 700 * _ms);
        expect(log.moves, 0);
        // out: moving again
        d.add(const ui.Offset(130, 100), 710 * _ms);
        expect(log.moves, 1);
        expect(d.fired, isFalse);
        // a drawn line (each sample > 8 pt from the last anchor): no fire, no move
        for (var i = 1; i <= 40; i++) {
          d.add(ui.Offset(130 + 9.0 * i, 100), (710 + 8 * i) * _ms);
        }
        expect((log.holds, log.moves), (1, 1));
        // hold at the end: fires again 500 ms after the last anchor sample
        final lastUs = (710 + 8 * 40) * _ms;
        d.add(const ui.Offset(490, 101), lastUs + 499 * _ms);
        expect(log.holds, 1);
        d.add(const ui.Offset(489, 99), lastUs + 500 * _ms);
        expect(log.holds, 2);
        expect(log.moves, 1);
        d.stop();
      });
    });

    test('moving out before any fire is not onMove', () {
      fakeAsync((async) {
        final log = _Log();
        final d = _detector(log);
        for (var i = 1; i <= 30; i++) {
          d.add(ui.Offset(100 + 10.0 * i, 100), i * 10 * _ms);
        }
        expect((log.holds, log.moves), (0, 0));
        d.stop();
      });
    });

    test('a slow drift: the anchor follows once the drift leaves the radius, '
        'so drawing slowly never fires', () {
      fakeAsync((async) {
        final log = _Log();
        final d = _detector(log);
        // 1 pt per 50 ms: 8 pt in 400 ms < 500 ms
        for (var i = 1; i <= 200; i++) {
          d.add(ui.Offset(100 + i * 1.0, 100), i * 50 * _ms);
        }
        expect(log.holds, 0);
        d.stop();
      });
    });

    test('a time going backwards counts as the previous one; a non-finite '
        'position is ignored', () {
      fakeAsync((async) {
        final log = _Log();
        final d = _detector(log, startUs: 1000 * _ms);
        d.add(const ui.Offset(101, 100), 1300 * _ms);
        d.add(const ui.Offset(101, 100), 200 * _ms); // backwards → 1300 ms
        expect(log.holds, 0);
        d.add(const ui.Offset(double.nan, 0), 5000 * _ms);
        d.add(const ui.Offset(double.infinity, 0), 5000 * _ms);
        expect(d.anchor, const ui.Offset(100, 100));
        expect(log.holds, 0);
        d.add(const ui.Offset(100, 101), 1500 * _ms);
        expect(log.holds, 1);
        d.stop();
      });
    });
  });

  group('by the timer (no samples)', () {
    test('the pen held still sends nothing: the timer fires at 500 ms, not at '
        '499 ms', () {
      fakeAsync((async) {
        final log = _Log();
        final d = _detector(log);
        expect(d.timerArmed, isTrue);
        async.elapse(const Duration(milliseconds: 499));
        expect(log.holds, 0);
        async.elapse(const Duration(milliseconds: 1));
        expect(log.holds, 1);
        expect(log.heldAt.single, -1, reason: 'from the timer');
        expect(d.timerArmed, isFalse);
        async.elapse(const Duration(seconds: 10));
        expect(log.holds, 1);
        d.stop();
      });
    });

    test('every anchor change re-arms it: 500 ms after the last move', () {
      fakeAsync((async) {
        final log = _Log();
        final d = _detector(log);
        async.elapse(const Duration(milliseconds: 300));
        d.add(const ui.Offset(120, 100), 300 * _ms); // moved: re-armed
        async.elapse(const Duration(milliseconds: 499));
        expect(log.holds, 0);
        // samples within the radius do not re-arm it
        d.add(const ui.Offset(121, 100), 790 * _ms);
        async.elapse(const Duration(milliseconds: 1));
        expect(log.holds, 1);
        // moving again after the fire → onMove, re-armed → fires again
        d.add(const ui.Offset(160, 100), 900 * _ms);
        expect(log.moves, 1);
        expect(d.timerArmed, isTrue);
        async.elapse(const Duration(milliseconds: 500));
        expect(log.holds, 2);
        d.stop();
      });
    });

    test('an anchor move on every sample (a fast line): one pending timer at '
        'any time, due 500 ms after the last move', () {
      // B20's worst case — the new timer is made before the old one is
      // cancelled (review 2.1): never two pending, never none while armed.
      fakeAsync((async) {
        final log = _Log();
        final d = _detector(log, start: const ui.Offset(0, 100));
        for (var i = 1; i <= 200; i++) {
          async.elapse(const Duration(milliseconds: 4));
          log.sample = i;
          d.add(ui.Offset(9.0 * i, 100), i * 4 * _ms);
          expect(async.pendingTimers, hasLength(1), reason: 'sample $i');
          expect(d.timerArmed, isTrue);
        }
        log.sample = -1;
        expect(log.holds, 0);
        // the last move at 800 ms: no fire at 1299 ms, the timer's at 1300 ms
        async.elapse(const Duration(milliseconds: 499));
        expect(log.holds, 0);
        async.elapse(const Duration(milliseconds: 1));
        expect(log.holds, 1);
        expect(log.heldAt.single, -1, reason: 'from the timer');
        expect(async.pendingTimers, isEmpty);
        d.stop();
      });
    });

    test('stop() cancels the timer and nothing fires any more', () {
      fakeAsync((async) {
        final log = _Log();
        final d = _detector(log);
        async.elapse(const Duration(milliseconds: 200));
        d.stop();
        expect(d.timerArmed, isFalse);
        expect(async.pendingTimers, isEmpty);
        async.elapse(const Duration(seconds: 2));
        d.add(const ui.Offset(100, 100), 900 * _ms);
        expect(log.holds, 0);
      });
    });
  });

  test('viewScale 2 → the radius is 4 pt; 0.5 → 16 pt', () {
    fakeAsync((async) {
      for (final (scale, inside, outside) in [
        (2.0, 3.99, 4.01),
        (1.0, 7.99, 8.01),
        (0.5, 15.99, 16.01),
      ]) {
        final log = _Log();
        final d = _detector(log, viewScale: scale);
        d.add(ui.Offset(100 + inside, 100), 100 * _ms);
        expect(d.anchor, const ui.Offset(100, 100), reason: '$scale inside');
        d.add(ui.Offset(100 - outside, 100), 200 * _ms);
        expect(
          d.anchor,
          ui.Offset(100 - outside, 100),
          reason: '$scale outside',
        );
        d.stop();
      }
    });
  });

  group('S-8: event times and the InkClock never mix', () {
    test('the detector: event times shifted by 11 days or negative give the '
        'same fires', () {
      List<int> run(int offsetUs) {
        late List<int> fires;
        fakeAsync((async) {
          final log = _Log();
          final d = _detector(log, startUs: offsetUs);
          final pts = [
            ...List.filled(70, const ui.Offset(100, 100)),
            for (var i = 1; i <= 20; i++) ui.Offset(100 + 9.0 * i, 100),
            ...List.filled(70, const ui.Offset(280, 100)),
          ];
          _feed(d, log, pts, fromUs: offsetUs);
          fires = [...log.heldAt, log.moves];
          d.stop();
        });
        return fires;
      }

      final aligned = run(0);
      // the last line sample (index 89) is the anchor of the second hold
      expect(aligned, [60, 149, 1]);
      expect(run(11 * 24 * 3600 * 1000000), aligned);
      expect(run(-5000000000), aligned);
      expect(run(123456789), aligned);
    });

    test('through a StrokeSession: an InkClock far from the event times '
        '(native) gives the same preview sample', () {
      int? previewAt(FakeInkClock clock, int eventOffsetUs) {
        int? at;
        fakeAsync((async) {
          final fitter = FakeInkShapeFitter(fit: _fit);
          final c = createTestPageController(clock: clock, shapeFitter: fitter)
            ..updateContent(SyntheticInk.pageContent());
          final samples = SyntheticInk.loopThenHold(
            bounds: const ui.Rect.fromLTRB(50, 50, 150, 150),
          );
          InkSample shifted(InkSample s) =>
              s.copyWith(timeUs: s.timeUs + eventOffsetUs);
          final session = c.beginStroke(
            shifted(samples.first),
            style: core.StrokeStyle.defaultsFor(core.PenTool.ballpoint),
            viewScale: 1,
            shapeAssist: ShapeAssist.holdToSnap,
          );
          for (var i = 1; i < samples.length; i++) {
            clock.advanceMs(3); // the InkClock runs at its own pace
            session.addSample(shifted(samples[i]));
            if (at == null && session.shapePreview.value != null) at = i;
          }
          expect(fitter.calls, 1);
          session.cancel();
          c.dispose();
        });
        return at;
      }

      final aligned = previewAt(FakeInkClock(), 0);
      expect(aligned, isNotNull);
      expect(
        previewAt(
          FakeInkClock(
            startUs: 11 * 24 * 3600 * 1000000,
            alignedWithEventTimestamps: false,
          ),
          0,
        ),
        aligned,
      );
      expect(
        previewAt(
          FakeInkClock(startUs: 0, alignedWithEventTimestamps: false),
          -7000000000,
        ),
        aligned,
      );
    });
  });

  group('the StrokeSession', () {
    test('holdToSnap with a fitter: a detector from the pen-down sample; '
        'off / no assist tools: none', () {
      fakeAsync((async) {
        final c = createTestPageController(
          shapeFitter: FakeInkShapeFitter(fit: _fit),
        )..updateContent(SyntheticInk.pageContent());
        final on = c.beginStroke(
          _sample(const ui.Offset(30, 40), 777),
          style: core.StrokeStyle.defaultsFor(core.PenTool.pencil),
          viewScale: 2,
          shapeAssist: ShapeAssist.holdToSnap,
        );
        final hold = strokeSessionHoldOf(on)!;
        expect((hold.anchor, hold.anchorUs), (const ui.Offset(30, 40), 777));
        // viewScale 2: 4 pt
        on.addSample(_sample(const ui.Offset(34.1, 40), 1000));
        expect(hold.anchor, const ui.Offset(34.1, 40));
        on.cancel();
        expect(hold.timerArmed, isFalse);
        final off = c.beginStroke(
          _sample(const ui.Offset(30, 40), 0),
          style: core.StrokeStyle.defaultsFor(core.PenTool.pencil),
          viewScale: 1,
        );
        expect(strokeSessionHoldOf(off), isNull);
        off.cancel();
        for (final tool in [
          core.PenTool.highlighter,
          core.PenTool.laser,
          core.PenTool.tape,
        ]) {
          final s = c.beginStroke(
            _sample(const ui.Offset(30, 40), 0),
            style: core.StrokeStyle.defaultsFor(tool),
            viewScale: 1,
            shapeAssist: ShapeAssist.holdToSnap,
          );
          expect(strokeSessionHoldOf(s), isNull, reason: tool.name);
          s.cancel();
        }
        c.dispose();
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('no samples after the loop: the timer fires the hold, the fitter '
        'gets the centerline so far, the preview is set and notified', () {
      fakeAsync((async) {
        final fitter = FakeInkShapeFitter(fit: _fit);
        final c = createTestPageController(shapeFitter: fitter)
          ..updateContent(SyntheticInk.pageContent());
        var inkActive = 0;
        c.layerRepaint(InkRenderLayer.inkActive).addListener(() => inkActive++);
        final loop = SyntheticInk.loopThenHold(
          bounds: const ui.Rect.fromLTRB(50, 50, 150, 150),
          holdMs: 0,
        );
        final session = c.beginStroke(
          loop.first,
          style: core.StrokeStyle.defaultsFor(core.PenTool.ballpoint),
          viewScale: 1,
          shapeAssist: ShapeAssist.holdToSnap,
        )..addSamples(loop.skip(1));
        final notified = <InkShapeFit?>[];
        session.shapePreview.addListener(
          () => notified.add(session.shapePreview.value),
        );
        expect(fitter.calls, 0);
        async.elapse(const Duration(milliseconds: 499));
        expect(fitter.calls, 0);
        final before = inkActive;
        async.elapse(const Duration(milliseconds: 1));
        expect(fitter.calls, 1);
        expect(session.shapePreview.value, _fit);
        expect(notified, [_fit]);
        expect(inkActive, greaterThan(before), reason: 'layer 4′ repainted');
        expect(strokeSessionPreviewShape(session)?.shapeKind, _fit.kind);
        // the centerline so far: the stable points + the raw tail, page pt
        final got = fitter.received.single;
        expect(got.length, greaterThanOrEqualTo(loop.length - 2));
        expect(got.first.dx, closeTo(loop.first.position.dx, 1));
        expect(got.first.dy, closeTo(loop.first.position.dy, 1));
        expect(got.last, loop.last.position);
        // (C212-01) moving again no longer drops the preview: the detector
        // stopped at the fit and the move drags the shape (notified again)
        expect(strokeSessionHoldOf(session)!.timerArmed, isFalse);
        session.addSample(_sample(const ui.Offset(200, 200), 2000000));
        expect(session.shapePreview.value, isNotNull);
        expect(session.shapePreview.value!.kind, _fit.kind);
        expect(notified, hasLength(2));
        expect(strokeSessionPreviewShape(session), isNotNull);
        // no new hold however long the pen stays
        async.elapse(const Duration(seconds: 2));
        expect(fitter.calls, 1);
        session.cancel();
        c.dispose();
        expect(async.pendingTimers, isEmpty);
      });
    });
  });
}
