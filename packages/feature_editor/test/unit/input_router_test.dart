// E-05: InputRouter (04-editor 6.5) — the router scenarios R1..R33 of 6.5.6,
// plus cancelAll / counters / trackpad. (v2) m5-7/04-editor 8.2 E2-04a:
// R34..R42 (stylus contact rule, gesture at contact — 6.3.2·6.3.3) and the
// pose hover of palm rejection P3 (R46 — 6.5.3); E2-04b: R43..R52 (taps and
// long press by actionFor, the pen dot tap, the text session — 6.3.4·6.3.5). Events go straight to
// router.handlePointerEvent with synthetic timestamps; testWidgets' fake time
// (tester.pump) drives the long-press Timer and VelocityTracker's clock.
// RecordingInputTargets (E-01) records every router → editor call.
import 'dart:async';

import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/input/input_router.dart';
import 'package:feature_editor/src/input/input_targets.dart';
import 'package:feature_editor/src/input/input_thresholds.dart';
import 'package:feature_editor/src/input/stylus_contact.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_editor.dart';
import '../helpers/recording_input_targets.dart';

const _frame = Duration(milliseconds: 16);
const _stylus = PointerDeviceKind.stylus;
const _mouse = PointerDeviceKind.mouse;
const _eraserTip = PointerDeviceKind.invertedStylus;

