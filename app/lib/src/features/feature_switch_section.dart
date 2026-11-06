/// Developer settings section 'app.features' — '기능 켜고 끄기'
/// (docs/plans/m5-7/01-infra.md 4.6.1, 6.6, 6.17; contract 7.3.3 '기능
/// 스위치', D14 · D17).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';

import '../app/strings.dart';
import '../errors/app_error_log.dart';
import '../providers.dart';
import 'app_features.dart';

/// Widget keys of [FeatureSwitchSection] (tests, V15).
abstract final class FeatureSwitchSectionKeys {
  static ValueKey<String> switchOf(AppFeature feature) =>
      ValueKey<String>('app.features.${feature.name}');
  static const ValueKey<String> restartHint = ValueKey<String>(
    'app.features.restartHint',
  );
  static const ValueKey<String> restart = ValueKey<String>(
    'app.features.restart',
  );
  static const ValueKey<String> message = ValueKey<String>(
    'app.features.message',
  );
}

/// Three switches over [AppFeatureKeys]: '녹음' ('녹음·녹음 패널. 이미지
/// 넣기는 꺼지지 않아요' — D17, image import stays), '인식' ('손글씨·수식 인식,
/// 자동 도형 보정'), '수식 엔진'. A switch whose build value
/// ([compileTime]) is false is disabled, shown off, with '이 빌드에서 꺼져
/// 있어요'.
///
/// The modules read the keys once per start (AppModuleContext.resolveFeatures),
/// so when the build AND the menu differ from what this start runs
/// ([appFeaturesProvider]) the section shows '다시 시작하면 적용돼요' and —
/// on the web — [다시 시작]: recording (`audioRecorderServiceProvider`
/// status.isActive — UI only, 6.17) → '녹음 중에는 새로 고칠 수 없어요. 녹음을
/// 멈춘 뒤 눌러 주세요.' and no reload; else store.flush() (≤ 2 s; a failure
/// or the time limit → '저장이 아직 끝나지 않아 …', one record, no reload)
/// then web.reload(). Native: '앱을 완전히 닫았다가 다시 열어 주세요' (no
/// button). A failed write → '설정을 저장하지 못했어요.' + one record.
class FeatureSwitchSection extends ConsumerStatefulWidget {
  const FeatureSwitchSection({
    super.key,
    this.compileTime = AppFeatures.compileTime,
  });

  /// The build's switches (tests pass others).
  final AppFeatures compileTime;

  /// Longest wait for store.flush() before the reload.
  static const Duration flushTimeout = Duration(seconds: 2);

  @override
  ConsumerState<FeatureSwitchSection> createState() =>
      _FeatureSwitchSectionState();
}

class _FeatureSwitchSectionState extends ConsumerState<FeatureSwitchSection> {
  String? _message;
  bool _restarting = false;

  void _log(Object error, StackTrace stackTrace) {
    ref
        .read(appErrorLogProvider)
        .add(
          AppErrorRecord.fromError(
            error,
            stackTrace,
            source: AppErrorSource.manual,
          ),
        );
  }

  Future<void> _set(AppFeature feature, bool value) async {
    setState(() => _message = null);
    try {
      await ref
          .read(settingsRepositoryProvider)
          .set(AppFeatureKeys.of(feature), value);
    } on Object catch (error, stackTrace) {
      _log(error, stackTrace);
      if (mounted) setState(() => _message = AppStrings.featureSaveFailed);
    }
  }

  Future<void> _restart() async {
    if (_restarting) return;
    if (ref.read(audioRecorderServiceProvider).status.isActive) {
      setState(() => _message = AppStrings.reloadBlockedByRecording);
      return;
    }
    setState(() {
      _message = null;
      _restarting = true;
    });
    final web = ref.read(webPlatformProvider);
    try {
      await ref
          .read(noteStoreProvider)
          .flush()
          .timeout(FeatureSwitchSection.flushTimeout);
    } on Object catch (error, stackTrace) {
      _log(error, stackTrace);
      if (mounted) {
        setState(() {
          _restarting = false;
          _message = AppStrings.featureFlushFailed;
        });
      }
      return;
    }
    web.reload();
    if (mounted) setState(() => _restarting = false);
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(settingsSnapshotProvider).value;
    if (snapshot == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final build = widget.compileTime;
    final menu = AppFeatures(
      media: snapshot.get(AppFeatureKeys.media),
      recognition: snapshot.get(AppFeatureKeys.recognition),
      mathEngine: snapshot.get(AppFeatureKeys.mathEngine),
    );
    final wanted = build.and(menu);
    final running = ref.watch(appFeaturesProvider);
    final pending = AppFeature.values.any(
      (f) => wanted.isOn(f) != running.isOn(f),
    );
    final isWeb = ref.watch(runtimeInfoProvider).isWeb;
    final theme = Theme.of(context);

    Widget tile(AppFeature feature, String title, String hint) {
      final inBuild = switch (feature) {
        AppFeature.media => build.media,
        AppFeature.recognition => build.recognition,
        AppFeature.mathEngine => build.mathEngine,
      };
      final value = switch (feature) {
        AppFeature.media => menu.media,
        AppFeature.recognition => menu.recognition,
        AppFeature.mathEngine => menu.mathEngine,
      };
      return SwitchListTile(
        key: FeatureSwitchSectionKeys.switchOf(feature),
        title: Text(title),
        subtitle: Text(inBuild ? hint : AppStrings.featureOffInBuild),
        value: inBuild && value,
        onChanged: inBuild ? (v) => unawaited(_set(feature, v)) : null,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tile(
          AppFeature.media,
          AppStrings.featureMedia,
          AppStrings.featureMediaHint,
        ),
        tile(
          AppFeature.recognition,
          AppStrings.featureRecognition,
          AppStrings.featureRecognitionHint,
        ),
        tile(
          AppFeature.mathEngine,
          AppStrings.featureMathEngine,
          AppStrings.featureMathEngineHint,
        ),
        if (pending)
          Padding(
            key: FeatureSwitchSectionKeys.restartHint,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    isWeb
                        ? AppStrings.featureRestartToApply
                        : '${AppStrings.featureRestartToApply}. '
                              '${AppStrings.featureRestartNative}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                if (isWeb)
                  FilledButton.tonal(
                    key: FeatureSwitchSectionKeys.restart,
                    onPressed: _restarting ? null : () => unawaited(_restart()),
                    child: const Text(AppStrings.featureRestart),
                  ),
              ],
            ),
          ),
        if (_message case final message?)
          Padding(
            key: FeatureSwitchSectionKeys.message,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }
}
