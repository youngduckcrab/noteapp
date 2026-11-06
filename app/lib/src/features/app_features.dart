/// Feature switches (docs/plans/m5-7/01-infra.md 4.6.1, 6.6; contract 7.3.3
/// '기능 스위치', D14 · D17).
///
/// FEATURE_MEDIA turns off recording only (image import stays — D17),
/// FEATURE_RECOGNITION turns off recognition together with automatic shape
/// correction, FEATURE_MATH_ENGINE turns off the math engine only. The
/// developer menu keys (AppFeatureKeys) can only switch a feature off on top
/// of the build (AppFeatures.and).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_core/note_core.dart' show SettingKey, SettingScope;

enum AppFeature { media, recognition, mathEngine }

/// FEATURE_* compile-time constants. Used directly in productionModules() so
/// that dart2js drops the code only a switched-off module reaches (6.6).
/// (v2.1, D17) FEATURE_MEDIA = recording only; image import stays.
/// FEATURE_RECOGNITION also turns off automatic shape correction.
const bool kFeatureMedia = bool.fromEnvironment(
  'FEATURE_MEDIA',
  defaultValue: true,
);
const bool kFeatureRecognition = bool.fromEnvironment(
  'FEATURE_RECOGNITION',
  defaultValue: true,
);
const bool kFeatureMathEngine = bool.fromEnvironment(
  'FEATURE_MATH_ENGINE',
  defaultValue: true,
);
const String kMathEndpoint = String.fromEnvironment('MATH_ENDPOINT');

@immutable
final class AppFeatures {
  const AppFeatures({
    this.media = true,
    this.recognition = true,
    this.mathEngine = true,
  });

  static const AppFeatures compileTime = AppFeatures(
    media: kFeatureMedia,
    recognition: kFeatureRecognition,
    mathEngine: kFeatureMathEngine,
  );
  static const AppFeatures all = AppFeatures();

  /// 'false' / '0' / 'off' / 'no' (case-insensitive) → false; missing or
  /// anything else → true. Keys are the AppFeature names
  /// ('media', 'recognition', 'mathEngine').
  factory AppFeatures.parse(Map<String, String> values) {
    bool on(AppFeature feature) {
      final value = values[feature.name];
      if (value == null) return true;
      return !_offWords.contains(value.trim().toLowerCase());
    }

    return AppFeatures(
      media: on(AppFeature.media),
      recognition: on(AppFeature.recognition),
      mathEngine: on(AppFeature.mathEngine),
    );
  }

  static const Set<String> _offWords = {'false', '0', 'off', 'no'};

  /// Recording (D17) — not image import.
  final bool media;
  final bool recognition;
  final bool mathEngine;

  /// mathEngine counts only together with recognition.
  bool isOn(AppFeature feature) => switch (feature) {
    AppFeature.media => media,
    AppFeature.recognition => recognition,
    AppFeature.mathEngine => recognition && mathEngine,
  };

  /// Field-wise AND (build ∧ developer menu).
  AppFeatures and(AppFeatures other) => AppFeatures(
    media: media && other.media,
    recognition: recognition && other.recognition,
    mathEngine: mathEngine && other.mathEngine,
  );

  @override
  bool operator ==(Object other) =>
      other is AppFeatures &&
      other.media == media &&
      other.recognition == recognition &&
      other.mathEngine == mathEngine;

  @override
  int get hashCode => Object.hash(media, recognition, mathEngine);

  /// 'media on · recognition off · mathEngine off'
  @override
  String toString() => [
    for (final feature in AppFeature.values)
      '${feature.name} ${isOn(feature) ? 'on' : 'off'}',
  ].join(' · ');
}

/// Developer-menu keys (S2-8 — prefix `app.`, contract 7.4.4). Read once per
/// start by AppModuleContext.resolveFeatures; a change applies on the next
/// start.
abstract final class AppFeatureKeys {
  static final SettingKey<bool> media = SettingKey.boolean(
    'app.features.media',
    true,
    scope: SettingScope.device,
  );
  static final SettingKey<bool> recognition = SettingKey.boolean(
    'app.features.recognition',
    true,
    scope: SettingScope.device,
  );
  static final SettingKey<bool> mathEngine = SettingKey.boolean(
    'app.features.mathEngine',
    true,
    scope: SettingScope.device,
  );

  static SettingKey<bool> of(AppFeature feature) => switch (feature) {
    AppFeature.media => media,
    AppFeature.recognition => recognition,
    AppFeature.mathEngine => mathEngine,
  };
}

/// What the modules saw at this start (BootstrapSuccess.features). Overridden
/// with that value in the root overrides.
final appFeaturesProvider = Provider<AppFeatures>(
  (ref) => AppFeatures.compileTime,
  name: 'appFeaturesProvider',
);
