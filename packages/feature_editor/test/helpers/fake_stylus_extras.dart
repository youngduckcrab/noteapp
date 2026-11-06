// test/helpers/fake_stylus_extras.dart — m5-7/04-editor 5.5, 8.2 E2-00.
//
// A StylusExtrasSource whose events the test injects. The editor reads
// `capabilities` once per screen (contract 7.2.10 (v2.1)); `isSupported`
// false means the editor must not subscribe (E2-18).
import 'dart:async';

import 'package:feature_editor/feature_editor.dart';

class FakeStylusExtras implements StylusExtrasSource {
  FakeStylusExtras({
    this.capabilities = const StylusCapabilities(
      doubleTap: true,
      squeeze: true,
      hoverPose: true,
      barrelRoll: true,
    ),
    this.isSupported = true,
  });

  @override
  final bool isSupported;

  @override
  final StylusCapabilities capabilities;

  late final StreamController<StylusExtraEvent> _events =
      StreamController<StylusExtraEvent>.broadcast(
        onListen: () => listenCount++,
        onCancel: () => cancelCount++,
      );

  /// How often the first listener arrived / the last one left (broadcast
  /// callbacks).
  int listenCount = 0;
  int cancelCount = 0;

  /// True while someone listens to [events].
  bool get hasListener => _events.hasListener;

  @override
  Stream<StylusExtraEvent> get events => _events.stream;

  /// Delivers [event] to the listeners (synchronously queued; pump to run).
  void emit(StylusExtraEvent event) => _events.add(event);

  /// Delivers an error to the listeners (the editor ignores it — 6.21).
  void emitError(Object error) => _events.addError(error);

  Future<void> close() => _events.close();
}
