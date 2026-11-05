// lib/src/input/pressure_detector.dart — INTERNAL (not exported): per-stroke decision (6.4).
//
// The ONLY pressure-detection rule of the app (contract 7.2.15). Order: mode →
// pointer kind → observation.
//
//  1. alwaysReal → real; alwaysSimulated → simulated (no observation, the
//     remembered capability is left alone).
//  2. auto: touch / mouse / trackpad / unknown → simulated at once.
//     stylus with prior supported → real at once (the constant-value rule
//     below still runs and re-reports unsupported: another pencil); prior
//     unsupported → simulated at once; prior unknown → pending + observation.
//  3. Observation (pending): a value that differs from the first one by more
//     than pressureVariationDelta → supported / real. constantRunLength values
//     in a row that differ from each other by less than constantEpsilon AND lie
//     within defaultValueTolerance of 0.0, 0.5 or 1.0 → unsupported /
//     simulated (constantValue recorded). A stroke that ends while pending is
//     simulated and the capability stays unknown (the next stroke observes again).
//  4. Each decision is reported to the store, so later strokes start decided.
import '../tuning.dart';
import 'ink_sample.dart';
import 'pressure_capability.dart';
import 'pressure_mode.dart';

final class PressureDetector {
  /// [store] receives the decisions of rule 3 (and the re-report of rule 2);
  /// null = decide without remembering (offline builds, tests).
  PressureDetector({
    required InkPointerKind kind,
    required PressureMode mode,
    required PressureCapability prior,
    this._store,
  }) : _kind = kind {
    final stylus = _isStylus(kind);
    switch (mode) {
      case PressureMode.alwaysReal:
        _source = PressureSource.real;
        _capability = stylus ? prior : PressureCapability.unsupported;
      case PressureMode.alwaysSimulated:
        _source = PressureSource.simulated;
        _capability = stylus ? prior : PressureCapability.unsupported;
      case PressureMode.auto when !stylus:
        _source = PressureSource.simulated;
        _capability = PressureCapability.unsupported;
      case PressureMode.auto:
        switch (prior) {
          case PressureCapability.supported:
            _source = PressureSource.real;
            _capability = PressureCapability.supported;
            _watching = true;
          case PressureCapability.unsupported:
            _source = PressureSource.simulated;
            _capability = PressureCapability.unsupported;
          case PressureCapability.unknown:
            _source = PressureSource.pending;
            _capability = PressureCapability.unknown;
            _watching = true;
        }
    }
  }

  final InkPointerKind _kind;
  final PressureCapabilityStore? _store;

  late PressureSource _source;
  late PressureCapability _capability;
  double? _constantValue;

  /// Whether observation still runs (pending, or prior supported).
  bool _watching = false;

  double? _first;
  double _runMin = 0, _runMax = 0;
  int _runLength = 0;

  /// pending until decided
  PressureSource get source => _source;

  /// unknown while pending
  PressureCapability get capability => _capability;

  /// The value an unsupported stylus keeps reporting (e.g. 0.5), else null.
  double? get constantValue => _constantValue;

  /// Feeds one normalized pressure (null = not reported: ignored).
  /// true if [source] changed.
  bool observe(double? normalizedPressure) {
    final p = normalizedPressure;
    if (p == null || p.isNaN || !_watching) return false;
    if (_source == PressureSource.pending) {
      final first = _first ??= p;
      if ((p - first).abs() > InkTuning.pressureVariationDelta) {
        _watching = false;
        _decide(PressureCapability.supported, PressureSource.real, null);
        return true;
      }
    }
    // Constant run: every value of the run within constantEpsilon of each other.
    final lo = p < _runMin ? p : _runMin;
    final hi = p > _runMax ? p : _runMax;
    if (_runLength > 0 && hi - lo < InkTuning.constantEpsilon) {
      _runMin = lo;
      _runMax = hi;
      _runLength++;
    } else {
      _runMin = p;
      _runMax = p;
      _runLength = 1;
    }
    if (_runLength < InkTuning.constantRunLength) return false;
    if (_defaultValueNear(p) == null) return false;
    _watching = false;
    if (_source == PressureSource.pending) {
      _decide(PressureCapability.unsupported, PressureSource.simulated, p);
      return true;
    }
    // Prior supported, but this pencil reports a fixed value: another pencil.
    // The stroke being drawn keeps its source; later strokes start simulated.
    _decide(PressureCapability.unsupported, _source, p);
    return false;
  }

  /// stroke end: pending → simulated (the capability stays unknown).
  PressureSource finish() {
    _watching = false;
    if (_source == PressureSource.pending) _source = PressureSource.simulated;
    return _source;
  }

  void _decide(
    PressureCapability capability,
    PressureSource source,
    double? constantValue,
  ) {
    _capability = capability;
    _source = source;
    _constantValue = constantValue;
    _store?.report(_kind, capability, constantValue: constantValue);
  }

  /// The W3C default the value sits on (0.0, 0.5 or 1.0), else null.
  static double? _defaultValueNear(double p) {
    for (final d in const [0.0, 0.5, 1.0]) {
      if ((p - d).abs() < InkTuning.defaultValueTolerance) return d;
    }
    return null;
  }

  static bool _isStylus(InkPointerKind kind) =>
      kind == InkPointerKind.stylus || kind == InkPointerKind.invertedStylus;
}
