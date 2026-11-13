// lib/src/input/input_router.dart — 04-editor 6.5 (6.5.2 classification,
// 6.5.3 input modes, 6.5.4 palm rejection P1–P6, 6.5.6 state machine);
// (v2) m5-7/04-editor 6.3: the stylus contact rule (6.3.2 — E-4), the gesture
// at contact (6.3.3), the pose hover of palm rejection P3 (6.5.3), taps and
// long press by GestureSettings.actionFor and the text session (6.3.4), and
// the pen dot tap judged before a pen stroke ends (6.3.5).
//
// One Listener on the canvas feeds every PointerEvent here. The router decides
// per pointer whether it draws (a ToolInteraction from InputTargets), navigates
// (pan / pinch), is a tap / long press, or is ignored. It never reads widget
// or provider state other than InputTargets.policy.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart' show HardwareKeyboard;

import '../state/settings/editor_settings.dart';
import '../tools/tool_interaction.dart';
import 'input_sample.dart';
import 'input_targets.dart';
import 'input_thresholds.dart';
import 'stylus_contact.dart';

typedef TimerFactory = Timer Function(
  Duration duration,
  void Function() callback,
);

/// A monotonic clock (palm rejection P3 for the pose hover — 6.5.3).
typedef MonotonicClock = Duration Function();

enum _Role { draw, navigate, rejected, consumed, idle }

enum _Kind { stylus, mouse, finger }

final class _Track {
  _Track({
    required this.kind,
    required this.role,
    required this.down,
    required this.downTime,
  }) : last = down;
  final _Kind kind;
  _Role role;
  final Offset down;
  final Duration downTime;
  Offset last;
  double maxMove = 0;

  /// (v2) A stylus pointer that is down but not touching (web rule: the
  /// buttons lack kStylusContact — 6.3.2). Flutter sends moves, not hovers,
  /// for it; the router treats them as hover.
  bool airborne = false;

  /// Set by cancelAll: the pointer is ignored until up, even if a web stylus
  /// touches again after lifting.
  bool cancelled = false;

  /// (v2) Where and when the current drawing contact started, and how far it
  /// moved since (the pen dot tap — 6.3.5).
  Offset contactAt = Offset.zero;
  Duration contactTime = Duration.zero;
  double contactMaxMove = 0;

  void markContact(PointerEvent e) {
    contactAt = e.localPosition;
    contactTime = e.timeStamp;
    contactMaxMove = 0;
  }
}

/// One burst of touches, from the first finger down to the last finger up.
final class _TouchSequence {
  _TouchSequence(this.start);
  final Duration start;
  final Set<int> active = {};
  int maxConcurrent = 0;
  Offset downSum = Offset.zero;
  int downCount = 0;
  bool moved = false;
  bool invalid = false;
  bool navStarted = false;
  bool hadInteraction = false;
}

final class _Navigation {
  _Navigation(this.pointers);
  final List<int> pointers;
  Offset baselineFocal = Offset.zero;
  double baselineSpan = 0;
  bool started = false;
  VelocityTracker tracker = VelocityTracker.withKind(PointerDeviceKind.touch);
}

class InputRouter {
  /// [contactRule] defaults to StylusContact.platformRule (web on the web).
  /// [monotonicClock] measures the pose hover of [noteStylusPoseHover] and
  /// the finger downs compared with it (default: a Stopwatch).
  InputRouter({
    required this._targets,
    this._thresholds = const InputThresholds(),
    this._timerFactory = Timer.new,
    StylusContactRule? contactRule,
    MonotonicClock? monotonicClock,
  }) : contactRule = contactRule ?? StylusContact.platformRule,
       _clock = monotonicClock ?? _stopwatchClock();

  final InputTargets _targets;
  final InputThresholds _thresholds;
  final TimerFactory _timerFactory;
  final MonotonicClock _clock;

  /// The stylus contact rule (6.3.2), chosen once.
  final StylusContactRule contactRule;

