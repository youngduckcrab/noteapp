// test/helpers/settings_env.dart — E-06: a fake store + provider container
// under fake_async for the settings notifiers (and E-07's tool controller).
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:feature_editor/feature_editor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

/// Records the writes that reach CORE (set / reset), then delegates.
final class RecordingSettings implements core.SettingsRepository {
  RecordingSettings(this.inner);
  final core.SettingsRepository inner;

  /// (op, key name, value) with op 'set' or 'reset' (value null).
  final List<(String, String, Object?)> writes = [];

  /// The values set for [keyName], 'reset' for a reset, in order.
  List<Object?> writesOf(String keyName) => [
    for (final (op, name, value) in writes)
      if (name == keyName) op == 'set' ? value : 'reset',
  ];

  @override
  Future<T> get<T>(core.SettingKey<T> key) => inner.get(key);
  @override
  Stream<T> watch<T>(core.SettingKey<T> key) => inner.watch(key);
  @override
  Future<void> set<T>(core.SettingKey<T> key, T value) {
    writes.add(('set', key.name, value));
    return inner.set(key, value);
  }

  @override
  Future<void> reset<T>(core.SettingKey<T> key) {
    writes.add(('reset', key.name, null));
    return inner.reset(key);
  }

  @override
  Stream<core.SettingsSnapshot> watchAll() => inner.watchAll();
}

final class SettingsEnv {
  SettingsEnv(
    this.async, {
    required this.faults,
    List<Override> overrides = const [],
  }) {
    store = createFakeNoteStore(faults: faults);
    settings = RecordingSettings(store.settings);
    container = ProviderContainer(
      overrides: [
        core.noteStoreProvider.overrideWithValue(store),
        core.settingsRepositoryProvider.overrideWithValue(settings),
        ...overrides,
      ],
    );
  }

  final FakeAsync async;
  final FakeNoteStoreFaults faults;
  late final core.NoteStore store;
  late final RecordingSettings settings;
  late final ProviderContainer container;

  EditorSettingsNotifier get notifier =>
      container.read(editorSettingsProvider.notifier);
  EditorSettings get state => container.read(editorSettingsProvider);

  /// Stores [value] directly through CORE (as an earlier run or another
  /// device did), bypassing the recorder.
  void storeValue(
    core.SettingKey<Map<String, Object?>> key,
    Map<String, Object?> value,
  ) {
    unawaited(store.settings.set(key, value));
    async.flushMicrotasks();
  }

  /// The value CORE holds for [key] now.
  Map<String, Object?> storedValue(core.SettingKey<Map<String, Object?>> key) {
    Map<String, Object?>? value;
    unawaited(store.settings.get(key).then((v) => value = v));
    async.flushMicrotasks();
    return value!;
  }

  /// Starts the settings notifier and lets its load finish.
  void load() {
    container.listen(editorSettingsProvider, (_, _) {});
    async.flushMicrotasks();
  }

  void dispose() {
    container.dispose();
    unawaited(store.close());
    async.elapse(const Duration(seconds: 5));
  }
}

/// Runs [body] in fake time with a fresh [SettingsEnv]; disposes it after.
void runSettingsEnv(
  void Function(SettingsEnv env) body, {
  Duration commitDelay = Duration.zero,
  List<Override> overrides = const [],
}) {
  fakeAsync((async) {
    final faults = FakeNoteStoreFaults()..commitDelay = commitDelay;
    final env = SettingsEnv(async, faults: faults, overrides: overrides);
    body(env);
    env.dispose();
  });
}
