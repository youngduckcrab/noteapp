// E-05: InputRouter (04-editor 6.5) — the router scenarios R1..R33 of 6.5.6,
// plus cancelAll / counters / trackpad. Events go straight to
// router.handlePointerEvent with synthetic timestamps; testWidgets' fake time
// (tester.pump) drives the long-press Timer and VelocityTracker's clock.
// RecordingInputTargets (E-01) records every router → editor call.
import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/input/input_router.dart';
import 'package:feature_editor/src/input/input_targets.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_editor.dart';
import '../helpers/recording_input_targets.dart';

const _frame = Duration(milliseconds: 16);
const _stylus = PointerDeviceKind.stylus;
const _mouse = PointerDeviceKind.mouse;

/// Synthetic pointer input with its own clock (kept in step with fake time).
final class _Input {
  _Input(this.tester, this.router);
  final WidgetTester tester;
  final InputRouter router;
  Duration now = const Duration(seconds: 10);
  int _nextPointer = 1;
  final Map<
    int,
    ({int pointer, PointerDeviceKind kind, Offset at, int buttons})
  >
  _down = {};

  Future<void> wait(Duration d) async {
    now += d;
    await tester.pump(d);
  }

  void down(
    int id,
    Offset at, {
    PointerDeviceKind kind = PointerDeviceKind.touch,
    double radiusMajor = 0,
    int buttons = kPrimaryButton,
  }) {
    final pointer = _nextPointer++;
    _down[id] = (pointer: pointer, kind: kind, at: at, buttons: buttons);
    router.handlePointerEvent(
      PointerDownEvent(
        timeStamp: now,
        pointer: pointer,
        device: id,
        kind: kind,
        position: at,
        buttons: buttons,
        radiusMajor: radiusMajor,
      ),
    );
  }

  void move(int id, Offset to) {
    final p = _down[id]!;
    _down[id] = (pointer: p.pointer, kind: p.kind, at: to, buttons: p.buttons);
    router.handlePointerEvent(
      PointerMoveEvent(
        timeStamp: now,
        pointer: p.pointer,
        device: id,
        kind: p.kind,
        position: to,
        delta: to - p.at,
        buttons: p.buttons,
      ),
    );
  }

  /// [steps] moves of [by] / steps, one frame apart.
  Future<void> drag(int id, Offset by, {int steps = 10}) async {
    final from = _down[id]!.at;
    for (var i = 1; i <= steps; i++) {
      await wait(_frame);
      move(id, from + by * (i / steps));
    }
  }

  void up(int id) {
    final p = _down.remove(id)!;
    router.handlePointerEvent(
      PointerUpEvent(
        timeStamp: now,
        pointer: p.pointer,
        device: id,
        kind: p.kind,
        position: p.at,
      ),
    );
  }

  void cancel(int id) {
    final p = _down.remove(id)!;
    router.handlePointerEvent(
      PointerCancelEvent(
        timeStamp: now,
        pointer: p.pointer,
        device: id,
        kind: p.kind,
        position: p.at,
      ),
    );
  }

  void hover(Offset at, {PointerDeviceKind kind = _stylus}) =>
      router.handlePointerEvent(
        PointerHoverEvent(timeStamp: now, kind: kind, position: at, device: 90),
      );

  void wheel(Offset delta, {Offset at = const Offset(300, 300)}) =>
      router.handlePointerEvent(
        PointerScrollEvent(
          timeStamp: now,
          kind: _mouse,
          position: at,
          scrollDelta: delta,
        ),
      );

  /// A full pen (or mouse) stroke: down, [moves] moves, up.
  Future<void> penStroke(
    Offset from, {
    int moves = 10,
    PointerDeviceKind kind = _stylus,
    int id = 100,
  }) async {
    down(id, from, kind: kind);
    await drag(id, const Offset(60, 20), steps: moves);
    up(id);
  }
}

typedef _Body = Future<void> Function(
  _Input input,
  RecordingInputTargets targets,
);

final _penOnly = testInputPolicy(penOnly: true, stylusSeen: true);
final _fingerDrawing = testInputPolicy();
final _autoUnseen = testInputPolicy();

