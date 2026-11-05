// lib/src/input/pressure_mode.dart — contract 7.2.15 (03-ink 4.3).
import 'package:riverpod/riverpod.dart';

// wire value of PressureMode = name (EDITOR settings JSON)
enum PressureMode { auto, alwaysReal, alwaysSimulated }

/// Set by EDITOR from its persisted settings (no override needed).
class PressureModeNotifier extends Notifier<PressureMode> {
  /// PressureMode.auto
  @override
  PressureMode build() => PressureMode.auto;

  /// Same value → no notification. Controllers read the mode at every
  /// beginStroke (a stroke being drawn keeps the mode it started with).
  void set(PressureMode mode) {
    if (state == mode) return;
    state = mode;
  }
}
