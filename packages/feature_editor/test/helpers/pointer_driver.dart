// test/helpers/pointer_driver.dart — 04-editor 9.1 (E-01); (v2) m5-7/04-editor
// 6.3.2, 8.2 E2-00: pen button (barrel button) buttons, the web hover →
// contact order and the eraser tip.
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

/// Sends raw PointerEvents (pressure, tilt, radius, kind, timestamps) via
/// tester.sendEventToBinding. Keeps a synthetic clock: every step advances
/// both the event timestamps and fake time (tester.pump(interval)), so
/// timestamp-based rules (taps, cooldown) and Timer-based rules (long
/// press) stay consistent.
///
/// [down] / [move] / [up] / [cancel] / [hover] / [wheel] send one event at
/// [now] and pump once without advancing time; [wait] advances both clocks.
/// The `pointer` argument is a logical finger / pen number: like the engine,
/// every down gets a fresh PointerEvent.pointer, and the logical number is
/// the event's `device`.
class PointerDriver {
  PointerDriver(this.tester, {Duration start = const Duration(seconds: 1)})
    : _now = start;

  final WidgetTester tester;

  Duration _now;
  Duration get now => _now;

  static int _nextEventPointer = 50000;

  final Map<int, _ActivePointer> _active = {};
  final Set<int> _addedDevices = {};

  /// The PointerEvent.pointer of logical [pointer] while it is down.
  int eventPointerOf(int pointer) => _require(pointer).eventPointer;

  bool isDown(int pointer) => _active.containsKey(pointer);

  Future<void> down(
    int pointer,
    Offset at, {
    PointerDeviceKind kind = PointerDeviceKind.touch,
    double pressure = 0.5,
    double tilt = 0,
    double radiusMajor = 0,
    int buttons = kPrimaryButton,
  }) async {
    if (_active.containsKey(pointer)) {
      throw StateError('pointer $pointer is already down');
    }
    await _ensureAdded(pointer, kind, at);
    final p = _ActivePointer(
      eventPointer: _nextEventPointer++,
      device: pointer,
      kind: kind,
      position: at,
      pressure: pressure,
      tilt: tilt,
      radiusMajor: radiusMajor,
      buttons: buttons,
    );
    _active[pointer] = p;
    await _send(
      PointerDownEvent(
        timeStamp: _now,
        pointer: p.eventPointer,
        device: pointer,
        kind: kind,
        position: at,
        buttons: buttons,
        pressure: pressure,
        pressureMin: 0,
        pressureMax: 1,
        tilt: tilt,
        radiusMajor: radiusMajor,
        radiusMinor: radiusMajor,
        radiusMin: 0,
        radiusMax: radiusMajor,
      ),
    );
  }

  /// [buttons] (v2) changes the pointer's buttons from this event on — the
  /// web reports contact as bit 0x01 of the move's buttons (6.3.2).
  Future<void> move(
    int pointer,
    Offset to, {
    double? pressure,
    double? tilt,
    int? buttons,
  }) async {
    final p = _require(pointer);
    final delta = to - p.position;
    p.position = to;
    if (pressure != null) p.pressure = pressure;
    if (tilt != null) p.tilt = tilt;
    if (buttons != null) p.buttons = buttons;
    await _send(
      PointerMoveEvent(
        timeStamp: _now,
        pointer: p.eventPointer,
        device: pointer,
        kind: p.kind,
        position: to,
        delta: delta,
        buttons: p.buttons,
        pressure: p.pressure,
        pressureMin: 0,
        pressureMax: 1,
        tilt: p.tilt,
        radiusMajor: p.radiusMajor,
        radiusMinor: p.radiusMajor,
        radiusMin: 0,
        radiusMax: p.radiusMajor,
      ),
    );
  }

  Future<void> up(int pointer) async {
    final p = _require(pointer);
    _active.remove(pointer);
    await _send(
      PointerUpEvent(
        timeStamp: _now,
        pointer: p.eventPointer,
        device: pointer,
        kind: p.kind,
        position: p.position,
        pressure: 0,
        pressureMin: 0,
        pressureMax: 1,
        tilt: p.tilt,
        radiusMajor: p.radiusMajor,
        radiusMinor: p.radiusMajor,
        radiusMin: 0,
        radiusMax: p.radiusMajor,
      ),
    );
  }

