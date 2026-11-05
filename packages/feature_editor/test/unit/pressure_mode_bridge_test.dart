// E-06: the ink.pressureModeProvider bridge (contract 7.3.3, 04-editor 4.8,
// 6.13.1 #7). After the load completes and after setPressureMode(), INK's
// value equals the editor setting; build() never changes it (V4).
import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/state/settings/editor_setting_keys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;

import '../helpers/settings_env.dart';

void main() {
  test('after the load INK has the stored pressure mode', () {
    runSettingsEnv((env) {
      env.storeValue(EditorSettingKeys.deviceSettings, {
        'v': 1,
        'pressure': 'alwaysReal',
      });
      env.load();
      expect(env.state.pressureMode, ink.PressureMode.alwaysReal);
      expect(
        env.container.read(ink.pressureModeProvider),
        ink.PressureMode.alwaysReal,
      );
    });
  });

  test('build() does not change INK; the load does, after an await', () {
    runSettingsEnv((env) {
      env.storeValue(EditorSettingKeys.deviceSettings, {
        'v': 1,
        'pressure': 'alwaysSimulated',
      });
      final inkValues = <ink.PressureMode>[];
      env.container.listen(
        ink.pressureModeProvider,
        (_, next) => inkValues.add(next),
        fireImmediately: true,
      );
      // Reading the settings runs build() — INK keeps its value meanwhile.
      expect(env.state, const EditorSettings());
      expect(
        env.container.read(ink.pressureModeProvider),
        ink.PressureMode.auto,
      );
      expect(
        env.container.read(ink.pressureModeProvider.notifier),
        isA<ink.PressureModeNotifier>(),
        reason: 'the INK provider is not in an error state (V4)',
      );
      env.async.flushMicrotasks();
      expect(inkValues, [
        ink.PressureMode.auto,
        ink.PressureMode.alwaysSimulated,
      ]);
    });
  });

  test('setPressureMode pushes every change to INK', () {
    runSettingsEnv((env) {
      env.load();
      for (final mode in [
        ink.PressureMode.alwaysSimulated,
        ink.PressureMode.alwaysReal,
        ink.PressureMode.auto,
      ]) {
        env.notifier.setPressureMode(mode);
        expect(env.state.pressureMode, mode);
        expect(env.container.read(ink.pressureModeProvider), mode);
      }
    });
  });

  test('resetToDefaults pushes auto to INK', () {
    runSettingsEnv((env) {
      env.load();
      env.notifier.setPressureMode(ink.PressureMode.alwaysReal);
      env.notifier.resetToDefaults();
      expect(
        env.container.read(ink.pressureModeProvider),
        ink.PressureMode.auto,
      );
    });
  });

  test('a value INK holds before the load is replaced by the stored one', () {
    runSettingsEnv((env) {
      env.container
          .read(ink.pressureModeProvider.notifier)
          .set(ink.PressureMode.alwaysReal);
      env.load();
      expect(
        env.container.read(ink.pressureModeProvider),
        ink.PressureMode.auto,
        reason: 'nothing stored → the editor default wins after the load',
      );
    });
  });
}
