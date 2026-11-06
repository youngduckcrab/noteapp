// lib/src/stylus/stylus_extras_listener.dart — m5-7/04-editor 6.5 (E2-18,
// P-B): the Apple Pencil events of StylusExtrasSource (contract 7.2.10) on the
// note screen.
//
// Subscription (6.5.1): stylusExtrasProvider's events while the page viewport
// is on screen (initState → dispose); nothing when the source is not
// supported. Stream errors are ignored (INFRA's adapter does not emit them —
// 01-infra 6.12.1). The capabilities are the source's, read once at app
// start by INFRA (v2.1, CD2-24); this screen reads them once.
//
//   StylusDoubleTap  → EditorActionRunner.run(actionFor(pencilDoubleTap),
//                      PencilSource(hoverGlobal: hoverPosition, preferred:))
//   StylusSqueeze    → only phase ended: run(actionFor(pencilSqueeze), …);
//                      began / changed / cancelled are ignored
//   StylusHoverPose  → the hover cursor (with capabilities.hoverPose — 6.5.3),
//                      palm rejection P3 (InputRouter.noteStylusPoseHover),
//                      the developer hover source; its roll → the barrel
//                      roll tracker (6.5.4)
//   StylusBarrelRoll → the barrel roll tracker (6.5.4)
//
// The first squeeze / roll on this device is stored (EditorDeviceState
// seenSqueeze / seenBarrelRoll — the settings rows show from then on); the
// events are handled either way.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../actions/editor_action_runner.dart';
import '../di/stylus_extras.dart';
import '../scope/editor_scope.dart';
import '../state/settings/editor_device_state.dart';
import '../state/settings/editor_settings.dart';
import '../state/settings/editor_settings_notifier.dart';
import '../ui/dev/dev_metrics.dart';

/// (6.5.3, S-12(c)) Pen only in effect: the input mode, or auto after the
/// first stylus — and (v2) auto also when iPadOS '펜슬로만 그리기' is on
/// ([capabilities].prefersPencilOnlyDrawing), before any stylus was seen.
/// EditorSettings.isPenOnlyEffective (settings only) stays as it was.
bool penOnlyEffectiveWith(
  EditorSettings settings,
  StylusCapabilities capabilities,
) =>
    settings.isPenOnlyEffective ||
    (settings.inputMode == InputMode.auto &&
        capabilities.prefersPencilOnlyDrawing);

/// The developer hover source of a pose: `pencilPose(<height>)`, the height
/// with two decimals ('-' when the event has none).
String pencilPoseSource(double? height) =>
    'pencilPose(${height == null ? '-' : height.toStringAsFixed(2)})';

/// Subscribes to the Pencil events while it is mounted. Put it where [child]
/// covers the page viewport: hover poses (global px) are converted into the
/// coordinates of [child]'s box (viewport coordinates).
class StylusExtrasListener extends ConsumerStatefulWidget {
  const StylusExtrasListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<StylusExtrasListener> createState() =>
      _StylusExtrasListenerState();
}

class _StylusExtrasListenerState extends ConsumerState<StylusExtrasListener> {
  StreamSubscription<StylusExtraEvent>? _subscription;
  StylusCapabilities _capabilities = StylusCapabilities.none;

  @override
  void initState() {
    super.initState();
    ref.listenManual<StylusExtrasSource>(
      stylusExtrasProvider,
      (_, source) => _subscribe(source),
      fireImmediately: true,
    );
  }

  void _subscribe(StylusExtrasSource source) {
    unawaited(_subscription?.cancel());
    _subscription = null;
    _capabilities = source.capabilities;
    if (!source.isSupported) return;
    _subscription = source.events.listen(
      _onEvent,
      onError: (Object _) {}, // ignored (6.5.1)
    );
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    super.dispose();
  }

  void _onEvent(StylusExtraEvent event) {
    if (!mounted) return;
    switch (event) {
      case StylusDoubleTap(:final preferredAction, :final hoverPosition):
        _run(EditorGesture.pencilDoubleTap, preferredAction, hoverPosition);
      case StylusSqueeze(
        :final phase,
        :final preferredAction,
        :final hoverPosition,
      ):
        _markSeen(squeeze: true);
        // Only the end of a squeeze acts (Apple's sample — 조사 02 9.1).
        if (phase == StylusSqueezePhase.ended) {
          _run(EditorGesture.pencilSqueeze, preferredAction, hoverPosition);
        }
      case StylusBarrelRoll(:final angle, :final timestamp):
        _markSeen(roll: true);
        ref
            .read(editorInteractionHostProvider)
            .barrelRoll
            .note(angle, timestamp: timestamp);
      case final StylusHoverPose pose:
        _onPose(pose);
    }
  }

  void _run(
    EditorGesture gesture,
    StylusPreferredAction preferred,
    Offset? hoverGlobal,
  ) {
    final action = ref.read(editorSettingsProvider).gestures.actionFor(gesture);
    ref
        .read(editorActionRunnerProvider)
        .run(
          action,
          PencilSource(hoverGlobal: hoverGlobal, preferred: preferred),
        );
  }

  void _onPose(StylusHoverPose pose) {
    final host = ref.read(editorInteractionHostProvider);
    final roll = pose.roll;
    if (roll != null) {
      _markSeen(roll: true);
      host.barrelRoll.note(roll, timestamp: pose.timestamp);
    }
    // Palm rejection P3 on the native iPad (6.5.3 — CP-E6).
    ref
        .read(editorInputRouterProvider)
        .noteStylusPoseHover(timestamp: pose.timestamp);
    final metrics = ref.read(editorDevMetricsProvider);
    if (metrics.isRunning) metrics.recordHover(pencilPoseSource(pose.height));
    if (!_capabilities.hoverPose) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    host.poseHover(box.globalToLocal(pose.position), height: pose.height);
  }

  /// The first squeeze / roll on this device (6.5.1) — stored once.
  void _markSeen({bool squeeze = false, bool roll = false}) {
    final seen = ref.read(editorDeviceStateProvider);
    final device = ref.read(editorDeviceStateProvider.notifier);
    if (squeeze && !seen.seenSqueeze) device.markSeenSqueeze();
    if (roll && !seen.seenBarrelRoll) device.markSeenBarrelRoll();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
