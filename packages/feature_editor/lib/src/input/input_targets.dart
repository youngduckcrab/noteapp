// lib/src/input/input_targets.dart — 04-editor 6.5.5: router → editor.
import 'package:flutter/gestures.dart';
import 'package:meta/meta.dart';

import '../state/settings/editor_settings.dart';
import '../tools/tool_interaction.dart';
import 'input_sample.dart';

enum InteractionSource { stylus, mouse, finger }

/// Snapshot read by the router on every pointer-down.
@immutable
class InputPolicy {
  const InputPolicy({
    required this.penOnly,
    required this.palm,
    required this.gestures,
    required this.stylusSeen,
    required this.eyedropperActive,
    this.textSessionActive = false,
  });
  final bool penOnly;
  final PalmRejectionSettings palm;
  final GestureSettings gestures;
  final bool stylusSeen;
  final bool eyedropperActive;

  /// (v2) A text edit session is open (m5-7/04-editor 6.3.4): fingers act as
  /// in pen-only mode and a finger down starts no interaction, so only a
  /// confirmed tap, a long press or a pen contact ends the session.
  final bool textSessionActive;

  @override
  bool operator ==(Object other) =>
      other is InputPolicy &&
      other.penOnly == penOnly &&
      other.palm == palm &&
      other.gestures == gestures &&
      other.stylusSeen == stylusSeen &&
      other.eyedropperActive == eyedropperActive &&
      other.textSessionActive == textSessionActive;

  @override
  int get hashCode => Object.hash(
    penOnly,
    palm,
    gestures,
    stylusSeen,
    eyedropperActive,
    textSessionActive,
  );
}

@immutable
class NavigationUpdate {
  const NavigationUpdate({
    required this.baselineFocal,
    required this.focal,
    required this.scaleRatio,
    required this.rebased,
  });
  final Offset baselineFocal;
  final Offset focal;
  final double scaleRatio; // span / baselineSpan (1 with one pointer)
  final bool rebased;

  @override
  bool operator ==(Object other) =>
      other is NavigationUpdate &&
      other.baselineFocal == baselineFocal &&
      other.focal == focal &&
      other.scaleRatio == scaleRatio &&
      other.rebased == rebased;

  @override
  int get hashCode => Object.hash(baselineFocal, focal, scaleRatio, rebased);

  @override
  String toString() =>
      'NavigationUpdate(baseline: $baselineFocal, focal: $focal, '
      'scale: $scaleRatio, rebased: $rebased)';
}

/// Implemented by InteractionHost (6.6). Router → editor.
abstract interface class InputTargets {
  InputPolicy get policy;

  /// Starts a tool interaction (pen, eraser, lasso, eyedropper or selection
  /// transform). Returns null when the input should be ignored (no page,
  /// page not loaded).
  ///
  /// (v2) [gesture] is the gesture that started at this contact (a stylus
  /// only — penButton / invertedStylus, m5-7/04-editor 6.3.3): its action
  /// (GestureSettings.actionFor) may pick a temporary tool for this contact.
  ToolInteraction? beginInteraction(
    InputSample sample, {
    required InteractionSource source,
    EditorGesture? gesture,
  });

  /// True only if the lasso tool is active, a selection exists and [screen]
  /// hits it (handle or body). The router does not know the active tool.
  bool hitsSelection(Offset screen);

  /// (v2) A pen stroke (ToolInteraction.interceptsPenDot) ended as a pen dot
  /// (InputThresholds.penTapMaxMovement / penTapMaxDuration) at [sample].
  /// Called before its end: true = the dot was taken (a tape toggled, a
  /// recording sought — m5-7/04-editor 6.3.5 ②③) and the router cancels the
  /// stroke instead of ending it. [source] finger = a finger in finger
  /// drawing (the tap-to-seek condition is the finger one).
  bool interceptPenDot(InputSample sample, {required InteractionSource source});

  void navigationStart();
  void navigationUpdate(NavigationUpdate update);
  void navigationEnd(Velocity velocity);
  void navigationCancel();

  /// fingerCount 1 = dismiss, 2 / 3 = the gesture's action (the router only
  /// sends 2 / 3 when GestureSettings.actionFor is not none — v2 6.3.4).
  void tapGesture(int fingerCount, Offset centroid);
  void longPress(Offset screen);
  void secondaryClick(Offset screen);
  void hover(InputSample sample);
  void scrollSignal(Offset scrollDelta, Offset at, {required bool zoom});
  void panZoomSignal({
    required Offset panDelta,
    required double scaleFactor,
    required Offset focal,
  });
  void stylusDetected();
  void palmRejected(InputSample sample);

  /// Every pointer event (dev metrics). Must be cheap.
  void observe(PointerEvent event, InputSample sample);
}
