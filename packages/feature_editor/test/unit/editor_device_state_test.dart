// E2-01 (m5-7/04-editor 4.3.3, 6.18; 17): EditorDeviceState — JSON round trip,
// unknown / wrong values → defaults, and the notifier: load, 500 ms write
// of editor.deviceState, a setter before the load wins, markSeenSqueeze /
// markSeenBarrelRoll record the first event once.
import 'package:fake_async/fake_async.dart';
import 'package:feature_editor/src/state/settings/editor_device_state.dart';
import 'package:feature_editor/src/state/settings/editor_setting_keys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/testing.dart';

import '../helpers/settings_env.dart';

void main() {
  group('EditorDeviceState JSON', () {
    test('defaults and the stored form of 4.3.3 (v2 — 04-editor 17 adds '
        'the chrome fields)', () {
      const d = EditorDeviceState();
      expect(d.webTextInput, WebTextInputMode.inline);
      expect(d.collectShapeSamples, isFalse);
      expect(d.seenSqueeze, isFalse);
      expect(d.seenBarrelRoll, isFalse);
      expect(d.toJson(), {
        'v': 2,
        'webTextInput': 'inline',
        'collectShapeSamples': false,
        'seenSqueeze': false,
        'seenBarrelRoll': false,
        'toolbarHidden': false,
        'seenToolbarHideHint': false,
        'paletteDetached': false,
        'palettePosition': {'x': 0.0, 'y': 1.0},
        'restorePillX': 0.5,
      });
    });

    test('round trip of every value', () {
      for (final mode in WebTextInputMode.values) {
        for (final flags in [
          (false, false, false),
          (true, false, true),
          (false, true, false),
          (true, true, true),
        ]) {
          final value = EditorDeviceState(
            webTextInput: mode,
            collectShapeSamples: flags.$1,
            seenSqueeze: flags.$2,
            seenBarrelRoll: flags.$3,
          );
          expect(EditorDeviceState.fromJson(value.toJson()), value);
        }
      }
    });

    test('unknown or wrong-typed values read as defaults', () {
      expect(EditorDeviceState.fromJson(const {}), const EditorDeviceState());
      expect(
        EditorDeviceState.fromJson(const {
          'v': 9,
          'webTextInput': 'voice',
          'collectShapeSamples': 'yes',
          'seenSqueeze': 1,
          'seenBarrelRoll': null,
          'later': {'x': 1},
        }),
        const EditorDeviceState(),
      );
      expect(
        EditorDeviceState.fromJson(const {
          'webTextInput': 'sheet',
          'seenSqueeze': true,
        }),
        const EditorDeviceState(
          webTextInput: WebTextInputMode.sheet,
          seenSqueeze: true,
        ),
      );
    });

    test('==, hashCode, copyWith', () {
      const a = EditorDeviceState(webTextInput: WebTextInputMode.sheet);
      expect(a, const EditorDeviceState(webTextInput: WebTextInputMode.sheet));
      expect(a.hashCode, a.copyWith().hashCode);
      expect(a.copyWith(seenBarrelRoll: true), isNot(a));
      expect(a.copyWith(seenBarrelRoll: true).webTextInput, a.webTextInput);
    });
  });

  group('EditorDeviceStateNotifier', () {
    test('loads the stored value', () {
      fakeAsync((async) {
        final env = SettingsEnv(async, faults: FakeNoteStoreFaults());
        env.storeValue(
          EditorSettingKeys.deviceState,
          const EditorDeviceState(
            webTextInput: WebTextInputMode.sheet,
            seenSqueeze: true,
          ).toJson(),
        );
        final sub = env.container.listen(editorDeviceStateProvider, (_, _) {});
        expect(sub.read(), const EditorDeviceState(), reason: 'sync default');
        async.flushMicrotasks();
        expect(
          sub.read(),
          const EditorDeviceState(
            webTextInput: WebTextInputMode.sheet,
            seenSqueeze: true,
          ),
        );
        expect(
          env.container.read(editorDeviceStateProvider.notifier).isLoaded,
          isTrue,
        );
        env.container.dispose();
      });
    });

    test('a setter writes editor.deviceState 500 ms later', () {
      fakeAsync((async) {
        final env = SettingsEnv(async, faults: FakeNoteStoreFaults());
        final sub = env.container.listen(editorDeviceStateProvider, (_, _) {});
        async.flushMicrotasks();
        final notifier = env.container.read(editorDeviceStateProvider.notifier)
          ..setWebTextInput(WebTextInputMode.sheet);
        expect(sub.read().webTextInput, WebTextInputMode.sheet);
        async.elapse(const Duration(milliseconds: 499));
        expect(env.settings.writesOf('editor.deviceState'), isEmpty);
        async.elapse(const Duration(milliseconds: 1));
        expect(env.settings.writesOf('editor.deviceState'), [
          const EditorDeviceState(webTextInput: WebTextInputMode.sheet)
              .toJson(),
        ]);
        notifier.setCollectShapeSamples(true);
        async.elapse(const Duration(milliseconds: 500));
        expect(
          env.storedValue(EditorSettingKeys.deviceState)['collectShapeSamples'],
          isTrue,
        );
        env.container.dispose();
      });
    });

    test('a setter before the load completes wins', () {
      fakeAsync((async) {
        final env = SettingsEnv(async, faults: FakeNoteStoreFaults());
        env.storeValue(
          EditorSettingKeys.deviceState,
          const EditorDeviceState(seenBarrelRoll: true).toJson(),
        );
        final sub = env.container.listen(editorDeviceStateProvider, (_, _) {});
        env.container
            .read(editorDeviceStateProvider.notifier)
            .setWebTextInput(WebTextInputMode.sheet);
        async.flushMicrotasks();
        expect(
          sub.read(),
          const EditorDeviceState(webTextInput: WebTextInputMode.sheet),
        );
        env.container.dispose();
      });
    });

    test(
      'markSeenSqueeze / markSeenBarrelRoll record the first event once',
      () {
        fakeAsync((async) {
          final env = SettingsEnv(async, faults: FakeNoteStoreFaults());
          final sub = env.container.listen(
            editorDeviceStateProvider,
            (_, _) {},
          );
          async.flushMicrotasks();
          final notifier = env.container.read(
            editorDeviceStateProvider.notifier,
          )..markSeenSqueeze();
          expect(sub.read().seenSqueeze, isTrue);
          expect(sub.read().seenBarrelRoll, isFalse);
          async.elapse(const Duration(milliseconds: 500));
          notifier.markSeenSqueeze(); // again: no change, no new write
          async.elapse(const Duration(milliseconds: 500));
          expect(env.settings.writesOf('editor.deviceState'), hasLength(1));
          expect(
            env.storedValue(EditorSettingKeys.deviceState)['seenSqueeze'],
            isTrue,
          );
          notifier.markSeenBarrelRoll();
          async.elapse(const Duration(milliseconds: 500));
          expect(
            env.storedValue(EditorSettingKeys.deviceState),
            const EditorDeviceState(
              seenSqueeze: true,
              seenBarrelRoll: true,
            ).toJson(),
          );
          env.container.dispose();
        });
      },
    );
  });
}
