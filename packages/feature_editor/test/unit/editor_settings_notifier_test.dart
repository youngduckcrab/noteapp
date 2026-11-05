// E-06: EditorSettingsNotifier (04-editor 4.8, 6.14) on the fake store, with
// fake_async: load then replace, a burst of changes writes its key once
// 500 ms later, the other scope's key is not written, remote synced values
// (settings.watch) are applied and our own echo is ignored; setters, reset,
// flush and the invalid-field report. The INK bridge has its own file
// (pressure_mode_bridge_test.dart).
import 'dart:async';

import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/state/settings/editor_setting_keys.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;

import '../helpers/settings_env.dart';

const _ms = Duration(milliseconds: 1);
final _device = EditorSettingKeys.deviceSettings;
final _synced = EditorSettingKeys.syncedSettings;

void main() {
  test('build returns the defaults, then the stored values replace them', () {
    runSettingsEnv((env) {
      env.storeValue(_device, {
        'v': 1,
        'inputMode': 'penOnly',
        'palm': {'cooldownMs': 800, 'hover': false, 'maxRadius': 60},
        'pressure': 'alwaysSimulated',
        'dev': true,
        'stylusSeen': true,
      });
      env.storeValue(_synced, {
        'v': 1,
        'gestures': {
          'twoFingerUndo': false,
          'threeFingerRedo': true,
          'longPressMenu': false,
        },
        'pageFlip': 'horizontalPaged',
      });

      final changes = <EditorSettings>[];
      env.container.listen(editorSettingsProvider, (_, next) {
        changes.add(next);
      });
      expect(env.state, const EditorSettings(), reason: 'synchronous build');
      expect(env.notifier.isLoaded, isFalse);

      env.async.flushMicrotasks();
      expect(env.notifier.isLoaded, isTrue);
      expect(
        env.state,
        const EditorSettings(
          inputMode: InputMode.penOnly,
          palmRejection: PalmRejectionSettings(
            penCooldown: Duration(milliseconds: 800),
            treatHoverAsPenActivity: false,
            maxTouchRadius: 60,
          ),
          gestures: GestureSettings(
            twoFingerTapUndo: false,
            longPressMenu: false,
          ),
          pageFlipMode: PageFlipMode.horizontalPaged,
          pressureMode: ink.PressureMode.alwaysSimulated,
          showDevOverlay: true,
          stylusSeen: true,
        ),
      );
      expect(changes, hasLength(1), reason: 'one replacement after the load');
      expect(env.settings.writes, isEmpty, reason: 'loading writes nothing');
    });
  });

  test('nothing stored → defaults, loaded', () {
    runSettingsEnv((env) {
      env.load();
      expect(env.notifier.isLoaded, isTrue);
      expect(env.state, const EditorSettings());
    });
  });

  test('a burst of device changes writes that key once, 500 ms later', () {
    runSettingsEnv((env) {
      env.load();
      env.notifier.setInputMode(InputMode.penOnly);
      env.async.elapse(_ms * 300);
      env.notifier.setShowDevOverlay(true);
      env.async.elapse(_ms * 300);
      env.notifier.markStylusSeen();
      env.async.elapse(_ms * 499);
      expect(env.settings.writes, isEmpty, reason: 'debounced from the last');

      env.async.elapse(_ms);
      expect(env.settings.writesOf(_device.name), [
        env.state.toJson(core.SettingScope.device),
      ]);
      expect(
        env.settings.writesOf(_synced.name),
        isEmpty,
        reason: 'the synced key did not change',
      );
      env.async.elapse(const Duration(seconds: 2));
      expect(env.settings.writes, hasLength(1));
    });
  });

  test('a synced change writes only the synced key', () {
    runSettingsEnv((env) {
      env.load();
      env.notifier.setGestures(const GestureSettings(longPressMenu: false));
      env.notifier.setPageFlipMode(PageFlipMode.horizontalPaged);
      env.async.elapse(_ms * 500);
      expect(env.settings.writesOf(_device.name), isEmpty);
      expect(env.settings.writesOf(_synced.name), [
        {
          'v': 1,
          'gestures': {
            'twoFingerUndo': true,
            'threeFingerRedo': true,
            'longPressMenu': false,
          },
          'pageFlip': 'horizontalPaged',
        },
      ]);
    });
  });

  test('the written values come back in a new container', () {
    runSettingsEnv((env) {
      env.load();
      env.notifier
        ..setInputMode(InputMode.fingerDrawing)
        ..setPageFlipMode(PageFlipMode.horizontalPaged);
      env.async.elapse(_ms * 500);

      final second = ProviderContainer(
        overrides: [core.noteStoreProvider.overrideWithValue(env.store)],
      );
      second.listen(editorSettingsProvider, (_, _) {});
      env.async.flushMicrotasks();
      expect(second.read(editorSettingsProvider), env.state);
      second.dispose();
    });
  });

  test('an equal value schedules no write and does not notify', () {
    runSettingsEnv((env) {
      env.load();
      final changes = <EditorSettings>[];
      env.container.listen(editorSettingsProvider, (_, next) {
        changes.add(next);
      });
      env.notifier
        ..setInputMode(InputMode.auto)
        ..setPalmRejection(const PalmRejectionSettings())
        ..setGestures(const GestureSettings());
      env.async.elapse(const Duration(seconds: 1));
      expect(changes, isEmpty);
      expect(env.settings.writes, isEmpty);
    });
  });

  test('every setter updates its field', () {
    runSettingsEnv((env) {
      env.load();
      final notifier = env.notifier;
      notifier.setInputMode(InputMode.penOnly);
      expect(env.state.inputMode, InputMode.penOnly);
      const palm = PalmRejectionSettings(
        penCooldown: Duration(milliseconds: 800),
        treatHoverAsPenActivity: false,
        maxTouchRadius: 90,
      );
      notifier.setPalmRejection(palm);
      expect(env.state.palmRejection, palm);
      const gestures = GestureSettings(threeFingerTapRedo: false);
      notifier.setGestures(gestures);
      expect(env.state.gestures, gestures);
      notifier.setPageFlipMode(PageFlipMode.horizontalPaged);
      expect(env.state.pageFlipMode, PageFlipMode.horizontalPaged);
      notifier.setShowDevOverlay(true);
      notifier.toggleDevOverlay();
      expect(env.state.showDevOverlay, isFalse);
      notifier.toggleDevOverlay();
      expect(env.state.showDevOverlay, isTrue);
    });
  });

  test('markStylusSeen sets the flag once and notifies once', () {
    runSettingsEnv((env) {
      env.load();
      final changes = <EditorSettings>[];
      env.container.listen(editorSettingsProvider, (_, next) {
        changes.add(next);
      });
      env.notifier
        ..markStylusSeen()
        ..markStylusSeen();
      expect(env.state.stylusSeen, isTrue);
      expect(changes, hasLength(1));
      expect(env.state.isPenOnlyEffective, isTrue); // auto + stylus seen
    });
  });

  test('a remote synced value is applied (settings.watch)', () {
    runSettingsEnv((env) {
      env.load();
      // Another device (M4) writes the synced key through CORE.
      env.storeValue(_synced, {
        'v': 1,
        'gestures': {
          'twoFingerUndo': false,
          'threeFingerRedo': false,
          'longPressMenu': true,
        },
        'pageFlip': 'horizontalPaged',
      });
      expect(
        env.state.gestures,
        const GestureSettings(
          twoFingerTapUndo: false,
          threeFingerTapRedo: false,
        ),
      );
      expect(env.state.pageFlipMode, PageFlipMode.horizontalPaged);
      expect(env.settings.writes, isEmpty, reason: 'not written back');
    });
  });

  test('our own echo from watch is ignored', () {
    // Commits take 100 ms: the echo of the first write arrives after the
    // user has changed the value again. Applying it would revert the state.
    runSettingsEnv(commitDelay: const Duration(milliseconds: 100), (env) {
      env.load();
      env.notifier.setPageFlipMode(PageFlipMode.horizontalPaged);
      env.async.elapse(_ms * 550); // written at 500, committed at 600
      env.notifier.setPageFlipMode(PageFlipMode.verticalScroll);
      env.async.elapse(_ms * 100); // the echo (horizontalPaged) arrives
      expect(env.state.pageFlipMode, PageFlipMode.verticalScroll);
      env.async.elapse(const Duration(seconds: 1));
      expect(env.state.pageFlipMode, PageFlipMode.verticalScroll);
      expect(env.settings.writesOf(_synced.name), hasLength(2));
    });
  });

  test('a change made before the load completes is kept', () {
    runSettingsEnv((env) {
      env.storeValue(_device, {'v': 1, 'inputMode': 'penOnly', 'dev': true});
      env.container.listen(editorSettingsProvider, (_, _) {});
      env.notifier.setInputMode(InputMode.fingerDrawing); // before the load
      env.async.flushMicrotasks();
      expect(env.notifier.isLoaded, isTrue);
      expect(env.state.inputMode, InputMode.fingerDrawing);
      expect(env.state.showDevOverlay, isFalse, reason: 'key had a write');
      env.async.elapse(_ms * 500);
      final written =
          env.settings.writesOf(_device.name).single! as Map<String, Object?>;
      expect(written['inputMode'], 'fingerDrawing');
    });
  });

  test('flush writes a scheduled value right away', () {
    runSettingsEnv((env) {
      env.load();
      env.notifier.setShowDevOverlay(true);
      var done = false;
      unawaited(env.notifier.flush().then((_) => done = true));
      env.async.flushMicrotasks(); // no time passes
      expect(env.settings.writesOf(_device.name), hasLength(1));
      expect(done, isTrue);
      env.async.elapse(const Duration(seconds: 1));
      expect(env.settings.writes, hasLength(1), reason: 'no second write');
    });
  });

  test('resetToDefaults resets both keys', () {
    runSettingsEnv((env) {
      env.storeValue(_device, {'v': 1, 'inputMode': 'penOnly'});
      env.storeValue(_synced, {'v': 1, 'pageFlip': 'horizontalPaged'});
      env.load();
      env.notifier.setShowDevOverlay(true); // pending, dropped by the reset
      env.notifier.resetToDefaults();
      expect(env.state, const EditorSettings());
      env.async.elapse(const Duration(seconds: 1));
      expect(env.settings.writesOf(_device.name), ['reset']);
      expect(env.settings.writesOf(_synced.name), ['reset']);
      expect(env.storedValue(_device), isEmpty);
      expect(env.storedValue(_synced), isEmpty);
      expect(env.state, const EditorSettings());
    });
  });

  test('invalid stored fields → defaults, reported once', () {
    final reported = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reported.add;
    addTearDown(() => FlutterError.onError = previous);
    runSettingsEnv((env) {
      env.storeValue(_device, {
        'v': 1,
        'inputMode': 'sideways',
        'palm': {'cooldownMs': 9999, 'hover': true},
        'pressure': 'never', // draft name: not an error
        'unknown': 1,
      });
      env.load();
      expect(env.state.inputMode, InputMode.auto);
      expect(env.state.palmRejection, const PalmRejectionSettings());
      expect(env.state.pressureMode, ink.PressureMode.alwaysSimulated);
      expect(reported, hasLength(1));
      expect(reported.single.library, 'feature_editor');
      final message = '${reported.single.exception}';
      expect(message, contains('inputMode'));
      expect(message, contains('palm.cooldownMs'));
      expect(message, isNot(contains('pressure')));
      expect(message, isNot(contains('unknown')));
    });
  });
}