// (v2) Stylus buttons (6.3.2): 0x01 contact, 0x02 barrel button.
const _contact = kStylusContact; // 0x01
const _barrel = kPrimaryStylusButton; // 0x02
const _contactBarrel = kStylusContact | kPrimaryStylusButton; // 0x03

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

  /// [buttons] (v2) changes the pointer's buttons from this move on.
  void move(int id, Offset to, {int? buttons}) {
    final p = _down[id]!;
    final b = buttons ?? p.buttons;
    _down[id] = (pointer: p.pointer, kind: p.kind, at: to, buttons: b);
    router.handlePointerEvent(
      PointerMoveEvent(
        timeStamp: now,
        pointer: p.pointer,
        device: id,
        kind: p.kind,
        position: to,
        delta: to - p.at,
        buttons: b,
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

  void hover(Offset at, {PointerDeviceKind kind = _stylus, int buttons = 0}) =>
      router.handlePointerEvent(
        PointerHoverEvent(
          timeStamp: now,
          kind: kind,
          position: at,
          device: 90,
          buttons: buttons,
        ),
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

/// [rule] (v2) is the stylus contact rule (VM default: native). The router's
/// monotonic clock (pose hover — 6.5.3) is the input's synthetic clock.
void _routerTest(
  String description,
  InputPolicy policy,
  _Body body, {
  StylusContactRule rule = StylusContactRule.native,
}) {
  testWidgets(description, (tester) async {
    final targets = RecordingInputTargets(policy: policy);
    late final _Input input;
    final router = InputRouter(
      targets: targets,
      contactRule: rule,
      monotonicClock: () => input.now,
    );
    input = _Input(tester, router);
    try {
      await body(input, targets);
    } finally {
      router.cancelAll(); // no timer left for the testWidgets check
    }
  });
}

/// The same scenario in every input mode.
void _allModesTest(
  String description,
  _Body body, {
  StylusContactRule rule = StylusContactRule.native,
}) {
  for (final MapEntry(key: mode, value: policy) in _allModes.entries) {
    _routerTest('$description [$mode]', policy, body, rule: rule);
  }
}

/// (v2) The same scenario under both stylus contact rules, in every mode.
void _bothRulesTest(String description, _Body body) {
  for (final rule in StylusContactRule.values) {
    _allModesTest('$description (${rule.name})', body, rule: rule);
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

  group('v2 — stylus contact (E2-04a, R34–R42)', () {
    const web = StylusContactRule.web;
    const native = StylusContactRule.native;
    final p1 = p0 + const Offset(4, 2);

    _allModesTest('R34 web: down 0x02 (airborne) → no interaction, the hover '
        'cursor follows', (input, t) async {
      input.down(100, p0, kind: _stylus, buttons: _barrel);
      expect(t.calls, ['hover(stylus)']);
      await input.wait(_frame);
      input.move(100, p1);
      expect(t.calls, ['hover(stylus)', 'hover(stylus)']);
      input.up(100);
      expect(t.calls, ['hover(stylus)', 'hover(stylus)']);
      expect(t.interactions, isEmpty);
    }, rule: web);

    _allModesTest('R35 web: then move 0x03 → a penButton interaction starts '
        'at that move', (input, t) async {
      input.down(100, p0, kind: _stylus, buttons: _barrel);
      await input.wait(_frame);
      input.move(100, p1, buttons: _contactBarrel);
      expect(t.callsStartingWith('begin'), ['begin(stylus, penButton)']);
      final i = t.interactions.single;
      expect(i.gesture, EditorGesture.penButton);
      expect(i.source, InteractionSource.stylus);
      expect(i.start.event, isA<PointerMoveEvent>());
      expect(i.start.position, p1);
      await input.drag(100, const Offset(40, 0), steps: 4);
      expect(i.moves, hasLength(4));
      input.up(100);
      expect(i.endCount, 1);
      expect(i.cancelCount, 0);
    }, rule: web);

    _allModesTest('R36 web: move 0x02 while touching ends the contact (end '
        'once); a later move 0x03 starts a new interaction', (input, t) async {
      input.down(100, p0, kind: _stylus, buttons: _barrel);
      await input.wait(_frame);
      input.move(100, p1, buttons: _contactBarrel);
      await input.drag(100, const Offset(30, 0), steps: 3);
      final first = t.interactions.single;
      final liftAt = p1 + const Offset(30, 0);
      await input.wait(_frame);
      input.move(100, liftAt, buttons: _barrel); // the pen lifts, button held
      expect(first.endCount, 1);
      expect(first.endSample!.position, liftAt);
      expect(t.calls.last, 'hover(stylus)');
      await input.wait(_frame);
      input.move(100, liftAt + const Offset(0, 20)); // airborne
      expect(t.interactions, hasLength(1));
      await input.wait(_frame);
      final again = liftAt + const Offset(0, 40);
      input.move(100, again, buttons: _contactBarrel);
      expect(t.callsStartingWith('begin'), [
        'begin(stylus, penButton)',
        'begin(stylus, penButton)',
      ]);
      final second = t.interactions.last;
      expect(second.start.position, again);
      await input.drag(100, const Offset(20, 0), steps: 2);
      input.up(100);
      expect(second.endCount, 1);
      expect(first.endCount, 1);
      expect(first.moves, hasLength(3));
    }, rule: web);

    _allModesTest('R37 native: down 0x02 → a penButton interaction at once', (
      input,
      t,
    ) async {
      input.down(100, p0, kind: _stylus, buttons: _barrel);
      expect(t.callsStartingWith('begin'), ['begin(stylus, penButton)']);
      expect(t.callsStartingWith('hover'), isEmpty);
      final i = t.interactions.single;
      expect(i.start.event, isA<PointerDownEvent>());
      await input.drag(100, const Offset(30, 0), steps: 3);
      input.up(100);
      expect(i.moves, hasLength(3));
      expect(i.endCount, 1);
    }, rule: native);

    _bothRulesTest('R38 down 0x01 → no gesture', (input, t) async {
      input.down(100, p0, kind: _stylus, buttons: _contact);
      expect(t.callsStartingWith('begin'), ['begin(stylus)']);
      expect(t.interactions.single.gesture, isNull);
      input.up(100);
      expect(t.interactions.single.endCount, 1);
    });

    _bothRulesTest('R39 invertedStylus → invertedStylus (also with the barrel '
        'button)', (input, t) async {
      input.down(100, p0, kind: _eraserTip, buttons: _contact);
      input.up(100);
      await input.wait(_frame);
      input.down(101, p0, kind: _eraserTip, buttons: _contactBarrel);
      input.up(101);
      expect(t.callsStartingWith('begin'), [
        'begin(stylus, invertedStylus)',
        'begin(stylus, invertedStylus)',
      ]);
      expect(t.interactions.map((i) => i.source), [
        InteractionSource.stylus,
        InteractionSource.stylus,
      ]);
    });

    _bothRulesTest('R40 the button pressed / released mid-stroke → the same '
        'interaction', (input, t) async {
      input.down(100, p0, kind: _stylus, buttons: _contact);
      await input.wait(_frame);
      input.move(100, p0 + const Offset(10, 0), buttons: _contactBarrel);
      await input.wait(_frame);
      input.move(100, p0 + const Offset(20, 0));
      await input.wait(_frame);
      input.move(100, p0 + const Offset(30, 0), buttons: _contact);
      input.up(100);
      final i = t.interactions.single;
      expect(t.callsStartingWith('begin'), ['begin(stylus)']);
      expect(i.gesture, isNull);
      expect(i.moves, hasLength(3));
      expect(i.endCount, 1);
      expect(t.callsStartingWith('hover'), isEmpty);
    });

    _allModesTest('R40 native: down 0x02, the button released mid-stroke '
        '(0x01 / 0x00) → the same penButton interaction', (input, t) async {
      input.down(100, p0, kind: _stylus, buttons: _barrel);
      await input.wait(_frame);
      input.move(100, p0 + const Offset(10, 0), buttons: _contact);
      await input.wait(_frame);
      input.move(100, p0 + const Offset(20, 0), buttons: 0);
      input.up(100);
      final i = t.interactions.single;
      expect(i.gesture, EditorGesture.penButton);
      expect(i.moves, hasLength(2));
      expect(i.endCount, 1);
    }, rule: native);

    _bothRulesTest('R41 toggling the button while hovering (hover buttons '
        '0x02) → nothing but the hover cursor', (input, t) async {
      input.hover(p0);
      await input.wait(_frame);
      input.hover(p1, buttons: _barrel);
      await input.wait(_frame);
      input.hover(p1 + const Offset(5, 0));
      await input.wait(_frame);
      input.hover(p1 + const Offset(10, 0), buttons: _barrel);
      expect(t.calls, List.filled(4, 'hover(stylus)'));
      expect(t.interactions, isEmpty);
    });

    _allModesTest('R42 web: a finger down while the pen is airborne → '
        'rejected by P2 (pen activity)', (input, t) async {
      input.down(100, p0, kind: _stylus, buttons: _barrel);
      await input.wait(const Duration(milliseconds: 100));
      input.down(a, p0 + const Offset(200, 300));
      await input.drag(a, const Offset(0, 60));
      input.up(a);
      expect(t.callsStartingWith('palmRejected'), hasLength(1));
      expect(t.callsStartingWith('begin'), isEmpty);
      expect(_navigationCalls(t), isEmpty);
      expect(t.callsStartingWith('tap'), isEmpty);
    }, rule: web);

    _allModesTest('R42 web: an airborne pen is not touching (not P1): a finger '
        'after the cooldown with no pen event is normal', (input, t) async {
      input.down(100, p0, kind: _stylus, buttons: _barrel);
      await input.wait(const Duration(milliseconds: 600));
      input.down(a, p0 + const Offset(200, 300));
      input.up(a);
      expect(t.callsStartingWith('palmRejected'), isEmpty);
      expect(
        t.policy.penOnly
            ? t.callsStartingWith('tap')
            : t.callsStartingWith('begin'),
        hasLength(1),
      );
      input.up(100);
    }, rule: web);

    _allModesTest('R42 web: the mouse right button is still secondaryClick, '
        'the left button draws', (input, t) async {
      input.down(200, p0, kind: _mouse, buttons: kSecondaryMouseButton);
      input.up(200);
      expect(t.calls, ['secondaryClick']);
      await input.penStroke(p0, kind: _mouse, id: 201, moves: 2);
      expect(t.callsStartingWith('begin'), ['begin(mouse)']);
      expect(t.interactions.single.gesture, isNull);
    }, rule: web);

    _routerTest(
      'web: P4 at the contact move, not at the airborne down',
      _penOnly,
      (input, t) async {
        input.down(a, p0);
        await input.drag(a, const Offset(0, 60));
        expect(t.calls, contains('navigationStart'));
        input.down(
          100,
          p0 + const Offset(200, 0),
          kind: _stylus,
          buttons: _barrel,
        );
        expect(t.calls, isNot(contains('navigationCancel')));
        await input.drag(a, const Offset(0, 20), steps: 2);
        input.move(100, p0 + const Offset(204, 0), buttons: _contactBarrel);
        expect(t.calls.sublist(t.calls.length - 2), [
          'navigationCancel',
          'begin(stylus, penButton)',
        ]);
        input
          ..up(100)
          ..up(a);
      },
      rule: web,
    );

    _routerTest(
      'web: stylusDetected at the contact, not at the airborne down',
      _autoUnseen,
      (input, t) async {
        input.down(100, p0, kind: _stylus, buttons: _barrel);
        expect(t.calls, ['hover(stylus)']);
        await input.wait(_frame);
        input.move(100, p1, buttons: _contactBarrel);
        expect(t.calls, [
          'hover(stylus)',
          'stylusDetected',
          'begin(stylus, penButton)',
        ]);
        input.up(100);
      },
      rule: web,
    );

    _allModesTest('web: up / cancel while airborne → no end, no cancel', (
      input,
      t,
    ) async {
      input.down(100, p0, kind: _stylus, buttons: _barrel);
      await input.wait(_frame);
      input.move(100, p1, buttons: _contactBarrel);
      await input.wait(_frame);
      input.move(100, p1, buttons: _barrel);
      final i = t.interactions.single;
      expect(i.endCount, 1);
      input.up(100);
      input.down(101, p0, kind: _stylus, buttons: _barrel);
      input.cancel(101);
      expect(t.interactions, hasLength(1));
      expect(i.endCount, 1);
      expect(i.cancelCount, 0);
    }, rule: web);

    _allModesTest('web: cancel while touching → the interaction is cancelled', (
      input,
      t,
    ) async {
      input.down(100, p0, kind: _stylus, buttons: _barrel);
      input.move(100, p1, buttons: _contactBarrel);
      input.cancel(100);
      final i = t.interactions.single;
      expect(i.cancelCount, 1);
      expect(i.endCount, 0);
    }, rule: web);

    _allModesTest('web: a refused contact (no page) → the next contact asks '
        'again', (input, t) async {
      t.refuseInteractions = true;
      input.down(100, p0, kind: _stylus, buttons: _barrel);
      input.move(100, p1, buttons: _contactBarrel);
      await input.wait(_frame);
      input.move(100, p1, buttons: _barrel);
      t.refuseInteractions = false;
      await input.wait(_frame);
      input.move(100, p1 + const Offset(10, 0), buttons: _contactBarrel);
      expect(t.callsStartingWith('begin'), [
        'begin(stylus, penButton)',
        'begin(stylus, penButton)',
      ]);
      expect(t.interactions, hasLength(1));
      input.up(100);
      expect(t.interactions.single.endCount, 1);
    }, rule: web);

    _allModesTest('web: after cancelAll an airborne pen stays ignored until '
        'up', (input, t) async {
      input.down(100, p0, kind: _stylus, buttons: _barrel);
      input.router.cancelAll();
      input.move(100, p1, buttons: _contactBarrel);
      await input.wait(_frame);
      input.move(100, p1, buttons: _barrel);
      input.move(100, p1, buttons: _contactBarrel);
      input.up(100);
      expect(t.callsStartingWith('begin'), isEmpty);
      input.down(101, p0, kind: _stylus, buttons: _contactBarrel);
      expect(t.callsStartingWith('begin'), ['begin(stylus, penButton)']);
      input.up(101);
    }, rule: web);

    test('the router picks the platform rule (native on the VM) unless '
        'given one', () {
      final targets = RecordingInputTargets();
      expect(InputRouter(targets: targets).contactRule, native);
      expect(InputRouter(targets: targets, contactRule: web).contactRule, web);
      addTearDown(() => StylusContact.debugRuleOverride = null);
      StylusContact.debugRuleOverride = web;
      expect(InputRouter(targets: targets).contactRule, web);
    });
  });

  group('v2 — pose hover (R46, 6.5.3)', () {
    _allModesTest('R46 a finger within penCooldown of a pose hover → '
        'rejected (treatHoverAsPenActivity)', (input, t) async {
      input.router.noteStylusPoseHover();
      await input.wait(const Duration(milliseconds: 100));
      input.down(a, p0);
      input.up(a);
      expect(t.callsStartingWith('palmRejected'), hasLength(1));
      expect(t.callsStartingWith('tap'), isEmpty);
      expect(t.callsStartingWith('begin'), isEmpty);
    });

    _allModesTest('R46 after the cooldown, or with the hover rule off → '
        'normal', (input, t) async {
      input.router.noteStylusPoseHover();
      await input.wait(const Duration(milliseconds: 600));
      input.down(a, p0);
      input.up(a);
      expect(t.callsStartingWith('palmRejected'), isEmpty);

      t.policy = InputPolicy(
        penOnly: t.policy.penOnly,
        palm: const PalmRejectionSettings(treatHoverAsPenActivity: false),
        gestures: t.policy.gestures,
        stylusSeen: t.policy.stylusSeen,
        eyedropperActive: false,
      );
      await input.wait(const Duration(milliseconds: 400));
      input.router.noteStylusPoseHover();
      await input.wait(const Duration(milliseconds: 100));
      input.down(b, p0);
      input.up(b);
      expect(t.callsStartingWith('palmRejected'), isEmpty);
      expect(
        t.policy.penOnly
            ? t.callsStartingWith('tap')
            : t.callsStartingWith('begin'),
        hasLength(2),
      );
    });
  });

  group('v2 — taps, pen dots, text session (E2-04b, R43–R52)', () {
    InputPolicy withActions(
      InputPolicy base,
      Map<EditorGesture, EditorAction> actions, {
      GestureSettings? gestures,
    }) => InputPolicy(
      penOnly: base.penOnly,
      palm: base.palm,
      gestures: (gestures ?? GestureSettings.defaults).copyWith(
        actions: actions,
      ),
      stylusSeen: base.stylusSeen,
      eyedropperActive: false,
    );

    Future<void> twoFingerTap(_Input input) async {
      input
        ..down(a, p0)
        ..down(b, p0 + const Offset(80, 0));
      await input.wait(const Duration(milliseconds: 100));
      input
        ..up(a)
        ..up(b);
    }

    Future<void> threeFingerTap(_Input input) async {
      input
        ..down(a, p0)
        ..down(b, p0 + const Offset(60, 0))
        ..down(c, p0 + const Offset(120, 0));
      await input.wait(const Duration(milliseconds: 100));
      input
        ..up(a)
        ..up(b)
        ..up(c);
    }

    _allModesTest('R43 twoFingerTap / threeFingerTap action none → no '
        'tapGesture (the v1.4 bools on)', (input, t) async {
      t.policy = withActions(t.policy, {
        EditorGesture.twoFingerTap: EditorAction.none,
        EditorGesture.threeFingerTap: EditorAction.none,
      });
      await twoFingerTap(input);
      await input.wait(const Duration(seconds: 1));
      await threeFingerTap(input);
      expect(t.callsStartingWith('tap'), isEmpty);
    });

    _allModesTest('R44 twoFingerTap = redo → tapGesture(2), also with the '
        'v1.4 bool off (the actions entry wins)', (input, t) async {
      t.policy = withActions(
        t.policy,
        {
          EditorGesture.twoFingerTap: EditorAction.redo,
          EditorGesture.threeFingerTap: EditorAction.undo,
        },
        gestures: const GestureSettings(
          twoFingerTapUndo: false,
          threeFingerTapRedo: false,
        ),
      );
      await twoFingerTap(input);
      await input.wait(const Duration(seconds: 1));
      await threeFingerTap(input);
      expect(t.callsStartingWith('tap'), ['tap(2)', 'tap(3)']);
    });

    testWidgets('R45 fingerLongPress = none → no long-press timer', (
      tester,
    ) async {
      final targets = RecordingInputTargets(
        policy: withActions(_penOnly, {
          EditorGesture.fingerLongPress: EditorAction.none,
        }),
      );
      var timers = 0;
      final router = InputRouter(
        targets: targets,
        timerFactory: (d, cb) {
          timers++;
          return Timer(d, cb);
        },
      );
      final input = _Input(tester, router);
      input.down(a, p0);
      await input.wait(const Duration(milliseconds: 600));
      input.up(a);
      expect(timers, 0);
      expect(targets.calls, isNot(contains('longPress')));

      // The default (contextMenu) arms it.
      targets.policy = _penOnly;
      input.down(b, p0);
      expect(timers, 1);
      await input.wait(const Duration(milliseconds: 600));
      expect(targets.calls, contains('longPress'));
      input.up(b);
      router.cancelAll();
    });

    Future<void> penDot(
      _Input input, {
      required Offset by,
      required Duration after,
      PointerDeviceKind kind = _stylus,
      int id = 100,
    }) async {
      input.down(id, p0, kind: kind);
      await input.wait(after ~/ 2);
      input.move(id, p0 + by * 0.5);
      await input.wait(after - after ~/ 2);
      input.move(id, p0 + by);
      input.up(id);
    }

    _allModesTest('R47 a pen 3 px · 150 ms contact → a pen dot: '
        'interceptPenDot once; taken → cancel once, end 0', (input, t) async {
      t.penDotTaken = (_, _) => true;
      await penDot(
        input,
        by: const Offset(3, 0),
        after: const Duration(milliseconds: 150),
      );
      expect(t.penDots, hasLength(1));
      expect(t.penDots.single.source, InteractionSource.stylus);
      expect(t.penDots.single.sample.event, isA<PointerUpEvent>());
      final i = t.interactions.single;
      expect(i.cancelCount, 1);
      expect(i.endCount, 0);
    });

    _allModesTest('R47 not taken → end once (the dot stroke stays)', (
      input,
      t,
    ) async {
      await penDot(
        input,
        by: const Offset(3, 0),
        after: const Duration(milliseconds: 150),
      );
      expect(t.penDots, hasLength(1));
      expect(t.interactions.single.endCount, 1);
      expect(t.interactions.single.cancelCount, 0);
    });

    _allModesTest('R47 the limits are inclusive: 4 px · 200 ms is a dot', (
      input,
      t,
    ) async {
      t.penDotTaken = (_, _) => true;
      await penDot(
        input,
        by: const Offset(4, 0),
        after: const Duration(milliseconds: 200),
      );
      expect(t.penDots, hasLength(1));
      expect(t.interactions.single.cancelCount, 1);
    });

    _allModesTest('R48 a pen 6 px, or 250 ms → not a dot (end once, no '
        'hook)', (input, t) async {
      t.penDotTaken = (_, _) => true;
      await penDot(
        input,
        by: const Offset(6, 0),
        after: const Duration(milliseconds: 100),
      );
      await input.wait(const Duration(seconds: 1));
      await penDot(
        input,
        by: const Offset(2, 0),
        after: const Duration(milliseconds: 250),
        id: 101,
      );
      // Out 6 px and back: the farthest point counts.
      await input.wait(const Duration(seconds: 1));
      input.down(102, p0, kind: _stylus);
      input
        ..move(102, p0 + const Offset(6, 0))
        ..move(102, p0);
      input.up(102);
      expect(t.penDots, isEmpty);
      expect(t.interactions.map((i) => i.endCount), [1, 1, 1]);
      expect(t.interactions.map((i) => i.cancelCount), [0, 0, 0]);
    });

    _allModesTest('R48 not a pen stroke (interceptsPenDot false) → no hook', (
      input,
      t,
    ) async {
      t
        ..interactionsInterceptPenDot = false
        ..penDotTaken = (_, _) => true;
      await penDot(
        input,
        by: const Offset(1, 0),
        after: const Duration(milliseconds: 50),
      );
      expect(t.penDots, isEmpty);
      expect(t.interactions.single.endCount, 1);
    });

    _allModesTest('a mouse click is a pen dot with source mouse', (
      input,
      t,
    ) async {
      await penDot(
        input,
        by: Offset.zero,
        after: const Duration(milliseconds: 80),
        kind: _mouse,
        id: 200,
      );
      expect(t.penDots.single.source, InteractionSource.mouse);
    });

    _routerTest(
      'fingerDrawing: a finger dot goes to the hook with source finger, no '
      'tap(1)',
      _fingerDrawing,
      (input, t) async {
        t.penDotTaken = (_, _) => true;
        input.down(a, p0);
        await input.wait(const Duration(milliseconds: 80));
        input.up(a);
        expect(t.penDots.single.source, InteractionSource.finger);
        expect(t.interactions.single.cancelCount, 1);
        expect(t.callsStartingWith('tap'), isEmpty);
      },
    );

    _allModesTest('web: the dot is judged from the contact move, and a lift '
        '(move 0x02) is a dot end too', (input, t) async {
      t.penDotTaken = (_, _) => true;
      input.down(100, p0, kind: _stylus, buttons: _barrel);
      await input.wait(const Duration(milliseconds: 300)); // airborne
      input.move(100, p0 + const Offset(40, 0)); // airborne, far away
      final at = p0 + const Offset(60, 0);
      input.move(100, at, buttons: _contactBarrel);
      await input.wait(const Duration(milliseconds: 100));
      input.move(100, at + const Offset(2, 0), buttons: _barrel);
      expect(t.penDots, hasLength(1));
      expect(t.interactions.single.cancelCount, 1);
      expect(t.interactions.single.endCount, 0);
      input.up(100);
      expect(t.penDots, hasLength(1));
    }, rule: StylusContactRule.web);

    InputPolicy inSession(InputPolicy base) => InputPolicy(
      penOnly: base.penOnly,
      palm: base.palm,
      gestures: base.gestures,
      stylusSeen: base.stylusSeen,
      eyedropperActive: false,
      textSessionActive: true,
    );

    _routerTest(
      'R49 text session, finger drawing: one finger down → no interaction, '
      'its drag scrolls',
      inSession(_fingerDrawing),
      (input, t) async {
        input.down(a, p0);
        expect(t.callsStartingWith('begin'), isEmpty);
        await input.drag(a, const Offset(0, 80));
        input.up(a);
        expect(t.callsStartingWith('begin'), isEmpty);
        expect(t.calls.first, 'navigationStart');
        expect(t.calls.last, 'navigationEnd');
        expect(t.callsStartingWith('tap'), isEmpty);
      },
    );

    _routerTest(
      'R49 the selection / eyedropper do not start a finger interaction in '
      'the session either',
      InputPolicy(
        penOnly: true,
        palm: const PalmRejectionSettings(),
        gestures: GestureSettings.defaults,
        stylusSeen: true,
        eyedropperActive: true,
        textSessionActive: true,
      ),
      (input, t) async {
        t.selectionHit = (_) => true;
        input.down(a, p0);
        await input.drag(a, const Offset(0, 60));
        input.up(a);
        expect(t.callsStartingWith('begin'), isEmpty);
        expect(t.calls, contains('navigationStart'));
      },
    );

    _allModesTest('R50 text session: a two-finger drag and a pinch → '
        'navigation only, no session-end signal (no tap, begin or long '
        'press)', (input, t) async {
      t.policy = inSession(t.policy);
      input
        ..down(a, p0)
        ..down(b, p0 + const Offset(80, 0));
      await input.drag(a, const Offset(0, 60), steps: 3);
      await input.drag(b, const Offset(0, 60), steps: 3);
      input
        ..up(a)
        ..up(b);
      await input.wait(const Duration(seconds: 1));
      input
        ..down(a, p0)
        ..down(b, p0 + const Offset(40, 0));
      await input.drag(b, const Offset(80, 0), steps: 4); // spread
      await input.wait(const Duration(milliseconds: 700));
      input
        ..up(a)
        ..up(b);
      expect(t.callsStartingWith('begin'), isEmpty);
      expect(t.callsStartingWith('tap'), isEmpty);
      expect(t.callsStartingWith('longPress'), isEmpty);
      expect(t.calls.where((c) => c == 'navigationStart'), hasLength(2));
    });

    _allModesTest('R51 text session: a one-finger tap → tapGesture(1) once', (
      input,
      t,
    ) async {
      t.policy = inSession(t.policy);
      input.down(a, p0);
      await input.wait(const Duration(milliseconds: 100));
      input.up(a);
      expect(t.calls, ['tap(1)']);
    });

    _allModesTest('R52 text session: a palm rejected by P1 (pen down) → no '
        'signal from it', (input, t) async {
      t.policy = inSession(t.policy);
      input.down(100, p0, kind: _stylus);
      input.down(a, p0 + const Offset(200, 300));
      await input.wait(const Duration(milliseconds: 100));
      input.up(a);
      await input.drag(100, const Offset(30, 0), steps: 3);
      input.up(100);
      expect(t.callsStartingWith('palmRejected'), hasLength(1));
      expect(t.callsStartingWith('tap'), isEmpty);
      expect(t.callsStartingWith('longPress'), isEmpty);
      expect(t.callsStartingWith('begin'), ['begin(stylus)']); // the pen
    });

    _routerTest(
      'text session: the long press still fires (its action ends the '
      'session — 6.3.4 ②)',
      inSession(_fingerDrawing),
      (input, t) async {
        input.down(a, p0);
        await input.wait(const Duration(milliseconds: 600));
        expect(t.calls, ['longPress']);
        input.up(a);
      },
    );

    test('InputPolicy: textSessionActive defaults to false and is part of '
        '== / hashCode', () {
      final off = testInputPolicy();
      final on = testInputPolicy(textSessionActive: true);
      expect(off.textSessionActive, isFalse);
      expect(on, isNot(off));
      expect(on, testInputPolicy(textSessionActive: true));
      expect(on.hashCode, testInputPolicy(textSessionActive: true).hashCode);
    });

    test('InputThresholds: the pen dot 4 px · 200 ms, apart from the finger '
        'tap', () {
      const t = InputThresholds();
      expect(t.penTapMaxMovement, 4);
      expect(t.penTapMaxDuration, const Duration(milliseconds: 200));
      expect(t.tapMaxMovement, 20);
      expect(t.singleTapMaxDuration, const Duration(milliseconds: 250));
    });
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
