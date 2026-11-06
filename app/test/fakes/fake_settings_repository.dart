// A SettingsRepository wrapper for app tests (docs/plans/m5-7/01-infra.md
// 9.1 — app_module_context_test, feature_switch_section_test): counts the
// reads, and can delay or fail get / set. Pass it as
// CountingNoteStore(settingsOverride: …).
import 'dart:async';

import 'package:note_core/note_core.dart';

final class FakeSettingsRepository implements SettingsRepository {
  FakeSettingsRepository(
    this.inner, {
    this.getDelay = Duration.zero,
    this.getError,
    this.setError,
  });

  final SettingsRepository inner;

  /// How long get() takes (fake time).
  Duration getDelay;

  /// Thrown by get() / set() when set.
  Object? getError;
  Object? setError;

  /// Key names in the order get() was called.
  final List<String> reads = [];

  @override
  Future<T> get<T>(SettingKey<T> key) async {
    reads.add(key.name);
    if (getDelay > Duration.zero) await Future<void>.delayed(getDelay);
    if (getError case final error?) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
    return inner.get(key);
  }

  @override
  Stream<T> watch<T>(SettingKey<T> key) => inner.watch(key);

  @override
  Future<void> set<T>(SettingKey<T> key, T value) async {
    if (setError case final error?) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
    await inner.set(key, value);
  }

  @override
  Future<void> reset<T>(SettingKey<T> key) => inner.reset(key);

  @override
  Stream<SettingsSnapshot> watchAll() => inner.watchAll();
}
