// AppFeatures / AppFeatureKeys / appFeaturesProvider
// (docs/plans/m5-7/01-infra.md 4.6.1, 6.6; contract 7.3.3 '기능 스위치', S2-7
// / S2-8).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';
import 'package:noteapp/src/features/app_features.dart';

void main() {
  test('defaults and the compile-time constants (no --dart-define here)', () {
    expect(kFeatureMedia, isTrue);
    expect(kFeatureRecognition, isTrue);
    expect(kFeatureMathEngine, isTrue);
    expect(kMathEndpoint, '');
    expect(AppFeatures.compileTime, AppFeatures.all);
    const all = AppFeatures.all;
    expect((all.media, all.recognition, all.mathEngine), (true, true, true));
  });

  group('parse', () {
    const off = ['false', '0', 'off', 'no', 'FALSE', 'Off', ' no ', 'No'];
    for (final value in off) {
      test('"$value" → false', () {
        final parsed = AppFeatures.parse({'media': value});
        expect(parsed, const AppFeatures(media: false));
      });
    }
    const on = ['true', '1', 'on', 'yes', '', 'nope', 'disabled'];
    for (final value in on) {
      test('"$value" → true', () {
        expect(AppFeatures.parse({'recognition': value}), AppFeatures.all);
      });
    }
    test('missing keys → true; each key by its AppFeature name', () {
      expect(AppFeatures.parse(const {}), AppFeatures.all);
      expect(
        AppFeatures.parse(const {
          'media': 'on',
          'recognition': 'off',
          'mathEngine': '0',
          'other': 'false',
        }),
        const AppFeatures(recognition: false, mathEngine: false),
      );
    });
  });

  test('isOn: mathEngine counts only together with recognition', () {
    expect(AppFeatures.all.isOn(AppFeature.mathEngine), isTrue);
    const noRecognition = AppFeatures(recognition: false);
    expect(noRecognition.mathEngine, isTrue);
    expect(noRecognition.isOn(AppFeature.mathEngine), isFalse);
    expect(noRecognition.isOn(AppFeature.recognition), isFalse);
    expect(noRecognition.isOn(AppFeature.media), isTrue);
    const noMath = AppFeatures(mathEngine: false);
    expect(noMath.isOn(AppFeature.mathEngine), isFalse);
    expect(noMath.isOn(AppFeature.recognition), isTrue);
  });

  test('and: field-wise (build ∧ developer menu)', () {
    const build = AppFeatures(mathEngine: false);
    const menu = AppFeatures(media: false);
    expect(build.and(menu), const AppFeatures(media: false, mathEngine: false));
    expect(AppFeatures.all.and(AppFeatures.all), AppFeatures.all);
    expect(build.and(AppFeatures.all), build);
  });

  test('==, hashCode, toString', () {
    expect(const AppFeatures(media: false), const AppFeatures(media: false));
    expect(
      const AppFeatures(media: false).hashCode,
      const AppFeatures(media: false).hashCode,
    );
    expect(const AppFeatures(media: false) == AppFeatures.all, isFalse);
    expect(
      AppFeatures.all.toString(),
      'media on · recognition on · mathEngine on',
    );
    expect(
      const AppFeatures(recognition: false).toString(),
      'media on · recognition off · mathEngine off',
    );
    expect(
      const AppFeatures(media: false, mathEngine: false).toString(),
      'media off · recognition on · mathEngine off',
    );
  });

  test('AppFeatureKeys: app.features.*, bool, default true, device scope', () {
    expect(AppFeatureKeys.media.name, 'app.features.media');
    expect(AppFeatureKeys.recognition.name, 'app.features.recognition');
    expect(AppFeatureKeys.mathEngine.name, 'app.features.mathEngine');
    for (final feature in AppFeature.values) {
      final key = AppFeatureKeys.of(feature);
      expect(key.name, 'app.features.${feature.name}');
      expect(key.defaultValue, isTrue);
      expect(key.scope, SettingScope.device);
    }
  });

  test('appFeaturesProvider: compileTime unless overridden', () {
    final plain = ProviderContainer.test();
    expect(plain.read(appFeaturesProvider), AppFeatures.compileTime);
    final overridden = ProviderContainer.test(
      overrides: [
        appFeaturesProvider.overrideWithValue(
          const AppFeatures(recognition: false),
        ),
      ],
    );
    expect(
      overridden.read(appFeaturesProvider),
      const AppFeatures(recognition: false),
    );
    expect(appFeaturesProvider.name, 'appFeaturesProvider');
  });

  test('the keys round-trip through a store (next start reads them)', () async {
    final store = createFakeNoteStore();
    addTearDown(store.close);
    expect(await store.settings.get(AppFeatureKeys.media), isTrue);
    await store.settings.set(AppFeatureKeys.media, false);
    expect(await store.settings.get(AppFeatureKeys.media), isFalse);
  });
}
