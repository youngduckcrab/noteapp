// E2-03 (m5-7/04-editor 6.19 — review S-10, 6.18, contract R-5): the
// tap-to-seek pre-roll editor.playback.preRollMs (synced, integer key) on the
// fake store under fake_async: default 1500, 9000 → 5000 and −1 → 0
// (setter and stored value), written once 500 ms after the last change,
// restored, a change before the load wins, a remote value followed.
import 'package:feature_editor/src/state/settings/editor_setting_keys.dart';
import 'package:feature_editor/src/state/settings/pre_roll.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;

import '../helpers/settings_env.dart';

const _ms = Duration(milliseconds: 1);
const _debounce = Duration(milliseconds: 500);
final _key = EditorSettingKeys.playbackPreRollMs;

extension on SettingsEnv {
  PreRollMsNotifier get preRoll =>
      container.read(editorPreRollMsProvider.notifier);
  int get preRollMs => container.read(editorPreRollMsProvider);

  void loadPreRoll() {
    container.listen(editorPreRollMsProvider, (_, _) {});
    async.flushMicrotasks();
  }

  void storeInt(int value) {
    store.settings.set(_key, value);
    async.flushMicrotasks();
  }

  int storedInt() {
    int? value;
    store.settings.get(_key).then((v) => value = v);
    async.flushMicrotasks();
    return value!;
  }

  int restored() {
    final other = ProviderContainer(
      overrides: [core.noteStoreProvider.overrideWithValue(store)],
    );
    final sub = other.listen(editorPreRollMsProvider, (_, _) {});
    async.flushMicrotasks();
    final value = other.read(editorPreRollMsProvider);
    sub.close();
    other.dispose();
    async.flushMicrotasks();
    return value;
  }
}

void main() {
  test('the key: synced integer, default 1500', () {
    expect(_key.name, 'editor.playback.preRollMs');
    expect(_key.scope, core.SettingScope.synced);
    expect(_key.defaultValue, 1500);
  });

  test('default 1500; 9000 → 5000, −1 → 0', () {
    runSettingsEnv((env) {
      env.loadPreRoll();
      expect(env.preRollMs, 1500);
      expect(env.settings.writes, isEmpty);
      env.preRoll.set(9000);
      expect(env.preRollMs, 5000);
      env.preRoll.set(-1);
      expect(env.preRollMs, 0);
      env.preRoll.set(2500);
      expect(env.preRollMs, 2500);
      env.async.elapse(_debounce);
    });
  });

  test('written once 500 ms after the last change; restored', () {
    runSettingsEnv((env) {
      env.loadPreRoll();
      env.preRoll
        ..set(1000)
        ..set(2000)
        ..set(3000);
      env.async.elapse(_debounce - _ms);
      expect(env.settings.writesOf(_key.name), isEmpty);
      env.async.elapse(_ms);
      expect(env.settings.writesOf(_key.name), [3000]);
      expect(env.storedInt(), 3000);
      expect(env.restored(), 3000);
    });
  });

  test('a stored value out of range is clamped; a change before the load '
      'wins', () {
    runSettingsEnv((env) {
      env.storeInt(9000);
      env.loadPreRoll();
      expect(env.preRollMs, 5000);
    });
    runSettingsEnv((env) {
      env.storeInt(4000);
      env.container.listen(editorPreRollMsProvider, (_, _) {});
      env.preRoll.set(500);
      env.async.flushMicrotasks();
      expect(env.preRollMs, 500);
      env.async.elapse(_debounce);
      expect(env.storedInt(), 500);
    });
  });

  test('a remote value is followed; flush writes a pending value now', () {
    runSettingsEnv((env) {
      env.loadPreRoll();
      env.storeInt(2200);
      expect(env.preRollMs, 2200);
      env.preRoll.set(800);
      env.preRoll.flush();
      env.async.flushMicrotasks();
      expect(env.settings.writesOf(_key.name), [800]);
    });
  });
}
