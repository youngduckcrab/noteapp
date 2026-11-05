// lib/src/input/pressure_capability.dart — 03-ink 4.3 (enums: contract 7.2.15).
import 'package:meta/meta.dart';
import 'package:riverpod/riverpod.dart';

import 'ink_sample.dart';

// contract 7.2.15
enum PressureCapability { unknown, supported, unsupported }

enum PressureSource { pending, real, simulated }

/// Session-wide memory of what each pointer kind supports (reset on app restart).
@immutable
final class PressureCapabilityState {
  const PressureCapabilityState({
    this.stylus = PressureCapability.unknown,
    this.stylusConstantValue,
  });
  final PressureCapability stylus;

  /// e.g. 0.5 when the stylus reports a fixed value
  final double? stylusConstantValue;

  /// stylus / invertedStylus → [stylus]; touch / mouse / trackpad / unknown → unsupported.
  PressureCapability capabilityOf(InkPointerKind kind) => switch (kind) {
    InkPointerKind.stylus || InkPointerKind.invertedStylus => stylus,
    InkPointerKind.touch ||
    InkPointerKind.mouse ||
    InkPointerKind.trackpad ||
    InkPointerKind.unknown => PressureCapability.unsupported,
  };

  PressureCapabilityState copyWith({
    PressureCapability? stylus,
    double? stylusConstantValue,
  }) => PressureCapabilityState(
    stylus: stylus ?? this.stylus,
    stylusConstantValue: stylusConstantValue ?? this.stylusConstantValue,
  );

  @override
  bool operator ==(Object other) =>
      other is PressureCapabilityState &&
      other.stylus == stylus &&
      other.stylusConstantValue == stylusConstantValue;

  @override
  int get hashCode => Object.hash(stylus, stylusConstantValue);

  @override
  String toString() =>
      'PressureCapabilityState(${stylus.name}, $stylusConstantValue)';
}

abstract interface class PressureCapabilityStore {
  PressureCapability capabilityOf(InkPointerKind kind);
  void report(
    InkPointerKind kind,
    PressureCapability capability, {
    double? constantValue,
  });
}

/// The ONLY pressure-detection state in the app; the detection rule is 6.4 (contract
/// 7.2.15). EDITOR's developer overlay and input settings section read [state].
class PressureCapabilityNotifier extends Notifier<PressureCapabilityState>
    implements PressureCapabilityStore {
  @override
  PressureCapabilityState build() => const PressureCapabilityState();

  @override
  PressureCapability capabilityOf(InkPointerKind kind) =>
      state.capabilityOf(kind);

  /// Only stylus kinds are remembered; reports for other kinds are ignored
  /// (they are always unsupported).
  @override
  void report(
    InkPointerKind kind,
    PressureCapability capability, {
    double? constantValue,
  }) {
    if (kind != InkPointerKind.stylus &&
        kind != InkPointerKind.invertedStylus) {
      return;
    }
    final next = PressureCapabilityState(
      stylus: capability,
      stylusConstantValue: capability == PressureCapability.unsupported
          ? constantValue
          : null,
    );
    if (next != state) state = next;
  }

  void reset() {
    const initial = PressureCapabilityState();
    if (state != initial) state = initial;
  }
}