  Future<void> cancel(int pointer) async {
    final p = _require(pointer);
    _active.remove(pointer);
    await _send(
      PointerCancelEvent(
        timeStamp: _now,
        pointer: p.eventPointer,
        device: pointer,
        kind: p.kind,
        position: p.position,
      ),
    );
  }

  /// Advances the synthetic clock and fake time together.
  Future<void> wait(Duration d) async {
    _now += d;
    await tester.pump(d);
  }

  /// Stylus down at points.first, a move per point every [interval], up at
  /// points.last. [pressures] (same length as [points]) defaults to 0.5.
  ///
  /// (v2) [kind] invertedStylus = the eraser tip; [buttons] for the whole
  /// stroke (native pen button: kPrimaryStylusButton — the Android engine
  /// sends down(buttons: 0x02) for a touching pen with the button held).
  Future<void> stylusStroke(
    List<Offset> points, {
    List<double>? pressures,
    double tilt = 0,
    Duration interval = const Duration(milliseconds: 4),
    int pointer = 1,
    PointerDeviceKind kind = PointerDeviceKind.stylus,
    int buttons = kPrimaryButton,
  }) async {
    if (points.isEmpty) throw ArgumentError.value(points, 'points', 'empty');
    if (pressures != null && pressures.length != points.length) {
      throw ArgumentError.value(pressures, 'pressures', 'length != points');
    }
    double pressureAt(int i) => pressures == null ? 0.5 : pressures[i];
    await down(
      pointer,
      points.first,
      kind: kind,
      pressure: pressureAt(0),
      tilt: tilt,
      buttons: buttons,
    );
    for (var i = 1; i < points.length; i++) {
      await wait(interval);
      await move(pointer, points[i], pressure: pressureAt(i));
    }
    await wait(interval);
    await up(pointer);
  }

  /// (v2) Native pen-button stroke: down(buttons: 0x02) = contact with the
  /// barrel button held (6.3.2 — native rule: down is contact).
  Future<void> nativePenButtonStroke(
    List<Offset> points, {
    Duration interval = const Duration(milliseconds: 4),
    int pointer = 1,
  }) => stylusStroke(
    points,
    interval: interval,
    pointer: pointer,
    buttons: kPrimaryStylusButton,
  );

  /// (v2) Eraser-tip stroke (PointerDeviceKind.invertedStylus).
  Future<void> eraserTipStroke(
    List<Offset> points, {
    Duration interval = const Duration(milliseconds: 4),
    int pointer = 1,
  }) => stylusStroke(
    points,
    interval: interval,
    pointer: pointer,
    kind: PointerDeviceKind.invertedStylus,
  );

  /// (v2) The web order for a pen-button stroke (6.3.2, research 02 8.4 CDP):
  /// `down 0x02` at points.first (airborne — barrel button, no contact),
  /// `move 0x03` to every following point (contact + button), then
  /// `move 0x02` at points.last (the pen lifts, button still held) and `up`.
  /// [points] needs at least two points.
  Future<void> webPenButtonStroke(
    List<Offset> points, {
    Duration interval = const Duration(milliseconds: 4),
    int pointer = 1,
  }) async {
    if (points.length < 2) {
      throw ArgumentError.value(points, 'points', 'needs >= 2 points');
    }
    const airborne = kPrimaryStylusButton; // 0x02
    const contact = kPrimaryButton | kPrimaryStylusButton; // 0x03
    await down(
      pointer,
      points.first,
      kind: PointerDeviceKind.stylus,
      buttons: airborne,
    );
    for (var i = 1; i < points.length; i++) {
      await wait(interval);
      await move(pointer, points[i], buttons: contact);
    }
    await wait(interval);
    await move(pointer, points.last, buttons: airborne);
    await wait(interval);
    await up(pointer);
  }

  /// One finger from [from] to [to] in [steps] equal moves.
  Future<void> fingerDrag(
    Offset from,
    Offset to, {
    int steps = 10,
    Duration interval = const Duration(milliseconds: 8),
    int pointer = 11,
  }) async {
    await down(pointer, from);
    for (var i = 1; i <= steps; i++) {
      await wait(interval);
      await move(pointer, Offset.lerp(from, to, i / steps)!);
    }
    await wait(interval);
    await up(pointer);
  }