  static MonotonicClock _stopwatchClock() {
    final watch = Stopwatch()..start();
    return () => watch.elapsed;
  }

  final Map<int, _Track> _pointers = {};
  int? _drawPointer;
  ToolInteraction? _interaction;
  _Navigation? _nav;
  _TouchSequence? _seq;
  Duration? _lastStylusActivity; // down / move / up (airborne included)
  Duration? _lastStylusHover;
  Duration? _lastPoseHover; // on [_clock], not event timestamps (6.5.3)
  Duration? _lastPoseHoverStamp; // the pose's own timestamp (event base)
  bool _stylusReported = false;
  Timer? _longPressTimer;

  // Trackpad pan/zoom (PointerPanZoom*).
  int? _panZoomPointer;
  Offset _panZoomStart = Offset.zero;
  VelocityTracker? _panZoomTracker;

  bool get hasActiveInteraction => _interaction != null;

  /// (v2) Native iPad: a StylusHoverPose arrived (6.5.3). The pencil hover
  /// reaches Flutter as a mouse hover, so palm rejection P3
  /// (treatHoverAsPenActivity) counts these instead.
  ///
  /// (v2.1, CP-E6 — E2-18) With the event's [timestamp] (iOS systemUptime —
  /// the same base as PointerEvent.timeStamp [추측, C-1]) a finger down is
  /// compared with it on its own PointerEvent.timeStamp; without one the
  /// time is taken from the router's monotonic clock and the finger down is
  /// read from the same clock. The two are separate ledgers: a value of one
  /// base is never compared with a value of the other.
  void noteStylusPoseHover({Duration? timestamp}) {
    if (timestamp != null) {
      _lastPoseHoverStamp = timestamp;
    } else {
      _lastPoseHover = _clock();
    }
  }

  /// (math pen) Whether a finger [down] that does not reach the router (the
  /// math pen bubble, a sibling of the page Listener) would be rejected as
  /// a palm now — P1–P3 and P5, the same rules as a finger on the page.
  /// Pen and mouse downs never are. Changes nothing.
  bool rejectsAsPalm(PointerDownEvent down) =>
      _kindOf(down) == _Kind.finger &&
      _isPalm(down, InputSample.fromEvent(down));

  /// Finger pointers down that are not rejected or consumed.
  int get activeTouchCount => _pointers.values
      .where(
        (t) =>
            t.kind == _Kind.finger &&
            t.role != _Role.rejected &&
            t.role != _Role.consumed,
      )
      .length;

  void handlePointerEvent(PointerEvent event) {
    switch (event) {
      case PointerDownEvent():
        _onDown(event);
      case PointerMoveEvent():
        _onMove(event);
      case PointerUpEvent():
        _onUp(event);
      case PointerCancelEvent():
        _onCancel(event);
      case PointerHoverEvent():
        _onHover(event);
      case PointerScrollEvent():
        _observe(event);
        if (_interaction != null) return;
        final keyboard = HardwareKeyboard.instance;
        _targets.scrollSignal(
          event.scrollDelta,
          event.localPosition,
          zoom: keyboard.isControlPressed || keyboard.isMetaPressed,
        );
      case PointerScaleEvent():
        _observe(event);
        if (_interaction != null) return;
        _targets.panZoomSignal(
          panDelta: Offset.zero,
          scaleFactor: event.scale,
          focal: event.localPosition,
        );
      case PointerPanZoomStartEvent():
        _onPanZoomStart(event);
      case PointerPanZoomUpdateEvent():
        _onPanZoomUpdate(event);
      case PointerPanZoomEndEvent():
        _onPanZoomEnd(event);
      default:
        _observe(event); // added / removed / other signals
    }
  }

  /// Cancels interactions, navigation and timers (dispose, app hidden).
  void cancelAll() {
    _cancelLongPress();
    _cancelInteraction();
    _cancelNavigation();
    if (_panZoomPointer != null) {
      _panZoomPointer = null;
      _panZoomTracker = null;
      _targets.navigationCancel();
    }
    for (final t in _pointers.values) {
      t
        ..role = _Role.consumed
        ..cancelled = true;
    }
    _seq?.invalid = true;
  }

