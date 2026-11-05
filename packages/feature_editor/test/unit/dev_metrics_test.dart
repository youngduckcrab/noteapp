// E-19: DevMetrics (04-editor 6.12.1, EDITOR-M10) — EDITOR-only values
// (pointers, palm rejections, input mode, viewport, page strokes), collected
// only while running, published at most 4 times a second (fake_async).
import 'package:fake_async/fake_async.dart';
import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/ui/dev/dev_metrics.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

PointerDownEvent _down(PointerDeviceKind kind) =>
    PointerDownEvent(kind: kind, position: const Offset(10, 10));

void main() {
  test('not running: nothing is recorded or published', () {
    fakeAsync((async) {
      final m = DevMetrics();
      var notified = 0;
      m.addListener(() => notified++);
      m
        ..recordPalmRejected()
        ..recordPointer(
          _down(PointerDeviceKind.stylus),
          drawing: true,
          activePointers: 1,
        )
        ..recordStrokeCommitted(pointCount: 9)
        ..recordPage(strokes: 3)
        ..recordInputMode('penOnly');
      async.elapse(const Duration(seconds: 1));
      expect(notified, 0);
      expect(m.isRunning, isFalse);
      expect(m.snapshot, DevMetricsSnapshot.empty);
      m.dispose();
    });
  });

  test('running: the last values, published ≤ 4 Hz', () {
    fakeAsync((async) {
      final m = DevMetrics()..start();
      var notified = 0;
      m.addListener(() => notified++);
      // 100 changes over one second (every 10 ms).
      for (var i = 0; i < 100; i++) {
        m.recordPointer(
          _down(i.isEven ? PointerDeviceKind.touch : PointerDeviceKind.stylus),
          drawing: true,
          activePointers: 2,
        );
        if (i % 10 == 0) m.recordPalmRejected();
        async.elapse(const Duration(milliseconds: 10));
      }
      m
        ..recordStrokeCommitted(pointCount: 182)
        ..recordPage(strokes: 1204)
        ..recordInputMode('penOnly (auto)');
      async.elapse(const Duration(milliseconds: 250));
      expect(notified, lessThanOrEqualTo(5)); // 1.25 s
      expect(notified, greaterThanOrEqualTo(4));
      final s = m.snapshot;
      expect(s.lastKind, PointerDeviceKind.stylus);
      expect(s.activePointers, 2);
      expect(s.palmRejectedCount, 10);
      expect(s.lastStrokePoints, 182);
      expect(s.currentPageStrokes, 1204);
      expect(s.inputModeLabel, 'penOnly (auto)');

      // Nothing changed → no publish.
      final before = notified;
      async.elapse(const Duration(seconds: 2));
      expect(notified, before);

      // reset() zeroes the counters.
      m.reset();
      async.elapse(const Duration(milliseconds: 250));
      expect(m.snapshot.palmRejectedCount, 0);
      expect(m.snapshot.lastStrokePoints, 0);
      expect(m.snapshot.lastKind, isNull);

      // stop(): a pending publish is dropped, later records ignored.
      m
        ..recordPalmRejected()
        ..stop()
        ..recordPalmRejected();
      final stopped = notified;
      async.elapse(const Duration(seconds: 1));
      expect(notified, stopped);
      expect(m.snapshot.palmRejectedCount, 0);
      m.dispose();
    });
  });

  test('labels: input mode (auto shows what it does now) and page ranges', () {
    const auto = EditorSettings();
    expect(inputModeLabelOf(auto), endsWith('(auto)'));
    expect(
      inputModeLabelOf(auto),
      auto.isPenOnlyEffective ? 'penOnly (auto)' : 'fingerDrawing (auto)',
    );
    expect(
      inputModeLabelOf(const EditorSettings(inputMode: InputMode.penOnly)),
      'penOnly',
    );
    expect(
      inputModeLabelOf(
        const EditorSettings(inputMode: InputMode.fingerDrawing),
      ),
      'fingerDrawing',
    );
    expect(pageRangeLabel(null), '-');
    expect(pageRangeLabel((first: 2, last: 2)), '3');
    expect(pageRangeLabel((first: 1, last: 4)), '2–5');
  });
}
