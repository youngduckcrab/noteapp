// lib/src/settings/on_device_math_tile.dart — (internal) settings › 인식 ›
// 수식 인식 › '기기에서 수식 인식' (the on-device math engine).
//
// ┌ 기기에서 수식 인식                                        (switch) ┐
// │ 손으로 쓴 수식을 이 기기 안에서 LaTeX로 바꿔요. …                   │
// │ 켜면 인식 모델(약 32MB)을 한 번 받아요. …   |  모델 받는 중… 45%    │
// └ [━━━━━━━━━──────] [취소]  ·  준비됨 · 약 32MB [지우기]  ·  … [다시] ┘
//
// - Only where the platform has a model manager (Android / iOS apps — not
//   the web, not the desktops).
// - On: recog.mathOnDevice = true and the download starts (nothing is
//   downloaded before — the model is not in the app). Off: false, a running
//   download stops; the files stay ([지우기] frees the space and turns the
//   switch off). Failed: the reason and [다시]; on but not installed (an
//   earlier run stopped): [받기].
import 'dart:async' show unawaited;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../common/report_error.dart';
import '../l10n/recognition_strings.dart';
import '../ondevice/math_model_manager.dart';
import '../ondevice/on_device_providers.dart';
import '../ui/recognition_sheet.dart' show kSheetMinTapStyle;
import 'recognition_settings_keys.dart';

/// The tile's keys (not appendix C).
abstract final class OnDeviceMathKeys {
  static const ValueKey<String> toggle = ValueKey(
    'recog.settings.mathOnDevice',
  );
  static const ValueKey<String> status = ValueKey(
    'recog.settings.mathOnDevice.status',
  );
  static const ValueKey<String> progress = ValueKey(
    'recog.settings.mathOnDevice.progress',
  );
  static const ValueKey<String> cancel = ValueKey(
    'recog.settings.mathOnDevice.cancel',
  );
  static const ValueKey<String> delete = ValueKey(
    'recog.settings.mathOnDevice.delete',
  );
  static const ValueKey<String> download = ValueKey(
    'recog.settings.mathOnDevice.download',
  );
}

/// The model's size in MB (decimal, rounded) for the texts.
int mathModelMegabytes(MathModelManager manager) =>
    (manager.manifest.totalBytes / 1000000).round();

/// The status text of [state] with the switch [on].
String onDeviceMathStatusText(
  MathModelState state, {
  required bool on,
  required int megabytes,
}) => switch (state) {
  MathModelReady() => RecognitionStrings.onDeviceMathReady(megabytes),
  MathModelDownloading(:final progress) =>
    RecognitionStrings.onDeviceMathDownloading((progress * 100).floor()),
  MathModelFailed(reason: MathModelFailure.offline) =>
    RecognitionStrings.onDeviceMathFailedOffline,
  MathModelFailed(reason: MathModelFailure.checksum) =>
    RecognitionStrings.onDeviceMathFailedChecksum,
  MathModelFailed(reason: MathModelFailure.storage) =>
    RecognitionStrings.onDeviceMathFailedStorage,
  MathModelFailed() => RecognitionStrings.onDeviceMathFailedOther,
  MathModelNotInstalled() || MathModelUnsupported() =>
    on
        ? RecognitionStrings.onDeviceMathNotInstalled
        : RecognitionStrings.onDeviceMathOffNote(megabytes),
};

class OnDeviceMathTile extends ConsumerWidget {
  const OnDeviceMathTile({super.key, required this.enabled});

  /// false while the settings load.
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = ref.watch(mathModelManagerProvider);
    if (manager == null) return const SizedBox.shrink();
    final state = ref.watch(mathModelStateProvider);
    final on =
        ref
            .watch(core.settingsSnapshotProvider)
            .value
            ?.get(RecognitionSettingsKeys.mathOnDevice) ??
        false;
    final mb = mathModelMegabytes(manager);

    void save(bool value) {
      final settings = ref.read(core.settingsRepositoryProvider);
      unawaited(
        settings
            .set(RecognitionSettingsKeys.mathOnDevice, value)
            .then<void>(
              (_) {},
              onError: (Object e, StackTrace s) => reportRecognitionError(
                e,
                s,
                'saving ${RecognitionSettingsKeys.mathOnDevice.name}',
              ),
            ),
      );
    }

    void toggle(bool value) {
      save(value);
      if (value) {
        unawaited(manager.download());
      } else {
        manager.cancel();
      }
    }

    void delete() {
      save(false);
      unawaited(manager.delete());
    }

    final scheme = Theme.of(context).colorScheme;
    final failed = state is MathModelFailed;
    final action = switch (state) {
      MathModelDownloading() => _action(
        OnDeviceMathKeys.cancel,
        RecognitionStrings.cancel,
        manager.cancel,
      ),
      MathModelReady() => _action(
        OnDeviceMathKeys.delete,
        RecognitionStrings.deleteModel,
        delete,
      ),
      MathModelFailed() => _action(
        OnDeviceMathKeys.download,
        RecognitionStrings.retry,
        () => toggle(true),
      ),
      MathModelNotInstalled() when on => _action(
        OnDeviceMathKeys.download,
        RecognitionStrings.download,
        () => unawaited(manager.download()),
      ),
      _ => null,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          key: OnDeviceMathKeys.toggle,
          title: const Text(RecognitionStrings.onDeviceMathTitle),
          subtitle: const Text(RecognitionStrings.onDeviceMathBody),
          value: on,
          onChanged: enabled ? toggle : null,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      onDeviceMathStatusText(state, on: on, megabytes: mb),
                      key: OnDeviceMathKeys.status,
                      style: TextStyle(
                        color: failed ? scheme.error : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  ?action,
                ],
              ),
              if (state is MathModelDownloading)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: LinearProgressIndicator(
                    key: OnDeviceMathKeys.progress,
                    value: state.progress,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

Widget _action(Key key, String label, VoidCallback onPressed) => Padding(
  padding: const EdgeInsets.only(left: 8),
  child: TextButton(
    key: key,
    style: kSheetMinTapStyle,
    onPressed: onPressed,
    child: Text(label),
  ),
);