  // ---- classification ----

  static _Kind? _kindOf(PointerEvent e) => switch (e.kind) {
    PointerDeviceKind.stylus ||
    PointerDeviceKind.invertedStylus => _Kind.stylus,
    PointerDeviceKind.mouse => _Kind.mouse,
    PointerDeviceKind.touch || PointerDeviceKind.unknown => _Kind.finger,
    PointerDeviceKind.trackpad => null,
  };

  InputSample _observe(PointerEvent e) {
    final sample = InputSample.fromEvent(e);
    _targets.observe(e, sample);
    return sample;
  }

  // ---- down ----

  void _onDown(PointerDownEvent e) {
    final sample = _observe(e);
    final kind = _kindOf(e);
    if (kind == null) return;
    final track = _Track(
      kind: kind,
      role: _Role.idle,
      down: e.localPosition,
      downTime: e.timeStamp,
    );
    _pointers[e.pointer] = track;
    if (kind == _Kind.mouse && e.buttons & kSecondaryMouseButton != 0) {
      track.role = _Role.consumed;
      _targets.secondaryClick(e.localPosition);
      return;
    }
    if (kind == _Kind.stylus || kind == _Kind.mouse) {
      _onPenDown(e, sample, track);
    } else {
      _onFingerDown(e, sample, track);
    }
  }

  void _onPenDown(PointerDownEvent e, InputSample sample, _Track track) {
    if (track.kind == _Kind.stylus) {
      _lastStylusActivity = e.timeStamp;
      if (!StylusContact.isContact(contactRule, e)) {
        // Web: down without the contact bit (barrel button above the
        // screen) — airborne: pen activity and the hover cursor only.
        track.airborne = true;
        _targets.hover(sample);
        return;
      }
      _onStylusContact(e, sample, track);
      return;
    }
    // A mouse (left button): contact, no gesture (6.3.2).
    if (_interaction != null) {
      track.role = _Role.rejected;
      return;
    }
    _startDrawing(
      e,
      track,
      _targets.beginInteraction(sample, source: InteractionSource.mouse),
    );
  }

  /// A stylus touches: at its down, or (web) at the first move with the
  /// contact bit after an airborne down / a contact end (6.3.2).
  void _onStylusContact(PointerEvent e, InputSample sample, _Track track) {
    track.airborne = false;
    if (!_stylusReported && !_targets.policy.stylusSeen) {
      _stylusReported = true;
      _targets.stylusDetected();
    }
    // P4: a pen touching down cancels every touch in progress.
    _rejectAllTouches();
    if (_interaction != null) {
      track.role = _Role.rejected;
      return;
    }
    _startDrawing(
      e,
      track,
      _targets.beginInteraction(
        sample,
        source: InteractionSource.stylus,
        gesture: StylusContact.gestureAtContact(e),
      ),
    );
  }

  void _startDrawing(
    PointerEvent e,
    _Track track,
    ToolInteraction? interaction,
  ) {
    if (interaction == null) {
      track.role = _Role.consumed;
      return;
    }
    _interaction = interaction;
    _drawPointer = e.pointer;
    track
      ..role = _Role.draw
      ..markContact(e);
  }

  /// Web: a move without the contact bit while touching ends that contact
  /// (contract E-4 (v2.1)); a later move with the bit is a new contact.
  void _onStylusLift(PointerMoveEvent e, InputSample sample, _Track track) {
    track.airborne = true;
    if (e.pointer == _drawPointer) _finishDrawing(sample, track);
    if (!track.cancelled) track.role = _Role.idle;
    _targets.hover(sample);
  }

