// lib/src/ondevice/on_device_providers.dart — (internal) the on-device math
// engine's providers. Not overridden by recognitionOverrides() (still
// exactly 3 overrides — 4.4.8): mathRecognizerProvider's override reads
// [onDeviceMathRecognizerProvider] first.
//
// - [mathModelManagerProvider]: null on the web and the desktops
//   (on_device_platform.dart); otherwise the manager, restored once
//   (an install from an earlier run is ready at once), disposed with the
//   container (a running download stops).
// - [mathModelStateProvider]: the manager's state (MathModelUnsupported
//   without a manager).
// - [onDeviceMathRecognizerProvider]: the engine while the model is ready
//   AND recog.mathOnDevice is on; else null (→ the server engine when
//   configured, else manual — today's behaviour). Disposed (sessions
//   closed) when either changes.
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_core/note_core.dart' as core;

import '../ports/math_recognizer.dart';
import '../settings/recognition_settings_keys.dart';
import 'math_model_manager.dart';
import 'on_device_math_recognizer.dart';
import 'on_device_platform.dart';

final mathModelManagerProvider = Provider<MathModelManager?>((ref) {
  if (kIsWeb) return null;
  final manager = createPlatformMathModelManager();
  if (manager == null) return null;
  ref.onDispose(manager.dispose);
  unawaited(manager.restore());
  return manager;
}, name: 'mathModelManagerProvider');

final mathModelStateProvider =
    NotifierProvider<MathModelStateNotifier, MathModelState>(
      MathModelStateNotifier.new,
      name: 'mathModelStateProvider',
    );

final class MathModelStateNotifier extends Notifier<MathModelState> {
  @override
  MathModelState build() {
    final manager = ref.watch(mathModelManagerProvider);
    if (manager == null) return const MathModelUnsupported();
    void update() => state = manager.state.value;
    manager.state.addListener(update);
    ref.onDispose(() => manager.state.removeListener(update));
    return manager.state.value;
  }
}

/// How an installed model becomes an engine (tests replace it).
final onDeviceMathRecognizerFactoryProvider =
    Provider<MathRecognizer Function(MathModelInstall install)>(
      (ref) => createOnDeviceMathRecognizer,
      name: 'onDeviceMathRecognizerFactoryProvider',
    );

final onDeviceMathRecognizerProvider = Provider<MathRecognizer?>((ref) {
  final install = ref.watch(
    mathModelStateProvider.select(
      (s) => s is MathModelReady ? s.install : null,
    ),
  );
  if (install == null) return null;
  final on = ref.watch(
    core.settingsSnapshotProvider.select(
      (s) => s.value?.get(RecognitionSettingsKeys.mathOnDevice) ?? false,
    ),
  );
  if (!on) return null;
  final engine = ref.watch(onDeviceMathRecognizerFactoryProvider)(install);
  if (engine is OnDeviceMathRecognizer) {
    ref.onDispose(() => unawaited(engine.dispose()));
  }
  return engine;
}, name: 'onDeviceMathRecognizerProvider');
