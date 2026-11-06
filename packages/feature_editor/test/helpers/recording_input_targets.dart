// test/helpers/recording_input_targets.dart — 04-editor 9.1 (E-01).
//
// An InputTargets double for unit/input_router_test.dart (6.5.6 R1..R33): it
// records every router → editor call as a short string, in order, and hands
// out RecordingToolInteractions that record their own move / end / cancel.
import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/input/input_sample.dart';
import 'package:feature_editor/src/input/input_targets.dart';
import 'package:feature_editor/src/tools/tool_interaction.dart';
import 'package:flutter/gestures.dart';

/// Policy with the defaults of 4.8 (pen-only off, auto palm settings).
InputPolicy testInputPolicy({
  bool penOnly = false,
  PalmRejectionSettings palm = const PalmRejectionSettings(),
  GestureSettings gestures = GestureSettings.defaults,
  bool stylusSeen = false,
  bool eyedropperActive = false,
}) => InputPolicy(
  penOnly: penOnly,
  palm: palm,
  gestures: gestures,
  stylusSeen: stylusSeen,
  eyedropperActive: eyedropperActive,
);

class RecordingInputTargets implements InputTargets {
  RecordingInputTargets({InputPolicy? policy})
    : policy = policy ?? testInputPolicy();

  /// Read by the router on every pointer-down; tests may replace it.
  @override
  InputPolicy policy;

  /// Every call except [observe], in order, e.g. 'begin(stylus)',
  /// 'navigationStart', 'tap(2)', 'scroll(zoom: true)'.
  final List<String> calls = [];

  /// Every observed event (observe is recorded separately: it fires per event).
  final List<PointerEvent> observed = [];

  /// Interactions handed out by [beginInteraction], in order.
  final List<RecordingToolInteraction> interactions = [];

  /// Arguments of the navigation calls, in order.
  final List<NavigationUpdate> navigationUpdates = [];
  final List<Velocity> navigationEndVelocities = [];

  /// Rejected samples passed to [palmRejected].
  final List<InputSample> palmRejectedSamples = [];

  /// When true, [beginInteraction] returns null (no page under the pointer).
  bool refuseInteractions = false;

  /// [hitsSelection] answer; default: no selection.
  bool Function(Offset screen) selectionHit = _never;

  /// Called from [stylusDetected] — e.g. to switch [policy] to pen-only as the
  /// real InteractionHost does in auto mode (R6).
  void Function()? onStylusDetected;

  static bool _never(Offset _) => false;

  /// The calls whose name starts with [prefix] (e.g. 'tap').
  List<String> callsStartingWith(String prefix) => [
    for (final c in calls)
      if (c.startsWith(prefix)) c,
  ];

  @override
  ToolInteraction? beginInteraction(
    InputSample sample, {
    required InteractionSource source,
  }) {
    calls.add('begin(${source.name})');
    if (refuseInteractions) return null;
    final interaction = RecordingToolInteraction(
      source: source,
      startedAt: sample.timeStamp,
      start: sample,
    );
    interactions.add(interaction);
    return interaction;
  }

  @override
  bool hitsSelection(Offset screen) => selectionHit(screen);

  @override
  void navigationStart() => calls.add('navigationStart');

  @override
  void navigationUpdate(NavigationUpdate update) {
    navigationUpdates.add(update);
    calls.add('navigationUpdate${update.rebased ? '(rebased)' : ''}');
  }

  @override
  void navigationEnd(Velocity velocity) {
    navigationEndVelocities.add(velocity);
    calls.add('navigationEnd');
  }

  @override
  void navigationCancel() => calls.add('navigationCancel');

  @override
  void tapGesture(int fingerCount, Offset centroid) =>
      calls.add('tap($fingerCount)');

  @override
  void longPress(Offset screen) => calls.add('longPress');

  @override
  void secondaryClick(Offset screen) => calls.add('secondaryClick');

  @override
  void hover(InputSample sample) => calls.add('hover(${sample.kind.name})');

  @override
  void scrollSignal(Offset scrollDelta, Offset at, {required bool zoom}) =>
      calls.add('scroll(zoom: $zoom)');

  @override
  void panZoomSignal({
    required Offset panDelta,
    required double scaleFactor,
    required Offset focal,
  }) => calls.add('panZoom($scaleFactor)');

  @override
  void stylusDetected() {
    calls.add('stylusDetected');
    onStylusDetected?.call();
  }

  @override
  void palmRejected(InputSample sample) {
    palmRejectedSamples.add(sample);
    calls.add('palmRejected');
  }

  @override
  void observe(PointerEvent event, InputSample sample) => observed.add(event);
}

/// Records what the router does with one interaction.
class RecordingToolInteraction extends ToolInteraction {
  RecordingToolInteraction({
    required super.source,
    required super.startedAt,
    required this.start,
  }) : _last = start.position;

  final InputSample start;
  final List<InputSample> moves = [];
  InputSample? endSample;
  int endCount = 0;
  int cancelCount = 0;
  double _travelled = 0;
  Offset _last;

  bool get isEnded => endCount > 0;
  bool get isCancelled => cancelCount > 0;

  @override
  double get travelled => _travelled;

  @override
  void move(InputSample sample) {
    moves.add(sample);
    _travelled += (sample.position - _last).distance;
    _last = sample.position;
  }

  @override
  void end(InputSample sample) {
    endSample = sample;
    endCount++;
  }

  @override
  void cancel() => cancelCount++;
}