  /// The drawing contact ends at [sample] (up, or a web lift). A pen stroke
  /// that was a pen dot is offered to InputTargets.interceptPenDot first —
  /// before its end, so a taken dot leaves no stroke and no command (6.3.5,
  /// contract R-5 (v2.1)).
  void _finishDrawing(InputSample sample, _Track track) {
    final interaction = _interaction!;
    _interaction = null;
    _drawPointer = null;
    if (interaction.interceptsPenDot &&
        _isPenDot(track, sample) &&
        _targets.interceptPenDot(sample, source: interaction.source)) {
      interaction.cancel();
      return;
    }
    interaction.end(sample);
  }

  bool _isPenDot(_Track track, InputSample sample) {
    final moved = math.max(
      track.contactMaxMove,
      (sample.position - track.contactAt).distance,
    );
    return moved <= _thresholds.penTapMaxMovement &&
        sample.timeStamp - track.contactTime <= _thresholds.penTapMaxDuration;
  }

  /// P4: active touches rejected, a finger interaction discarded, navigation
  /// stopped without fling, tap and long press invalid.
  void _rejectAllTouches() {
    _cancelLongPress();
    final hadTouch = _pointers.values.any(
      (t) => t.kind == _Kind.finger && t.role != _Role.rejected,
    );
    if (_interaction?.source == InteractionSource.finger) {
      _cancelInteraction();
    }
    _cancelNavigation();
    for (final t in _pointers.values) {
      if (t.kind == _Kind.finger) t.role = _Role.rejected;
    }
    if (hadTouch) _seq?.invalid = true;
  }

  void _onFingerDown(PointerDownEvent e, InputSample sample, _Track track) {
    final policy = _targets.policy;
    // P1, P2, P3, P5.
    if (_isPalm(e, sample)) {
      track.role = _Role.rejected;
      _seq?.invalid = true;
      _targets.palmRejected(sample);
      return;
    }
    final seq = _seq ??= _TouchSequence(e.timeStamp);
    seq.active.add(e.pointer);
    seq.downSum += e.localPosition;
    seq.downCount++;
    if (seq.active.length > seq.maxConcurrent) {
      seq.maxConcurrent = seq.active.length;
    }

    final interaction = _interaction;
    if (interaction != null) {
      if (interaction.source != InteractionSource.finger) {
        track.role = _Role.rejected; // a mouse is drawing
        return;
      }
      // P6: a second finger soon after a finger stroke started turns it into
      // a two-finger navigation; later ones are ignored.
      final age = e.timeStamp - interaction.startedAt;
      final inWindow =
          age <= _thresholds.fingerStrokeCancelWindow ||
          interaction.travelled <= _thresholds.fingerStrokeCancelDistance;
      if (!inWindow) {
        track.role = _Role.rejected;
        return;
      }
      final drawing = _drawPointer!;
      _cancelInteraction();
      _pointers[drawing]?.role = _Role.navigate;
      track.role = _Role.navigate;
      _startNavigationWith([drawing, e.pointer]);
      return;
    }

    final others = _pointers.entries.where(
      (p) =>
          p.key != e.pointer &&
          p.value.kind == _Kind.finger &&
          (p.value.role == _Role.navigate || p.value.role == _Role.draw),
    );
    if (others.isEmpty) {
      // The only active touch. (v2, 6.3.4) While a text session is open a
      // finger down starts nothing (it may be the first finger of a pinch):
      // fingers act as in pen-only mode, a one-finger drag scrolls.
      ToolInteraction? started;
      if (!policy.textSessionActive &&
          (policy.eyedropperActive ||
              _targets.hitsSelection(e.localPosition) ||
              !policy.penOnly)) {
        started = _targets.beginInteraction(
          sample,
          source: InteractionSource.finger,
        );
      }
      if (started != null) {
        _interaction = started;
        _drawPointer = e.pointer;
        track
          ..role = _Role.draw
          ..markContact(e);
        return;
      }
      track.role = _Role.navigate;
      _startNavigationWith([e.pointer]);
      // (v2) The timer only when the long press has an action (6.3.4).
      if (policy.gestures.actionFor(EditorGesture.fingerLongPress) !=
          EditorAction.none) {
        _longPressTimer = _timerFactory(
          _thresholds.longPressDuration,
          _onLongPress,
        );
      }
      return;
    }

    // A second (third, …) finger joins the navigation.
    _cancelLongPress();
    track.role = _Role.navigate;
    final nav = _nav;
    if (nav == null) {
      _startNavigationWith([for (final p in others) p.key, e.pointer]);
    } else {
      nav.pointers.add(e.pointer);
      _rebase(nav, e.timeStamp);
    }
  }

