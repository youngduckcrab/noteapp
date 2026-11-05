// E-16: PresetBarNotifier (04-editor 6.10) on the fake store with fake_async:
// editor.presetBar (device) {"v":1,"group":…} — load, 500 ms debounce, a
// change before the load wins, invalid stored values → default + one report,
// values written elsewhere arrive through settings.watch, flush; and the two
// list providers on core.penPresetsProvider (visible = pinned + filter in
// CORE order, groups = distinct sorted).
import 'dart:async';

import 'package:feature_editor/src/state/preset_bar.dart';
import 'package:feature_editor/src/state/settings/editor_setting_keys.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;

import '../helpers/settings_env.dart';

const _ms = Duration(milliseconds: 1);
final _key = EditorSettingKeys.presetBar;

PresetBarNotifier _notifier(SettingsEnv env) =>
    env.container.read(editorPresetBarProvider.notifier);
PresetBarState _state(SettingsEnv env) =>
    env.container.read(editorPresetBarProvider);

void _start(SettingsEnv env) {
  env.container.listen(editorPresetBarProvider, (_, _) {});
  env.async.flushMicrotasks();
}

void main() {
  group('PresetBarState JSON', () {
    test('round trip and the stored form of 6.14', () {
      expect(const PresetBarState().toJson(), {'v': 1, 'group': null});
      const s = PresetBarState(groupFilter: '수업용');
      expect(s.toJson(), {'v': 1, 'group': '수업용'});
      expect(PresetBarState.fromJson(s.toJson()), s);
      expect(PresetBarState.fromJson(const {}), const PresetBarState());
    });

    test('a group that is not a non-blank string is the default', () {
      for (final bad in <Object>[
        3,
        true,
        '',
        '  ',
        const ['a'],
      ]) {
        final invalid = <String>[];
        expect(
          PresetBarState.fromJson({
            'v': 1,
            'group': bad,
          }, invalidFields: invalid),
          const PresetBarState(),
        );
        expect(invalid, ['group'], reason: '$bad');
      }
    });

    test('value equality', () {
      expect(
        const PresetBarState(groupFilter: 'a'),
        const PresetBarState(groupFilter: 'a'),
      );
      expect(
        const PresetBarState(groupFilter: 'a').hashCode,
        const PresetBarState(groupFilter: 'a').hashCode,
      );
      expect(
        const PresetBarState(groupFilter: 'a'),
        isNot(const PresetBarState()),
      );
    });
  });

  group('PresetBarNotifier', () {
    test('build returns all groups, then the stored filter replaces it', () {
      runSettingsEnv((env) {
        env.storeValue(_key, {'v': 1, 'group': '수업용'});
        env.container.listen(editorPresetBarProvider, (_, _) {});
        expect(_state(env), const PresetBarState(), reason: 'synchronous');
        env.async.flushMicrotasks();
        expect(_state(env).groupFilter, '수업용');
      });
    });

    test('a burst of changes writes editor.presetBar once, 500 ms after '
        'the last one', () {
      runSettingsEnv((env) {
        _start(env);
        _notifier(env).setGroupFilter('a');
        env.async.elapse(const Duration(milliseconds: 300));
        _notifier(env).setGroupFilter('b');
        env.async.elapse(const Duration(milliseconds: 499));
        expect(env.settings.writesOf(_key.name), isEmpty);
        env.async.elapse(_ms);
        expect(env.settings.writesOf(_key.name), [
          {'v': 1, 'group': 'b'},
        ]);
        expect(env.storedValue(_key), {'v': 1, 'group': 'b'});
        // No other key is written.
        expect(env.settings.writes.map((w) => w.$2).toSet(), {_key.name});
        // Back to all groups.
        _notifier(env).setGroupFilter(null);
        env.async.elapse(const Duration(milliseconds: 500));
        expect(env.storedValue(_key), {'v': 1, 'group': null});
      });
    });

    test('the key is a device setting (contract 7.4.6 프리셋 바 필터)', () {
      expect(_key.scope, core.SettingScope.device);
      expect(_key.name, 'editor.presetBar');
    });

    test('setting the same filter or a blank one does not write', () {
      runSettingsEnv((env) {
        _start(env);
        _notifier(env).setGroupFilter(null);
        _notifier(env).setGroupFilter('  ');
        env.async.elapse(const Duration(seconds: 1));
        expect(env.settings.writesOf(_key.name), isEmpty);
        expect(_state(env), const PresetBarState());
      });
    });

    test('a change made before the load completes wins', () {
      runSettingsEnv((env) {
        env.storeValue(_key, {'v': 1, 'group': '수업용'});
        env.container.listen(editorPresetBarProvider, (_, _) {});
        _notifier(env).setGroupFilter('필기'); // before the load's microtask
        env.async.flushMicrotasks();
        expect(_state(env).groupFilter, '필기');
        env.async.elapse(const Duration(milliseconds: 500));
        expect(env.storedValue(_key), {'v': 1, 'group': '필기'});
      });
    });

    test('an invalid stored value → default and one report', () {
      final reports = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = reports.add;
      try {
        runSettingsEnv((env) {
          env.storeValue(_key, {'v': 1, 'group': 42});
          _start(env);
          expect(_state(env), const PresetBarState());
        });
      } finally {
        FlutterError.onError = previous;
      }
      expect(reports, hasLength(1));
      expect(reports.single.library, 'feature_editor');
      expect(reports.single.exception, isA<FormatException>());
      expect('${reports.single.exception}', contains('editor.presetBar.group'));
    });

    test('a value written elsewhere arrives; our own echo is ignored', () {
      runSettingsEnv((env) {
        _start(env);
        _notifier(env).setGroupFilter('a');
        env.async.elapse(const Duration(milliseconds: 500));
        expect(_state(env).groupFilter, 'a');
        env.storeValue(_key, {'v': 1, 'group': 'other'});
        env.async.flushMicrotasks();
        expect(_state(env).groupFilter, 'other');
      });
    });

    test('flush writes a pending change now', () {
      runSettingsEnv((env) {
        _start(env);
        _notifier(env).setGroupFilter('a');
        unawaited(_notifier(env).flush());
        env.async.flushMicrotasks();
        expect(env.settings.writesOf(_key.name), [
          {'v': 1, 'group': 'a'},
        ]);
        env.async.elapse(const Duration(seconds: 1));
        expect(env.settings.writesOf(_key.name), hasLength(1));
      });
    });
  });

  group('visible presets and groups', () {
    List<core.PenPreset> visible(SettingsEnv env) =>
        env.container.read(editorVisiblePresetsProvider).value!;

    void edit(
      SettingsEnv env,
      Future<void> Function(core.PenPresetRepository) f,
    ) {
      unawaited(f(env.store.penPresets));
      env.async.elapse(_ms); // commits and the watch delivery
    }

    test(
      'pinned presets of the filter group, in CORE order; groups sorted',
      () {
        runSettingsEnv((env) {
          env.container.listen(editorVisiblePresetsProvider, (_, _) {});
          env.container.listen(editorPresetGroupsProvider, (_, _) {});
          env.async.flushMicrotasks();
          expect(visible(env).map((p) => p.name), [
            '볼펜',
            '만년필',
            '형광펜',
            '연필',
            '마커',
          ]);
          expect(env.container.read(editorPresetGroupsProvider), isEmpty);

          final all = env.container.read(core.penPresetsProvider).value!;
          edit(env, (r) async {
            await r.updatePreset(all[0].copyWith(group: '필기'));
            await r.updatePreset(all[2].copyWith(group: '수업용'));
            await r.updatePreset(all[3].copyWith(group: '수업용', pinned: false));
            await r.updatePreset(all[4].copyWith(group: '수업용'));
          });
          expect(env.container.read(editorPresetGroupsProvider), ['수업용', '필기']);
          // No filter: pinned only.
          expect(visible(env).map((p) => p.name), ['볼펜', '만년필', '형광펜', '마커']);

          _notifier(env).setGroupFilter('수업용');
          expect(visible(env).map((p) => p.name), ['형광펜', '마커']);
          _notifier(env).setGroupFilter('필기');
          expect(visible(env).map((p) => p.name), ['볼펜']);

          // The filter's group disappears → all groups (the filter is kept).
          edit(env, (r) => r.updatePreset(all[0].copyWith(clearGroup: true)));
          expect(env.container.read(editorPresetGroupsProvider), ['수업용']);
          expect(visible(env).map((p) => p.name), ['볼펜', '만년필', '형광펜', '마커']);
          expect(_state(env).groupFilter, '필기');
        });
      },
    );
  });
}
