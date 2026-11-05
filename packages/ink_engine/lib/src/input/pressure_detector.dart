// lib/src/input/pressure_detector.dart — INTERNAL (not exported): per-stroke decision (6.4).
//
// Foundation step B3 (03-ink 4.15): simple rule — alwaysReal → real,
// alwaysSimulated → simulated, auto: stylus = real (unless the stylus is
// already known to be unsupported), every other kind = simulated. The full
// observation rule of 6.4 replaces the body in INK T03 (signature unchanged).
import 'ink_sample.dart';
import 'pressure_capability.dart';
import 'pressure_mode.dart';

final class PressureDetector {
  PressureDetector({
    required InkPointerKind kind,
    required PressureMode mode,
    required PressureCapability prior,
  }) : _source = _decide(kind, mode, prior),
       _capability = _capabilityFor(kind, mode, prior);

  final PressureSource _source;
  final PressureCapability _capability;

  /// pending until decided
  PressureSource get source => _source;

  /// unknown while pending
  PressureCapability get capability => _capability;
  double? get constantValue => null;

  /// true if [source] changed
  bool observe(double? normalizedPressure) => false;

  /// stroke end: pending → simulated
  PressureSource finish() =>
      _source == PressureSource.pending ? PressureSource.simulated : _source;

  static bool _isStylus(InkPointerKind kind) =>
      kind == InkPointerKind.stylus || kind == InkPointerKind.invertedStylus;

  static PressureSource _decide(
    InkPointerKind kind,
    PressureMode mode,
    PressureCapability prior,
  ) => switch (mode) {
    PressureMode.alwaysReal => PressureSource.real,
    PressureMode.alwaysSimulated => PressureSource.simulated,
    PressureMode.auto =>
      _isStylus(kind) && prior != PressureCapability.unsupported
          ? PressureSource.real
          : PressureSource.simulated,
  };

  static PressureCapability _capabilityFor(
    InkPointerKind kind,
    PressureMode mode,
    PressureCapability prior,
  ) {
    if (!_isStylus(kind)) return PressureCapability.unsupported;
    if (mode != PressureMode.auto) return prior;
    return prior == PressureCapability.unsupported
        ? PressureCapability.unsupported
        : PressureCapability.supported;
  }
}