  bool _isPalm(PointerDownEvent e, InputSample sample) {
    final palm = _targets.policy.palm;
    // P1: a stylus is touching (an airborne web stylus is not — P2 below).
    if (_pointers.values.any((t) => t.kind == _Kind.stylus && !t.airborne)) {
      return true;
    }
    // P2 / P3: recent pen activity (hover counts when enabled).
    final cooldown = palm.penCooldown;
    bool recentAt(Duration now, Duration? at) =>
        at != null && now >= at && now - at < cooldown;
    bool recent(Duration? at) => recentAt(e.timeStamp, at);
    if (recent(_lastStylusActivity)) return true;
    if (palm.treatHoverAsPenActivity) {
      if (recent(_lastStylusHover)) return true;
      // (v2) The iPad pose hover: its timestamp against the down's
      // timestamp, else the router's own clock against itself (6.5.3).
      if (recent(_lastPoseHoverStamp)) return true;
      final pose = _lastPoseHover;
      if (pose != null && recentAt(_clock(), pose)) return true;
    }
    // P5: contact size (0 = not reported).
    final radius = sample.radiusMajor;
    if (radius > 0 && palm.maxTouchRadius > 0 && radius > palm.maxTouchRadius) {
      return true;
    }
    return false;
  }

  // ---- move ----

  void _onMove(PointerMoveEvent e) {
    final sample = _observe(e);
    final track = _pointers[e.pointer];
    if (track == null) return;
    track.last = e.localPosition;
    final moved = (e.localPosition - track.down).distance;
    if (moved > track.maxMove) track.maxMove = moved;
    if (track.kind == _Kind.stylus) {
      _lastStylusActivity = e.timeStamp;
      final contact = StylusContact.isContact(contactRule, e);
      if (track.airborne) {
        if (!contact) {
          _targets.hover(sample); // airborne move = hover
        } else if (!track.cancelled) {
          _onStylusContact(e, sample, track); // this move is the contact
        }
        return;
      }
      if (!contact) {
        _onStylusLift(e, sample, track);
        return;
      }
    }
    if (track.role == _Role.rejected || track.role == _Role.consumed) return;
    if (track.kind == _Kind.finger &&
        track.maxMove > _thresholds.tapMaxMovement) {
      _seq?.moved = true;
    }
    if (e.pointer == _drawPointer) {
      final fromContact = (e.localPosition - track.contactAt).distance;
      if (fromContact > track.contactMaxMove) {
        track.contactMaxMove = fromContact;
      }
      _interaction?.move(sample);
      return;
    }
    final nav = _nav;
    if (track.role != _Role.navigate || nav == null) return;
    if (track.maxMove > _thresholds.longPressMaxMovement) _cancelLongPress();
    final (focal, span) = _focalAndSpan(nav);
    if (!nav.started) {
      final panned =
          (focal - nav.baselineFocal).distance > _thresholds.touchSlop;
      final scaled =
          nav.pointers.length > 1 &&
          (span - nav.baselineSpan).abs() > _thresholds.scaleSlop;
      if (!panned && !scaled) return;
      // Start from the current values (no jump of the first slop).
      _cancelLongPress();
      nav
        ..started = true
        ..baselineFocal = focal
        ..baselineSpan = span
        ..tracker = VelocityTracker.withKind(PointerDeviceKind.touch);
      nav.tracker.addPosition(e.timeStamp, focal);
      _seq?.navStarted = true;
      _targets.navigationStart();
      return;
    }
    nav.tracker.addPosition(e.timeStamp, focal);
    _targets.navigationUpdate(
      NavigationUpdate(
        baselineFocal: nav.baselineFocal,
        focal: focal,
        scaleRatio: _ratio(nav, span),
        rebased: false,
      ),
    );
  }

