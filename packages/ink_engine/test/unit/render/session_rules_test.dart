// T10 (03-ink 8, 4.8 sessions): one active session per controller — starting
// a new one cancels the previous; a cancelled or ended session throws
// StateError on further input; cancel leaves no edit, no pending display and
// no live geometry.
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

import '../../support/pixels.dart';

const _sample = InkSample(
  position: ui.Offset(50, 50),
  timeUs: 0,
  kind: InkPointerKind.stylus,
  pressure: 0.5,
);

InkSample _at(double x, double y, int i) => InkSample(
  position: ui.Offset(x, y),
  timeUs: i * 8333,
  kind: InkPointerKind.stylus,
  pressure: 0.5,
);

void main() {
  late InkPageController c;
  var notified = 0;

  setUp(() {
    notified = 0;
    c = createTestPageController()
      ..updateContent(
        SyntheticInk.pageContent(
          strokes: [
            strokeThrough(
              segment(const ui.Offset(20, 50), const ui.Offset(120, 50)),
              core.StrokeStyle.defaultsFor(core.PenTool.ballpoint),
              id: 'a',
            ),
          ],
        ),
      )
      ..addListener(() => notified++);
  });
  tearDown(() => c.dispose());

  StrokeSession pen() => c.beginStroke(
    _sample,
    style: core.StrokeStyle.defaultsFor(core.PenTool.ballpoint),
    viewScale: 1,
  );
  EraserSession eraser() => c.beginErase(
    _sample,
    spec: const EraserSpec(mode: EraserMode.stroke, radius: 4),
    viewScale: 1,
  );
  LassoSession lasso() => c.beginLasso(_sample.position, viewScale: 1);

  final starts = <String, InkGestureSession Function()>{
    'stroke': pen,
    'eraser': eraser,
    'lasso': lasso,
  };

  group('a new session cancels the previous one', () {
    for (final first in starts.entries) {
      for (final second in starts.entries) {
        test('${first.key} → ${second.key}', () {
          final s1 = first.value();
          expect(c.activeSession, same(s1));
          final s2 = second.value();
          expect(s1.isActive, isFalse);
          expect(s2.isActive, isTrue);
          expect(c.activeSession, same(s2));
          expect(c.pendingIds, isEmpty, reason: 'the cancelled one: no edit');
        });
      }
    }
  });

  group('after cancel every input throws StateError', () {
    test('stroke', () {
      final s = pen()..addSample(_at(60, 55, 1));
      s.cancel();
      expect(s.isActive, isFalse);
      expect(s.live.isEmpty, isTrue, reason: 'live geometry cleared');
      expect(() => s.addSample(_at(70, 60, 2)), throwsStateError);
      expect(() => s.addSamples([_at(70, 60, 2)]), throwsStateError);
      expect(s.end, throwsStateError);
      expect(c.activeSession, isNull);
      expect(c.pendingIds, isEmpty);
    });

    test('eraser', () {
      final s = eraser()..addSample(_at(60, 50, 1));
      expect(s.touchedStrokeIds, {'a'});
      s.cancel();
      expect(s.touchedStrokeIds, isEmpty, reason: 'preview removed');
      expect(() => s.addSample(_at(70, 50, 2)), throwsStateError);
      expect(s.end, throwsStateError);
      expect(c.pendingIds, isEmpty);
      expect(c.hitTest(const ui.Offset(60, 50))?.id, 'a');
    });

    test('lasso', () {
      final s = lasso()..addPoint(const ui.Offset(150, 50));
      s.cancel();
      expect(() => s.addPoint(const ui.Offset(150, 150)), throwsStateError);
      expect(s.end, throwsStateError);
      expect(c.selection, isNull);
    });

    test('cancel twice is a no-op; cancel after end too', () {
      final s = pen();
      s.cancel();
      s.cancel();
      final e = eraser();
      e.end();
      e.cancel();
      expect(e.isActive, isFalse);
    });
  });

  group('after end', () {
    test('stroke: end once, then StateError; the edit stays pending', () {
      final s = pen()..addSamples([_at(80, 60, 1), _at(120, 70, 2)]);
      final edit = s.end(_at(130, 72, 3))!;
      expect(c.activeSession, isNull);
      expect(c.pendingIds, {edit.added.single.id});
      expect(() => s.addSample(_at(140, 75, 4)), throwsStateError);
      expect(s.end, throwsStateError);
      s.cancel(); // no effect on the pending edit
      expect(c.pendingIds, {edit.added.single.id});
    });

    test('a new session does not drop pending edits of ended ones', () {
      final s1 = pen()..addSample(_at(120, 70, 1));
      final edit = s1.end()!;
      final s2 = pen()..addSample(_at(200, 90, 1));
      expect(c.pendingIds, {edit.added.single.id});
      s2.cancel();
      expect(c.pendingIds, {edit.added.single.id});
    });
  });

  test('session start and end notify the controller listeners', () {
    final s = pen();
    expect(notified, 1);
    s.addSample(_at(60, 55, 1));
    expect(notified, 1, reason: 'samples repaint layers only');
    s.end();
    expect(notified, 2);
  });

  test('a disposed controller refuses new sessions', () {
    final other = createTestPageController()
      ..updateContent(SyntheticInk.pageContent());
    final s = other.beginStroke(
      _sample,
      style: core.StrokeStyle.defaultsFor(core.PenTool.pencil),
      viewScale: 1,
    );
    other.dispose();
    expect(s.isActive, isFalse, reason: 'dispose cancels the active one');
    expect(
      () => other.beginLasso(ui.Offset.zero, viewScale: 1),
      throwsStateError,
    );
  });

  test('viewScale must be > 0 and finite', () {
    for (final v in [0.0, -1.0, double.nan, double.infinity]) {
      expect(
        () => c.beginStroke(
          _sample,
          style: core.StrokeStyle.defaultsFor(core.PenTool.ballpoint),
          viewScale: v,
        ),
        throwsArgumentError,
        reason: '$v',
      );
    }
  });
}