final Map<String, InputPolicy> _allModes = {
  'penOnly': _penOnly,
  'fingerDrawing': _fingerDrawing,
};

void _routerTest(String description, InputPolicy policy, _Body body) {
  testWidgets(description, (tester) async {
    final targets = RecordingInputTargets(policy: policy);
    final router = InputRouter(targets: targets);
    try {
      await body(_Input(tester, router), targets);
    } finally {
      router.cancelAll(); // no timer left for the testWidgets check
    }
  });
}

/// The same scenario in every input mode.
void _allModesTest(String description, _Body body) {
  for (final MapEntry(key: mode, value: policy) in _allModes.entries) {
    _routerTest('$description [$mode]', policy, body);
  }
}

List<String> _navigationCalls(RecordingInputTargets t) =>
    t.callsStartingWith('navigation');

void main() {
  const a = 1, b = 2, c = 3;
  const p0 = Offset(400, 500);

  _allModesTest('R1 pen down → move ×10 → up: one interaction, no '
      'navigation', (input, t) async {
    await input.penStroke(p0);
    expect(t.interactions, hasLength(1));
    final i = t.interactions.single;
    expect(i.source, InteractionSource.stylus);
    expect(i.moves, hasLength(10));
    expect(i.endCount, 1);
    expect(i.cancelCount, 0);
    expect(_navigationCalls(t), isEmpty);
    expect(t.callsStartingWith('tap'), isEmpty);
  });

  _routerTest(
    'R2 penOnly: a 30 px finger drag starts navigation after 18 px',
    _penOnly,
    (input, t) async {
      input.down(a, p0);
      for (var px = 3; px <= 30; px += 3) {
        await input.wait(_frame);
        input.move(a, p0 + Offset(0, px.toDouble()));
        expect(
          t.calls.contains('navigationStart'),
          px > 18,
          reason: 'after $px px',
        );
      }
      input.up(a);
      expect(t.callsStartingWith('navigationStart'), hasLength(1));
      expect(t.calls.last, 'navigationEnd');
      expect(t.callsStartingWith('begin'), isEmpty);
      expect(t.callsStartingWith('tap'), isEmpty);
    },
  );

  _routerTest(
    'R3 penOnly: 5 px, up after 150 ms → tap(1), no navigation',
    _penOnly,
    (input, t) async {
      input.down(a, p0);
      await input.wait(const Duration(milliseconds: 75));
      input.move(a, p0 + const Offset(5, 0));
      await input.wait(const Duration(milliseconds: 75));
      input.up(a);
      expect(t.calls, ['tap(1)']);
    },
  );

  for (final (name, policy) in [
    ('R4 fingerDrawing', _fingerDrawing),
    ('R5 auto, no stylus seen', _autoUnseen),
  ]) {
    _routerTest('$name: a finger drag draws (one finger interaction)', policy, (
      input,
      t,
    ) async {
      input.down(a, p0);
      await input.drag(a, const Offset(80, 40));
      input.up(a);
      expect(t.calls, ['begin(finger)']);
      final i = t.interactions.single;
      expect(i.source, InteractionSource.finger);
      expect(i.moves, hasLength(10));
      expect(i.endCount, 1);
    });
  }

  _routerTest(
    'R6 auto: after a pen stroke and the cooldown, a finger '
    'navigates',
    _autoUnseen,
    (input, t) async {
      t.onStylusDetected = () =>
          t.policy = testInputPolicy(penOnly: true, stylusSeen: true);
      await input.penStroke(p0);
      await input.penStroke(p0 + const Offset(0, 100));
      expect(t.callsStartingWith('stylusDetected'), hasLength(1));
      await input.wait(const Duration(milliseconds: 450));
      input.down(a, p0);
      await input.drag(a, const Offset(0, 60));
      input.up(a);
      expect(t.callsStartingWith('begin(finger)'), isEmpty);
      expect(t.calls, contains('navigationStart'));
      expect(t.callsStartingWith('palmRejected'), isEmpty);
    },
  );

  _allModesTest('R7 two fingers down together, 5 px, up after 120 ms → '
      'tap(2) once', (input, t) async {
    input
      ..down(a, p0)
      ..down(b, p0 + const Offset(80, 0));
    await input.wait(const Duration(milliseconds: 60));
    input
      ..move(a, p0 + const Offset(5, 0))
      ..move(b, p0 + const Offset(85, 0));
    await input.wait(const Duration(milliseconds: 60));
    input
      ..up(a)
      ..up(b);
    expect(t.callsStartingWith('tap'), ['tap(2)']);
    expect(_navigationCalls(t), isEmpty);
    for (final i in t.interactions) {
      expect(i.endCount, 0, reason: 'a started finger stroke is discarded');
    }
  });

  _allModesTest('R8 three-finger tap → tap(3) once', (input, t) async {
    input
      ..down(a, p0)
      ..down(b, p0 + const Offset(60, 0))
      ..down(c, p0 + const Offset(120, 0));
    await input.wait(const Duration(milliseconds: 100));
    input
      ..up(a)
      ..up(b)
      ..up(c);
    expect(t.callsStartingWith('tap'), ['tap(3)']);
  });

  _routerTest(
    'R9 penOnly: two fingers spread 40 px → navigation, '
    'scaleRatio > 1, no tap',
    _penOnly,
    (input, t) async {
      input
        ..down(a, p0)
        ..down(b, p0 + const Offset(40, 0));
      for (var i = 1; i <= 10; i++) {
        await input.wait(_frame);
        input
          ..move(a, p0 - Offset(2.0 * i, 0))
          ..move(b, p0 + Offset(40 + 2.0 * i, 0));
      }
      input
        ..up(a)
        ..up(b);
      expect(t.calls.first, 'navigationStart');
      expect(t.navigationUpdates, isNotEmpty);
      final pinch = t.navigationUpdates.where((u) => !u.rebased);
      expect(pinch.last.scaleRatio, greaterThan(1));
      expect(t.callsStartingWith('tap'), isEmpty);
    },
  );

  _allModesTest('R10 two fingers held 400 ms → no tap', (input, t) async {
    input
      ..down(a, p0)
      ..down(b, p0 + const Offset(80, 0));
    await input.wait(const Duration(milliseconds: 400));
    input
      ..up(a)
      ..up(b);
    expect(t.callsStartingWith('tap'), isEmpty);
  });

  _routerTest(
    'R11 fingerDrawing: B 100 ms after A → A cancelled, no commit, '
    'navigation [A, B]',
    _fingerDrawing,
    (input, t) async {
      input.down(a, p0);
      await input.drag(a, const Offset(30, 0), steps: 6); // ~100 ms
      input.down(b, p0 + const Offset(100, 100));
      final first = t.interactions.single;
      expect(first.cancelCount, 1);
      expect(first.endCount, 0);
      // Both fingers move together: one navigation of two pointers.
      for (var i = 1; i <= 6; i++) {
        await input.wait(_frame);
        input
          ..move(a, p0 + Offset(30, 10.0 * i))
          ..move(b, p0 + Offset(100, 100 + 10.0 * i));
      }
      input
        ..up(a)
        ..up(b);
      expect(t.calls, contains('navigationStart'));
      expect(t.callsStartingWith('begin'), hasLength(1));
      expect(first.endCount, 0, reason: 'nothing committed');
    },
  );

  _routerTest(
    'R12 fingerDrawing: B after A drew 400 ms / 50 px → B rejected, '
    'A continues',
    _fingerDrawing,
    (input, t) async {
      input.down(a, p0);
      for (var i = 1; i <= 25; i++) {
        await input.wait(_frame);
        input.move(a, p0 + Offset(2.0 * i, 0));
      }
      input.down(b, p0 + const Offset(0, 200));
      await input.drag(b, const Offset(0, 80));
      await input.drag(a, const Offset(20, 0), steps: 4);
      input
        ..up(b)
        ..up(a);
      final i = t.interactions.single;
      expect(i.cancelCount, 0);
      expect(i.moves, hasLength(29));
      expect(i.endCount, 1);
      expect(_navigationCalls(t), isEmpty);
      expect(t.callsStartingWith('tap'), isEmpty);
    },
  );

  _routerTest(
    'R13 fingerDrawing: A·B two-finger tap 100 ms apart → A '
    'cancelled, tap(2)',
    _fingerDrawing,
    (input, t) async {
      input.down(a, p0);
      await input.wait(const Duration(milliseconds: 100));
      input.down(b, p0 + const Offset(70, 0));
      await input.wait(const Duration(milliseconds: 50));
      input
        ..up(a)
        ..up(b);
      expect(t.interactions.single.cancelCount, 1);
      expect(t.interactions.single.endCount, 0);
      expect(t.callsStartingWith('tap'), ['tap(2)']);
    },
  );

  _allModesTest('R14 a finger while the pen is down → rejected, palmRejected '
      'once', (input, t) async {
    input.down(100, p0, kind: _stylus);
    await input.drag(100, const Offset(20, 0), steps: 2);
    input.down(a, p0 + const Offset(200, 300));
    await input.drag(a, const Offset(0, 80));
    input.up(a);
    await input.drag(100, const Offset(20, 0), steps: 2);
    input.up(100);
    expect(t.callsStartingWith('palmRejected'), hasLength(1));
    expect(t.callsStartingWith('begin'), ['begin(stylus)']);
    expect(_navigationCalls(t), isEmpty);
    expect(t.callsStartingWith('tap'), isEmpty);
    expect(t.interactions.single.endCount, 1);
  });

  _allModesTest('R15 a finger 200 ms after pen up (cooldown 400) → rejected', (
    input,
    t,
  ) async {
    await input.penStroke(p0);
    await input.wait(const Duration(milliseconds: 200));
    input.down(a, p0);
    await input.drag(a, const Offset(0, 50));
    input.up(a);
    expect(t.callsStartingWith('palmRejected'), hasLength(1));
    expect(t.callsStartingWith('begin'), ['begin(stylus)']);
    expect(_navigationCalls(t), isEmpty);
  });

  _allModesTest('R16 a finger 600 ms after pen up → normal', (input, t) async {
    await input.penStroke(p0);
    await input.wait(const Duration(milliseconds: 600));
    input.down(a, p0);
    await input.drag(a, const Offset(0, 50));
    input.up(a);
    expect(t.callsStartingWith('palmRejected'), isEmpty);
    if (t.policy.penOnly) {
      expect(t.calls, contains('navigationStart'));
    } else {
      expect(t.callsStartingWith('begin'), ['begin(stylus)', 'begin(finger)']);
    }
  });

  _routerTest(
    'R17 penOnly: pen down while scrolling → navigationCancel, pen '
    'interaction, the finger is ignored after',
    _penOnly,
    (input, t) async {
      input.down(a, p0);
      await input.drag(a, const Offset(0, 60));
      expect(t.calls, contains('navigationStart'));
      input.down(100, p0 + const Offset(200, 0), kind: _stylus);
      expect(t.calls.sublist(t.calls.length - 2), [
        'navigationCancel',
        'begin(stylus)',
      ]);
      final updates = t.navigationUpdates.length;
      await input.drag(a, const Offset(0, 60));
      input.up(a);
      expect(t.navigationUpdates, hasLength(updates));
      expect(t.calls, isNot(contains('navigationEnd')), reason: 'no fling');
      await input.drag(100, const Offset(30, 0), steps: 3);
      input.up(100);
      expect(t.interactions.single.endCount, 1);
    },
  );

  _allModesTest('R18 a finger 100 ms after pen hover (hover rule on) → '
      'rejected', (input, t) async {
    input.hover(p0);
    expect(t.calls, ['hover(stylus)']);
    await input.wait(const Duration(milliseconds: 100));
    input.down(a, p0 + const Offset(100, 100));
    input.up(a);
    expect(t.callsStartingWith('palmRejected'), hasLength(1));
    expect(t.callsStartingWith('tap'), isEmpty);
  });

  _allModesTest('R19 the same with the hover rule off → normal', (
    input,
    t,
  ) async {
    t.policy = InputPolicy(
      penOnly: t.policy.penOnly,
      palm: const PalmRejectionSettings(treatHoverAsPenActivity: false),
      gestures: t.policy.gestures,
      stylusSeen: t.policy.stylusSeen,
      eyedropperActive: false,
    );
    input.hover(p0);
    await input.wait(const Duration(milliseconds: 100));
    input.down(a, p0 + const Offset(100, 100));
    input.up(a);
    expect(t.callsStartingWith('palmRejected'), isEmpty);
    expect(
      t.policy.penOnly
          ? t.callsStartingWith('tap')
          : t.callsStartingWith('begin'),
      hasLength(1),
    );
  });

  _allModesTest('R20 a finger with radiusMajor 60 (max 45) → rejected', (
    input,
    t,
  ) async {
    input.down(a, p0, radiusMajor: 60);
    await input.drag(a, const Offset(0, 60));
    input.up(a);
    expect(t.callsStartingWith('palmRejected'), hasLength(1));
    expect(t.calls, ['palmRejected']);
  });

  _allModesTest('R21 radiusMajor 0 → the radius rule does not apply', (
    input,
    t,
  ) async {
    input.down(a, p0);
    input.up(a);
    expect(t.callsStartingWith('palmRejected'), isEmpty);
  });

  _routerTest(
    'R22 penOnly: a finger held 600 ms → longPress once, no '
    'navigation or tap after',
    _penOnly,
    (input, t) async {
      input.down(a, p0);
      await input.wait(const Duration(milliseconds: 300));
      input.move(a, p0 + const Offset(4, 4));
      await input.wait(const Duration(milliseconds: 300));
      expect(t.calls, ['longPress']);
      await input.drag(a, const Offset(0, 120));
      input.up(a);
      expect(t.calls, ['longPress']);
    },
  );

  _routerTest(
    'R23 penOnly + lasso: a finger on the selection drags it',
    _penOnly,
    (input, t) async {
      t.selectionHit = (screen) => (screen - p0).distance < 50;
      input.down(a, p0);
      await input.drag(a, const Offset(60, 60));
      input.up(a);
      expect(t.calls, ['begin(finger)']);
      expect(t.interactions.single.endCount, 1);
      // Outside the selection the finger navigates as usual.
      input.down(b, p0 + const Offset(300, 300));
      await input.drag(b, const Offset(0, 60));
      input.up(b);
      expect(t.calls.sublist(1), contains('navigationStart'));
    },
  );

  _allModesTest('R24 pen down → PointerCancel → the interaction is cancelled', (
    input,
    t,
  ) async {
    input.down(100, p0, kind: _stylus);
    await input.drag(100, const Offset(30, 0), steps: 3);
    input.cancel(100);
    final i = t.interactions.single;
    expect(i.cancelCount, 1);
    expect(i.endCount, 0);
  });

  _allModesTest('R25 a mouse left drag draws (mouse), no stylusDetected, no '
      'cooldown for the next finger', (input, t) async {
    await input.penStroke(p0, kind: _mouse, id: 200);
    expect(t.callsStartingWith('begin'), ['begin(mouse)']);
    expect(t.interactions.single.source, InteractionSource.mouse);
    expect(t.calls, isNot(contains('stylusDetected')));
    input.down(a, p0);
    input.up(a);
    expect(t.callsStartingWith('palmRejected'), isEmpty);
  });

  _allModesTest('R26 mouse right click → secondaryClick', (input, t) async {
    input.down(200, p0, kind: _mouse, buttons: kSecondaryMouseButton);
    input.up(200);
    expect(t.calls, ['secondaryClick']);
  });

  _allModesTest('R27 wheel dy=100 → scroll(zoom: false); with Ctrl or ⌘ → '
      'scroll(zoom: true)', (input, t) async {
    input.wheel(const Offset(0, 100));
    await input.tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    input.wheel(const Offset(0, 100));
    await input.tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await input.tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    input.wheel(const Offset(0, -100));
    await input.tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    expect(t.calls, [
      'scroll(zoom: false)',
      'scroll(zoom: true)',
      'scroll(zoom: true)',
    ]);
  });

  _allModesTest('R28 a wheel during a pen stroke is ignored', (input, t) async {
    input.down(100, p0, kind: _stylus);
    await input.drag(100, const Offset(30, 0), steps: 3);
    input.wheel(const Offset(0, 100));
    input.up(100);
    expect(t.callsStartingWith('scroll'), isEmpty);
  });

  _routerTest(
    'R29 two-finger tap with twoFingerTapUndo off → no call',
    testInputPolicy(
      penOnly: true,
      stylusSeen: true,
      gestures: const GestureSettings(twoFingerTapUndo: false),
    ),
    (input, t) async {
      input
        ..down(a, p0)
        ..down(b, p0 + const Offset(80, 0));
      await input.wait(const Duration(milliseconds: 100));
      input
        ..up(a)
        ..up(b);
      expect(t.calls, isEmpty);
    },
  );

  _routerTest(
    'R29b three-finger tap with threeFingerTapRedo off → no tap',
    testInputPolicy(
      penOnly: true,
      stylusSeen: true,
      gestures: const GestureSettings(threeFingerTapRedo: false),
    ),
    (input, t) async {
      input
        ..down(a, p0)
        ..down(b, p0 + const Offset(60, 0))
        ..down(c, p0 + const Offset(120, 0));
      await input.wait(const Duration(milliseconds: 100));
      input
        ..up(a)
        ..up(b)
        ..up(c);
      expect(t.calls, isEmpty);
    },
  );

  _routerTest(
    'R30 penOnly + eyedropper: a finger tap starts the eyedropper '
    '(finger interaction)',
    testInputPolicy(penOnly: true, stylusSeen: true, eyedropperActive: true),
    (input, t) async {
      input.down(a, p0);
      await input.wait(const Duration(milliseconds: 80));
      input.up(a);
      expect(t.calls, ['begin(finger)']);
      expect(t.interactions.single.endCount, 1);
    },
  );

  _routerTest(
    'R31 penOnly: lifting one finger of a pinch keeps panning '
    '(rebased), no tap',
    _penOnly,
    (input, t) async {
      input
        ..down(a, p0)
        ..down(b, p0 + const Offset(60, 0));
      for (var i = 1; i <= 8; i++) {
        await input.wait(_frame);
        input
          ..move(a, p0 - Offset(3.0 * i, 0))
          ..move(b, p0 + Offset(60 + 3.0 * i, 0));
      }
      expect(t.calls, contains('navigationStart'));
      input.up(b);
      expect(t.calls.last, 'navigationUpdate(rebased)');
      final rebased = t.navigationUpdates.last;
      expect(rebased.scaleRatio, 1);
      expect(rebased.focal, rebased.baselineFocal);
      final before = t.navigationUpdates.length;
      await input.drag(a, const Offset(0, 90), steps: 6);
      expect(t.navigationUpdates.length, before + 6);
      final last = t.navigationUpdates.last;
      expect(last.rebased, isFalse);
      expect(last.scaleRatio, 1);
      expect(last.focal - last.baselineFocal, const Offset(0, 90));
      input.up(a);
      expect(t.calls.last, 'navigationEnd');
      expect(t.callsStartingWith('tap'), isEmpty);
    },
  );

  _routerTest(
    'R32 fingerDrawing: after a pinch the remaining finger pans, '
    'does not draw',
    _fingerDrawing,
    (input, t) async {
      input
        ..down(a, p0)
        ..down(b, p0 + const Offset(60, 0));
      for (var i = 1; i <= 8; i++) {
        await input.wait(_frame);
        input
          ..move(a, p0 - Offset(3.0 * i, 0))
          ..move(b, p0 + Offset(60 + 3.0 * i, 0));
      }
      input.up(b);
      await input.drag(a, const Offset(0, 90), steps: 6);
      input.up(a);
      expect(t.callsStartingWith('begin'), ['begin(finger)']);
      expect(t.interactions.single.cancelCount, 1);
      expect(t.calls.last, 'navigationEnd');
      expect(
        t.navigationUpdates.last.focal - t.navigationUpdates.last.baselineFocal,
        const Offset(0, 90),
      );
    },
  );

  testWidgets('R33 the editor does not turn on pointer resampling '
      '(contract E-1)', (tester) async {
    expect(GestureBinding.instance.resamplingEnabled, isFalse);
    await pumpEditor(tester);
    expect(GestureBinding.instance.resamplingEnabled, isFalse);
  });

  group('beyond R1–R33', () {
    _routerTest(
      'a navigation fling passes its velocity; a slow release '
      'passes zero',
      _penOnly,
      (input, t) async {
        input.down(a, p0);
        await input.drag(a, const Offset(0, -300), steps: 6);
        input.up(a);
        final v = t.navigationEndVelocities.single.pixelsPerSecond;
        expect(v.dy, lessThan(-1000));
        expect(v.distance, lessThanOrEqualTo(8000));

        input.down(b, p0);
        await input.drag(b, const Offset(0, 40), steps: 4);
        await input.wait(const Duration(milliseconds: 200));
        input.up(b);
        expect(t.navigationEndVelocities.last, Velocity.zero);
      },
    );

    _routerTest(
      'cancelAll stops the interaction, navigation and long press',
      _penOnly,
      (input, t) async {
        input.down(100, p0, kind: _stylus);
        expect(input.router.hasActiveInteraction, isTrue);
        input.router.cancelAll();
        expect(input.router.hasActiveInteraction, isFalse);
        expect(t.interactions.single.cancelCount, 1);
        await input.drag(100, const Offset(30, 0), steps: 3);
        input.up(100);
        expect(t.interactions.single.moves, isEmpty);
        expect(t.interactions.single.endCount, 0);

        await input.wait(const Duration(seconds: 1));
        input.down(a, p0);
        await input.drag(a, const Offset(0, 60));
        expect(input.router.activeTouchCount, 1);
        input.router.cancelAll();
        expect(t.calls.last, 'navigationCancel');
        expect(input.router.activeTouchCount, 0);
        await input.wait(const Duration(seconds: 1));
        input.up(a);
        expect(t.calls.last, 'navigationCancel', reason: 'no end, no tap');

        input.down(b, p0);
        input.router.cancelAll();
        await input.wait(const Duration(seconds: 1));
        expect(t.calls, isNot(contains('longPress')));
        input.up(b);
      },
    );

    _routerTest(
      'a finger on a gap in finger drawing (no interaction) '
      'navigates instead',
      _fingerDrawing,
      (input, t) async {
        t.refuseInteractions = true;
        input.down(a, p0);
        await input.drag(a, const Offset(0, 60));
        input.up(a);
        expect(t.calls.first, 'begin(finger)');
        expect(t.calls, contains('navigationStart'));
      },
    );

    _routerTest('a pen on a gap (no interaction) is consumed', _penOnly, (
      input,
      t,
    ) async {
      t.refuseInteractions = true;
      await input.penStroke(p0);
      expect(t.calls, ['begin(stylus)']);
      expect(input.router.hasActiveInteraction, isFalse);
    });

    _routerTest(
      'trackpad pan/zoom → navigation; scale events → panZoomSignal',
      _penOnly,
      (input, t) async {
        final r = input.router;
        r.handlePointerEvent(
          PointerPanZoomStartEvent(timeStamp: input.now, position: p0),
        );
        await input.wait(_frame);
        r.handlePointerEvent(
          PointerPanZoomUpdateEvent(
            timeStamp: input.now,
            position: p0,
            pan: const Offset(10, 20),
            scale: 1.5,
          ),
        );
        r.handlePointerEvent(
          PointerPanZoomEndEvent(timeStamp: input.now, position: p0),
        );
        expect(t.calls, [
          'navigationStart',
          'navigationUpdate',
          'navigationEnd',
        ]);
        final u = t.navigationUpdates.single;
        expect(u.baselineFocal, p0);
        expect(u.focal, p0 + const Offset(10, 20));
        expect(u.scaleRatio, 1.5);

        r.handlePointerEvent(
          PointerScaleEvent(timeStamp: input.now, position: p0, scale: 1.1),
        );
        expect(t.calls.last, 'panZoom(1.1)');
      },
    );

    _routerTest('every event is observed', _penOnly, (input, t) async {
      await input.penStroke(p0, moves: 3);
      input.hover(p0);
      expect(t.observed, hasLength(1 + 3 + 1 + 1));
    });
  });
}