  /// All fingers down together, held for [hold], all up together.
  Future<void> multiTap(
    List<Offset> positions, {
    Duration hold = const Duration(milliseconds: 100),
    int firstPointer = 21,
  }) async {
    for (var i = 0; i < positions.length; i++) {
      await down(firstPointer + i, positions[i]);
    }
    await wait(hold);
    for (var i = 0; i < positions.length; i++) {
      await up(firstPointer + i);
    }
  }

  /// Two fingers on a horizontal line through [center], their distance going
  /// from [startSpan] to [endSpan] in [steps] moves.
  Future<void> pinch({
    required Offset center,
    required double startSpan,
    required double endSpan,
    int steps = 10,
    Duration interval = const Duration(milliseconds: 8),
    int firstPointer = 31,
  }) async {
    Offset left(double span) => center - Offset(span / 2, 0);
    Offset right(double span) => center + Offset(span / 2, 0);
    await down(firstPointer, left(startSpan));
    await down(firstPointer + 1, right(startSpan));
    for (var i = 1; i <= steps; i++) {
      await wait(interval);
      final span = startSpan + (endSpan - startSpan) * i / steps;
      await move(firstPointer, left(span));
      await move(firstPointer + 1, right(span));
    }
    await wait(interval);
    await up(firstPointer);
    await up(firstPointer + 1);
  }

  /// A hover event (stylus or mouse, not down).
  ///
  /// (v2) [buttons]: a hovering pen with its barrel button held reports 0x02
  /// (the editor ignores hover buttons — 6.3.2, R41).
  Future<void> hover(
    Offset at, {
    PointerDeviceKind kind = PointerDeviceKind.stylus,
    int pointer = 41,
    int buttons = 0,
  }) async {
    await _ensureAdded(pointer, kind, at);
    await _send(
      PointerHoverEvent(
        timeStamp: _now,
        device: pointer,
        kind: kind,
        position: at,
        buttons: buttons,
      ),
    );
  }

  /// A mouse wheel event. With [withControl] / [withMeta] the key is held
  /// during the event (zoom on wheel, 6.5.6 R27).
  Future<void> wheel(
    Offset at,
    Offset delta, {
    bool withControl = false,
    bool withMeta = false,
    int pointer = 51,
  }) async {
    await _ensureAdded(pointer, PointerDeviceKind.mouse, at);
    final key = withControl
        ? LogicalKeyboardKey.controlLeft
        : withMeta
        ? LogicalKeyboardKey.metaLeft
        : null;
    if (key != null) await simulateKeyDownEvent(key);
    await _send(
      PointerScrollEvent(
        timeStamp: _now,
        device: pointer,
        kind: PointerDeviceKind.mouse,
        position: at,
        scrollDelta: delta,
      ),
    );
    if (key != null) await simulateKeyUpEvent(key);
  }

  _ActivePointer _require(int pointer) =>
      _active[pointer] ?? (throw StateError('pointer $pointer is not down'));

  Future<void> _ensureAdded(int device, PointerDeviceKind kind, Offset at) {
    // Mouse / stylus devices exist before they hover (the engine sends an
    // added event first); touches need none.
    if (kind == PointerDeviceKind.touch || !_addedDevices.add(device)) {
      return Future<void>.value();
    }
    return tester.sendEventToBinding(
      PointerAddedEvent(
        timeStamp: _now,
        device: device,
        kind: kind,
        position: at,
      ),
    );
  }

  Future<void> _send(PointerEvent event) async {
    await tester.sendEventToBinding(event);
    await tester.pump();
  }
}

final class _ActivePointer {
  _ActivePointer({
    required this.eventPointer,
    required this.device,
    required this.kind,
    required this.position,
    required this.pressure,
    required this.tilt,
    required this.radiusMajor,
    required this.buttons,
  });

  final int eventPointer;
  final int device;
  final PointerDeviceKind kind;
  Offset position;
  double pressure;
  double tilt;
  final double radiusMajor;
  int buttons;
}