  static double _ratio(_Navigation nav, double span) =>
      nav.pointers.length > 1 && nav.baselineSpan > 0
      ? span / nav.baselineSpan
      : 1;

  (Offset, double) _focalAndSpan(_Navigation nav) {
    var sum = Offset.zero;
    var n = 0;
    for (final id in nav.pointers) {
      final t = _pointers[id];
      if (t == null) continue;
      sum += t.last;
      n++;
    }
    if (n == 0) return (nav.baselineFocal, nav.baselineSpan);
    final focal = sum / n.toDouble();
    if (n == 1) return (focal, 0);
    var spanSum = 0.0;
    for (final id in nav.pointers) {
      final t = _pointers[id];
      if (t == null) continue;
      spanSum += (t.last - focal).distance;
    }
    return (focal, spanSum / n);
  }

  void _startNavigationWith(List<int> pointers) {
    final nav = _nav = _Navigation(pointers);
    final (focal, span) = _focalAndSpan(nav);
    nav
      ..baselineFocal = focal
      ..baselineSpan = span;
  }

  /// The pointer set changed: new baseline at the current values.
  void _rebase(_Navigation nav, Duration at) {
    final (focal, span) = _focalAndSpan(nav);
    nav
      ..baselineFocal = focal
      ..baselineSpan = span;
    if (!nav.started) return;
    nav.tracker = VelocityTracker.withKind(PointerDeviceKind.touch)
      ..addPosition(at, focal);
    _targets.navigationUpdate(
      NavigationUpdate(
        baselineFocal: focal,
        focal: focal,
        scaleRatio: 1,
        rebased: true,
      ),
    );
  }

  // ---- up / cancel ----

  void _onUp(PointerUpEvent e) {
    final sample = _observe(e);
    final track = _pointers.remove(e.pointer);
    if (track == null) return;
    if (track.kind == _Kind.stylus) _lastStylusActivity = e.timeStamp;
    if (e.pointer == _drawPointer) {
      final source = _interaction!.source;
      _finishDrawing(sample, track);
      if (source == InteractionSource.finger) {
        _seq?.hadInteraction = true;
      }
    } else if (track.role == _Role.navigate) {
      _removeFromNavigation(e.pointer, e.timeStamp);
    }
    if (track.kind == _Kind.finger) _endTouch(e.pointer, e.timeStamp);
  }

  void _removeFromNavigation(int pointer, Duration at) {
    final nav = _nav;
    if (nav == null) return;
    nav.pointers.remove(pointer);
    _cancelLongPress();
    if (nav.pointers.isNotEmpty) {
      _rebase(nav, at);
      return;
    }
    _nav = null;
    if (!nav.started) return;
    final v = nav.tracker.getVelocity().clampMagnitude(
      0,
      _thresholds.maxFlingVelocity,
    );
    _targets.navigationEnd(
      v.pixelsPerSecond.distance < _thresholds.minFlingVelocity
          ? Velocity.zero
          : v,
    );
  }

  void _endTouch(int pointer, Duration at) {
    final seq = _seq;
    if (seq == null || !seq.active.remove(pointer)) return;
    if (seq.active.isNotEmpty) return;
    _seq = null;
    final valid =
        !seq.invalid && !seq.moved && !seq.navStarted && !seq.hadInteraction;
    if (!valid) return;
    final duration = at - seq.start;
    final count = seq.maxConcurrent;
    final maxDuration = count == 1
        ? _thresholds.singleTapMaxDuration
        : _thresholds.multiTapMaxDuration;
    if (duration > maxDuration) return;
    final gestures = _targets.policy.gestures;
    final centroid = seq.downSum / seq.downCount.toDouble();
    // (v2, 6.3.4) 2 / 3 fingers only when their action is not none.
    bool enabled(EditorGesture g) => gestures.actionFor(g) != EditorAction.none;
    switch (count) {
      case 1:
        _targets.tapGesture(1, centroid);
      case 2 when enabled(EditorGesture.twoFingerTap):
        _targets.tapGesture(2, centroid);
      case 3 when enabled(EditorGesture.threeFingerTap):
        _targets.tapGesture(3, centroid);
      default:
        break;
    }
  }

  void _onCancel(PointerCancelEvent e) {
    _observe(e);
    final track = _pointers.remove(e.pointer);
    if (track == null) return;
    if (e.pointer == _drawPointer) {
      _cancelInteraction();
    } else if (track.role == _Role.navigate) {
      _cancelNavigation();
    }
    if (track.kind == _Kind.finger) {
      _seq?.invalid = true;
      _endTouch(e.pointer, e.timeStamp);
    }
  }

  void _cancelInteraction() {
    final interaction = _interaction;
    if (interaction == null) return;
    _interaction = null;
    final pointer = _drawPointer;
    _drawPointer = null;
    _pointers[pointer]?.role = _Role.consumed;
    interaction.cancel();
  }

  /// Stops the navigation without fling; its remaining pointers are ignored.
  void _cancelNavigation() {
    final nav = _nav;
    if (nav == null) return;
    _nav = null;
    _cancelLongPress();
    for (final id in nav.pointers) {
      _pointers[id]?.role = _Role.consumed;
    }
    if (nav.started) _targets.navigationCancel();
  }

  void _cancelLongPress() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
  }

  void _onLongPress() {
    _longPressTimer = null;
    final nav = _nav;
    if (nav == null || nav.started || nav.pointers.length != 1) return;
    final pointer = nav.pointers.single;
    final track = _pointers[pointer];
    if (track == null || track.maxMove > _thresholds.longPressMaxMovement) {
      return;
    }
    track.role = _Role.consumed;
    _nav = null;
    _seq?.invalid = true;
    _targets.longPress(track.last);
  }

  // ---- hover / trackpad ----

  void _onHover(PointerHoverEvent e) {
    final sample = _observe(e);
    final kind = _kindOf(e);
    if (kind == _Kind.stylus) _lastStylusHover = e.timeStamp;
    if (kind == _Kind.stylus || kind == _Kind.mouse) _targets.hover(sample);
  }

  void _onPanZoomStart(PointerPanZoomStartEvent e) {
    _observe(e);
    if (_interaction != null || _panZoomPointer != null) return;
    _panZoomPointer = e.pointer;
    _panZoomStart = e.localPosition;
    _panZoomTracker = VelocityTracker.withKind(PointerDeviceKind.trackpad)
      ..addPosition(e.timeStamp, Offset.zero);
    _targets.navigationStart();
  }

  void _onPanZoomUpdate(PointerPanZoomUpdateEvent e) {
    _observe(e);
    if (e.pointer != _panZoomPointer) return;
    _panZoomTracker?.addPosition(e.timeStamp, e.localPan);
    _targets.navigationUpdate(
      NavigationUpdate(
        baselineFocal: _panZoomStart,
        focal: _panZoomStart + e.localPan,
        scaleRatio: e.scale,
        rebased: false,
      ),
    );
  }

  void _onPanZoomEnd(PointerPanZoomEndEvent e) {
    _observe(e);
    if (e.pointer != _panZoomPointer) return;
    _panZoomPointer = null;
    final v = (_panZoomTracker?.getVelocity() ?? Velocity.zero).clampMagnitude(
      0,
      _thresholds.maxFlingVelocity,
    );
    _panZoomTracker = null;
    _targets.navigationEnd(
      v.pixelsPerSecond.distance < _thresholds.minFlingVelocity
          ? Velocity.zero
          : v,
    );
  }
}
